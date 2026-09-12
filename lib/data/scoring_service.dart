import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/errors/app_exception.dart';
import '../core/firebase/firestore_refs.dart';
import '../core/models/draw_slot.dart' show Bracket;
import '../core/models/enums.dart';
import '../core/models/fixture.dart';
import '../core/sync/sync_batch_planner.dart';
import '../core/sync/sync_queue_entry.dart';
import '../core/sync/uuid_v7.dart';
import '../domain/cheer.dart';
import '../domain/scoring/match_award.dart';
import '../domain/scoring/scoring_plugin.dart';
import '../domain/scoring/scoring_registry.dart';
import 'competition_repository.dart';
import 'org_repository.dart' show guard, guardStream;
import 'rating_service.dart';

/// Writes match events and keeps the fixture's live projection in step.
///
/// ## Why it is built this way
///
/// The append-only `events` subcollection is the truth; `fixture.scoreState`
/// is a cache of it. That split buys three things at once:
///
///  * **Spectators are cheap.** Someone following from an office holds one
///    document listener, not a listener over a growing collection. Ten
///    thousand viewers cost ten thousand small reads, not ten thousand
///    reads *per ball*.
///  * **Disputes are answerable.** Replaying the event log reproduces the
///    score exactly, so "the scorer added two runs that never happened" is a
///    checkable claim rather than an argument.
///  * **Offline works honestly.** A queued event is a fact with an
///    idempotency key, so replaying after reconnection cannot double-count.
///
/// ## The concurrency guard
///
/// Each event document id is its zero-padded sequence number. Firestore's
/// `create` fails when a document already exists, so two scorers acting on
/// the same ball cannot both win — the loser is rejected and re-syncs. No
/// locks, no transactions across collections, no server code required.
class ScoringService {
  /// Takes no [RatingService] any more, deliberately.
  ///
  /// It used to, and fired a projection on every completed match whose result
  /// was discarded — see the note in [submit]. Ratings are settled by
  /// `onMatchSettled`, so the scoring path has no rating dependency at all and
  /// should not be able to acquire one by accident.
  ScoringService({SharedPreferences? prefs}) : _prefs = prefs;

  SharedPreferences? _prefs;

  static const _queueKey = 'playsphere_pending_score_events_v1';

  Future<SharedPreferences> get _store async =>
      _prefs ??= await SharedPreferences.getInstance();

  final StreamController<AppException> _failures =
      StreamController<AppException>.broadcast();

  /// Failures that happen *after* [submit] has returned.
  ///
  /// The commit is deliberately not awaited (see [submit]), so a rejected
  /// write — a lost race for a sequence number, or a rules rejection —
  /// cannot be delivered by throwing. The pad listens here instead and tells
  /// the scorer, which is the only honest way to report it without freezing
  /// the screen until the server answers.
  Stream<AppException> get writeFailures => _failures.stream;

  final StreamController<void> _resyncs = StreamController<void>.broadcast();

  /// Fires when a write lost a race and the score is being taken from the
  /// authoritative log instead.
  ///
  /// ## Why this is not on [writeFailures]
  ///
  /// It used to be, and scorers saw "Someone else scored this first" as an
  /// error snackbar on a routine, self-healing condition. It is neither a
  /// fault nor something the scorer can act on: the fixture document is
  /// server-authoritative, Firestore rolls the rejected local mutation back,
  /// and the snapshot listener the pad is already rendering from delivers the
  /// winning state a moment later. The board corrects itself whether or not
  /// anybody is told.
  ///
  /// So the recovery is silent and the NOTIFICATION is separate and calm —
  /// the scorer needs to know the number they are looking at just changed
  /// under them, which is different from being told something went wrong.
  Stream<void> get resyncs => _resyncs.stream;

  final StreamController<int> _pendingCountController =
      StreamController<int>.broadcast();

  /// Live count of queued events not yet confirmed by the server.
  ///
  /// A one-shot `Future` (see [pendingCount]) is wrong for a badge that stays
  /// on screen for the length of a match: it is correct exactly once, at the
  /// first frame it is read, and then silently stale for everything after —
  /// a `FutureBuilder` fed from it shows "3 pending" forever after the queue
  /// has actually drained to zero, or stays at "0" after twenty more actions
  /// have queued behind a dropped connection. This recomputes and pushes a
  /// fresh count after every enqueue, dequeue and reconcile pass, so a
  /// listener stays honest for as long as it is subscribed. Each new
  /// listener is given the current count immediately, then live updates —
  /// it is a `Stream`, not a delta feed, so `StreamBuilder` needs no
  /// separate initial fetch.
  /// Subscribes FIRST, then reads.
  ///
  /// Written the other way round — await the count, then forward the
  /// controller — there is a gap between the two during which this stream is
  /// subscribed to nothing, and an enqueue landing inside it is dropped. The
  /// badge then sits on a stale number until the next unrelated action nudges
  /// it. Attaching to the controller before the await closes the gap; the
  /// initial value is emitted ahead of anything buffered, so a listener still
  /// sees a count on its first frame.
  Stream<int> get pendingCountStream {
    final out = StreamController<int>();
    StreamSubscription<int>? sub;

    out.onListen = () {
      // Forward first, so nothing enqueued while the initial read is in flight
      // is lost.
      sub = _pendingCountController.stream.listen(
        out.add,
        onError: out.addError,
        onDone: out.close,
      );
      // Then the current value, so a `StreamBuilder` has something on its very
      // first frame without a separate fetch.
      pendingCount().then((n) {
        if (!out.isClosed) out.add(n);
      });
    };
    out.onCancel = () async => sub?.cancel();

    return out.stream;
  }

  Future<void> _notifyPendingCountChanged() async {
    // No `hasListener` guard. On a broadcast controller that is only true once
    // somebody is already attached, so the very first update after a subscribe
    // could be swallowed by the race the getter above exists to close. Adding
    // to a broadcast controller with no listeners is a no-op, not an error.
    if (_pendingCountController.isClosed) return;
    _pendingCountController.add(await pendingCount());
  }

  void dispose() {
    _failures.close();
    _resyncs.close();
    _pendingCountController.close();
  }

  /// Reports a rejected write on the right channel for what it is.
  ///
  /// A conflict is expected and self-healing, so it goes to [resyncs].
  /// Everything else — a network failure, a rules rejection, a bad payload —
  /// is something the scorer has to know about and goes to [writeFailures].
  void _report(AppException error) {
    if (error is ConflictException) {
      if (!_resyncs.isClosed) _resyncs.add(null);
      return;
    }
    if (!_failures.isClosed) _failures.add(error);
  }

  // --- Reads ------------------------------------------------------------

  /// The one listener a spectator needs.
  Stream<Fixture?> watchFixture(
          String orgId, String compId, String fixtureId) =>
      guardStream(
        () => Refs.fixture(orgId, compId, fixtureId).snapshots().map(
              (doc) => doc.exists ? Fixture.fromDoc(doc) : null,
            ),
      );

  /// Ball-by-ball commentary feed. Only opened on screens that actually show
  /// the timeline, never just to display a score.
  Stream<List<MatchEvent>> watchEvents(
    String orgId,
    String compId,
    String fixtureId, {
    int limit = 60,
  }) {
    return guardStream(
      () => Refs.matchEvents(orgId, compId, fixtureId)
          .orderBy('seq', descending: true)
          .limit(limit)
          .snapshots()
          .map((snap) => snap.docs.map(MatchEvent.fromDoc).toList()),
    );
  }

  /// [source] exists for the replay path, which must never read the local
  /// cache: the cache contains this device's own unacknowledged writes, so a
  /// cached log would report a queued action as confirmed and the queue would
  /// drop the only durable record of it. See [_replayFixtureGroup].
  Future<List<MatchEvent>> fetchAllEvents(
    String orgId,
    String compId,
    String fixtureId, {
    Source source = Source.serverAndCache,
  }) async {
    final snap = await Refs.matchEvents(orgId, compId, fixtureId)
        .orderBy('seq')
        .get(GetOptions(source: source));
    return snap.docs.map(MatchEvent.fromDoc).toList();
  }

  // --- Cheering ---------------------------------------------------------

  /// Live cheer tally for a match, and what [myUid] has sent.
  ///
  /// One listener over a small collection rather than a counter on the fixture
  /// document. The fixture is the hottest document in the product — every ball
  /// rewrites it — and putting a cheer counter on it would mean every cheer
  /// from every spectator contending with the scorer's writes for the same
  /// document. A cheer must never be able to slow down or lose a delivery.
  Stream<CheerTally> watchCheers({
    required String orgId,
    required String compId,
    required String fixtureId,
    String? myUid,
  }) =>
      guardStream(
        () => Refs.cheers(orgId, compId, fixtureId).snapshots().map((snap) {
          final forA = <Cheer, int>{};
          final forB = <Cheer, int>{};
          Cheer? mine;
          String? mineSide;

          for (final doc in snap.docs) {
            final data = doc.data();
            final cheer = Cheer.fromWire(data['cheer'] as String?);
            if (cheer == null) continue;
            final side = data['side'] == 'b' ? 'b' : 'a';
            final bucket = side == 'a' ? forA : forB;
            bucket[cheer] = (bucket[cheer] ?? 0) + 1;
            if (doc.id == myUid) {
              mine = cheer;
              mineSide = side;
            }
          }
          return CheerTally(
            forA: forA,
            forB: forB,
            mine: mine,
            mineSide: mineSide,
          );
        }),
      );

  /// Sends, changes or takes back a cheer.
  ///
  /// The document id is the sender's uid, so cheering twice replaces rather
  /// than adds. Passing the same [cheer] and [side] again withdraws it, which
  /// is what makes the button a toggle: somebody who cheered the wrong team by
  /// accident should be able to undo it without an extra control.
  ///
  /// Deliberately not awaited by callers on the hot path, and deliberately
  /// tolerant of failure — a cheer that does not send is not worth an error
  /// message in front of somebody watching a match.
  Future<void> sendCheer({
    required String orgId,
    required String compId,
    required String fixtureId,
    required String uid,
    required Cheer? cheer,
    required String side,
  }) =>
      guard(() async {
        final ref = Refs.cheer(orgId, compId, fixtureId, uid);
        if (cheer == null) {
          await ref.delete();
          return;
        }
        await ref.set({
          'cheer': cheer.wire,
          'side': side,
          'at': FieldValue.serverTimestamp(),
        });
      });

