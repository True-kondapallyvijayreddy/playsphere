import 'dart:convert';

import '../../domain/scoring/scoring_plugin.dart';

/// One scoring action waiting to reach the server, durable across a process
/// kill because it is persisted as JSON in `SharedPreferences`.
///
/// ## Why this is its own type
///
/// The queue used to be a bag of raw JSON maps, decoded and re-encoded ad hoc
/// at every call site. That made three things impossible to do safely:
/// batching reads (nothing grouped entries by fixture), bounding a reconnect
/// burst (nothing capped how many were processed at once), and giving a
/// permanently-broken entry a way out (nothing counted attempts). This type
/// carries that bookkeeping alongside the action itself and keeps the JSON
/// shape in one place — see [SyncBatchPlanner] in `sync_batch_planner.dart`
/// for what actually reads [attempts] and [nextAttemptAt].
///
/// ## Backward compatibility with entries queued before this existed
///
/// An entry written by the previous queue implementation has no `attempts`
/// or `nextAttemptAtMs` field, and its `clientEventId` may be built from the
/// old, unstable `fixtureId:seq:type:hash` scheme (see `ScoringService`'s
/// former `_clientEventId`) rather than a UUIDv7. Neither is migrated —
/// [fromJson] simply defaults missing bookkeeping to "never attempted, not
/// backed off", and the id is treated as an opaque string everywhere in this
/// file and in `ScoringService`: nothing ever parses or validates its shape.
/// That is what lets an old-style id already sitting in a scorer's queue at
/// upgrade time keep working exactly as it did before. Orphaning an in-flight
/// queue on an app update would silently drop real scoring actions recorded
/// on a ground with no signal, which is a worse failure than tolerating one
/// more id format forever.
class SyncQueueEntry {
  const SyncQueueEntry({
    required this.orgId,
    required this.compId,
    required this.fixtureId,
    required this.seq,
    required this.type,
    required this.payload,
    required this.byUid,
    required this.clientEventId,
    this.note,
    this.attempts = 0,
    this.nextAttemptAt,
  });

  final String orgId;
  final String compId;
  final String fixtureId;
  final int seq;
  final String type;
  final Map<String, dynamic> payload;
  final String byUid;
  final String clientEventId;
  final String? note;

  /// How many replay attempts have failed for this entry. Consulted by
  /// [SyncBatchPlanner] to space out retries and, past a threshold, to evict
  /// the entry instead of retrying it forever — see the backoff module's doc
  /// comment for why a fixed attempt count is what tells "still offline"
  /// apart from "permanently rejected".
  final int attempts;

  /// Set after a failed replay attempt. The entry is skipped by
  /// [SyncBatchPlanner.plan] until this time passes, so one malformed or
  /// rejected entry cannot spin the reconcile loop — and burn a network
  /// request — on every single reconnect.
  final DateTime? nextAttemptAt;

  /// Grouping key for causal replay: every entry for the same fixture must
  /// be delivered in `seq` order, but different fixtures have no ordering
  /// requirement relative to one another.
  String get fixtureKey => '$orgId/$compId/$fixtureId';

  /// Reconstructs the scorer's original action from the persisted payload,
  /// the same shape `ScoringService._toAction` builds from a stored
  /// [MatchEvent] — so a replayed action and a confirmed event are
  /// indistinguishable to the plugin that rebuilds the projection.
  ScoreAction toScoreAction() => ScoreAction(
        type: type,
        side: Side.fromWire(payload['side'] as String?),
        payload: payload,
      );

  SyncQueueEntry copyWith({
    int? attempts,
    DateTime? nextAttemptAt,
    bool clearNextAttemptAt = false,
  }) {
    return SyncQueueEntry(
      orgId: orgId,
      compId: compId,
      fixtureId: fixtureId,
      seq: seq,
      type: type,
      payload: payload,
      byUid: byUid,
      clientEventId: clientEventId,
      note: note,
      attempts: attempts ?? this.attempts,
      nextAttemptAt:
          clearNextAttemptAt ? null : (nextAttemptAt ?? this.nextAttemptAt),
    );
  }

  Map<String, Object?> toJson() => {
        'orgId': orgId,
        'compId': compId,
        'fixtureId': fixtureId,
        'seq': seq,
        'type': type,
        'payload': payload,
        'byUid': byUid,
        'clientEventId': clientEventId,
        'note': note,
        'attempts': attempts,
        'nextAttemptAtMs': nextAttemptAt?.millisecondsSinceEpoch,
      };

  String toJsonString() => jsonEncode(toJson());

  factory SyncQueueEntry.fromJson(Map<String, dynamic> json) {
    final nextMs = json['nextAttemptAtMs'];
    return SyncQueueEntry(
      orgId: json['orgId'] as String? ?? '',
      compId: json['compId'] as String? ?? '',
      fixtureId: json['fixtureId'] as String? ?? '',
      seq: (json['seq'] as num?)?.toInt() ?? 0,
      type: json['type'] as String? ?? '',
      payload: json['payload'] is Map
          ? Map<String, dynamic>.from(json['payload'] as Map)
          : const {},
      byUid: json['byUid'] as String? ?? '',
      clientEventId: json['clientEventId'] as String? ?? '',
      note: json['note'] as String?,
      // Absent on any entry queued before this bookkeeping existed — read as
      // "never attempted", which is simply true for those entries.
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      nextAttemptAt: nextMs is num
          ? DateTime.fromMillisecondsSinceEpoch(nextMs.toInt())
          : null,
    );
  }

  /// Parses one persisted line, or returns null for a corrupted entry rather
  /// than throwing. A single mangled line — a partial write cut off by a
  /// process kill mid-`setStringList`, for instance — must not take the rest
  /// of a scorer's queue down with it.
  static SyncQueueEntry? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return SyncQueueEntry.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }
}
