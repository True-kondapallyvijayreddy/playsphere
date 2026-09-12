import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_codec.dart';

// ===========================================================================
// Player auctions — a sealed-bid squad draft that runs over days, not minutes.
// ===========================================================================
//
// ## What this is, and what it deliberately is not
//
// The obvious way to build a player auction is the televised one: everybody
// in one room, one player on the block at a time, an auctioneer, a countdown,
// paddles going up. `PlaySphere-SRS/11_Team_Engine.md` specifies exactly that
// — a "Live Auction Console" with a timer and an "accept bid" button.
//
// This is not that, on purpose.
//
// A live outcry auction requires every franchise owner to be awake, online,
// and holding a stable connection for the same two hours. For the organizers
// this product is actually for — a village cricket league, a school inter-
// house season, an apartment-block tournament — that is the single hardest
// thing to arrange, harder than the tournament itself. It also makes every
// bid a race: two people tap at the same instant, one wins on network
// latency, and the loser is certain the app cheated them.
//
// So the auction here is SEALED and DEADLINE-BASED. Each team privately
// commits an amount to each player they want, any time over the days the
// bidding window is open. Nobody can see anybody else's bids. At a moment the
// organizer picks — `bidsCloseAt` — every lot opens at once and the highest
// bid on each takes the player. No room, no timing, no race, and the whole
// thing works over a week on a shared phone with patchy signal.
//
// ## The one rule that makes the reveal honest: committed money
//
// A sealed auction has a problem a live one does not. If bids are free, a
// team with ₹1,00,000 can bid ₹80,000 on each of five players, and if they
// win three they owe ₹2,40,000 they never had. Resolving that means either
// asking bidders to rank their own preferences (which nobody does correctly)
// or cascading players down to people who did not bid highest (which makes
// the result unexplainable at the ground).
//
// So a bid LOCKS the money for as long as it stands. [AuctionTeam.committed]
// is the sum of a team's live bids, and no bid may push it past the purse.
// You may raise, lower or withdraw any bid until the deadline; what you may
// not do is promise the same rupee twice.
//
// That single constraint is what makes the reveal a pure per-lot maximum with
// no interaction between lots — every winner can always pay, every result is
// arithmetic anybody can check by hand, and nothing has to be undone. The
// cost is real and is stated plainly in the UI: you cannot bid on ten players
// hoping to win three. That is the honest shape of a blind budget, and it is
// the same one fantasy-sports auction drafts have settled on.
//
// ## Why this is not nested under a club
//
// `orgId` is absent. An auction is run by whoever calls it — a village
// elder, a school sports teacher, four friends who booked a ground — and the
// requirement was explicit that it work "irrespective of clubs & teams,
// district or village". [Auction.linkedOrgId] exists for a club that DOES
// want to run one under its own name, and changes nothing about who may take
// part. Membership of the auction is the `participants` subcollection and
// nothing else.

/// How far along an auction is. The order here is the order a real one moves
/// through, and several rules key off it directly.
enum AuctionStatus {
  /// The organizer is still writing it. Visible to staff only — nobody is
  /// notified, nobody can join, and it can still be deleted outright.
  draft('draft', 'Draft'),

  /// Open for people to put their hands up, as a bidder or as a player.
  /// Purses are set during this stage; no bidding yet.
  registration('registration', 'Registration open'),

  /// Bids are being taken, privately, until [Auction.bidsCloseAt].
  bidding('bidding', 'Bidding open'),

  /// The lots have been opened and the squads are public. Trades are allowed
  /// until [Auction.exchangeClosesAt].
  revealed('revealed', 'Squads revealed'),

  /// The tournament has started. Rosters are final and nothing moves.
  locked('locked', 'Squads locked'),

  /// Called off. Kept rather than deleted so the people who registered can
  /// see what happened to it.
  cancelled('cancelled', 'Cancelled');

  const AuctionStatus(this.wire, this.label);
  final String wire;
  final String label;

  static AuctionStatus fromWire(String? w) => AuctionStatus.values.firstWhere(
        (e) => e.wire == w,
        // `draft` rather than something later: an unreadable status must never
        // fail open into a state where money can move.
        orElse: () => AuctionStatus.draft,
      );

  bool get acceptsBids => this == AuctionStatus.bidding;

  /// Whether squads, bid history and results are public. Everything about the
  /// reveal is visible from here on, including the losing bids — see
  /// [AuctionBid] for why that transparency is not optional.
  bool get isRevealed =>
      this == AuctionStatus.revealed || this == AuctionStatus.locked;
}

/// What one person is in one auction. A person may be more than one at once:
/// the owner of a side very often plays for it too, and a village organizer
/// running the thing usually also wants a team.
enum AuctionRole {
  /// Runs the auction: approves people, sets purses, opens and closes
  /// bidding, reveals, locks. The creator holds this from the start.
  organizer('organizer', 'Organizer'),

  /// Holds a purse and a squad — the franchise owner.
  bidder('bidder', 'Team owner'),

  /// In the pool, to be bought.
  player('player', 'Player'),
  ;

  const AuctionRole(this.wire, this.label);
  final String wire;
  final String label;

  static AuctionRole? fromWire(String? w) {
    for (final r in AuctionRole.values) {
      if (r.wire == w) return r;
    }
    return null;
  }
}

/// Where somebody's request to take part stands.
enum AuctionJoinStatus {
  pending('pending', 'Waiting for approval'),
  approved('approved', 'Approved'),
  declined('declined', 'Not accepted');

  const AuctionJoinStatus(this.wire, this.label);
  final String wire;
  final String label;

  static AuctionJoinStatus fromWire(String? w) =>
      AuctionJoinStatus.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => AuctionJoinStatus.pending,
      );
}