  // --- Writing ----------------------------------------------------------

  /// Applies [action] to [fixture] and persists both the event and the
  /// updated projection in one atomic batch.
  ///
  /// Returns the updated fixture so the pad can render immediately; the
  /// Firestore listener will deliver the same state moments later.
  /// Returns SYNCHRONOUSLY. There is no `await` between the scorer's tap and
  /// the number changing on their own screen.
  ///
  /// ## The bug this shape exists for
  ///
  /// This used to be `Future<Fixture>` and the pad awaited it. Nothing on the
  /// network was awaited even then — the commit was already fire-and-forget —
  /// but `_enqueue` was, and that is a `SharedPreferences` read, a re-encode
  /// of the WHOLE queue, and a disk write through a platform channel, on
  /// every single tap. The queue only shrinks when the server acknowledges an
  /// event, so during a match played out of signal it grows monotonically and
  /// that per-tap cost grows with it: the pad got slower the longer the match
  /// went on. Meanwhile the pad disabled every button behind `_busy` until
  /// the future returned, so the cost was not just latency — it was a dead
  /// pad, and taps made during it were swallowed entirely.
  ///
  /// Everything on this path that a scorer must wait for is pure computation:
  /// validate the action against the current projection, fold it in, build
  /// the batch. That is microseconds. The durable enqueue and the commit are
  /// chained behind it and run on their own time — in that order, so the
  /// "record it before the write leaves" guarantee below is unchanged.
  ///
  /// The caller gets the new projection back immediately and is expected to
  /// RENDER IT, rather than waiting for the fixture listener to echo it. See
  /// `_ScoringScreenState._local`.
  Fixture submit({
    required Fixture fixture,
    required ScoreAction action,
    required ScoringContext context,
    required String byUid,
  }) {
    _assertHoldsPen(fixture, byUid);
    _assertNotDecided(fixture);
    final plugin = ScoringRegistry.resolve(fixture.scoringPluginKey);

    // Validate against the current projection first. A rejected action never
    // reaches the network, so an illegal press costs nothing and the scorer
    // gets an instant, specific reason.
    final result = plugin.apply(fixture.scoreState, action, context);
    if (!result.isAccepted) {
      throw ValidationException(
          result.rejection ?? 'That move is not allowed.');
    }

    final nextSeq = fixture.lastSeq + 1;
    final outcome = plugin.outcome(result.state, context);
    final clientEventId = _clientEventId();

    final updated = fixture.copyWith(
      scoreState: result.state,
      lastSeq: nextSeq,
      summary: plugin.summary(result.state, context),
      status: outcome.isComplete ? FixtureStatus.completed : FixtureStatus.live,
      winnerEntrantId: outcome.isComplete
          ? _entrantIdForSide(fixture, outcome.winnerSide)
          : null,
      // An action that takes a finished match back to in-progress — a
      // correction after a reopen — must drop the recorded winner, not
      // quietly keep it.
      clearWinner: !outcome.isComplete,
      isDraw: outcome.isDraw,
    );

    final batch = Refs.db.batch();

    batch.set(
      Refs.matchEvents(fixture.orgId, fixture.compId, fixture.id)
          .doc(MatchEvent.docId(nextSeq)),
      MatchEvent(
        seq: nextSeq,
        type: action.type,
        payload: action.toEventPayload(),
        byUid: byUid,
        clientEventId: clientEventId,
      ).toCreate(),
    );

    batch.update(
      Refs.fixture(fixture.orgId, fixture.compId, fixture.id),
      {
        'scoreState': updated.scoreState,
        'lastSeq': updated.lastSeq,
        'summary': updated.summary,
        'status': updated.status.wire,
        'winnerEntrantId': updated.winnerEntrantId,
        'isDraw': updated.isDraw,
        if (fixture.lastSeq == 0) 'startedAt': FieldValue.serverTimestamp(),
        if (outcome.isComplete) 'completedAt': FieldValue.serverTimestamp(),
        // The heartbeat that lets a reader tell a match in progress from one
        // somebody walked away from. Written on EVERY action, undos included,
        // because an undo is a scorer at the pad just as much as a run is.
        'lastEventAt': FieldValue.serverTimestamp(),
        // The best performer is decided in the SAME batch as the result. Any
        // later and there is a window where the match is over but the award
        // is still being worked out — and, worse, it would need a network
        // round trip on a ground that may not have one.
        if (outcome.isComplete) 'mvp': _awardFor(updated)?.toMap(),
      },
    );

    // A knockout winner advances into the next round in the SAME batch as the
    // result that produced them. Doing it afterwards would leave a window
    // where the semi-final is decided but the final still reads "To be
    // decided", and any failure in between would strand the bracket there
    // permanently — which is exactly what happened before: the generator
    // recorded where a winner should go and nothing ever read it. Shared
    // with the offline queue's replay path (see [_replayFixtureGroup]) so a
    // completing event that only lands during a reconnect advances the
    // bracket exactly the same way one scored live does.
    _maybeAdvanceWinner(batch, fixture, outcome, updated.winnerEntrantId);

    // This device has now spoken for sequence [nextSeq] on this fixture, and
    // the replay path must not write a projection that predates it. See
    // [_localHead].
    _noteLocalHead(fixture, nextSeq);

    // NOT a rating write, and no longer a rating READ either.
    //
    // `RatingService.processMatchRatings` stopped persisting anything when
    // settlement moved into `onMatchSettled`; what stayed behind was a call
    // that performed one Firestore read PER PLAYER and then threw the answer
    // away — the future was unawaited and its value never captured. On a
    // completed cricket match that is twenty-two round trips, fired at the
    // exact moment the scorer taps the last ball, on a ground chosen for its
    // pitch rather than its signal.
    //
    // The projection is still worth showing — "this result moves you +18" —
    // and the method is still there to compute it. It belongs on the screen
    // that displays it, where its cost is visible and it can be awaited, not
    // on the write path.
    //
    // Deliberately NOT awaited.
    //
    // With offline persistence enabled — and it is, because matches are
    // scored on grounds with no signal — Firestore applies the write to the
    // local cache immediately but does not complete this Future until the
    // server acknowledges it. Offline that is never. Awaiting here froze the
    // scoring pad for the remainder of the match, which is the exact failure
    // the offline design exists to prevent.
    //
    // The local write has already applied, so the scorer's own listener
    // shows the new score at once and the SDK flushes to the server on
    // reconnect. Failures arrive asynchronously on [writeFailures].
    // Record the action in our durable queue BEFORE the write leaves, so a
    // process kill between the local write and the server acknowledgement
    // cannot lose a delivery. `reconcileQueue` drops entries the server has
    // since confirmed.
    //
    // Chained rather than awaited. The ordering guarantee is exactly the one
    // it always was — the queue entry is on disk before `commit()` is called
    // — but the scorer is no longer standing in the queue behind it. The few
    // milliseconds this delays the local Firestore write cost nothing now
    // that the pad renders the projection returned above instead of waiting
    // for the snapshot to come back.
    unawaited(
      _enqueue(fixture, action, byUid, nextSeq, clientEventId)
          .then<void>((_) => batch.commit())
          .then<void>((_) {
        _dequeue(clientEventId);
        if (outcome.isComplete) _maybeResolveQualifiers(fixture);
      }).catchError((Object error) => _report(_translateWriteFailure(error))),
    );

    return updated;
  }

