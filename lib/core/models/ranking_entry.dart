import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_codec.dart';

/// One tournament result, worth points, at `rankingEntries/{entryId}`.
///
/// ## Written only by the server
///
/// This is the one collection with no client write path at all —
/// `firestore.rules` denies every client write, and the
/// `onTournamentCompleted` Cloud Function is the only writer. A ranking table
/// decides seeding, selection and funding, which makes it the most valuable
/// thing in the database to forge; a client that could write here could award
/// itself a national title.
///
/// ## Why entries rather than a running total
///
/// A rolling 52-week window is not expressible as a total: points have to
/// *leave* it as they age out, and a stored total cannot forget. Keeping the
/// individual results means the ranking is always a sum over what is still
/// current, and a player can be shown exactly which results are carrying them
/// — and which are about to expire.
class RankingEntry {
  const RankingEntry({
    required this.id,
    required this.uid,
    required this.displayName,
    required this.points,
    required this.round,
    required this.sportId,
    this.entrantId = '',
    this.orgId = '',
    this.tournamentId = '',
    this.tournamentName = '',
    this.grade = 'club',
    this.compId = '',
    this.eventName = '',
    this.categoryLabel = 'Open',
    this.awardedAt,
    this.expiresAt,
  });

  final String id;
  final String uid;
  final String displayName;
  final int points;

  /// `FinishingRound.wire` — "winner", "semi_final", and so on.
  final String round;

  final String sportId;
  final String entrantId;
  final String orgId;
  final String tournamentId;
  final String tournamentName;
  final String grade;
  final String compId;
  final String eventName;
  final String categoryLabel;

  final DateTime? awardedAt;

  /// When this result drops out of the rolling window.
  final DateTime? expiresAt;

  bool isCurrentAt(DateTime now) {
    final expiry = expiresAt;
    return expiry == null || expiry.isAfter(now);
  }

  /// Days until this result stops counting. Negative once it has.
  int? daysRemainingAt(DateTime now) => expiresAt?.difference(now).inDays;

  factory RankingEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return RankingEntry(
      id: doc.id,
      uid: Fs.str(d['uid']),
      displayName: Fs.str(d['displayName'], 'Player'),
      points: Fs.integer(d['points']),
      round: Fs.str(d['round'], 'participated'),
      sportId: Fs.str(d['sportId'], 'unknown'),
      entrantId: Fs.str(d['entrantId']),
      orgId: Fs.str(d['orgId']),
      tournamentId: Fs.str(d['tournamentId']),
      tournamentName: Fs.str(d['tournamentName'], 'Tournament'),
      grade: Fs.str(d['grade'], 'club'),
      compId: Fs.str(d['compId']),
      eventName: Fs.str(d['eventName'], 'Event'),
      categoryLabel: Fs.str(d['categoryLabel'], 'Open'),
      awardedAt: Fs.dateOrNull(d['awardedAt']),
      expiresAt: Fs.dateOrNull(d['expiresAt']),
    );
  }
}

/// One player's place on a ranking list, summed from their current entries.
class RankingRow {
  const RankingRow({
    required this.uid,
    required this.displayName,
    required this.points,
    required this.entries,
    required this.rank,
  });

  final String uid;
  final String displayName;
  final int points;

  /// The results carrying this ranking, best first. Shown so a player can see
  /// exactly what is holding them up and what is about to age out — a ranking
  /// nobody can account for is one people argue with.
  final List<RankingEntry> entries;

  final int rank;

  int get eventsCounted => entries.length;

  RankingEntry? get best => entries.isEmpty ? null : entries.first;
}

/// Builds a ranking list from the raw entries.
///
/// Summing on the client rather than storing a total per player is deliberate:
/// a rolling window means points must leave as they age, and a stored total
/// cannot forget. See [RankingEntry] for the full reasoning.
List<RankingRow> buildRanking(List<RankingEntry> entries, {DateTime? now}) {
  final clock = now ?? DateTime.now();
  final byUid = <String, List<RankingEntry>>{};
  for (final e in entries) {
    if (!e.isCurrentAt(clock)) continue;
    if (e.uid.isEmpty) continue;
    byUid.putIfAbsent(e.uid, () => []).add(e);
  }

  final rows = <({String uid, String name, int points, List<RankingEntry> es})>[];
  for (final entry in byUid.entries) {
    final es = entry.value..sort((a, b) => b.points.compareTo(a.points));
    rows.add((
      uid: entry.key,
      // The most recent name wins: people change how they are listed, and a
      // ranking showing a name they no longer use reads as somebody else.
      name: (es.toList()
            ..sort((a, b) => (b.awardedAt ?? DateTime(0))
                .compareTo(a.awardedAt ?? DateTime(0))))
          .first
          .displayName,
      points: es.fold<int>(0, (total, e) => total + e.points),
      es: es,
    ));
  }

  rows.sort((a, b) {
    final byPoints = b.points.compareTo(a.points);
    if (byPoints != 0) return byPoints;
    // Fewer events for the same points is the better ranking — the same total
    // from three tournaments beats it from ten.
    final byCount = a.es.length.compareTo(b.es.length);
    if (byCount != 0) return byCount;
    return a.name.compareTo(b.name);
  });

  return [
    for (var i = 0; i < rows.length; i++)
      RankingRow(
        uid: rows[i].uid,
        displayName: rows[i].name,
        points: rows[i].points,
        entries: rows[i].es,
        rank: i + 1,
      ),
  ];
}