/// Where one player stands in the auction.
enum AuctionLotStatus {
  /// Available. Bids are accepted on this lot while the auction is bidding.
  pool('pool', 'In the pool'),

  /// Bought. [AuctionLot.soldToTeamId] and [AuctionLot.soldPricePaise] are
  /// set, and no further bid is accepted on this lot in any later round.
  sold('sold', 'Sold'),

  /// Went through a reveal with no bid on it at all. Still eligible for the
  /// next round if the organizer opens one — see [Auction.round].
  unsold('unsold', 'Unsold'),

  /// Pulled out by the organizer or by the player themselves before the
  /// reveal. Never bid on again.
  withdrawn('withdrawn', 'Withdrawn');

  const AuctionLotStatus(this.wire, this.label);
  final String wire;
  final String label;

  static AuctionLotStatus fromWire(String? w) =>
      AuctionLotStatus.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => AuctionLotStatus.pool,
      );
}

/// Where a proposed swap stands.
enum AuctionTradeStatus {
  proposed('proposed', 'Waiting on them'),
  accepted('accepted', 'Agreed'),
  declined('declined', 'Declined'),
  cancelled('cancelled', 'Withdrawn');

  const AuctionTradeStatus(this.wire, this.label);
  final String wire;
  final String label;

  static AuctionTradeStatus fromWire(String? w) =>
      AuctionTradeStatus.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => AuctionTradeStatus.proposed,
      );
}

/// Who can find the auction without being handed the code.
enum AuctionVisibility {
  /// Listed on the auctions board for anyone signed in.
  public('public', 'Listed publicly'),

  /// Reachable only through [Auction.joinCode]. The default, because most of
  /// these are somebody's local tournament and have no reason to be on a
  /// national board.
  unlisted('unlisted', 'Code only');

  const AuctionVisibility(this.wire, this.label);
  final String wire;
  final String label;

  static AuctionVisibility fromWire(String? w) =>
      AuctionVisibility.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => AuctionVisibility.unlisted,
      );
}

// ---------------------------------------------------------------------------
// Money
// ---------------------------------------------------------------------------

/// Rupee formatting for auction amounts.
///
/// Deliberately not `Pricing.formatPaise`, which this codebase already has.
/// That one renders zero as "Free" — correct for a shop listing and actively
/// wrong here, where ₹0 remaining is the most important number on the screen
/// and "Free" is nonsense. It also has no grouping, and auction figures are
/// lakhs: `₹100000` is misread as ₹10,000 at a glance by everyone, every
/// time.
///
/// Grouped the Indian way (2,2,3) because the people using this read
/// "one lakh", not "one hundred thousand".
class AuctionMoney {
  const AuctionMoney._();

  /// `₹1,00,000`. Paise below the rupee are dropped rather than rounded — an
  /// auction is denominated in whole rupees everywhere it is entered, so a
  /// fraction here could only come from a trade splitting an odd number, and
  /// showing two decimals on every purse to cover that would cost more than
  /// it buys.
  static String format(int paise) => '₹${groupIndian(paise ~/ 100)}';

  /// Short form for a tile where the full number will not fit: `₹1.0L`,
  /// `₹12.5K`. Falls back to the full grouped figure below ₹1,000, where
  /// abbreviating buys nothing.
  static String compact(int paise) {
    final rupees = paise ~/ 100;
    if (rupees >= 10000000) {
      return '₹${(rupees / 10000000).toStringAsFixed(1)}Cr';
    }
    if (rupees >= 100000) return '₹${(rupees / 100000).toStringAsFixed(1)}L';
    if (rupees >= 1000) return '₹${(rupees / 1000).toStringAsFixed(1)}K';
    return '₹$rupees';
  }

  /// 1234567 -> "12,34,567". The last three digits group together and
  /// everything above them groups in twos.
  static String groupIndian(int value) {
    final negative = value < 0;
    final digits = value.abs().toString();
    if (digits.length <= 3) return negative ? '-$digits' : digits;

    final tail = digits.substring(digits.length - 3);
    var head = digits.substring(0, digits.length - 3);
    final parts = <String>[];
    while (head.length > 2) {
      parts.insert(0, head.substring(head.length - 2));
      head = head.substring(0, head.length - 2);
    }
    if (head.isNotEmpty) parts.insert(0, head);
    final out = '${parts.join(',')},$tail';
    return negative ? '-$out' : out;
  }

  /// What somebody typed into a bid box, as paise, or null if it is not a
  /// usable amount.
  ///
  /// Forgiving about presentation and strict about value: `1,00,000`,
  /// `₹50000` and ` 25000 ` all parse, a negative or non-numeric does not.
  /// Entry is in whole rupees — nobody bids ₹4.37 for a fast bowler — so the
  /// multiplication by 100 is exact and no rounding decision is ever made on
  /// somebody's money.
  static int? parseRupees(String input) {
    final cleaned = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.isEmpty) return null;
    final rupees = int.tryParse(cleaned);
    if (rupees == null || rupees < 0) return null;
    // Guards a paste of forty digits from overflowing into a negative purse.
    if (rupees > 1000000000) return null;
    return rupees * 100;
  }
}

/// The public code that gets an auction into a WhatsApp group.
///
/// Same shape and the same reasoning as [PlayerCode] — an unambiguous
/// alphabet, dictatable over a phone, claimed by document id so uniqueness is
/// structural rather than checked. A different prefix so a person who has
/// been sent both can tell which box to type it into.
class AuctionCode {
  const AuctionCode._();

  static const prefix = 'PSA';

  /// Crockford's base32 minus the misread letters, identical to
  /// `PlayerCode.alphabet` and for identical reasons.
  static const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static const length = 5;

  static final _random = Random.secure();