  /// Records the result the engine has ALREADY decided, on a fixture that is
  /// still marked live.
  ///
  /// ## The gap this closes
  ///
  /// [submit] writes `status: completed` in the same batch as the event that
  /// decided the match, so the ordinary path never needs this. But the stored
  /// fixture and its own projection can come apart, and when they did, the pad
  /// had no way back:
  ///
  ///  * Upholding a protest returns a finished fixture to `live` and does not
  ///    touch `scoreState` (see `CompetitionRepository.decideProtest`), so the
  ///    engine still says the match is over while every list in the app says
  ///    it is in progress.
  ///  * A completing batch the server refused — the pen had changed hands, a
  ///    rule said no — leaves exactly the same disagreement behind, and it
  ///    arrives on [writeFailures] long after the pad has moved on.
  ///
  /// In both cases the pad went silent from both ends at once: the engine is
  /// finished so it offers no scoring controls, and the finish bar only draws
  /// while a match is UNfinished. A scorer was left looking at a decided match
  /// with no buttons on it, unable to record the result, while the fixture sat
  /// Live for everybody else. This is the button that ends it.
  ///
  /// Appends an event rather than writing the status by itself, for the reason
  /// spelled out at length in [setFixtureOutcome]: `firestore.rules` admits a
  /// scorer's fixture write only when it advances `lastSeq`, so a status-only
  /// update by an umpire who is not also an organizer applies locally and is
  /// refused seconds later. The engines skip an unrecognised type when they
  /// replay a log ([ScoringPlugin.rebuild]), so the projection is untouched by
  /// it and a rebuild still reproduces the same score.
  /// Returns the projection to render immediately, exactly as [submit] does,
  /// so the pad flips to "finished" on the tap rather than on the round trip.
  Fixture finalizeMatch({
    required Fixture fixture,
    required ScoringContext context,
    required String byUid,
  }) {
    _assertHoldsPen(fixture, byUid);
    if (fixture.status == FixtureStatus.completed) return fixture;

    final plugin = ScoringRegistry.resolve(fixture.scoringPluginKey);
    final outcome = plugin.outcome(fixture.scoreState, context);
    // Only ever a confirmation of the engine's own verdict. Ending a match the
    // engine has NOT decided is a different act with different consequences —
    // a retirement, a walkover, an abandonment — and belongs to the outcome
    // sheet, which records why.
    if (!outcome.isComplete) {
      throw const ValidationException(
        'This match is not over yet. Score it to its end, or record a '
        'walkover, a retirement or an abandonment under "Match did not play '
        'normally".',
      );
    }

    final nextSeq = fixture.lastSeq + 1;
    final clientEventId = _clientEventId();
    final winnerEntrantId = _entrantIdForSide(fixture, outcome.winnerSide);
    final updated = fixture.copyWith(
      lastSeq: nextSeq,
      summary: plugin.summary(fixture.scoreState, context),
      status: FixtureStatus.completed,
      winnerEntrantId: winnerEntrantId,
      // A drawn match completes with no winner, and the fixture may be
      // carrying a stale one from before it was reopened.
      clearWinner: winnerEntrantId == null,
      isDraw: outcome.isDraw,
    );

    final batch = Refs.db.batch();
    batch.set(
      Refs.matchEvents(fixture.orgId, fixture.compId, fixture.id)
          .doc(MatchEvent.docId(nextSeq)),
      MatchEvent(
        seq: nextSeq,
        type: 'outcome',
        payload: {
          'resultType': MatchResultType.normal.wire,
          if (winnerEntrantId != null) 'winnerEntrantId': winnerEntrantId,
        },
        byUid: byUid,
        clientEventId: clientEventId,
      ).toCreate(),
    );
    batch.update(
      Refs.fixture(fixture.orgId, fixture.compId, fixture.id),
      {
        'lastSeq': updated.lastSeq,
        // Deliberately NOT `scoreState`. Nothing about the score changed and
        // rewriting it here would put this method in competition with the
        // replay pass over the one field a scorer cannot afford to lose.
        'summary': updated.summary,
        'status': FixtureStatus.completed.wire,
        'resultType': MatchResultType.normal.wire,
        'winnerEntrantId': winnerEntrantId,
        'isDraw': outcome.isDraw,
        'completedAt': FieldValue.serverTimestamp(),
        'lastEventAt': FieldValue.serverTimestamp(),
        'mvp': _awardFor(updated)?.toMap(),
      },
    );
    // Same batch as the result, for the reason given at the [submit] call
    // site: a bracket must never be left with a decided semi-final and a final
    // that still reads "To be decided".
    _maybeAdvanceWinner(batch, fixture, outcome, winnerEntrantId);
    _noteLocalHead(fixture, nextSeq);

    // Fire-and-forget, like every other write on the scoring path — awaiting
    // it on a ground with no signal never returns. See the long note in
    // [submit]; failures arrive on [writeFailures].
    unawaited(
      batch
          .commit()
          .then<void>((_) => _maybeResolveQualifiers(fixture))
          .catchError((Object error) => _report(_translateWriteFailure(error))),
    );

    return updated;
  }

  /// The highest sequence number THIS device has committed per fixture.
  ///
  /// ## The bug this exists for
  ///
  /// [_replayFixtureGroup] rebuilds a fixture's projection from the server's
  /// confirmed log plus whatever is still in the local queue, and writes the
  /// result back over `scoreState`/`lastSeq`. It reads that queue once, at
  /// the top of the pass. A tap made while the pass is in flight is therefore
  /// invisible to it — so the projection it writes is the score MINUS the
  /// scorer's most recent actions, and it lands a second or two after they
  /// made them. On the pad that reads as the score jumping backwards on its
  /// own; on a spectator's screen it reads as runs being un-scored.
  ///
  /// Passes used to run every three seconds during active scoring (and once
  /// more after every single tap), so the window this race needs was open
  /// essentially all the time.
  ///
  /// In-memory on purpose. It is a guard against *this process* racing
  /// itself, and a restart cannot race a pass that no longer exists. Anything
  /// durable would also have to be correct after an uninstall, which is what
  /// the `SharedPreferences` queue is already for.
  final Map<String, int> _localHead = <String, int>{};

  void _noteLocalHead(Fixture fixture, int seq) {
    final key = '${fixture.orgId}/${fixture.compId}/${fixture.id}';
    final current = _localHead[key] ?? 0;
    if (seq > current) _localHead[key] = seq;
  }

  /// Fires the exact same qualifier-fill `CompetitionRepository
  /// .resolveQualifiers` already runs from the "Update the bracket" button
  /// on [fixture]'s competition — automatically, the instant a group-stage
  /// fixture becomes resulted, instead of needing an organizer to notice a
  /// group finished and remember to tap something.
  ///
  /// Gated on [Bracket.group] rather than firing after every completed
  /// fixture: a knockout match completing can never complete a group, so
  /// checking would only be a wasted read of every fixture and entrant in
  /// the competition.
  ///
  /// Fire-and-forget for the same reason every write in this class is:
  /// `resolveQualifiers` is idempotent (see its own doc comment) and a
  /// failed read here just leaves the bracket exactly as manual as before —
  /// the button stays as a fallback — not corrupted.
  void _maybeResolveQualifiers(Fixture fixture) {
    if (fixture.bracket != Bracket.group) return;
    unawaited(_resolveQualifiers(fixture));
  }

  Future<void> _resolveQualifiers(Fixture fixture) async {
    try {
      await const CompetitionRepository()
          .resolveQualifiers(orgId: fixture.orgId, compId: fixture.compId);
    } catch (error) {
      debugPrint('Auto-resolve qualifiers failed: $error');
    }
  }

  AppException _translateWriteFailure(Object error) {
    if (error is! FirebaseException) {
      return const ValidationException('That score could not be saved.');
    }
    return switch (error.code) {
      // Another scorer took this sequence number. The document id IS the
      // sequence number, so `create` losing the race is the concurrency
      // guard doing its job: the fixture listener delivers the winning state
      // and the pad re-renders from it.
      'already-exists' => const ConflictException(),
      // Deliberately NOT a conflict any more, and deliberately not phrased
      // as a device problem either.
      //
      // It used to say "this device is not the one scoring this match", which
      // named the one thing the server never checks: `firestore.rules` does
      // not look at a device id at all, on purpose, because a device id is a
      // string the client chose (see `holdsPen` in that file). So the message
      // asserted a cause it could not know, and when the real cause was
      // something else entirely — a rules deploy lagging the app, or the
      // 1,000-expression evaluation budget running out mid-statement — it
      // sent the scorer looking for a second device that did not exist.
      //
      // What IS knowable here is only that the server refused the write. The
      // wording now says that and lists the causes that are actually
      // reachable, rather than picking one and stating it as fact.
      //
      // These two were folded together, and the cost of that was a scorer on
      // a single device being told "Score updated from another device" every
      // few seconds with no other device anywhere near them. A rules
      // rejection is not a race — it means this account may not write this
      // match right now (the pen is somebody else's, the match is finished,
      // the assignment never landed) — and it does not resolve itself by
      // waiting, which is precisely what the conflict path tells the scorer
      // to do. Reporting it as what it is also stops the retry loop from
      // re-announcing the same non-event on every tick.
      'permission-denied' => const PermissionDeniedException(
          'That action was not saved — this account cannot write to this '
          'match right now. Someone else may be holding the pen, or the '
          'match may have been finished or reassigned.',
        ),
      'unavailable' || 'deadline-exceeded' => const NetworkException(),
      _ =>
        ValidationException(error.message ?? 'That score could not be saved.'),
    };
  }

  /// Rebuilds a fixture's score from its event log.
  ///
  /// Used to recover from a conflict, and to verify a disputed result: if the
  /// replayed state disagrees with the stored projection, the projection was
  /// tampered with or a client wrote a bad update.
  Future<Map<String, dynamic>> replayFromEvents({
    required Fixture fixture,
    required ScoringContext context,
  }) async {
    final events = await fetchAllEvents(
      fixture.orgId,
      fixture.compId,
      fixture.id,
    );
    final plugin = ScoringRegistry.resolve(fixture.scoringPluginKey);
    return plugin.rebuild(
      events.map((e) => LoggedAction(seq: e.seq, action: _toAction(e))),
      context,
    );
  }

  /// Recomputes a match from its log and writes the result back, per §12.1.
  ///
  /// The projection is a cache. This is the function that proves it can always
  /// be thrown away and regenerated — after a disputed result, after a bad
  /// client write, or after a correction. Returns the rebuilt state.
  ///
  /// [dryRun] recomputes without writing, which is how a dispute is
  /// investigated before anyone changes the visible score.
  ///
  /// ## When it can actually write, and why it says so
  ///
  /// A rebuild recomputes the projection from a log it does not add to, so it
  /// writes the SAME `lastSeq` back. `firestore.rules` refuses that on both
  /// paths that could reach it: the scorer branch demands a strictly increasing
  /// sequence (the guard that stops a stale device overwriting a newer score),
  /// and the organizer branch freezes every score-bearing field once a fixture
  /// is `completed`.
  ///
  /// Both rules are right and neither should be relaxed — an unconditional
  /// "rewrite the score of a finished match" is the one write in the product
  /// that could not be audited. What was wrong was issuing the write anyway
  /// and letting it fail somewhere the caller could not see: the method
  /// returned `written: true` on a request Firestore had already rejected.
  ///
  /// So it checks first and reports [RebuildReport.blockedReason] instead.
  /// Correcting a finished match goes through the protest flow — raise it,
  /// uphold it, which returns the fixture to `live` — and then this can write.
  Future<RebuildReport> rebuildMatch({
    required Fixture fixture,
    required ScoringContext context,
    bool dryRun = false,
  }) async {
    final plugin = ScoringRegistry.resolve(fixture.scoringPluginKey);
    final events = await fetchAllEvents(
      fixture.orgId,
      fixture.compId,
      fixture.id,
    );

    final rebuilt = plugin.rebuild(
      events.map((e) => LoggedAction(seq: e.seq, action: _toAction(e))),
      context,
    );
    final outcome = plugin.outcome(rebuilt, context);
    final matched = _sameProjection(fixture.scoreState, rebuilt);

    if (dryRun || matched) {
      return RebuildReport(
        state: rebuilt,
        matchedStoredProjection: matched,
        eventCount: events.length,
        written: false,
      );
    }

    if (fixture.status == FixtureStatus.completed) {
      return RebuildReport(
        state: rebuilt,
        matchedStoredProjection: false,
        eventCount: events.length,
        written: false,
        blockedReason:
            'The stored score disagrees with this match’s event log, but a '
            'finished result cannot be rewritten directly. Raise a protest and '
            'uphold it — that reopens the match — then run this again.',
      );
    }

    try {
      await Refs.fixture(fixture.orgId, fixture.compId, fixture.id).update({
        'scoreState': rebuilt,
        'summary': plugin.summary(rebuilt, context),
        'status': outcome.isComplete
            ? FixtureStatus.completed.wire
            : FixtureStatus.live.wire,
        'winnerEntrantId': outcome.isComplete
            ? _entrantIdForSide(fixture, outcome.winnerSide)
            : null,
        'isDraw': outcome.isDraw,
      });
    } on FirebaseException catch (e) {
      // Awaited, unlike the scoring path: a rebuild is an investigation run by
      // somebody sitting still looking at the answer, not a tap on a ground.
      // Reporting "rebuilt" for a write the server refused is the failure this
      // whole method exists to detect in the first place.
      return RebuildReport(
        state: rebuilt,
        matchedStoredProjection: false,
        eventCount: events.length,
        written: false,
        blockedReason: e.code == 'permission-denied'
            ? 'You do not have permission to rewrite this match’s score. '
                'Only an organizer of this club can.'
            : (e.message ?? 'The rebuilt score could not be saved.'),
      );
    }

    return RebuildReport(
      state: rebuilt,
      matchedStoredProjection: false,
      eventCount: events.length,
      written: true,
    );
  }

