import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/errors/app_exception.dart';
import '../core/firebase/firestore_refs.dart';
import '../core/models/enums.dart';
import '../core/models/fixture.dart';
import '../domain/scoring/scoring_plugin.dart';
import '../domain/scoring/scoring_registry.dart';

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

  void dispose() => _failures.close();

  // --- Reads ------------------------------------------------------------

  /// The one listener a spectator needs.
  Stream<Fixture?> watchFixture(String orgId, String compId, String fixtureId) =>
      Refs.fixture(orgId, compId, fixtureId).snapshots().map(
            (doc) => doc.exists ? Fixture.fromDoc(doc) : null,
          );

  /// Ball-by-ball commentary feed. Only opened on screens that actually show
  /// the timeline, never just to display a score.
  Stream<List<MatchEvent>> watchEvents(
    String orgId,
    String compId,
    String fixtureId, {
    int limit = 60,
  }) {
    return Refs.matchEvents(orgId, compId, fixtureId)
        .orderBy('seq', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(MatchEvent.fromDoc).toList());
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
    final clientEventId = _clientEventId(fixture.id, nextSeq, action);

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
      },
    );

    // A knockout winner advances into the next round in the SAME batch as the
    // result that produced them. Doing it afterwards would leave a window
    // where the semi-final is decided but the final still reads "To be
    // decided", and any failure in between would strand the bracket there
    // permanently — which is exactly what happened before: the generator
    // recorded where a winner should go and nothing ever read it.
    if (outcome.isComplete &&
        !outcome.isDraw &&
        fixture.feedsWinnerToFixtureId != null &&
        fixture.feedsWinnerToSlot != null &&
        updated.winnerEntrantId != null) {
      final slot = fixture.feedsWinnerToSlot == 'a' ? 'A' : 'B';
      final winnerName = updated.winnerEntrantId == fixture.entrantAId
          ? fixture.entrantAName
          : fixture.entrantBName;
      batch.update(
        Refs.fixture(
          fixture.orgId,
          fixture.compId,
          fixture.feedsWinnerToFixtureId!,
        ),
        {
          'entrant${slot}Id': updated.winnerEntrantId,
          'entrant${slot}Name': winnerName,
        },
      );
    }

    // Record the action in our durable queue BEFORE the write leaves, so a
    // process kill between the local write and the server acknowledgement
    // cannot lose a delivery. `reconcileQueue` drops entries the server has
    // since confirmed.
    await _enqueue(fixture, action, byUid, nextSeq, clientEventId);

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
      batch.commit().then((_) => _dequeue(clientEventId)).catchError(
        (Object error) {
          _failures.add(_translateWriteFailure(error));
        },
      ),
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
    return plugin.replay(events.map(_toAction), context);
  }

  /// Marks a fixture as a walkover, abandonment or dispute.
  ///
  /// Kept off the plugin path because none of these are scoring events — they
  /// are administrative decisions about a match that did not play out
  /// normally, and every real tournament needs them.
  Future<void> setFixtureOutcome({
    required Fixture fixture,
    required FixtureStatus status,
    String? winnerEntrantId,
    String? note,
  }) async {
    if (status.acceptsScoring) {
      throw const ValidationException(
        'Use the scoring pad to record a normal result.',
      );
    }
    await Refs.fixture(fixture.orgId, fixture.compId, fixture.id).update({
      'status': status.wire,
      'winnerEntrantId': winnerEntrantId,
      'isDraw': false,
      'summary': switch (status) {
        FixtureStatus.walkover => 'Walkover',
        FixtureStatus.abandoned => 'Abandoned',
        FixtureStatus.disputed => 'Under dispute',
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
    queue.add(jsonEncode({
      'orgId': fixture.orgId,
      'compId': fixture.compId,
      'fixtureId': fixture.id,
      'seq': seq,
      'type': action.type,
      'payload': action.toEventPayload(),
      'byUid': byUid,
      'clientEventId': clientEventId,
    }));
    await store.setStringList(_queueKey, queue);
  }

  /// Drops one entry once the server has acknowledged its write.
  Future<void> _dequeue(String clientEventId) async {
    final store = await _store;
    final queue = store.getStringList(_queueKey) ?? <String>[];
    if (queue.isEmpty) return;
    final remaining = queue.where((raw) {
      try {
        return (jsonDecode(raw) as Map<String, dynamic>)['clientEventId'] !=
            clientEventId;
      } catch (_) {
        // Unparseable entry: keep it, `reconcileQueue` will deal with it.
        return true;
      }
    }).toList();
    if (remaining.length != queue.length) {
      await store.setStringList(_queueKey, remaining);
    }
  }

  /// Clears queue entries the server has since confirmed.
  ///
  /// Firestore's own offline persistence replays the writes; this queue exists
  /// only so the UI can report honestly and so nothing is invisible if the
  /// process is killed. Entries whose sequence the server already holds are
  /// dropped rather than retried, which is what the idempotency key is for.
  Future<void> reconcileQueue() async {
    final store = await _store;
    final queue = store.getStringList(_queueKey) ?? <String>[];
    if (queue.isEmpty) return;

    final remaining = <String>[];
    for (final raw in queue) {
      try {
        final item = jsonDecode(raw) as Map<String, dynamic>;
        final doc = await Refs.matchEvents(
          item['orgId'] as String,
          item['compId'] as String,
          item['fixtureId'] as String,
        ).doc(MatchEvent.docId(item['seq'] as int)).get();

        final confirmed = doc.exists &&
            (doc.data()?['clientEventId'] == item['clientEventId']);
        if (!confirmed) remaining.add(raw);
      } catch (e) {
        // Still offline, or a malformed entry. Keep it and try again later
        // rather than discarding a real scoring action.
        debugPrint('[PlaySphere] queue reconcile deferred: $e');
        remaining.add(raw);
      }
    }
    await store.setStringList(_queueKey, remaining);
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

  /// Deterministic from the fixture, sequence and action, so the *same*
  /// logical press retried after a timeout produces the same key and can be
  /// recognised as already applied.
  String _clientEventId(String fixtureId, int seq, ScoreAction action) {
    final payload = jsonEncode(action.toEventPayload());
    return '$fixtureId:$seq:${action.type}:${payload.hashCode}';
  }
}