  static String generate() {
    final buffer = StringBuffer(prefix)..write('-');
    for (var i = 0; i < length; i++) {
      buffer.write(alphabet[_random.nextInt(alphabet.length)]);
    }
    return buffer.toString();
  }

  /// What somebody typed, as what is stored, or null if it cannot be one of
  /// ours. Same two substitutions [PlayerCode.normalize] makes, for the same
  /// reason: a code read aloud turns O into zero and I into one somewhere
  /// between the two ends of the call.
  static String? normalize(String input) {
    var s = input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (s.startsWith(prefix)) s = s.substring(prefix.length);
    if (s.length != length) return null;
    s = s.replaceAll('O', '0').replaceAll('I', '1').replaceAll('L', '1');
    for (final ch in s.split('')) {
      if (!alphabet.contains(ch)) return null;
    }
    return '$prefix-$s';
  }
}

// ---------------------------------------------------------------------------
// The auction itself
// ---------------------------------------------------------------------------

/// One auction event, at `auctions/{auctionId}`.
class Auction {
  const Auction({
    required this.id,
    required this.name,
    required this.sportId,
    required this.sportName,
    required this.status,
    required this.visibility,
    required this.createdByUid,
    required this.createdByName,
    required this.joinCode,
    required this.defaultPursePaise,
    required this.defaultBasePricePaise,
    required this.round,
    this.minSquadSize,
    this.maxSquadSize,
    this.maxTeams,
    this.description,
    this.locationLabel,
    this.linkedOrgId,
    this.linkedOrgName,
    this.eventStartsAt,
    this.bidsCloseAt,
    this.exchangeClosesAt,
    this.revealedAt,
    this.lockedAt,
    this.createdAt,
    this.updatedAt,
    this.teamCount = 0,
    this.playerCount = 0,
    this.soldCount = 0,
  });

  final String id;

  /// What the organizer calls it — "Maram 2026 Dec Sports — Cricket".
  final String name;

  final String sportId;

  /// Denormalized so the board can render a row without resolving the
  /// catalogue, the same reason `Competition` carries `sportName`.
  final String sportName;

  final AuctionStatus status;
  final AuctionVisibility visibility;

  final String createdByUid;
  final String createdByName;

  /// `PSA-4K7M2`. Set once at creation and never rotated: it is written on a
  /// noticeboard and forwarded through three WhatsApp groups, and a code that
  /// changes underneath that is worse than no code.
  final String joinCode;

  /// What each approved team gets, unless the organizer overrides that team
  /// individually. "Admin gives 100K for each member (dynamic — admin may
  /// decide)" is exactly this field plus [AuctionTeam.pursePaise].
  final int defaultPursePaise;

  /// The floor under every bid. A lot may carry its own
  /// [AuctionLot.basePricePaise]; this is what a lot gets when it does not.
  final int defaultBasePricePaise;

  /// Which reveal this will be. Starts at 1 and increases every time the
  /// organizer reopens bidding on the players nobody bought — see
  /// [AuctionLotStatus.unsold]. Shown so a team can tell "nobody wanted him"
  /// from "this is his third time up".
  final int round;

  /// Advisory. Shown to a team as "you still need 4" and never enforced,
  /// because the only way to enforce it would be to force somebody to spend.
  final int? minSquadSize;

  /// Enforced, at bid time, against won players plus live bids — see
  /// `placeAuctionBid`. Null means no cap.
  final int? maxSquadSize;

  /// How many teams may be approved. Null means no cap.
  final int? maxTeams;

  final String? description;

  /// Free text — "Maram village", "Sector 7". Not a geo lookup: this is a
  /// label on a board, and the product's real location fields belong to
  /// grounds and clubs, neither of which an auction is required to have.
  final String? locationLabel;

  /// A club running this under its own name. Optional, and confers nothing:
  /// membership of that club is not membership of this auction. It exists so
  /// a club's auction can carry its crest, and so the club page can link to
  /// it.
  final String? linkedOrgId;
  final String? linkedOrgName;

  /// When the tournament itself begins. Drives the default for
  /// [exchangeClosesAt] and is what "once events started no exchange" means.
  final DateTime? eventStartsAt;

  /// The moment every lot opens. Null while the auction has not reached
  /// [AuctionStatus.bidding].
  final DateTime? bidsCloseAt;

  /// The end of the trade window. After this, squads are final even if the
  /// organizer never presses Lock — see [tradingOpenAt].
  final DateTime? exchangeClosesAt;

  final DateTime? revealedAt;
  final DateTime? lockedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Counters maintained by the server, for the board row. Never read as
  /// authority for anything — the subcollections are the truth.
  final int teamCount;
  final int playerCount;
  final int soldCount;

  bool get isOpenForJoining => status == AuctionStatus.registration;

  /// Whether a bid placed right now would be accepted. The deadline is
  /// checked as well as the status because the scheduled reveal runs every
  /// few minutes, so there is always a window in which the status still says
  /// `bidding` and the deadline has passed. The server checks the same two
  /// things; this one only greys the button out early.
  bool bidsOpenAt(DateTime now) =>
      status.acceptsBids &&
      (bidsCloseAt == null || now.isBefore(bidsCloseAt!));

  /// Whether a trade could be agreed right now. Squads have to be revealed,
  /// the auction must not be locked, and the exchange window must still be
  /// open.
  bool tradingOpenAt(DateTime now) =>
      status == AuctionStatus.revealed &&
      (exchangeClosesAt == null || now.isBefore(exchangeClosesAt!));

