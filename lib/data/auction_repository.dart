import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../core/errors/app_exception.dart';
import '../core/firebase/firestore_refs.dart';
import '../core/models/auction.dart';
import '../core/models/app_user.dart';
import 'org_repository.dart' show guard, guardStream;

/// Player auctions: the sealed-bid squad draft.
///
/// ## The split this class is built around
///
/// Two kinds of write live here and they are not interchangeable.
///
/// **Ordinary writes** — joining, approving, naming a side, repricing a lot,
/// proposing and accepting a trade — are plain Firestore writes governed by
/// `firestore.rules`, matching the rest of this codebase's philosophy that
/// rules are the actual boundary.
///
/// **Guarded writes** — every bid, every status transition, the reveal, and
/// the roster half of a trade — go through callables in
/// `functions/auctions.js`, because each is two or more documents that must
/// change together. The rules deny those paths to clients outright. See that
/// file's header for the full argument.
///
/// A method here that calls `_functions` is in the second group; one that
/// touches `Refs` directly is in the first. Nothing does both.
class AuctionRepository {
  const AuctionRepository();

  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'asia-south1');

  /// Turns a callable's refusal into a sentence safe to put in front of
  /// somebody. The functions in `auctions.js` are written so that every
  /// `failed-precondition` message already reads as one — "You have ₹40,000
  /// free for this player" — so the message is passed through rather than
  /// replaced with a generic apology that throws away the only useful part.
  Future<T> _call<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on FirebaseFunctionsException catch (e) {
      throw ValidationException(e.message ?? 'That did not go through.');
    }
  }

  // --- Finding an auction ------------------------------------------------

  /// The public board.
  ///
  /// Pins `visibility` and excludes drafts because `list` is authorised
  /// against each document the query returns — an unpinned query would
  /// include one unlisted auction and Firestore would refuse the whole page
  /// rather than trimming it. See `reference_firestore_list_rules`: the
  /// filter is not an optimisation here, it is what makes the read legal.
  Stream<List<Auction>> watchPublicAuctions({String? sportId}) =>
      guardStream(() {
        var q = Refs.auctions
            .where('visibility', isEqualTo: AuctionVisibility.public.wire)
            .where('status', whereIn: [
          AuctionStatus.registration.wire,
          AuctionStatus.bidding.wire,
          AuctionStatus.revealed.wire,
          AuctionStatus.locked.wire,
        ]);
        if (sportId != null) q = q.where('sportId', isEqualTo: sportId);
        return q
            .orderBy('createdAt', descending: true)
            .limit(60)
            .snapshots()
            .map((s) => s.docs.map(Auction.fromDoc).toList(growable: false));
      });

  /// Every auction this person is in, whatever their role and whatever the
  /// auction's visibility.
  ///
  /// A collection-group query over `participants`, which is the only read
  /// that can find an unlisted auction somebody has already joined — the
  /// auction document itself is unreadable until this row exists, so nothing
  /// else the client can ask would name it.
  ///
  /// Sorted on the client. A single equality filter plus an `orderBy` on a
  /// different field would need a composite index on a collection group for a
  /// list that is never more than a handful of rows.
  Stream<List<AuctionParticipant>> watchMyAuctions(String uid) => guardStream(
        () => Refs.auctionParticipantsGroup
            .where('uid', isEqualTo: uid)
            .limit(60)
            .snapshots()
            .map((s) {
          final rows = s.docs.map(AuctionParticipant.fromDoc).toList();
          rows.sort((a, b) {
            final at = a.createdAt;
            final bt = b.createdAt;
            if (at == null && bt == null) return 0;
            if (at == null) return 1;
            if (bt == null) return -1;
            return bt.compareTo(at);
          });
          return rows;
        }),
      );

  /// Resolve a code somebody was given into an auction id.
  ///
  /// Reads `auctionCodes/{code}`, never the auction — an unlisted auction is
  /// unreadable until you have joined it, so the code document is the only
  /// thing that can tell a newcomer where to knock.
  Future<String?> resolveJoinCode(String typed) => guard(() async {
        final code = AuctionCode.normalize(typed);
        if (code == null) return null;
        final snap = await Refs.auctionCode(code).get();
        if (!snap.exists) return null;
        final id = snap.data()?['auctionId'];
        return id is String && id.isNotEmpty ? id : null;
      });

  Stream<Auction?> watchAuction(String auctionId) => guardStream(
        () => Refs.auction(auctionId).snapshots().map(
              (d) => d.exists ? Auction.fromDoc(d) : null,
            ),
      );

  // --- Creating one ------------------------------------------------------

  /// Calls a new auction into being, with its join code and the creator's own
  /// organizer row.
  ///
  /// All three in one batch. A code claimed for an auction that failed to
  /// write would burn a code forever; an auction with no organizer row would
  /// be unreachable by the person who just made it, since membership is that
  /// subcollection and nothing else.
  ///
  /// Retries on code collision, exactly like `UserRepository.ensureCode`:
  /// uniqueness comes from the create failing when the document id is taken,
  /// not from a check-then-write that races.
  Future<String> createAuction({
    required Auction draft,
    required AppUser creator,
  }) =>
      guard(() async {
        for (var attempt = 0; attempt < 5; attempt++) {
          final code = AuctionCode.generate();
          final auctionRef = Refs.auctions.doc();
          final batch = Refs.db.batch();

          batch.set(auctionRef, {
            ...draft.toCreate(),
            'joinCode': code,
          });
          // `create` semantics: the batch fails whole if this id is taken.
          batch.set(
            Refs.auctionCode(code),
            {
              'auctionId': auctionRef.id,
              'name': draft.name,
              'sportName': draft.sportName,
              'createdByUid': creator.uid,
              'createdAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: false),
          );
          batch.set(
            Refs.auctionParticipant(auctionRef.id, creator.uid),
            AuctionParticipant(
              uid: creator.uid,
              auctionId: auctionRef.id,
              auctionName: draft.name,
              displayName: creator.displayName,
              photoUrl: creator.photoUrl,
              playerCode: creator.playerCode,
              roles: const {AuctionRole.organizer},
              status: AuctionJoinStatus.approved,
            ).toCreate()
              // The creator is approved from the start — there is nobody else
              // to approve them, and an organizer waiting on their own
              // approval is a deadlock.
              ..['status'] = AuctionJoinStatus.approved.wire,
          );

          try {
            await batch.commit();
            return auctionRef.id;
          } on FirebaseException catch (e) {
            if (e.code != 'already-exists' && e.code != 'aborted') rethrow;
            if (attempt == 4) rethrow;
          }
        }
        throw const ValidationException('Could not create that auction.');
      });

  Future<void> updateSettings(Auction auction) => guard(
        () => Refs.auction(auction.id).update(auction.toSettingsUpdate()),
      );

  /// Publish a draft so people can join. The one status transition a client
  /// makes directly — it moves no money, notifies nobody, and an organizer
  /// expects it to be instant.
  Future<void> openRegistration(String auctionId) => guard(
        () => Refs.auction(auctionId).update({
          'status': AuctionStatus.registration.wire,
          'updatedAt': FieldValue.serverTimestamp(),
        }),
      );

  Future<void> cancelAuction(String auctionId) => guard(
        () => Refs.auction(auctionId).update({
          'status': AuctionStatus.cancelled.wire,
          'updatedAt': FieldValue.serverTimestamp(),
        }),
      );

  Future<void> deleteDraft(String auctionId, String joinCode) =>
      guard(() async {
        final batch = Refs.db.batch();
        batch.delete(Refs.auction(auctionId));
        // Frees the code for somebody else. Safe only because the rules let a
        // draft be deleted and nothing else, so no live auction can lose the
        // code on its noticeboard this way.
        if (joinCode.isNotEmpty) batch.delete(Refs.auctionCode(joinCode));
        await batch.commit();
      });

  // --- Taking part -------------------------------------------------------

  Stream<List<AuctionParticipant>> watchParticipants(String auctionId) =>
      guardStream(
        () => Refs.auctionParticipants(auctionId).snapshots().map(
              (s) => s.docs
                  .map(AuctionParticipant.fromDoc)
                  .toList(growable: false),
            ),
      );

  Stream<AuctionParticipant?> watchMyPlace(String auctionId, String uid) =>
      guardStream(
        () => Refs.auctionParticipant(auctionId, uid).snapshots().map(
              (d) => d.exists ? AuctionParticipant.fromDoc(d) : null,
            ),
      );

  /// Putting your hand up. Lands as `pending` — the rules pin it, so this is
  /// a request and never a self-approval.
  Future<void> join({
    required Auction auction,
    required AppUser user,
    required Set<AuctionRole> roles,
    String? note,
  }) =>
      guard(() async {
        await Refs.auctionParticipant(auction.id, user.uid).set(
          AuctionParticipant(
            uid: user.uid,
            auctionId: auction.id,
            auctionName: auction.name,
            displayName: user.displayName,
            photoUrl: user.photoUrl,
            playerCode: user.playerCode,
            roles: roles,
            status: AuctionJoinStatus.pending,
            note: note,
          ).toCreate(),
        );
      });

  /// Editing the note on an application nobody has decided yet.
  Future<void> updateJoinNote({
    required String auctionId,
    required String uid,
    required String note,
  }) =>
      guard(() => Refs.auctionParticipant(auctionId, uid).update({'note': note}));

  Future<void> withdrawJoinRequest(String auctionId, String uid) =>
      guard(() => Refs.auctionParticipant(auctionId, uid).delete());

  /// The organizer's decision, and everything that follows from it.
  ///
  /// Approving is three writes, not one: the row flips to `approved`, and
  /// then a bidder gets a side with a purse and a player gets a lot in the
  /// pool. They are sequential rather than batched because the rules require
  /// the participant row to ALREADY read `approved` before a team or a lot
  /// naming that uid may be created — a batch would evaluate both against the
  /// pre-batch state and be refused.
  ///
  /// [statLine], [matchesPlayed] and [wins] are the career snapshot copied
  /// onto the lot. See `AuctionLot` for why the pool list reads a copy and
  /// only the opened player reads the live record.
  Future<void> decide({
    required Auction auction,
    required AuctionParticipant participant,
    required bool approve,
    required String deciderUid,
    int? pursePaiseOverride,
    String? teamName,
    String? roleLabel,
    String? statLine,
    int matchesPlayed = 0,
    int wins = 0,
    String? ratingLabel,
  }) =>
      guard(() async {
        await Refs.auctionParticipant(auction.id, participant.uid).update({
          'status': approve
              ? AuctionJoinStatus.approved.wire
              : AuctionJoinStatus.declined.wire,
          'decidedByUid': deciderUid,
          'decidedAt': FieldValue.serverTimestamp(),
        });

        if (!approve) {
          await _notifyDecision(auction.id, participant.uid);
          return;
        }

        if (participant.isBidder) {
          await Refs.auctionTeam(auction.id, participant.uid).set({
            'auctionId': auction.id,
            'ownerUid': participant.uid,
            'ownerName': participant.displayName,
            'ownerPhotoUrl': participant.photoUrl,
            'name': (teamName == null || teamName.trim().isEmpty)
                ? '${participant.displayName} XI'
                : teamName.trim(),
            'pursePaise': pursePaiseOverride ?? auction.defaultPursePaise,
            'committedPaise': 0,
            'spentPaise': 0,
            'wonCount': 0,
            'liveBidCount': 0,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          await Refs.auction(auction.id).update({
            'teamCount': FieldValue.increment(1),
          });
        }

        if (participant.isPlayer) {
          await Refs.auctionLot(auction.id, participant.uid).set({
            'auctionId': auction.id,
            'playerUid': participant.uid,
            'displayName': participant.displayName,
            'photoUrl': participant.photoUrl,
            'playerCode': participant.playerCode,
            'roleLabel': roleLabel,
            'status': AuctionLotStatus.pool.wire,
            'basePricePaise': auction.defaultBasePricePaise,
            'bidCount': 0,
            'statLine': statLine,
            'matchesPlayed': matchesPlayed,
            'wins': wins,
            'ratingLabel': ratingLabel,
            'createdAt': FieldValue.serverTimestamp(),
          });
          await Refs.auction(auction.id).update({
            'playerCount': FieldValue.increment(1),
          });
        }

        await _notifyDecision(auction.id, participant.uid);
      });

  /// Best-effort. The decision is the Firestore write above and stands
  /// whether or not the push goes out, so a failure here must not surface as
  /// "approval failed" on a screen where the approval plainly worked.
  Future<void> _notifyDecision(String auctionId, String targetUid) async {
    try {
      await _functions.httpsCallable('notifyAuctionDecision').call({
        'auctionId': auctionId,
        'targetUid': targetUid,
      });
    } on FirebaseFunctionsException {
      // Swallowed deliberately — see the doc comment.
    }
  }

  // --- Sides -------------------------------------------------------------

  Stream<List<AuctionTeam>> watchTeams(String auctionId) => guardStream(
        () => Refs.auctionTeams(auctionId).snapshots().map(
              (s) => s.docs.map(AuctionTeam.fromDoc).toList(growable: false),
            ),
      );

  Stream<AuctionTeam?> watchTeam(String auctionId, String teamId) =>
      guardStream(
        () => Refs.auctionTeam(auctionId, teamId).snapshots().map(
              (d) => d.exists ? AuctionTeam.fromDoc(d) : null,
            ),
      );

  /// The organizer setting one side's purse — "admin gives 100K for each
  /// member, dynamic, admin may decide". The rules refuse a purse below what
  /// the side has already committed or spent.
  Future<void> setPurse({
    required String auctionId,
    required String teamId,
    required int pursePaise,
  }) =>
      guard(() => Refs.auctionTeam(auctionId, teamId).update({
            'pursePaise': pursePaise,
            'updatedAt': FieldValue.serverTimestamp(),
          }));

  /// The owner naming their own side.
  Future<void> renameTeam({
    required String auctionId,
    required String teamId,
    required String name,
  }) =>
      guard(() => Refs.auctionTeam(auctionId, teamId).update({
            'name': name.trim(),
            'updatedAt': FieldValue.serverTimestamp(),
          }));

  // --- The pool ----------------------------------------------------------

  Stream<List<AuctionLot>> watchLots(String auctionId) => guardStream(
        () => Refs.auctionLots(auctionId).snapshots().map(
              (s) => s.docs.map(AuctionLot.fromDoc).toList(growable: false),
            ),
      );

  Stream<AuctionLot?> watchLot(String auctionId, String lotId) => guardStream(
        () => Refs.auctionLot(auctionId, lotId).snapshots().map(
              (d) => d.exists ? AuctionLot.fromDoc(d) : null,
            ),
      );

  /// One side's squad, after the reveal. A plain query on the lots rather
  /// than a roster subcollection: the lot document is already where "who owns
  /// this player" lives, and a second copy would be one more thing a trade
  /// has to keep in step.
  Stream<List<AuctionLot>> watchSquad(String auctionId, String teamId) =>
      guardStream(
        () => Refs.auctionLots(auctionId)
            .where('soldToTeamId', isEqualTo: teamId)
            .snapshots()
            .map((s) => s.docs.map(AuctionLot.fromDoc).toList(growable: false)),
      );

  /// Repricing a lot's floor. Refused by the rules once bidding has opened —
  /// a floor raised under a sealed bid already placed would invalidate it
  /// without telling the bidder.
  Future<void> setBasePrice({
    required String auctionId,
    required String lotId,
    required int basePricePaise,
  }) =>
      guard(() => Refs.auctionLot(auctionId, lotId).update({
            'basePricePaise': basePricePaise,
          }));

  Future<void> withdrawLot(String auctionId, String lotId) =>
      guard(() => Refs.auctionLot(auctionId, lotId).update({
            'status': AuctionLotStatus.withdrawn.wire,
          }));

  // --- Bids (server-guarded) --------------------------------------------

  /// One team's own sealed bids across every lot in this auction.
  ///
  /// A collection-group query filtered by `teamId`, which is also the
  /// document id — so the per-document rule that keeps a bid private
  /// authorises every row this returns and cannot return anybody else's.
  Stream<List<AuctionBid>> watchMyBids(String auctionId, String teamId) =>
      guardStream(
        () => Refs.auctionBidsGroup
            .where('auctionId', isEqualTo: auctionId)
            .where('teamId', isEqualTo: teamId)
            .snapshots()
            .map((s) => s.docs.map(AuctionBid.fromDoc).toList(growable: false)),
      );

  /// Every bid on one lot.
  ///
  /// Before the reveal this returns exactly one document — the caller's own —
  /// because that is all the rules will hand over. Afterwards it returns all
  /// of them, which is what makes the result checkable by hand. The caller
  /// does not branch on which case it is in; the rules decide and the list is
  /// simply longer.
  Stream<List<AuctionBid>> watchLotBids(String auctionId, String lotId) =>
      guardStream(
        () => Refs.auctionBids(auctionId, lotId).snapshots().map(
              (s) => s.docs.map(AuctionBid.fromDoc).toList(growable: false),
            ),
      );

  /// Place, raise or lower a bid. Never a direct write — see the class doc.
  Future<void> placeBid({
    required String auctionId,
    required String lotId,
    required int amountPaise,
  }) =>
      _call(() async {
        await _functions.httpsCallable('placeAuctionBid').call({
          'auctionId': auctionId,
          'lotId': lotId,
          'amountPaise': amountPaise,
        });
      });

  /// Take a bid back and release the money it locked. Zero is the withdraw
  /// signal, which keeps one transaction rather than two doing the same
  /// arithmetic in opposite directions.
  Future<void> withdrawBid({
    required String auctionId,
    required String lotId,
  }) =>
      placeBid(auctionId: auctionId, lotId: lotId, amountPaise: 0);

  // --- Running it (server-guarded) --------------------------------------

  Future<void> openBidding({
    required String auctionId,
    required DateTime closesAt,
  }) =>
      _call(() async {
        await _functions.httpsCallable('openAuctionBidding').call({
          'auctionId': auctionId,
          'bidsCloseAtMs': closesAt.millisecondsSinceEpoch,
        });
      });

  /// Open the lots now rather than waiting for the scheduled sweep.
  Future<void> revealNow(String auctionId) => _call(() async {
        await _functions.httpsCallable('revealAuctionNow').call({
          'auctionId': auctionId,
        });
      });

  Future<void> lockSquads(String auctionId) => _call(() async {
        await _functions.httpsCallable('lockAuctionSquads').call({
          'auctionId': auctionId,
        });
      });

  // --- Trades ------------------------------------------------------------

  /// The trades one side is party to, proposed or answered.
  ///
  /// Filtered on `teamIds`, an array carrying both sides, so a single
  /// `arrayContains` finds an owner's whole inbox — the alternative is two
  /// queries (`fromTeamId`, `toTeamId`) merged on the client, which would
  /// also mean two listeners on a screen that shows one list.
  Stream<List<AuctionTrade>> watchMyTrades(String auctionId, String teamId) =>
      guardStream(
        () => Refs.auctionTrades(auctionId)
            .where('teamIds', arrayContains: teamId)
            .orderBy('createdAt', descending: true)
            .limit(60)
            .snapshots()
            .map((s) => s.docs.map(AuctionTrade.fromDoc).toList(
                  growable: false,
                )),
      );

  Future<String> proposeTrade(AuctionTrade trade) => guard(() async {
        final ref = Refs.auctionTrades(trade.auctionId).doc();
        await ref.set(trade.toCreate());
        await _notifyTrade(trade.auctionId, ref.id);
        return ref.id;
      });

  /// Saying yes. Only marks agreement — the roster moves in [executeTrade],
  /// which is a separate call for the reason `executeAuctionTrade` documents.
  Future<void> acceptTrade({
    required String auctionId,
    required String tradeId,
  }) =>
      guard(() async {
        await Refs.auctionTrade(auctionId, tradeId).update({
          'status': AuctionTradeStatus.accepted.wire,
          'decidedAt': FieldValue.serverTimestamp(),
        });
        await _notifyTrade(auctionId, tradeId);
      });

  Future<void> declineTrade({
    required String auctionId,
    required String tradeId,
  }) =>
      guard(() => Refs.auctionTrade(auctionId, tradeId).update({
            'status': AuctionTradeStatus.declined.wire,
            'decidedAt': FieldValue.serverTimestamp(),
          }));

  Future<void> cancelTrade({
    required String auctionId,
    required String tradeId,
  }) =>
      guard(() => Refs.auctionTrade(auctionId, tradeId).update({
            'status': AuctionTradeStatus.cancelled.wire,
            'decidedAt': FieldValue.serverTimestamp(),
          }));

  /// Move the players. Idempotent — safe to call on a trade that already
  /// went through, which is what makes it correct to call from either side's
  /// screen without coordinating.
  Future<void> executeTrade({
    required String auctionId,
    required String tradeId,
  }) =>
      _call(() async {
        await _functions.httpsCallable('executeAuctionTrade').call({
          'auctionId': auctionId,
          'tradeId': tradeId,
        });
      });

  Future<void> _notifyTrade(String auctionId, String tradeId) async {
    try {
      await _functions.httpsCallable('notifyAuctionTrade').call({
        'auctionId': auctionId,
        'tradeId': tradeId,
      });
    } on FirebaseFunctionsException {
      // Best-effort, same reasoning as _notifyDecision.
    }
  }
}
