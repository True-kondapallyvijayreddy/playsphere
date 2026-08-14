/// A precomputed, app-wide "who leads in this stat" ranking —
/// `functions/leaderboard.js`'s published output, and the CricHeroes/IPL/
/// World-Cup-style "Orange Cap" board this product never had: `career_stats`
/// has always held a lifetime tally per player, but nothing ever put one
/// player's number next to everyone else's.
///
/// ## Why a precomputed document instead of a query
///
/// Same reasoning as `TalentBoard`: ranking every player in the app is a
/// scan across profiles `firestore.rules` deliberately refuses a client
/// permission to run, so it happens once, server-side, with the Admin SDK,
/// and the client receives a finished top-50. There is no `scout` variant
/// the way a talent board has one — see `functions/leaderboard.js` for why a
/// stat leaderboard gets no gated exception: eligibility (public visibility,
/// not a minor) is decided once, before the document exists, full stop.
library;

/// Identifies one leaderboard: a sport and the one tally key it ranks by.
///
/// [statKey] is one of that sport's `ScoringPlugin.headlineStats` — cricket
/// has two boards (`runsScored`, `wickets`), most sports have one.
class LeaderboardKey {
  const LeaderboardKey({required this.sportId, required this.statKey});

  final String sportId;
  final String statKey;

  /// `{sportId}:{statKey}` — matches the document id
  /// `functions/leaderboard.js` writes.
  String get docId => '$sportId:$statKey';

  static LeaderboardKey? parse(String docId) {
    final i = docId.indexOf(':');
    if (i <= 0 || i == docId.length - 1) return null;
    return LeaderboardKey(
      sportId: docId.substring(0, i),
      statKey: docId.substring(i + 1),
    );
  }

  // Value equality so `leaderboardProvider.family` (Riverpod) dedupes two
  // widgets asking for the same board into one listener instead of opening
  // one per instance.
  @override
  bool operator ==(Object other) =>
      other is LeaderboardKey &&
      other.sportId == sportId &&
      other.statKey == statKey;

  @override
  int get hashCode => Object.hash(sportId, statKey);
}

/// One player's row on a board.
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.uid,
    required this.displayName,
    required this.value,
    required this.rank,
    this.photoUrl,
  });

  final String uid;
  final String displayName;
  final String? photoUrl;
  final num value;

  /// 1-based position on this board.
  final int rank;

  static LeaderboardEntry? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final uid = raw['uid'];
    if (uid is! String || uid.isEmpty) return null;
    final value = raw['value'];
    if (value is! num) return null;
    return LeaderboardEntry(
      uid: uid,
      displayName: (raw['displayName'] as String?) ?? 'Player',
      photoUrl: raw['photoUrl'] as String?,
      value: value,
      rank: (raw['rank'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A whole board document — the top players for one [key], largest value
/// first.
class Leaderboard {
  const Leaderboard({
    required this.key,
    required this.entries,
    this.updatedAt,
  });

  /// How many rows a board keeps — see `functions/leaderboard.js`'s `TOP_N`.
  /// A leaderboard is read top-down; the two-hundredth name on it is not a
  /// result anybody scrolls to.
  static const maxEntries = 50;

  final LeaderboardKey key;
  final List<LeaderboardEntry> entries;
  final DateTime? updatedAt;

  bool get isEmpty => entries.isEmpty;

  /// This player's row, or null if they are not (yet) in the top
  /// [maxEntries] — a real and common state, not an error.
  LeaderboardEntry? entryFor(String uid) =>
      entries.where((e) => e.uid == uid).firstOrNull;

  static Leaderboard? fromMap(
    Map<String, dynamic>? d,
    String docId, {
    DateTime? updatedAt,
  }) {
    final key = LeaderboardKey.parse(docId);
    if (key == null) return null;
    final data = d ?? const <String, dynamic>{};
    final entries = <LeaderboardEntry>[];
    for (final raw in (data['entries'] as List? ?? const [])) {
      final e = LeaderboardEntry.fromMap(raw);
      if (e != null) entries.add(e);
    }
    entries.sort((a, b) => a.rank.compareTo(b.rank));
    return Leaderboard(key: key, entries: entries, updatedAt: updatedAt);
  }
}