  /// The sentence the detail screen leads with. Written here rather than in
  /// the widget because three screens ask the same question and drifted apart
  /// when each answered it itself.
  String headline(DateTime now) {
    switch (status) {
      case AuctionStatus.draft:
        return 'Not published yet';
      case AuctionStatus.registration:
        return 'Open for players and team owners to join';
      case AuctionStatus.bidding:
        final close = bidsCloseAt;
        if (close == null) return 'Bidding is open';
        if (!now.isBefore(close)) return 'Bidding closed — revealing shortly';
        return 'Bids open until ${_when(close)}';
      case AuctionStatus.revealed:
        final close = exchangeClosesAt;
        if (close == null || !now.isBefore(close)) {
          return 'Squads revealed — trading closed';
        }
        return 'Squads revealed — trades until ${_when(close)}';
      case AuctionStatus.locked:
        return 'Squads are final';
      case AuctionStatus.cancelled:
        return 'This auction was called off';
    }
  }

  static String _when(DateTime t) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final minute = t.minute.toString().padLeft(2, '0');
    final ampm = t.hour < 12 ? 'am' : 'pm';
    return '${t.day} ${months[t.month - 1]}, $hour:$minute$ampm';
  }

  factory Auction.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Auction(
      id: doc.id,
      name: Fs.str(d['name'], 'Auction'),
      sportId: Fs.str(d['sportId'], 'cricket'),
      sportName: Fs.str(d['sportName'], 'Cricket'),
      status: AuctionStatus.fromWire(d['status'] as String?),
      visibility: AuctionVisibility.fromWire(d['visibility'] as String?),
      createdByUid: Fs.str(d['createdByUid']),
      createdByName: Fs.str(d['createdByName'], 'Organizer'),
      joinCode: Fs.str(d['joinCode']),
      defaultPursePaise: Fs.integer(d['defaultPursePaise']),
      defaultBasePricePaise: Fs.integer(d['defaultBasePricePaise']),
      round: Fs.integer(d['round'], 1),
      minSquadSize: Fs.intOrNull(d['minSquadSize']),
      maxSquadSize: Fs.intOrNull(d['maxSquadSize']),
      maxTeams: Fs.intOrNull(d['maxTeams']),
      description: Fs.strOrNull(d['description']),
      locationLabel: Fs.strOrNull(d['locationLabel']),
      linkedOrgId: Fs.strOrNull(d['linkedOrgId']),
      linkedOrgName: Fs.strOrNull(d['linkedOrgName']),
      eventStartsAt: Fs.dateOrNull(d['eventStartsAt']),
      bidsCloseAt: Fs.dateOrNull(d['bidsCloseAt']),
      exchangeClosesAt: Fs.dateOrNull(d['exchangeClosesAt']),
      revealedAt: Fs.dateOrNull(d['revealedAt']),
      lockedAt: Fs.dateOrNull(d['lockedAt']),
      createdAt: Fs.dateOrNull(d['createdAt']),
      updatedAt: Fs.dateOrNull(d['updatedAt']),
      teamCount: Fs.integer(d['teamCount']),
      playerCount: Fs.integer(d['playerCount']),
      soldCount: Fs.integer(d['soldCount']),
    );
  }

  /// The create payload. `status` is pinned to `draft` here and not taken
  /// from the caller: an auction that could be created directly into
  /// `bidding` would be one that never passed through the screen where the
  /// organizer sets the purses.
  Map<String, Object?> toCreate() => Fs.prune({
        'name': name,
        'sportId': sportId,
        'sportName': sportName,
        'status': AuctionStatus.draft.wire,
        'visibility': visibility.wire,
        'createdByUid': createdByUid,
        'createdByName': createdByName,
        'joinCode': joinCode,
        'defaultPursePaise': defaultPursePaise,
        'defaultBasePricePaise': defaultBasePricePaise,
        'round': 1,
        'minSquadSize': minSquadSize,
        'maxSquadSize': maxSquadSize,
        'maxTeams': maxTeams,
        'description': description,
        'locationLabel': locationLabel,
        'linkedOrgId': linkedOrgId,
        'linkedOrgName': linkedOrgName,
        'eventStartsAt': Fs.ts(eventStartsAt),
        'exchangeClosesAt': Fs.ts(exchangeClosesAt),
        'teamCount': 0,
        'playerCount': 0,
        'soldCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// The settings an organizer may change from the edit screen.
  ///
  /// Note what is absent: `status`, every counter, and all four outcome
  /// timestamps. Those move through the repository's named transitions and
  /// the callable functions, never through a form — see `firestore.rules`,
  /// which freezes each of them against client writes for real.
  Map<String, Object?> toSettingsUpdate() => Fs.prune({
        'name': name,
        'visibility': visibility.wire,
        'defaultPursePaise': defaultPursePaise,
        'defaultBasePricePaise': defaultBasePricePaise,
        'minSquadSize': minSquadSize,
        'maxSquadSize': maxSquadSize,
        'maxTeams': maxTeams,
        'description': description,
        'locationLabel': locationLabel,
        'eventStartsAt': Fs.ts(eventStartsAt),
        'exchangeClosesAt': Fs.ts(exchangeClosesAt),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Auction copyWith({
    String? name,
    AuctionVisibility? visibility,
    int? defaultPursePaise,
    int? defaultBasePricePaise,
    int? minSquadSize,
    int? maxSquadSize,
    int? maxTeams,
    String? description,
    String? locationLabel,
    DateTime? eventStartsAt,
    DateTime? exchangeClosesAt,
  }) =>
      Auction(
        id: id,
        name: name ?? this.name,
        sportId: sportId,
        sportName: sportName,
        status: status,
        visibility: visibility ?? this.visibility,
        createdByUid: createdByUid,
        createdByName: createdByName,
        joinCode: joinCode,
        defaultPursePaise: defaultPursePaise ?? this.defaultPursePaise,
        defaultBasePricePaise:
            defaultBasePricePaise ?? this.defaultBasePricePaise,
        round: round,
        minSquadSize: minSquadSize ?? this.minSquadSize,
        maxSquadSize: maxSquadSize ?? this.maxSquadSize,
        maxTeams: maxTeams ?? this.maxTeams,
        description: description ?? this.description,
        locationLabel: locationLabel ?? this.locationLabel,
        linkedOrgId: linkedOrgId,
        linkedOrgName: linkedOrgName,
        eventStartsAt: eventStartsAt ?? this.eventStartsAt,
        bidsCloseAt: bidsCloseAt,
        exchangeClosesAt: exchangeClosesAt ?? this.exchangeClosesAt,
        revealedAt: revealedAt,
        lockedAt: lockedAt,
        createdAt: createdAt,
        updatedAt: updatedAt,
        teamCount: teamCount,
        playerCount: playerCount,
        soldCount: soldCount,
      );
}

// ---------------------------------------------------------------------------
// Participants
// ---------------------------------------------------------------------------

/// One person's standing in one auction, at
/// `auctions/{auctionId}/participants/{uid}`.
///
/// ## Why the document id is the uid
///
/// It makes "one row per person per auction" structural rather than checked,
/// the same trick `members/{uid}` uses — pressing Join twice from two phones
/// cannot produce two rows, and the security rules can answer "is the caller
/// a participant" with an `exists()` on a path they can build, with no query.
///
/// ## Why this is one collection rather than three
///
/// Teams and lots could each have carried their own membership. They do not,
/// because "which auctions am I in" is a collection-group query and three
/// collections would mean three of them, unioned on the client, each needing
/// its own rule and its own index. One row per person, with a `roles` list,
/// answers it in one query — and it is also the only place that can represent
/// the common case honestly: the man who owns a side AND plays for it.
class AuctionParticipant {
  const AuctionParticipant({
    required this.uid,
    required this.auctionId,
    required this.auctionName,
    required this.displayName,
    required this.roles,
    required this.status,
    this.photoUrl,
    this.playerCode,
    this.note,
    this.decidedByUid,
    this.createdAt,
    this.decidedAt,
  });

  /// Also the document id.
  final String uid;

  /// The parent, repeated on the document so the collection-group query that
  /// finds "my auctions" can route to each one without walking the path.
  final String auctionId;

  /// Denormalized so the "my auctions" list renders from one query rather
  /// than N document reads. Refreshed only on join; a renamed auction shows
  /// its old name in that one list until the person opens it, which is the
  /// right trade against a fan-out write across every participant.
  final String auctionName;

  final String displayName;
  final String? photoUrl;
  final String? playerCode;

  /// What they are here as. A list, not a single value — see the class doc.
  final Set<AuctionRole> roles;

  final AuctionJoinStatus status;

  /// What they wrote when asking to join — "I keep wicket", "I can bring a
  /// team of 11". The organizer reads these to decide.
  final String? note;

  final String? decidedByUid;
  final DateTime? createdAt;
  final DateTime? decidedAt;

  bool get isOrganizer => roles.contains(AuctionRole.organizer);
  bool get isBidder => roles.contains(AuctionRole.bidder);
  bool get isPlayer => roles.contains(AuctionRole.player);
  bool get isApproved => status == AuctionJoinStatus.approved;

  /// Approved AND holding the role. The pair is asked for often enough, and
  /// getting it wrong means showing a bid box to somebody whose application
  /// the organizer has not looked at yet.
  bool get canBid => isApproved && isBidder;

  String get rolesLabel {
    final parts = [
      if (isOrganizer) 'Organizer',
      if (isBidder) 'Team owner',
      if (isPlayer) 'Player',
    ];
    return parts.isEmpty ? 'Participant' : parts.join(' · ');
  }

  factory AuctionParticipant.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const {};
    return AuctionParticipant(
      uid: Fs.str(d['uid'], doc.id),
      auctionId: Fs.str(d['auctionId']),
      auctionName: Fs.str(d['auctionName'], 'Auction'),
      displayName: Fs.str(d['displayName'], 'Player'),
      photoUrl: Fs.strOrNull(d['photoUrl']),
      playerCode: Fs.strOrNull(d['playerCode']),
      roles: {
        for (final w in Fs.strList(d['roles']))
          if (AuctionRole.fromWire(w) != null) AuctionRole.fromWire(w)!,
      },
      status: AuctionJoinStatus.fromWire(d['status'] as String?),
      note: Fs.strOrNull(d['note']),
      decidedByUid: Fs.strOrNull(d['decidedByUid']),
      createdAt: Fs.dateOrNull(d['createdAt']),
      decidedAt: Fs.dateOrNull(d['decidedAt']),
    );
  }

  Map<String, Object?> toCreate() => Fs.prune({
        'uid': uid,
        'auctionId': auctionId,
        'auctionName': auctionName,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'playerCode': playerCode,
        'roles': roles.map((r) => r.wire).toList(),
        'status': status.wire,
        'note': note,
        'createdAt': FieldValue.serverTimestamp(),
      });
}

// ---------------------------------------------------------------------------
// Teams
// ---------------------------------------------------------------------------

/// A side with a purse, at `auctions/{auctionId}/teams/{teamId}`, where
/// `teamId` IS the owning uid.
///
/// ## Why teamId is the owner's uid
///
/// One person, one side. It removes a whole class of lookup — every rule that
/// asks "is the caller this team's owner" compares two path segments instead
/// of reading a document — and it makes "this person already has a team"
/// impossible to get wrong. A co-owned side is not supported, and that is a
/// deliberate limit rather than an oversight: the alternative is a members
/// list on a document that also holds a spendable balance, and two people
/// spending the same purse from two phones is the one race this design exists
/// to avoid.
///
/// ## The three money fields
///
/// * [pursePaise] — what the organizer gave them. Only an organizer changes it.
/// * [committedPaise] — locked behind live bids that have not been resolved.
/// * [spentPaise] — actually paid, for players actually held.
///
/// Only `placeAuctionBid`, the reveal and `executeAuctionTrade` ever write the
/// last two, all inside transactions. See [availablePaise] for the number a
/// bidder actually looks at.
class AuctionTeam {
  const AuctionTeam({
    required this.id,
    required this.auctionId,
    required this.ownerUid,
    required this.ownerName,
    required this.name,
    required this.pursePaise,
    required this.committedPaise,
    required this.spentPaise,
    required this.wonCount,
    required this.liveBidCount,
    this.logoUrl,
    this.ownerPhotoUrl,
    this.createdAt,
    this.updatedAt,
  });

  /// Also the owner's uid, and also the document id. See the class doc.
  final String id;

  final String auctionId;
  final String ownerUid;
  final String ownerName;
  final String? ownerPhotoUrl;

  /// The side's name — "Maram Warriors". Defaults to the owner's name plus
  /// "XI" when they cannot think of one.
  final String name;
  final String? logoUrl;

  final int pursePaise;
  final int committedPaise;
  final int spentPaise;

  /// Players held. Maintained by the same transactions that move the money,
  /// so squad-size enforcement never has to count a subcollection inside a
  /// rule.
  final int wonCount;

  /// Live bids on lots still in the pool. Together with [wonCount] this is
  /// what `maxSquadSize` is checked against at bid time — every live bid is a
  /// player this team might be about to own.
  final int liveBidCount;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// What this team may still commit to a new bid. THE number on the bidding
  /// screen.
  int get availablePaise => pursePaise - committedPaise;

  /// What is left after the reveal, for trades. Distinct from
  /// [availablePaise] because after a reveal `committedPaise` and
  /// `spentPaise` agree, and before one they emphatically do not.
  int get remainingPaise => pursePaise - spentPaise;

  /// How much of the purse is doing something, 0..1. For the bar on the team
  /// card. Guards a zero purse, which an organizer can legitimately set for a
  /// no-money "pick teams by lot" auction.
  double get committedFraction =>
      pursePaise <= 0 ? 0 : (committedPaise / pursePaise).clamp(0, 1);

  factory AuctionTeam.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return AuctionTeam(
      id: doc.id,
      auctionId: Fs.str(d['auctionId']),
      ownerUid: Fs.str(d['ownerUid'], doc.id),
      ownerName: Fs.str(d['ownerName'], 'Owner'),
      ownerPhotoUrl: Fs.strOrNull(d['ownerPhotoUrl']),
      name: Fs.str(d['name'], 'Team'),
      logoUrl: Fs.strOrNull(d['logoUrl']),
      pursePaise: Fs.integer(d['pursePaise']),
      committedPaise: Fs.integer(d['committedPaise']),
      spentPaise: Fs.integer(d['spentPaise']),
      wonCount: Fs.integer(d['wonCount']),
      liveBidCount: Fs.integer(d['liveBidCount']),
      createdAt: Fs.dateOrNull(d['createdAt']),
      updatedAt: Fs.dateOrNull(d['updatedAt']),
    );
  }
}

// ---------------------------------------------------------------------------
// Lots
// ---------------------------------------------------------------------------

/// One player on the block, at `auctions/{auctionId}/lots/{lotId}`, where
/// `lotId` IS the player's uid — same structural-uniqueness reasoning as
/// [AuctionTeam].
///
/// ## Why the stats are copied onto this document
///
/// [statLine] and [matchesPlayed] are a snapshot of the player's real career
/// record, taken when the organizer approves them into the pool. The live
/// record still exists and the lot screen reads it — see `careerProvider` —
/// but a pool of sixty players cannot open sixty extra listeners to render a
/// list. The copy is for the list; the live read is for the one player
/// somebody has actually tapped.
class AuctionLot {
  const AuctionLot({
    required this.id,
    required this.auctionId,
    required this.playerUid,
    required this.displayName,
    required this.status,
    required this.basePricePaise,
    required this.bidCount,
    this.photoUrl,
    this.playerCode,
    this.roleLabel,
    this.statLine,
    this.matchesPlayed = 0,
    this.wins = 0,
    this.ratingLabel,
    this.soldToTeamId,
    this.soldToTeamName,
    this.soldPricePaise,
    this.soldInRound,
    this.acquiredBy,
    this.createdAt,
    this.resolvedAt,
  });

  final String id;
  final String auctionId;

  /// Also [id]. Kept as a field so a rule and a query can both reach it.
  final String playerUid;

  final String displayName;
  final String? photoUrl;
  final String? playerCode;

  /// What the player says they are — "Batter", "Left-arm spin". Free text
  /// they write on joining, because a per-sport position vocabulary is a
  /// different feature and an empty dropdown would have taught them nothing.
  final String? roleLabel;

  final AuctionLotStatus status;

  /// The floor under a bid on this lot. Seeded from
  /// [Auction.defaultBasePricePaise] and overridable per player, because a
  /// village league does price its two best bowlers differently.
  final int basePricePaise;

  /// How many teams have a live bid on this lot.
  ///
  /// A COUNT, never the amounts, and this is the load-bearing distinction in
  /// the whole design. It is on the lot document, which everyone can read;
  /// the amounts live one level down in `bids/{teamId}`, which nobody but the
  /// bidder can read until the reveal. So the pool can honestly say "3 teams
  /// are interested in him" — which is most of what makes an auction feel
  /// alive — without leaking a single figure anyone could bid against.
  final int bidCount;

  /// Career snapshot, for the list. See the class doc.
  final String? statLine;
  final int matchesPlayed;
  final int wins;
  final String? ratingLabel;

  final String? soldToTeamId;
  final String? soldToTeamName;
  final int? soldPricePaise;

  /// Which round took them. Lets the squad screen show "Round 2" beside a
  /// player who went unsold first time.
  final int? soldInRound;

  /// `auction` or `trade` — how the current holder got them. A squad list
  /// that cannot tell a bought player from a traded one loses the story the
  /// exchange window exists to create.
  final String? acquiredBy;

  final DateTime? createdAt;
  final DateTime? resolvedAt;

  bool get isSold => status == AuctionLotStatus.sold;
  bool get isBiddable => status == AuctionLotStatus.pool;

  /// The line under the name in the pool list.
  String get summaryLine {
    final line = statLine;
    if (line != null && line.isNotEmpty) return line;
    if (matchesPlayed > 0) {
      return '$matchesPlayed match${matchesPlayed == 1 ? '' : 'es'} · $wins won';
    }
    return 'No matches on record yet';
  }

  factory AuctionLot.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return AuctionLot(
      id: doc.id,
      auctionId: Fs.str(d['auctionId']),
      playerUid: Fs.str(d['playerUid'], doc.id),
      displayName: Fs.str(d['displayName'], 'Player'),
      photoUrl: Fs.strOrNull(d['photoUrl']),
      playerCode: Fs.strOrNull(d['playerCode']),
      roleLabel: Fs.strOrNull(d['roleLabel']),
      status: AuctionLotStatus.fromWire(d['status'] as String?),
      basePricePaise: Fs.integer(d['basePricePaise']),
      bidCount: Fs.integer(d['bidCount']),
      statLine: Fs.strOrNull(d['statLine']),
      matchesPlayed: Fs.integer(d['matchesPlayed']),
      wins: Fs.integer(d['wins']),
      ratingLabel: Fs.strOrNull(d['ratingLabel']),
      soldToTeamId: Fs.strOrNull(d['soldToTeamId']),
      soldToTeamName: Fs.strOrNull(d['soldToTeamName']),
      soldPricePaise: Fs.intOrNull(d['soldPricePaise']),
      soldInRound: Fs.intOrNull(d['soldInRound']),
      acquiredBy: Fs.strOrNull(d['acquiredBy']),
      createdAt: Fs.dateOrNull(d['createdAt']),
      resolvedAt: Fs.dateOrNull(d['resolvedAt']),
    );
  }
}