  /// The best performer of a finished match.
  ///
  /// Pure — it reads only the projection and the line-ups — so the same
  /// fixture always produces the same award, whether it is being scored live,
  /// replayed from the offline queue, or rebuilt from the event log after a
  /// dispute. That property is the whole reason it is computed rather than
  /// stored as an opinion.
  MatchAward? _awardFor(Fixture f) => selectMvp(
        scoreState: f.scoreState,
        lineupA: f.lineupA,
        lineupB: f.lineupB,
        entrantAId: f.entrantAId,
        entrantBId: f.entrantBId,
        winnerEntrantId: f.winnerEntrantId,
      );

  /// Withdraws an earlier event by appending a reversal, never by editing it.
  ///
  /// This is UNDO. The engines have no undo of their own — a correction is a
  /// cross-cutting concern and implementing it per sport would guarantee they
  /// disagreed. Instead the reversal is appended to the log and the whole
  /// projection is recomputed from the events that survive, which keeps the
  /// log append-only and leaves an audit trail showing the mistake and its
  /// withdrawal.
  Future<Fixture> undo({
    required Fixture fixture,
    required ScoringContext context,
    required String byUid,
    int? reversesSeq,
    String? note,
  }) async {
    _assertHoldsPen(fixture, byUid);
    _assertNotDecided(fixture);
    final plugin = ScoringRegistry.resolve(fixture.scoringPluginKey);

    final events = await fetchAllEvents(
      fixture.orgId,
      fixture.compId,
      fixture.id,
    );
    if (events.isEmpty) {
      throw const ValidationException('There is nothing to undo yet.');
    }

    // Default to the most recent event that is still standing — which is what
    // a scorer means by "undo" almost every time.
    final target = reversesSeq ?? _lastLiveSeq(events);
    if (target == null) {
      throw const ValidationException(
        'Every event in this match has already been withdrawn.',
      );
    }
    if (!events.any((e) => e.seq == target)) {
      throw ValidationException('There is no event $target in this match.');
    }

    final nextSeq = fixture.lastSeq + 1;
    final action = ScoreAction(
      type: ScoringPlugin.undoActionType,
      payload: {'reversesSeq': target},
    );

    final log = [
      ...events.map((e) => LoggedAction(seq: e.seq, action: _toAction(e))),
      LoggedAction(seq: nextSeq, action: action),
    ];
    final rebuilt = plugin.rebuild(log, context);
    final outcome = plugin.outcome(rebuilt, context);
    final clientEventId = _clientEventId();

    final updated = fixture.copyWith(
      scoreState: rebuilt,
      lastSeq: nextSeq,
      summary: plugin.summary(rebuilt, context),
      status: outcome.isComplete ? FixtureStatus.completed : FixtureStatus.live,
      winnerEntrantId: outcome.isComplete
          ? _entrantIdForSide(fixture, outcome.winnerSide)
          : null,
      clearWinner: !outcome.isComplete,
      isDraw: outcome.isDraw,
    );

    final batch = Refs.db.batch();
    batch.set(
      Refs.matchEvents(fixture.orgId, fixture.compId, fixture.id)
          .doc(MatchEvent.docId(nextSeq)),
      MatchEvent(
        seq: nextSeq,
        type: ScoringPlugin.undoActionType,
        payload: action.toEventPayload(),
        byUid: byUid,
        clientEventId: clientEventId,
        note: note,
      ).toCreate(),
    );
    batch.update(
      Refs.fixture(fixture.orgId, fixture.compId, fixture.id),
      {
        'scoreState': updated.scoreState,
        'lastSeq': updated.lastSeq,
        'summary': updated.summary,
        'status': updated.status.wire,
        'winnerEntrantId': updated.winnerEntrantId,
        'isDraw': updated.isDraw,
        // Recomputed, not carried. Undoing a restart is how "continue the
        // previous score" is spelled, and the field that offers that button
        // has to stop being set the moment it is taken — otherwise the pad
        // keeps offering to continue a score it has already continued.
        'lastRestartSeq': _liveRestartSeq(log),
        'lastEventAt': FieldValue.serverTimestamp(),
      },
    );

    _noteLocalHead(fixture, nextSeq);
    await _enqueue(fixture, action, byUid, nextSeq, clientEventId);

    unawaited(
      batch
          .commit()
          .then((_) => _dequeue(clientEventId))
          .catchError((Object error) => _report(_translateWriteFailure(error))),
    );

    return updated;
  }

  /// The newest event that has not itself been withdrawn.
  ///
  /// Uses the same resolution as [ScoringPlugin.rebuild] rather than a second
  /// implementation, so "what undo will remove" can never disagree with "what
  /// the rebuild then drops".
  int? _lastLiveSeq(List<MatchEvent> events) {
    final sorted = events
        .map((e) => LoggedAction(seq: e.seq, action: _toAction(e)))
        .toList()
      ..sort((x, y) => x.seq.compareTo(y.seq));
    final withdrawn = ScoringPlugin.resolveWithdrawn(sorted);

    for (final e in events.reversed) {
      if (e.type == ScoringPlugin.undoActionType) continue;
      if (!withdrawn.contains(e.seq)) return e.seq;
    }
    return null;
  }

  /// The restart the match is currently running from, if any.
  ///
  /// Shares [ScoringPlugin.resolveWithdrawn] with the rebuild rather than
  /// re-deciding what counts as withdrawn, so "the pad offers to continue the
  /// old score" and "the rebuild would actually produce it" can never
  /// disagree.
  static int? _liveRestartSeq(List<LoggedAction> log) {
    final sorted = [...log]..sort((x, y) => x.seq.compareTo(y.seq));
    final withdrawn = ScoringPlugin.resolveWithdrawn(sorted);
    for (final e in sorted.reversed) {
      if (e.action.type != ScoringPlugin.restartActionType) continue;
      if (withdrawn.contains(e.seq)) continue;
      return e.seq;
    }
    return null;
  }

  /// Starts the match again from nothing, keeping every event that came
  /// before it.
  ///
  /// The reset is an appended marker, not a wipe — see
  /// [ScoringPlugin.restartActionType] for why, and for how
  /// "continue the previous score" is then just an ordinary undo of this
  /// event. Callers offer that as [continuePreviousScore].
  ///
  /// Reachable while a match is completed as well as live, because the
  /// commonest restart of all is a match that finished on the wrong pad.
  Future<Fixture> restartMatch({
    required Fixture fixture,
    required ScoringContext context,
    required String byUid,
    String? note,
  }) async {
    _assertHoldsPen(fixture, byUid);
    final plugin = ScoringRegistry.resolve(fixture.scoringPluginKey);
    final nextSeq = fixture.lastSeq + 1;
    final clientEventId = _clientEventId();
    const action = ScoreAction(type: ScoringPlugin.restartActionType);
    final fresh = plugin.initialState(context);

    final updated = fixture.copyWith(
      scoreState: fresh,
      lastSeq: nextSeq,
      summary: plugin.summary(fresh, context),
      status: FixtureStatus.live,
      clearWinner: true,
      isDraw: false,
      resultType: MatchResultType.normal,
      clearResultNote: true,
      lastRestartSeq: nextSeq,
    );

    final batch = Refs.db.batch();
    batch.set(
      Refs.matchEvents(fixture.orgId, fixture.compId, fixture.id)
          .doc(MatchEvent.docId(nextSeq)),
      MatchEvent(
        seq: nextSeq,
        type: ScoringPlugin.restartActionType,
        payload: action.toEventPayload(),
        byUid: byUid,
        clientEventId: clientEventId,
        note: note,
      ).toCreate(),
    );
    batch.update(
      Refs.fixture(fixture.orgId, fixture.compId, fixture.id),
      {
        'scoreState': updated.scoreState,
        'lastSeq': updated.lastSeq,
        'summary': updated.summary,
        'status': updated.status.wire,
        // A restarted match has no winner and no result. Written explicitly
        // rather than left alone: a restart most often follows a match that
        // was finished by mistake, so these are exactly the fields that are
        // dirty when it is tapped.
        'winnerEntrantId': null,
        'isDraw': false,
        'completedAt': null,
        'mvp': null,
        // The ruling goes with the result it belongs to.
        //
        // These two were left behind, and they are the only fields on a
        // fixture that no rebuild ever recomputes — so a match abandoned for
        // rain and then restarted when it cleared kept `resultType:
        // abandoned` forever. `countsForStandings` is false for that value,
        // so the replayed match was scored to a proper finish and then
        // awarded nobody anything, with nothing on any screen to say why.
        'resultType': MatchResultType.normal.wire,
        'resultNote': null,
        'lastRestartSeq': nextSeq,
        'lastEventAt': FieldValue.serverTimestamp(),
      },
    );

    _noteLocalHead(fixture, nextSeq);
    await _enqueue(fixture, action, byUid, nextSeq, clientEventId);
    unawaited(
      batch
          .commit()
          .then((_) => _dequeue(clientEventId))
          .catchError((Object error) => _report(_translateWriteFailure(error))),
    );

    return updated;
  }

