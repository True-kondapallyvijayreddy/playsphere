import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/errors/app_exception.dart';
import '../core/firebase/firestore_refs.dart';
import '../core/models/enums.dart';
import '../core/models/fixture.dart';
import '../core/sync/sync_batch_planner.dart';
import '../core/sync/sync_queue_entry.dart';
import '../core/sync/uuid_v7.dart';
import '../domain/cheer.dart';
import '../domain/scoring/match_award.dart';
import '../domain/scoring/scoring_plugin.dart';
import '../domain/scoring/scoring_registry.dart';
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
  Stream<Fixture?> watchFixture(String orgId, String compId, String fixtureId) =>
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

  Future<List<MatchEvent>> fetchAllEvents(
    String orgId,
    String compId,
    String fixtureId,
  ) async {
    final snap = await Refs.matchEvents(orgId, compId, fixtureId)
        .orderBy('seq')
        .get();
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
  Future<Fixture> submit({
    required Fixture fixture,
    required ScoreAction action,
    required ScoringContext context,
    required String byUid,
  }) async {
    final plugin = ScoringRegistry.resolve(fixture.scoringPluginKey);

    // Validate against the current projection first. A rejected action never
    // reaches the network, so an illegal press costs nothing and the scorer
    // gets an instant, specific reason.
    final result = plugin.apply(fixture.scoreState, action, context);
    if (!result.isAccepted) {
      throw ValidationException(result.rejection ?? 'That move is not allowed.');
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

    // Record the action in our durable queue BEFORE the write leaves, so a
    // process kill between the local write and the server acknowledgement
    // cannot lose a delivery. `reconcileQueue` drops entries the server has
    // since confirmed.
    await _enqueue(fixture, action, byUid, nextSeq, clientEventId);

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
    unawaited(
      batch.commit()
          .then((_) => _dequeue(clientEventId))
          .catchError((Object error) => _report(_translateWriteFailure(error))),
    );

    return updated;
  }

  AppException _translateWriteFailure(Object error) {
    if (error is! FirebaseException) {
      return const ValidationException('That score could not be saved.');
    }
    return switch (error.code) {
      // Either another scorer took this sequence number, or our projection
      // was behind and the monotonic-sequence rule rejected the write. Both
      // resolve the same way: the fixture listener delivers the winning
      // state and the pad re-renders from it.
      'already-exists' || 'permission-denied' => const ConflictException(),
      'unavailable' || 'deadline-exceeded' => const NetworkException(),
      _ => ValidationException(error.message ?? 'That score could not be saved.'),
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
      status:
          outcome.isComplete ? FixtureStatus.completed : FixtureStatus.live,
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
      },
    );

    await _enqueue(fixture, action, byUid, nextSeq, clientEventId);

    unawaited(
      batch.commit()
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
    final sorted = events.map((e) => LoggedAction(seq: e.seq, action: _toAction(e)))
        .toList()
      ..sort((x, y) => x.seq.compareTo(y.seq));
    final withdrawn = ScoringPlugin.resolveWithdrawn(sorted);

    for (final e in events.reversed) {
      if (e.type == ScoringPlugin.undoActionType) continue;
      if (!withdrawn.contains(e.seq)) return e.seq;
    }
    return null;
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
    await Refs.fixture(fixture.orgId, fixture.compId, fixture.id).update({
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
      'completedAt': FieldValue.serverTimestamp(),
    });
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

    final finalQueue = <String>[
      ...unparsable,
      ...stillPending.map((e) => e.toJsonString()),
      ...plan.deferred.map((e) => e.toJsonString()),
      ...plan.overflow.map((e) => e.toJsonString()),
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
      final fixtureDoc = await Refs.fixture(
        first.orgId,
        first.compId,
        first.fixtureId,
      ).get();
      if (!fixtureDoc.exists) {
        // Most likely still offline — this read itself would have thrown if
        // there were truly no connection, so an absent-but-reachable
        // fixture more likely means the match was deleted server-side.
        // Either way there is nothing to replay onto right now; back off
        // and let the next reconnect re-evaluate rather than guessing.
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

      if (maxSeq <= fixture.lastSeq) {
        // The server's sequence has already moved past what we are trying
        // to deliver, yet the clientEventId at that seq did not match ours
        // above — so this is not "still offline", it is a genuine conflict:
        // some other write legitimately owns that sequence slot now (a
        // second device scoring the same locked match, most plausibly).
        // Writing anyway would fail the security rules' monotonic-sequence
        // check regardless, so this is treated the same as any other
        // rejection: back off and report it rather than spinning on it.
        _report(const ConflictException());
        return stillUnconfirmed.map(_bumpForRetry).toList();
      }

      final winnerEntrantId = outcome.isComplete
          ? _entrantIdForSide(fixture, outcome.winnerSide)
          : null;

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
          'summary': plugin.summary(rebuilt, context),
          'status': outcome.isComplete
              ? FixtureStatus.completed.wire
              : FixtureStatus.live.wire,
          'winnerEntrantId': winnerEntrantId,
          'isDraw': outcome.isDraw,
          if (fixture.lastSeq == 0) 'startedAt': FieldValue.serverTimestamp(),
          if (outcome.isComplete)
            'completedAt': FieldValue.serverTimestamp(),
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

      await batch.commit();

      // No rating call here either — see the note at the [submit] call site.
      // Settlement is `onMatchSettled`'s, and it fires off the same status
      // transition this batch just wrote, so a match completed offline settles
      // on reconnect exactly like one completed live.
      return const [];
    } catch (e) {
      _report(_translateWriteFailure(e));
      return group.map(_bumpForRetry).toList();
    }
  }

  SyncQueueEntry _bumpForRetry(SyncQueueEntry e) {
    final attempts = e.attempts + 1;
    return e.copyWith(
      attempts: attempts,
      nextAttemptAt: DateTime.now().add(SyncBackoff.delayFor(attempts)),
    );
  }

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
      batch.update(
        Refs.fixture(fixture.orgId, fixture.compId, targetFixtureId),
        {'entrant${slot}Id': entrantId, 'entrant${slot}Name': name},
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