// ---------------------------------------------------------------------------
// Bids
// ---------------------------------------------------------------------------

/// One team's sealed offer for one player, at
/// `auctions/{auctionId}/lots/{lotId}/bids/{teamId}`.
///
/// ## Secrecy is the path, not a field
///
/// There is no "hidden" flag and no server-side redaction. The document id IS
/// the bidding team's id, so the security rule that keeps a bid private is one
/// line — `teamId == uid()` — and it cannot be got round by a crafted query,
/// because there is no query that returns a document whose path the caller
/// cannot already write down. Firestore rules cannot hide a FIELD from a
/// reader who may read the document, so anything short of putting the secret
/// in its own document would have leaked it.
///
/// ## And why every bid becomes public at the reveal
///
/// The moment the lots open, the same rule lets everybody read every bid. That
/// is not an afterthought. An auction where only the winning price is
/// published asks five team owners to trust arithmetic they cannot check, and
/// the first person who believes they were robbed takes the whole league down
/// with them. Publishing the losing bids makes the result verifiable by hand
/// by anybody who cares to — which is the only form of trust that survives a
/// disagreement at a ground.
///
/// ## Why no client ever writes one
///
/// A bid and the purse it locks have to move together or the budget means
/// nothing, so every write goes through `placeAuctionBid` in a transaction and
/// `firestore.rules` denies the path to clients outright. Clients read; the
/// server writes.
class AuctionBid {
  const AuctionBid({
    required this.teamId,
    required this.lotId,
    required this.auctionId,
    required this.teamName,
    required this.amountPaise,
    required this.round,
    this.playerName,
    this.isWinning = false,
    this.amountSetAt,
    this.createdAt,
  });