  /// Takes back a restart, restoring the score exactly as it stood.
  ///
  /// Nothing was deleted by the restart, so this is a plain undo of the
  /// marker event and the projection rebuilds itself from the log.
  Future<Fixture> continuePreviousScore({
    required Fixture fixture,
    required ScoringContext context,
    required String byUid,
  }) {
    final target = fixture.lastRestartSeq;
    if (target == null) {
      throw const ValidationException(
        'This match has not been restarted, so there is no earlier score to '
        'continue.',
      );
    }
    return undo(
      fixture: fixture,
      context: context,
      byUid: byUid,
      reversesSeq: target,
      note: 'Restart withdrawn — previous score continued',
    );
  }

  /// Compares two projections for equality, tolerating the numeric widening
  /// Firestore applies on a round trip (an int written, a double read back).
  static bool _sameProjection(Map<String, dynamic> a, Map<String, dynamic> b) =>
      _normalise(a).toString() == _normalise(b).toString();

  static Object? _normalise(Object? v) {
    if (v is num) return v.toDouble();
    if (v is Map) {
      final keys = v.keys.map((k) => k.toString()).toList()..sort();
      return {for (final k in keys) k: _normalise(v[k])};
    }
    if (v is List) return v.map(_normalise).toList();
    return v;
  }

  /// Marks a fixture as a walkover, abandonment or dispute.
  ///
  /// Kept off the plugin path because none of these are scoring events — they
  /// are administrative decisions about a match that did not play out
  /// normally, and every real tournament needs them.
  ///
  /// [resultType] is what the rest of the system actually reads to decide
  /// whether this counts towards a table, a rating, or a career profile. It
  /// defaults from [status] so existing callers keep working, but a caller who
  /// knows more should say so — "retired" and "disqualified" are both
  /// `completed` fixtures with a winner and are otherwise indistinguishable
  /// from a straight-sets win once written.
  Future<void> setFixtureOutcome({
    required Fixture fixture,
    required FixtureStatus status,
    String? winnerEntrantId,
    String? note,
    MatchResultType? resultType,
    String? byUid,
  }) async {
    if (status.acceptsScoring) {
      throw const ValidationException(
        'Use the scoring pad to record a normal result.',
      );
    }
    final type = resultType ??
        switch (status) {
          FixtureStatus.walkover => MatchResultType.walkover,
          FixtureStatus.abandoned => MatchResultType.abandoned,
          _ => MatchResultType.normal,
        };
    // Deliberately NOT awaited, for the same reason as every other write on
    // this path — see the long note in [submit].
    //
    // This one is the official's decision: a walkover, an abandonment, a
    // disqualification. Awaiting it meant the dialog sat on its spinner until
    // the SERVER answered, and with offline persistence on, off signal that is
    // never. An umpire awarding a walkover at a ground with no bars watched
    // the button spin, gave up, and backed out — and because the local write
    // had in fact already applied, the decision was recorded on their own
    // device and looked to them like it had failed. That is the "the official
    // awarded it and nothing happened" report.
    //
    // Firestore has the mutation the instant this returns and flushes it on
    // reconnect; every listener on every device sees it as soon as it lands.
    // A rejection arrives on [writeFailures] rather than by throwing.
    // A retirement or a disqualification goes into the EVENT LOG, not just
    // onto the fixture, and that is what makes it work for the person who
    // actually declares one.
    //
    // ## The bug
    //
    // This used to be a bare field update. `firestore.rules` admits a fixture
    // write through exactly two doors: an organizer (branch a), or the
    // assigned scorer advancing the score (branch b) — and branch (b) opens
    // on `request.resource.data.lastSeq > resource.data.lastSeq`, because
    // that test is pure and false for every write that is not a score. A
    // status-only update moves no sequence number, so it matched neither
    // door. An umpire holding the pen who was not also an org admin pressed
    // "Retired — A wins", the local cache applied it, the screen showed it,
    // and the server refused it seconds later: the match went back to Live on
    // its own and the retirement was gone. Organizers never saw it, because
    // branch (a) let THEM through — which is the worst way for a bug to
    // present, since the people who could reproduce it were the people
    // nobody believed.
    //
    // Recording it as an event fixes it at the root rather than by widening
    // the rules: the write now carries a sequence number, so it is a scoring
    // write in the sense branch (b) already means, and the match log gains
    // the retirement in the same order everything else happened in. The
    // engines ignore the event when they replay a log — an unknown type is
    // skipped, see [ScoringPlugin.rebuild] — so the projection is unchanged
    // and the outcome lives where it belongs, on the fixture.
    //
    // Only for the outcomes a scorer may declare. A walkover, an abandonment
    // and a dispute stay plain updates, because those are the organizer's
    // call and the rules deliberately do not admit a scorer for them.
    final logged = status == FixtureStatus.completed && byUid != null;
    final nextSeq = fixture.lastSeq + 1;
    if (logged) {
      unawaited(
        Refs.matchEvents(fixture.orgId, fixture.compId, fixture.id)
            .doc(MatchEvent.docId(nextSeq))
            .set(MatchEvent(
              seq: nextSeq,
              type: 'outcome',
              payload: {
                'resultType': type.wire,
                if (winnerEntrantId != null) 'winnerEntrantId': winnerEntrantId,
              },
              byUid: byUid,
              clientEventId: _clientEventId(),
              note: note,
            ).toCreate())
            .catchError((Object error) {
          _report(_translateWriteFailure(error));
        }),
      );
      _noteLocalHead(fixture, nextSeq);
    }

    unawaited(
      Refs.fixture(fixture.orgId, fixture.compId, fixture.id).update({
        if (logged) 'lastSeq': nextSeq,
        'status': status.wire,
        'resultType': type.wire,
        'winnerEntrantId': winnerEntrantId,
        'isDraw': false,
        // Stored as a stable token, never as a translated phrase.
        //
        // This field is persisted and read back by every client, so writing
        // "Walkover" here would freeze one scorer's language onto the document
        // and show it to a Telugu spectator in English forever. The UI
        // translates the token at render time — see `FixtureStatus` and the
        // `result*` keys in lib/l10n.
        'summary': switch (status) {
          FixtureStatus.walkover ||
          FixtureStatus.abandoned ||
          FixtureStatus.disputed =>
            status.wire,
          _ => fixture.summary,
        },
        'resultNote': note,
        // Only where the match actually ENDED. A dispute freezes a result
        // pending a decision — it does not finish anything, and stamping a
        // completion time on it put "Completed 14:32" under a match nobody
        // had agreed the result of, and moved it to the top of every
        // most-recent list on the strength of a timestamp that meant the
        // opposite of what it said.
        if (status != FixtureStatus.disputed)
          'completedAt': FieldValue.serverTimestamp(),
      }).catchError((Object error) {
        _report(_translateWriteFailure(error));
      }),
    );
    if (status.isResulted) _maybeResolveQualifiers(fixture);
  }

  /// Withdraws an official's ruling and gives the match back to the pad.
  ///
  /// The other half of [setFixtureOutcome], and the half that was missing.
  /// Every one of those rulings was a one-way door: an organizer who awarded
  /// a walkover to the wrong side, or abandoned a match for rain that stopped
  /// twenty minutes later, had no way back at all — the pad refuses a scoring
  /// write to a walkover, and nothing anywhere offered to take the ruling
  /// off. "Restart the match" was the only route, and it throws the score
  /// away to get there.
  ///
  /// ## What it restores, and why none of it is remembered
  ///
  /// Nothing is read back from a stored "previous status". The event log is
  /// the record and it already knows: a match with events was live, one
  /// without was scheduled ([Fixture.statusWithoutDecision]), and if the
  /// engine had in fact finished the match before somebody disputed it, the
  /// projection still says so — so the outcome is recomputed from
  /// `scoreState` here and the match goes back to `completed` with its own
  /// winner rather than to a `live` match that is actually over.
  ///
  /// Written as an EVENT, for the same reason a retirement is (see the long
  /// note in [setFixtureOutcome]): the write carries a sequence number, so
  /// `firestore.rules` admits it through the scorer branch instead of
  /// refusing it seconds after the local cache has already shown it working.
  Future<Fixture> clearFixtureOutcome({
    required Fixture fixture,
    required ScoringContext context,
    required String byUid,
    String? note,
  }) async {
    if (!fixture.endedByDecision) {
      throw const ValidationException(
        'This match has no ruling on it to withdraw.',
      );
    }
    _assertHoldsPen(fixture, byUid);

    final plugin = ScoringRegistry.resolve(fixture.scoringPluginKey);
    final outcome = plugin.outcome(fixture.scoreState, context);
    final nextSeq = fixture.lastSeq + 1;
    final clientEventId = _clientEventId();

    // The engine's own verdict on the score as it stands, which is the only
    // honest thing to go back to. A match retired at 21-19, 15-12 in a
    // best-of-three is NOT finished once the retirement is withdrawn, and a
    // match disputed after a completing point IS.
    final status = outcome.isComplete
        ? FixtureStatus.completed
        : fixture.statusWithoutDecision;
    final winnerEntrantId = outcome.isComplete
        ? _entrantIdForSide(fixture, outcome.winnerSide)
        : null;

    final updated = fixture.copyWith(
      status: status,
      summary: plugin.summary(fixture.scoreState, context),
      lastSeq: nextSeq,
      winnerEntrantId: winnerEntrantId,
      clearWinner: !outcome.isComplete,
      isDraw: outcome.isComplete && outcome.isDraw,
      resultType: MatchResultType.normal,
      clearResultNote: true,
    );

    unawaited(
      Refs.matchEvents(fixture.orgId, fixture.compId, fixture.id)
          .doc(MatchEvent.docId(nextSeq))
          .set(MatchEvent(
            seq: nextSeq,
            type: 'outcome_cleared',
            payload: {'from': fixture.resultType.wire},
            byUid: byUid,
            clientEventId: clientEventId,
            note: note,
          ).toCreate())
          .catchError((Object error) {
        _report(_translateWriteFailure(error));
      }),
    );
    _noteLocalHead(fixture, nextSeq);

    unawaited(
      Refs.fixture(fixture.orgId, fixture.compId, fixture.id).update({
        'lastSeq': nextSeq,
        'status': status.wire,
        'resultType': MatchResultType.normal.wire,
        'resultNote': null,
        'winnerEntrantId': winnerEntrantId,
        'isDraw': updated.isDraw,
        'summary': updated.summary,
        // Cleared unless the engine says the match really is over. A
        // resumed match that still reads "completed at 14:32" is the same
        // lie the dispute path used to tell.
        'completedAt': outcome.isComplete ? FieldValue.serverTimestamp() : null,
        // The match is being played again from this moment, so it must not
        // read as a scoreboard somebody walked away from. See
        // [Fixture.isLiveAt].
        'lastEventAt': FieldValue.serverTimestamp(),
      }).catchError((Object error) {
        _report(_translateWriteFailure(error));
      }),
    );

    return updated;
  }

