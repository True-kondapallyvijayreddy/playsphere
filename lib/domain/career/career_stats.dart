import '../scoring/player_stats.dart';
import '../scoring/scoring_plugin.dart';

/// A player's record in one sport, accumulated across every match they have
/// ever played, anywhere.
///
/// This is the thing the whole product is for. A player from a Hyderabad
/// community club moves to Delhi University and ten years later anyone can
/// still see what they did — but only if every match contributed to one
/// record rather than to a scorecard that dies with the fixture.
///
/// It works across sports without knowing anything about any of them because
/// every engine stores its per-player tallies in the same shape. Adding a
/// tenth sport does not change this file.
class CareerStats {
  const CareerStats({
    required this.uid,
    required this.sportId,
    required this.matchesPlayed,
    required this.tally,
    this.firstPlayedAt,
    this.lastPlayedAt,
    this.clubsPlayedFor = const {},
  });

  final String uid;
  final String sportId;
  final int matchesPlayed;

  /// Lifetime totals, keyed exactly as the sport's engine keys them.
  final Map<String, num> tally;

  final DateTime? firstPlayedAt;
  final DateTime? lastPlayedAt;

  /// Every club this player has represented in this sport.
  ///
  /// Kept as a set rather than a single "current club" because the point of a
  /// portable identity is that moving does not erase where you came from.
  final Set<String> clubsPlayedFor;

  num operator [](String key) => tally[key] ?? 0;

  /// Per-match average for any counter. Returns 0 rather than dividing by
  /// zero, so a player with no matches renders as 0 rather than crashing a
  /// profile screen.
  double per(String key) =>
      matchesPlayed == 0 ? 0 : (tally[key] ?? 0) / matchesPlayed;

  Map<String, Object?> toMap() => {
        'uid': uid,
        'sportId': sportId,
        'matchesPlayed': matchesPlayed,
        'tally': tally,
        'clubsPlayedFor': clubsPlayedFor.toList(),
      };

  /// Reads a career-stats document back.
  ///
  /// These documents have been written on every match finalize since ratings
  /// shipped, but nothing had ever read them — there was no decoder and no
  /// screen. The [docId] is the sport id, because the write path stores one
  /// document per sport at `users/{uid}/career_stats/{sportId}`.
  ///
  /// `firstPlayedAt` is not written by the finalize path, so it is always null
  /// here.
  ///
  /// [lastPlayedAt] is passed in already decoded rather than read from [d].
  /// This file is pure domain — it must not import `cloud_firestore`, or the
  /// scoring engines stop being testable without a Firebase harness — and a
  /// `Timestamp` cannot be recognised here. The repository converts it.
  factory CareerStats.fromMap(
    Map<String, dynamic>? d,
    String docId, {
    String? uid,
    DateTime? lastPlayedAt,
  }) {
    final data = d ?? const <String, dynamic>{};
    final rawTally = data['tally'];
    return CareerStats(
      uid: uid ?? (data['uid'] is String ? data['uid'] as String : ''),
      // Trust the path over the field: the document id is authoritative and a
      // mismatched `sportId` field would silently merge two sports' totals.
      sportId: docId,
      matchesPlayed:
          data['matchesPlayed'] is num ? (data['matchesPlayed'] as num).toInt() : 0,
      tally: rawTally is Map
          ? {
              for (final e in rawTally.entries)
                if (e.key is String && e.value is num)
                  e.key as String: e.value as num,
            }
          : const {},
      lastPlayedAt: lastPlayedAt,
      clubsPlayedFor: data['clubsPlayedFor'] is List
          ? {
              for (final c in data['clubsPlayedFor'] as List)
                if (c is String) c,
            }
          : const {},
    );
  }
}

/// One match's contribution to a career.
class MatchContribution {
  const MatchContribution({
    required this.uid,
    required this.sportId,
    required this.orgId,
    required this.tally,
    required this.playedAt,
  });

  final String uid;
  final String sportId;
  final String orgId;
  final Map<String, num> tally;
  final DateTime playedAt;
}

/// Turns finished matches into career records.
///
/// Pure, so the same code can run on a profile screen today and inside a
/// scheduled Cloud Function tomorrow, with identical answers. That property is
/// what makes a career statistic defensible: it can always be recomputed from
/// the matches, and any stored rollup can be checked against a recomputation.
class CareerAggregator {
  const CareerAggregator();

  /// Extracts what each REGISTERED player did in one match.
  ///
  /// Guests are skipped deliberately. A borrowed player who has never
  /// installed the app appears on the scorecard — that match is a real record
  /// and they belong on it — but they have no identity to attach a career to.
  /// Their line stays with the fixture until somebody claims it.
  List<MatchContribution> contributionsFrom({
    required Map<String, dynamic> scoreState,
    required ScoringContext ctx,
    required String sportId,
    required String orgId,
    required DateTime playedAt,
  }) {
    final out = <MatchContribution>[];
    for (final side in [Side.a, Side.b]) {
      for (final player in ctx.lineupFor(side)) {
        final uid = player.uid;
        if (uid == null) continue; // guest — no career to credit
        final tally = PlayerTally.of(scoreState, player.id);
        if (tally.isEmpty) continue; // named but never took part
        out.add(MatchContribution(
          uid: uid,
          sportId: sportId,
          orgId: orgId,
          tally: tally,
          playedAt: playedAt,
        ));
      }
    }
    return out;
  }

  /// Folds contributions into one career record per (player, sport).
  ///
  /// Sport is part of the key rather than being merged: a batting average and
  /// a raid average are not the same quantity, and summing them would produce
  /// a number that means nothing. The cross-sport view is a separate,
  /// deliberately-normalised index.
  Map<String, CareerStats> accumulate(
    Iterable<MatchContribution> contributions, {
    Map<String, CareerStats> existing = const {},
  }) {
    final result = <String, CareerStats>{...existing};

    for (final c in contributions) {
      final key = '${c.uid}::${c.sportId}';
      final prior = result[key];

      final merged = <String, num>{...?prior?.tally};
      for (final entry in c.tally.entries) {
        merged[entry.key] = (merged[entry.key] ?? 0) + entry.value;
      }

      final first = prior?.firstPlayedAt;
      final last = prior?.lastPlayedAt;

      result[key] = CareerStats(
        uid: c.uid,
        sportId: c.sportId,
        matchesPlayed: (prior?.matchesPlayed ?? 0) + 1,
        tally: merged,
        firstPlayedAt:
            first == null || c.playedAt.isBefore(first) ? c.playedAt : first,
        lastPlayedAt:
            last == null || c.playedAt.isAfter(last) ? c.playedAt : last,
        clubsPlayedFor: {...?prior?.clubsPlayedFor, c.orgId},
      );
    }
    return result;
  }

  /// A player's headline numbers for one sport, ready to render.
  ///
  /// Which counters matter differs per sport, so the caller passes the
  /// engine's own column definitions. The aggregator never hard-codes what
  /// "important" means for a sport it has never heard of.
  List<(String label, String value)> headline(
    CareerStats stats,
    List<StatColumn> columns, {
    int limit = 4,
  }) {
    final rows = <(String, String)>[
      ('Matches', '${stats.matchesPlayed}'),
    ];
    for (final column in columns) {
      if (rows.length > limit) break;
      final value = column.valueFrom(stats.tally);
      // A counter nobody ever moved is noise on a profile.
      if (value == 0) continue;
      rows.add((column.label, column.format(stats.tally)));
    }
    return rows;
  }
}
