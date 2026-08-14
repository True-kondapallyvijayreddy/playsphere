import 'firestore_codec.dart';

/// One club's record over one window, as `functions/clubs.js` writes it.
class ClubTally {
  const ClubTally({
    this.played = 0,
    this.won = 0,
    this.drawn = 0,
    this.lost = 0,
    this.points = 0,
  });

  final int played;
  final int won;
  final int drawn;
  final int lost;
  final int points;

  bool get isEmpty => played == 0;

  /// Null below three matches rather than 100%.
  ///
  /// The same rule the tournament leaderboard applies, and for the same
  /// reason: a club that has played one inter-club match and won it is not
  /// the best club in the state, and a ladder that says so on one result is
  /// one nobody believes twice.
  double? get winRate => played < 3 ? null : won / played;

  factory ClubTally.fromMap(Map<String, dynamic>? d) {
    final m = d ?? const <String, dynamic>{};
    return ClubTally(
      played: Fs.integer(m['played']),
      won: Fs.integer(m['won']),
      drawn: Fs.integer(m['drawn']),
      lost: Fs.integer(m['lost']),
      points: Fs.integer(m['points']),
    );
  }
}

/// One club's row on the ladder, with a tally per window.
///
/// A stored total cannot forget, so the rollup publishes one tally per window
/// the screen offers rather than a single number the client tries to slice.
class ClubStanding {
  const ClubStanding({
    required this.clubId,
    required this.name,
    this.logoUrl,
    this.byWindow = const {},
  });

  final String clubId;
  final String name;
  final String? logoUrl;

  /// Keyed `all` / `d365` / `d90` / `d30` — see `WINDOWS` in
  /// `functions/clubs.js`, which this must agree with.
  final Map<String, ClubTally> byWindow;

  ClubTally tallyFor(String window) =>
      byWindow[window] ?? const ClubTally();

  factory ClubStanding.fromMap(Map<String, dynamic> d) => ClubStanding(
        clubId: Fs.str(d['clubId']),
        name: Fs.str(d['name'], 'Club'),
        logoUrl: Fs.strOrNull(d['logoUrl']),
        byWindow: {
          for (final key in const ['all', 'd365', 'd90', 'd30'])
            key: ClubTally.fromMap(Fs.map(d[key])),
        },
      );
}

/// One sport's club ladder, at `clubStandings/{sportId}`.
///
/// ## What is and is not on it
///
/// Built from inter-club fixtures — the one shape where a club is a
/// competitor in its own right, with an identity stable across every event it
/// plays. A club that only ever runs internal events has no position here,
/// which is correct rather than unfortunate: it has not played anybody. See
/// `functions/clubs.js` for why this cannot be derived from `rankingEntries`.
class ClubStandings {
  const ClubStandings({
    required this.sportId,
    this.clubs = const [],
    this.computedAt,
  });

  final String sportId;

  /// Ranked on the all-time tally. A screen showing a narrower window
  /// re-sorts, because one document can only carry one order.
  final List<ClubStanding> clubs;

  /// When the rollup last ran. The ladder needs this so a nightly number is
  /// not presented as a live one.
  final DateTime? computedAt;

  bool get isEmpty => clubs.isEmpty;

  /// The ladder for [window], highest points first, clubs with no result in
  /// that window dropped.
  ///
  /// Re-sorted here rather than server-side: the stored order is all-time, and
  /// showing it under a 30-day filter would list a club that played nothing
  /// this month above one that won four.
  List<ClubStanding> ranked(String window) {
    final rows = [
      for (final c in clubs)
        if (!c.tallyFor(window).isEmpty) c,
    ];
    rows.sort((a, b) {
      final x = a.tallyFor(window);
      final y = b.tallyFor(window);
      final byPoints = y.points.compareTo(x.points);
      if (byPoints != 0) return byPoints;
      final byWins = y.won.compareTo(x.won);
      if (byWins != 0) return byWins;
      return a.name.compareTo(b.name);
    });
    return rows;
  }

  factory ClubStandings.fromMap(Map<String, dynamic>? d, String sportId) {
    final m = d ?? const <String, dynamic>{};
    return ClubStandings(
      sportId: sportId,
      clubs: [
        // `whereType`, not a cast: one malformed row in a server-written list
        // must not take the whole ladder down with it.
        for (final row in (m['clubs'] is List ? m['clubs'] as List : const []))
          if (row is Map) ClubStanding.fromMap(Map<String, dynamic>.from(row)),
      ],
      computedAt: Fs.dateOrNull(m['computedAt']),
    );
  }
}