  /// Refuses a scoring write to a match an official has ruled on.
  ///
  /// Here rather than only in the UI because of what the write would DO. The
  /// status a scoring write commits is derived from the projection — see
  /// [submit] — and no ruling is in the projection, so a single tap on an
  /// abandoned match writes `status: live` and the abandonment is gone, with
  /// no error anywhere and nothing for the organizer to notice. The pad hides
  /// its controls in this state; this is what makes the same thing true for a
  /// queued action replayed from a cold start, a keyboard shortcut, and every
  /// future caller.
  void _assertNotDecided(Fixture fixture) {
    if (!fixture.endedByDecision) return;
    final what = fixture.status.isDecision
        ? fixture.status.label.toLowerCase()
        : fixture.resultType.label.toLowerCase();
    throw ValidationException(
      'This match was recorded as $what. Withdraw that decision first and '
      'the score continues from exactly where it stopped.',
    );
  }

  /// Refuses a write from anybody but the current pen holder.
  ///
  /// `firestore.rules` enforces the same thing, and this does not exist
  /// because the rule might fail — it exists because of WHERE the rule's
  /// answer arrives. A scoring write is deliberately not awaited (see
  /// [submit]), so a rejection comes back seconds later, after the local
  /// cache has already applied the action and the pad has already drawn it.
  /// The scorer sees the point land and then jump back off the board, with a
  /// message about permissions attached to a tap they made ten seconds ago.
  ///
  /// Refusing locally makes it instant and specific instead: the action never
  /// enters the queue, the projection never moves, and the pad says why on
  /// the frame the button was pressed.
  ///
  /// A fixture with no pen is unrestricted here — the older role-based gates
  /// still apply — so nothing that predates exclusive control changes
  /// behaviour.
  void _assertHoldsPen(Fixture fixture, String byUid) {
    if (!fixture.penIsHeld) return;
    if (fixture.penHeldBy(byUid)) return;
    throw const ValidationException(
      'Someone else has scoring control of this match. An admin can move it '
      'back to you.',
    );
  }

  // --- Offline queue ----------------------------------------------------

  /// Number of events written while offline that have not yet been confirmed
  /// by the server. Surfaced in the scoring pad so a scorer on a ground with
  /// no signal can see their work is held, not lost.
  Future<int> pendingCount() async {
    final store = await _store;
    return (store.getStringList(_queueKey) ?? const []).length;
  }

  Future<void> _enqueue(
    Fixture fixture,
    ScoreAction action,
    String byUid,
    int seq,
    String clientEventId,
  ) async {
    final store = await _store;
    final queue = store.getStringList(_queueKey) ?? <String>[];
    queue.add(
      SyncQueueEntry(
        orgId: fixture.orgId,
        compId: fixture.compId,
        fixtureId: fixture.id,
        seq: seq,
        type: action.type,
        payload: action.toEventPayload(),
        byUid: byUid,
        clientEventId: clientEventId,
      ).toJsonString(),
    );
    await store.setStringList(_queueKey, queue);
    unawaited(_notifyPendingCountChanged());
  }

  /// Drops one entry once the server has acknowledged its write.
  Future<void> _dequeue(String clientEventId) async {
    final store = await _store;
    final queue = store.getStringList(_queueKey) ?? <String>[];
    if (queue.isEmpty) return;
    final remaining = queue.where((raw) {
      final entry = SyncQueueEntry.tryParse(raw);
      // Unparseable entry: keep it, `reconcileQueue` will deal with it.
      return entry == null || entry.clientEventId != clientEventId;
    }).toList();
    if (remaining.length != queue.length) {
      await store.setStringList(_queueKey, remaining);
      unawaited(_notifyPendingCountChanged());
    }
  }

  /// Cap matching CLAUDE.md §12.9's sync-batch budget ("sync batches ≤ 500
  /// events"). Replaying more than this in a single reconnect risks the app
  /// being backgrounded mid-flush on one flaky bar of signal before the
  /// queue ever finishes draining — steady, bounded progress every time the
  /// device gets signal beats attempting everything and completing nothing.
  static const _maxReplayBatch = 500;

  /// Reconciles the local queue against the server: drops entries the server
  /// already holds, and — the half the old implementation's own doc comment
  /// admitted was missing — actually re-submits the ones it does not.
  ///
  /// ## Why replay has to exist at all
  ///
  /// Firestore's own offline persistence normally flushes a pending write on
  /// reconnect without any help from this queue. This queue is not a
  /// substitute for that; it is what survives when the *local cache itself*
  /// is gone — an app uninstall, the OS evicting storage under pressure, a
  /// support-flow `clearPersistence()` call. When that happens, the pending
  /// writes Firestore was holding are gone with it, and this queue —
  /// durable in `SharedPreferences`, deliberately separate storage — is the
  /// only remaining record of what was scored offline. Pruning confirmed
  /// entries without ever resubmitting the rest meant that record was
  /// write-only: comforting to look at, useless in the actual disaster it
  /// exists for.
  ///
  /// ## The three passes
  ///
  ///  1. [SyncBatchPlanner.partitionPoison] evicts entries that have failed
  ///     so many replay attempts they are clearly not "still offline" — see
  ///     `sync_batch_planner.dart` for why that distinction matters and how
  ///     many attempts it takes.
  ///  2. [SyncBatchPlanner.plan] groups what is left by fixture, orders each
  ///     group by `seq` (the causal order §4 requires), holds back anything
  ///     still inside its backoff window, and caps this round at
  ///     [_maxReplayBatch].
  ///  3. [_replayFixtureGroup] resolves each fixture group with one fixture
  ///     read plus one event-log read *per fixture* — not per queued entry,
  ///     which is what fixes the N-network-round-trips-on-reconnect problem
  ///     the old per-entry `.get()` loop had.
  Future<void> reconcileQueue() async {
    final store = await _store;
    final raw = store.getStringList(_queueKey) ?? const [];
    if (raw.isEmpty) return;

    final unparsable = <String>[];
    final parsed = <SyncQueueEntry>[];
    for (final line in raw) {
      final entry = SyncQueueEntry.tryParse(line);
      if (entry == null) {
        // Keep the raw line rather than discarding it. A single line
        // corrupted by a partial write (a process kill mid-`setStringList`)
        // must not take a genuine, still-recoverable scoring action down
        // with it — it just never resolves itself, which is a smaller
        // failure than silently losing it.
        unparsable.add(line);
      } else {
        parsed.add(entry);
      }
    }

    final (alive, poisoned) = SyncBatchPlanner.partitionPoison(parsed);
    for (final p in poisoned) {
      debugPrint(
        '[PlaySphere] evicting poisoned sync entry after ${p.attempts} '
        'attempts: ${p.type} seq ${p.seq} on fixture ${p.fixtureId}',
      );
      _failures.add(
        const ValidationException(
          'A queued scoring action could not be saved after repeated '
          'attempts and was discarded. Check this match for a possible '
          'manual correction.',
        ),
      );
    }

    final plan = SyncBatchPlanner.plan(alive, maxBatchSize: _maxReplayBatch);

    // Group the entries selected for this round by fixture, preserving the
    // planner's ordering (first-appearance fixture order, seq-ascending
    // within each fixture) so replay proceeds in causal order.
    final fixtureOrder = <String>[];
    final byFixture = <String, List<SyncQueueEntry>>{};
    for (final e in plan.toReplay) {
      final key = e.fixtureKey;
      if (!byFixture.containsKey(key)) fixtureOrder.add(key);
      byFixture.putIfAbsent(key, () => <SyncQueueEntry>[]).add(e);
    }

    final stillPending = <SyncQueueEntry>[];
    for (final key in fixtureOrder) {
      stillPending.addAll(await _replayFixtureGroup(byFixture[key]!));
    }

    // Re-read before writing, and keep anything that arrived while this pass
    // was in flight.
    //
    // ## The bug this exists for
    //
    // The queue was read once at the top of this method and then overwritten
    // here with a list derived entirely from that snapshot. A pass involves
    // two server reads and a batch commit per fixture, so it is open for
    // hundreds of milliseconds at best and the full `passTimeout` at worst —
    // and every scoring action taken inside that window was appended to the
    // stored queue by [_enqueue] and then silently erased by this line.
    //
    // Those actions were not merely un-replayed, they were un-recorded: the
    // durable queue is the ONLY surviving record of an offline action once
    // Firestore's own cache is gone, which is the single disaster it exists
    // for. A scorer tapping steadily through a match in a dead spot was
    // losing the entries fastest at exactly the moment the queue was longest
    // and the passes were slowest.
    final seen = {
      for (final e in [...parsed, ...poisoned]) e.clientEventId,
    };
    final latest = store.getStringList(_queueKey) ?? const [];
    final arrivedDuringPass = <String>[
      for (final line in latest)
        if (SyncQueueEntry.tryParse(line) case final e?)
          if (!seen.contains(e.clientEventId)) line,
    ];

    final finalQueue = <String>[
      ...unparsable,
      ...stillPending.map((e) => e.toJsonString()),
      ...plan.deferred.map((e) => e.toJsonString()),
      ...plan.overflow.map((e) => e.toJsonString()),
      ...arrivedDuringPass,
    ];
    await store.setStringList(_queueKey, finalQueue);
    unawaited(_notifyPendingCountChanged());
  }