  /// Also the document id, and also the bidding team's owner's uid.
  final String teamId;

  final String lotId;
  final String auctionId;

  /// Denormalized so the revealed bid list renders without joining to teams.
  final String teamName;

  /// Denormalized for "my bids", which lists across lots.
  final String? playerName;

  final int amountPaise;

  /// Which round this bid was placed in. A bid from an earlier round on a
  /// lot that has since been sold is history and is never resolved again.
  final int round;

  /// Set by the reveal. Not trusted for anything — [AuctionLot.soldToTeamId]
  /// is the record — but it saves the bid list from re-deriving the maximum
  /// to draw one tick.
  final bool isWinning;

  /// When the AMOUNT last changed, which is what breaks ties at the reveal —
  /// not when the row was created. Raising your bid restarts your seniority,
  /// which is the reading that cannot be gamed: otherwise the way to win a
  /// tie is to bid ₹1 on day one and raise it in the last minute.
  final DateTime? amountSetAt;

  final DateTime? createdAt;

  factory AuctionBid.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return AuctionBid(
      teamId: Fs.str(d['teamId'], doc.id),
      lotId: Fs.str(d['lotId']),
      auctionId: Fs.str(d['auctionId']),
      teamName: Fs.str(d['teamName'], 'Team'),
      playerName: Fs.strOrNull(d['playerName']),
      amountPaise: Fs.integer(d['amountPaise']),
      round: Fs.integer(d['round'], 1),
      isWinning: Fs.boolean(d['isWinning']),
      amountSetAt: Fs.dateOrNull(d['amountSetAt']),
      createdAt: Fs.dateOrNull(d['createdAt']),
    );
  }
}