  /// Replays every entry in [group] — all queued actions for one fixture,
  /// already ordered by `seq` — against the server, and returns the ones
  /// that still need to be retried (empty on full success).
  ///
  /// Rebuilds the whole projection from the server-confirmed log plus the
  /// still-missing queued actions via [ScoringPlugin.rebuild], rather than
  /// applying each queued action as an incremental delta on top of
  /// `fixture.scoreState`. That is the same machinery [rebuildMatch] and
  /// [undo] already rely on, and it means a gap in the confirmed log, or
  /// queued actions that do not perfectly abut the server's `lastSeq`, can
  /// never leave the projection half-updated — the result is always exactly
  /// what replaying the true log from scratch would produce.
  Future<List<SyncQueueEntry>> _replayFixtureGroup(
    List<SyncQueueEntry> group,
  ) async {
    final first = group.first;
    try {
      // Server-only, deliberately, and the same for the event log below.
      //
      // A default `.get()` falls back to the local cache when the device is
      // offline and returns happily — including this device's own pending
      // writes. Replay then compared a queued action against a log that
      // already "contained" it, concluded the server had it, and deleted the
      // queue entry. The durable queue exists precisely for the case where
      // that cache is later lost, so confirming from the cache made it a
      // record of nothing.
      //
      // Off signal this read throws `unavailable` instead, which is the
      // honest answer — there is nothing to reconcile against — and is
      // handled below as a deferral rather than a failure.
      final fixtureDoc = await Refs.fixture(
        first.orgId,
        first.compId,
        first.fixtureId,
      ).get(const GetOptions(source: Source.server));
      if (!fixtureDoc.exists) {
        // The read came from the server, so this is not ambiguous any more:
        // the match is genuinely gone. There is nothing to replay onto, and
        // nothing that will make it come back, so these entries walk up the
        // backoff and are eventually evicted as poison — which is the correct
        // end for an action whose match no longer exists.
        return group.map(_bumpForRetry).toList();
      }
      final fixture = Fixture.fromDoc(fixtureDoc);

      // One query for the fixture's whole confirmed log — not one read per
      // queued entry — is what turns "N round trips on reconnect" into "two
      // reads per affected fixture, however many of its events are queued".
      final serverEvents = await fetchAllEvents(
        first.orgId,
        first.compId,
        first.fixtureId,
        source: Source.server,
      );
      final confirmedIdBySeq = {
        for (final e in serverEvents) e.seq: e.clientEventId,
      };

      final stillUnconfirmed = <SyncQueueEntry>[
        for (final e in group)
          if (confirmedIdBySeq[e.seq] != e.clientEventId) e,
      ];
      if (stillUnconfirmed.isEmpty) {
        // Every queued action in this group already landed. This is the
        // idempotent-double-delivery case §12.3 requires explicitly: the
        // sequence slot and its clientEventId already agree, so nothing is
        // re-sent — a replay of an already-applied action is a no-op, not a
        // duplicate.
        return const [];
      }

      if (!fixture.status.acceptsScoring) {
        // The match is over on the server and these actions never reached it.
        //
        // Retrying is pointless and not neutral: the security rules only
        // accept a scoring write onto a `scheduled` or `live` fixture, so
        // every future attempt is refused for exactly the reason this one
        // was. Left alone, they walk the backoff for twenty minutes and are
        // then discarded anyway — with the pending count stuck on screen the
        // whole time, which is what the scorer in the bug report was looking
        // at: twenty-six actions "waiting to sync" on a match that had been
        // finished for an hour.
        //
        // So they are discarded now, and the scorer is told once, plainly.
        // This is the honest message: the actions are gone, the match needs
        // a correction, and no amount of waiting was ever going to change
        // that.
        _reportTerminalOnce(fixture.id, stillUnconfirmed.length);
        return const [];
      }

      final plugin = ScoringRegistry.resolve(fixture.scoringPluginKey);
      final context = fixture.scoringContext();

      final combinedLog = [
        for (final e in serverEvents)
          LoggedAction(seq: e.seq, action: _toAction(e)),
        for (final e in stillUnconfirmed)
          LoggedAction(seq: e.seq, action: e.toScoreAction()),
      ];
      final rebuilt = plugin.rebuild(combinedLog, context);
      final outcome = plugin.outcome(rebuilt, context);
      final maxSeq =
          stillUnconfirmed.map((e) => e.seq).reduce((a, b) => a > b ? a : b);

      // Never write a projection this device has already scored past.
      //
      // `stillUnconfirmed` came from a queue snapshot taken at the top of
      // `reconcileQueue`, before the two server reads above. If the scorer
      // has tapped since then, `rebuilt` is the score without those taps and
      // `maxSeq` is behind where this device actually is — committing it
      // would roll the live score backwards on the pad and on every
      // spectator's screen. See [_localHead].
      //
      // Deferred rather than dropped, and without burning a retry attempt:
      // nothing is wrong with these entries, they are just being replayed
      // from a stale reading. The next pass re-snapshots the queue, finds the
      // newer taps in it, and rebuilds a projection that includes them.
      final head =
          _localHead['${first.orgId}/${first.compId}/${first.fixtureId}'];
      if (head != null && maxSeq < head) {
        return group.map(_deferForNetwork).toList();
      }

      if (maxSeq <= fixture.lastSeq) {
        // The server's sequence has already moved past what we are trying to
        // deliver, and the clientEventId sitting in that slot is not ours —
        // some other write legitimately owns it now.
        //
        // Dropped, not retried. Retrying was the honest-looking choice and
        // the wrong one: the monotonic-sequence rule will refuse this write
        // on every future attempt for exactly the same reason it would refuse
        // it now, so the entries could only ever walk up the backoff and be
        // discarded as "poison" several minutes later — with an alarming
        // message about a manual correction — after re-announcing a conflict
        // on every tick in between. That loop is what a scorer sees as a
        // permanently stuck pending count and a snackbar every few seconds.
        //
        // Nothing is lost by dropping them: the slot is filled, the log is
        // authoritative, and the projection on screen already reflects the
        // events that won.
        _reportSupersededOnce(fixture.id);
        return const [];
      }

      final winnerEntrantId = outcome.isComplete
          ? _entrantIdForSide(fixture, outcome.winnerSide)
          : null;

      // A result an official wrote by hand, on a match whose projection never
      // reached a finish: a retirement, a walkover, an abandonment. The whole
      // block below recomputes the result from the event log, and none of
      // those decisions are IN the event log — so every field they own has to
      // be carried across untouched rather than recomputed into nothing.
      final byDecision = !outcome.isComplete && !fixture.status.acceptsScoring;

      final batch = Refs.db.batch();
      for (final e in stillUnconfirmed) {
        batch.set(
          Refs.matchEvents(first.orgId, first.compId, first.fixtureId)
              .doc(MatchEvent.docId(e.seq)),
          MatchEvent(
            seq: e.seq,
            type: e.type,
            payload: e.payload,
            byUid: e.byUid,
            clientEventId: e.clientEventId,
            note: e.note,
          ).toCreate(),
        );
      }
      batch.update(
        Refs.fixture(first.orgId, first.compId, first.fixtureId),
        {
          'scoreState': rebuilt,
          'lastSeq': maxSeq,
          'summary':
              byDecision ? fixture.summary : plugin.summary(rebuilt, context),
          // A match the engine has not finished is LIVE — unless somebody
          // has already ended it by hand.
          //
          // Replay recomputes the status from the projection, and a
          // retirement, a walkover or an abandonment is not in the
          // projection: it is an official's decision written straight onto
          // the fixture. Writing `live` unconditionally here took a match an
          // umpire had retired an hour earlier and put it back on the board
          // as in progress, the first time a queued event from that match
          // reached the server. The result did not come back — it was simply
          // overwritten by a pass that had no idea it existed.
          'status': outcome.isComplete
              ? FixtureStatus.completed.wire
              : (fixture.status.acceptsScoring
                  ? FixtureStatus.live.wire
                  : fixture.status.wire),
          'winnerEntrantId':
              byDecision ? fixture.winnerEntrantId : winnerEntrantId,
          'isDraw': byDecision ? fixture.isDraw : outcome.isDraw,
          // Same derivation as the live path, so a restart (or the undo of
          // one) that only reaches the server on reconnect leaves the
          // "continue the previous score" offer in the same state it would
          // have been in had it been written live.
          'lastRestartSeq': _liveRestartSeq(combinedLog),
          if (fixture.lastSeq == 0) 'startedAt': FieldValue.serverTimestamp(),
          if (outcome.isComplete) 'completedAt': FieldValue.serverTimestamp(),
          // Same heartbeat as the online path. A match scored in a dead spot
          // and flushed on reconnect is being played now, and must not be
          // read as abandoned just because the server heard about it late.
          'lastEventAt': FieldValue.serverTimestamp(),
          // Same award, same inputs, on the path a match takes when it was
          // scored offline and only reaches the server on reconnect. A match
          // must not get a different MVP for having been played out of signal.
          if (outcome.isComplete)
            'mvp': selectMvp(
              scoreState: rebuilt,
              lineupA: fixture.lineupA,
              lineupB: fixture.lineupB,
              entrantAId: fixture.entrantAId,
              entrantBId: fixture.entrantBId,
              winnerEntrantId: winnerEntrantId,
            )?.toMap(),
        },
      );
      _maybeAdvanceWinner(batch, fixture, outcome, winnerEntrantId);

      // Bounded, because an awaited Firestore commit does not settle until
      // the server acknowledges it and the connection can drop between the
      // reads above and this line. An unbounded await here is what used to
      // wedge the whole sync driver for the life of the process — see
      // `SyncDriver.passTimeout`.
      //
      // The commit is NOT cancelled by the timeout; Firestore keeps it in its
      // own durable queue and flushes it on reconnect. Timing out only means
      // "we did not see the acknowledgement", so the entries stay queued and
      // the next pass — which reads the server log — either finds them landed
      // and drops them, or sends them again. Re-sending is safe: the event
      // document id is its sequence number, so a second delivery of the same
      // action is a no-op rather than a duplicate.
      await batch.commit().timeout(_commitTimeout);

      // No rating call here either — see the note at the [submit] call site.
      // Settlement is `onMatchSettled`'s, and it fires off the same status
      // transition this batch just wrote, so a match completed offline settles
      // on reconnect exactly like one completed live.
      return const [];
    } on TimeoutException {
      // Not a failure and not the entry's fault. Deferred without counting an
      // attempt, so a long spell out of signal cannot walk an honest action
      // up to the poison threshold and get it discarded.
      return group.map(_deferForNetwork).toList();
    } catch (e) {
      final error = _translateWriteFailure(e);
      if (error is NetworkException) {
        // "Still offline" is the expected state on a ground, not something to
        // interrupt the scorer about, and it must not burn a retry attempt.
        return group.map(_deferForNetwork).toList();
      }
      _reportReplayFailureOnce(first.fixtureId, error);
      return group.map(_bumpForRetry).toList();
    }
  }

  /// Fixtures whose replay failure has already been surfaced this session.
  final Set<String> _replayFailureReported = <String>{};

  /// Reports a failed replay at most once per fixture.
  ///
  /// The driver retries every few seconds while anything is queued, and the
  /// failures worth reporting here — a rules rejection, a bad payload — are
  /// by nature the ones that will fail again on every single one of those
  /// ticks. Reporting each attempt turned one problem into a snackbar every
  /// three seconds for the rest of the session, which is how a recoverable
  /// condition ends up looking like the app is broken. The entry is still
  /// retried, still backs off, and is still evicted as poison if it never
  /// succeeds — that eviction has its own, deliberately loud, message.
  void _reportReplayFailureOnce(String fixtureId, AppException error) {
    if (!_replayFailureReported.add(fixtureId)) return;
    _report(error);
  }

  /// Fixtures whose "the match had already ended" notice has been given.
  final Set<String> _terminalReported = <String>{};

  void _reportTerminalOnce(String fixtureId, int count) {
    if (!_terminalReported.add(fixtureId)) return;
    if (_failures.isClosed) return;
    _failures.add(
      ValidationException(
        count == 1
            ? 'One scoring action could not be saved because the match had '
                'already been finished. Reopen the match if it needs '
                'correcting.'
            : '$count scoring actions could not be saved because the match '
                'had already been finished. Reopen the match if it needs '
                'correcting.',
      ),
    );
  }

  /// Fixtures already told about, so a queue holding twenty superseded
  /// actions for one match produces one notice rather than twenty.
  final Set<String> _supersededReported = <String>{};

  void _reportSupersededOnce(String fixtureId) {
    if (!_supersededReported.add(fixtureId)) return;
    if (!_resyncs.isClosed) _resyncs.add(null);
  }

  /// How long a replay waits for the server to acknowledge a batch before
  /// giving the sync driver its thread back. Long enough to ride out a slow
  /// 2G handshake, short enough that a scorer's next action is not stuck
  /// behind it.
  static const _commitTimeout = Duration(seconds: 10);

  SyncQueueEntry _bumpForRetry(SyncQueueEntry e) {
    final attempts = e.attempts + 1;
    return e.copyWith(
      attempts: attempts,
      nextAttemptAt: DateTime.now().add(SyncBackoff.delayFor(attempts)),
    );
  }

  /// Holds an entry back briefly because the network was not there — as
  /// distinct from [_bumpForRetry], which records a real failed attempt.
  ///
  /// The distinction is the whole point of `SyncBackoff`'s attempt cap: it is
  /// how a permanently-broken entry is told apart from a device that has been
  /// in a dead spot all afternoon. Counting "no signal" as a failed attempt
  /// collapsed the two, and eight ticks of a 3-second retry timer — under a
  /// minute out of signal — was enough to have a real scoring action
  /// discarded as poison.
  ///
  /// The short, flat delay is deliberate. There is nothing to back off from
  /// when there is no connection to overload, and the next pass costs one
  /// cheap read that fails fast.
  SyncQueueEntry _deferForNetwork(SyncQueueEntry e) => e.copyWith(
        nextAttemptAt: DateTime.now().add(const Duration(seconds: 5)),
      );

  // --- Helpers ----------------------------------------------------------

  ScoreAction _toAction(MatchEvent e) => ScoreAction(
        type: e.type,
        side: Side.fromWire(e.payload['side'] as String?),
        payload: e.payload,
      );

  String? _entrantIdForSide(Fixture fixture, Side? side) => switch (side) {
        Side.a => fixture.entrantAId,
        Side.b => fixture.entrantBId,
        _ => null,
      };

  /// Advances a knockout winner into the next round's fixture — and, in a
  /// double-elimination draw, drops the loser into the losers bracket — in the
  /// SAME batch as the result that produced them.
  ///
  /// Factored out of [submit] so [_replayFixtureGroup] applies the identical
  /// rule to a match completed by a queued event that only lands during a
  /// reconnect — see the comment at the [submit] call site for why this must
  /// never happen in a second, separate write.
  ///
  /// The loser leg exists because losing a winners-bracket match is not an
  /// elimination: it is a transfer. The draw generator has always wired that
  /// transfer and nothing ever read it, so a double-elimination tournament
  /// wrote a full losers bracket that no player could ever reach.
  void _maybeAdvanceWinner(
    WriteBatch batch,
    Fixture fixture,
    MatchOutcome outcome,
    String? winnerEntrantId,
  ) {
    if (!outcome.isComplete || outcome.isDraw || winnerEntrantId == null) {
      return;
    }

    void feed(String? targetFixtureId, String? targetSlot, String entrantId) {
      if (targetFixtureId == null || targetSlot == null) return;
      final slot = targetSlot == 'a' ? 'A' : 'B';
      final name = entrantId == fixture.entrantAId
          ? fixture.entrantAName
          : fixture.entrantBName;
      // The account travels with the id. In an individual draw this is the
      // only record that the promoted player is in the next round — there is
      // no line-up on a knockout fixture and never will be — so without it a
      // semi-finalist's own match list stops at the quarter-final.
      final entrantUid = entrantId == fixture.entrantAId
          ? fixture.entrantAUid
          : fixture.entrantBUid;
      batch.update(
        Refs.fixture(fixture.orgId, fixture.compId, targetFixtureId),
        {
          'entrant${slot}Id': entrantId,
          'entrant${slot}Name': name,
          'entrant${slot}Uid': entrantUid,
          // Extends the target's stored summary rather than rewriting it: the
          // other half of that fixture may already be decided.
          if (entrantUid != null)
            'playerUids': FieldValue.arrayUnion([entrantUid]),
        },
      );
    }

    feed(
      fixture.feedsWinnerToFixtureId,
      fixture.feedsWinnerToSlot,
      winnerEntrantId,
    );

    // Whoever was not the winner. Derived rather than passed in, because the
    // outcome only ever names a winner and a two-sided fixture makes the
    // other side unambiguous.
    final loserEntrantId = winnerEntrantId == fixture.entrantAId
        ? fixture.entrantBId
        : fixture.entrantAId;
    if (loserEntrantId.isNotEmpty) {
      feed(
        fixture.feedsLoserToFixtureId,
        fixture.feedsLoserToSlot,
        loserEntrantId,
      );
    }
  }

  /// Generates the durable idempotency key for one event: a fresh UUIDv7,
  /// created exactly once here and then carried everywhere the event goes —
  /// onto the Firestore document, into the offline queue, and back out again
  /// unchanged if [_replayFixtureGroup] ever has to resubmit it.
  ///
  /// This used to be `'$fixtureId:$seq:$type:${payload.hashCode}'`, derived
  /// from the action's content so that a retried press would supposedly
  /// recompute the same key on its own. It never actually delivered that
  /// guarantee: `Object.hashCode` (and therefore `String.hashCode`) is not
  /// specified to be stable across process launches or between JIT and AOT
  /// builds — and this key is exactly the kind of thing that gets persisted
  /// to `SharedPreferences` and compared again after a restart. CLAUDE.md §4
  /// and §12.3 both require a client-generated UUIDv7 for this reason. The
  /// key is no longer a function of the event's content at all; the
  /// guarantee now comes from generating it once and never regenerating it
  /// — see [UuidV7]'s own doc comment for why v7 specifically.
  String _clientEventId() => UuidV7.generate();
}

/// The outcome of recomputing a match from its log.
///
/// [matchedStoredProjection] is the interesting field: false means the stored
/// score disagreed with the events, which is either a bug or tampering, and
/// is exactly what a dispute needs to establish.
class RebuildReport {
  const RebuildReport({
    required this.state,
    required this.matchedStoredProjection,
    required this.eventCount,
    required this.written,
    this.blockedReason,
  });

  final Map<String, dynamic> state;
  final bool matchedStoredProjection;
  final int eventCount;
  final bool written;

  /// Why a needed correction was not written, in words a referee can act on.
  ///
  /// Null when nothing was blocked — which includes the ordinary happy case
  /// where the projection already matched and there was nothing to write.
  /// Non-null means the log and the stored score genuinely disagree AND the
  /// disagreement is still on screen.
  final String? blockedReason;

  /// The projection disagrees with the log and could not be corrected. The one
  /// state a referee must not be allowed to mistake for "verified".
  bool get needsAttention => blockedReason != null;
}