// ---------------------------------------------------------------------------
// Trades
// ---------------------------------------------------------------------------

/// A proposed swap between two squads, at
/// `auctions/{auctionId}/trades/{tradeId}`.
///
/// ## The window
///
/// Trades exist only between the reveal and the start of the event — the
/// "player exchange program before the event starts only" requirement. Two
/// independent gates close it: [Auction.exchangeClosesAt], which the organizer
/// sets to whatever they want (two days, a week, the morning of the first
/// match), and [AuctionStatus.locked], which the organizer can trigger by
/// hand the moment the first ball is bowled. Either one alone is enough to
/// refuse a trade, so an organizer who forgets to press Lock is still
/// protected by the date, and one whose event starts early is still protected
/// by the button.
///
/// ## Why cash is allowed to move
///
/// A straight player-for-player swap is almost never a fair one, and an
/// exchange window where nothing is ever fair is one nobody uses. Cash makes
/// the trade that both sides actually want expressible. It is bounded by what
/// the sending team has left unspent, checked in the same transaction that
/// moves the players.
///
/// ## Why acceptance is a separate step from execution
///
/// The counterparty ACCEPTS here, as an ordinary rules-governed write; the
/// roster then moves in `executeAuctionTrade`. Splitting them means the
/// accept can never half-apply — a client that dies between the two leaves a
/// trade marked accepted and un-executed, which the function is idempotent
/// about and will finish.
class AuctionTrade {
  const AuctionTrade({
    required this.id,
    required this.auctionId,
    required this.fromTeamId,
    required this.fromTeamName,
    required this.toTeamId,
    required this.toTeamName,
    required this.fromLotIds,
    required this.toLotIds,
    required this.fromCashPaise,
    required this.toCashPaise,
    required this.status,
    this.fromLotNames = const [],
    this.toLotNames = const [],
    this.note,
    this.executedAt,
    this.createdAt,
    this.decidedAt,
  });

  final String id;
  final String auctionId;

  /// Who proposed it, and whose players [fromLotIds] are.
  final String fromTeamId;
  final String fromTeamName;

  /// Who has to answer.
  final String toTeamId;
  final String toTeamName;

  /// Players leaving [fromTeamId]. May be empty — a pure cash offer for
  /// somebody else's player is a real thing to want to send.
  final List<String> fromLotIds;
  final List<String> toLotIds;

  /// Names alongside the ids so the inbox row reads as a sentence without
  /// resolving every lot.
  final List<String> fromLotNames;
  final List<String> toLotNames;

  /// Cash from the proposer to the other side, and back the other way. Both
  /// may be zero; at most one should be non-zero, which the composer enforces
  /// because "I pay you ₹5,000 and you pay me ₹3,000" is a ₹2,000 offer
  /// written confusingly.
  final int fromCashPaise;
  final int toCashPaise;

  final AuctionTradeStatus status;
  final String? note;

  final DateTime? executedAt;
  final DateTime? createdAt;
  final DateTime? decidedAt;

  bool get isPending => status == AuctionTradeStatus.proposed;
  bool get isDone => executedAt != null;

  /// "2 players + ₹5,000 for 1 player" — the one-line summary an inbox row
  /// needs. Built here so the inbox and the detail sheet cannot disagree.
  String get summary {
    String side(List<String> lots, int cash) {
      final parts = <String>[
        if (lots.isNotEmpty)
          '${lots.length} player${lots.length == 1 ? '' : 's'}',
        if (cash > 0) AuctionMoney.format(cash),
      ];
      return parts.isEmpty ? 'nothing' : parts.join(' + ');
    }

    return '${side(fromLotIds, fromCashPaise)} for '
        '${side(toLotIds, toCashPaise)}';
  }

  factory AuctionTrade.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return AuctionTrade(
      id: doc.id,
      auctionId: Fs.str(d['auctionId']),
      fromTeamId: Fs.str(d['fromTeamId']),
      fromTeamName: Fs.str(d['fromTeamName'], 'Team'),
      toTeamId: Fs.str(d['toTeamId']),
      toTeamName: Fs.str(d['toTeamName'], 'Team'),
      fromLotIds: Fs.strList(d['fromLotIds']),
      toLotIds: Fs.strList(d['toLotIds']),
      fromLotNames: Fs.strList(d['fromLotNames']),
      toLotNames: Fs.strList(d['toLotNames']),
      fromCashPaise: Fs.integer(d['fromCashPaise']),
      toCashPaise: Fs.integer(d['toCashPaise']),
      status: AuctionTradeStatus.fromWire(d['status'] as String?),
      note: Fs.strOrNull(d['note']),
      executedAt: Fs.dateOrNull(d['executedAt']),
      createdAt: Fs.dateOrNull(d['createdAt']),
      decidedAt: Fs.dateOrNull(d['decidedAt']),
    );
  }

  Map<String, Object?> toCreate() => Fs.prune({
        'auctionId': auctionId,
        'fromTeamId': fromTeamId,
        'fromTeamName': fromTeamName,
        'toTeamId': toTeamId,
        'toTeamName': toTeamName,
        'fromLotIds': fromLotIds,
        'toLotIds': toLotIds,
        'fromLotNames': fromLotNames,
        'toLotNames': toLotNames,
        'fromCashPaise': fromCashPaise,
        'toCashPaise': toCashPaise,
        // Pinned, not taken from the caller, for the same reason
        // `Auction.toCreate` pins its status: a trade that could be created
        // already `accepted` is one that never passed the other team's screen.
        'status': AuctionTradeStatus.proposed.wire,
        'note': note,
        // Both teams on one array so the inbox is a single query — see
        // `AuctionRepository.watchMyTrades`.
        'teamIds': [fromTeamId, toTeamId],
        'createdAt': FieldValue.serverTimestamp(),
      });
}
