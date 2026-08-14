/// The published output of talent discovery: a small, already-filtered
/// leaderboard document that a client reads whole.
///
/// ## Why a precomputed document instead of a query
///
/// "Rising players in Nalgonda, U-17, kabaddi" is a ranking over every rated
/// player in a district. There is no Firestore query that produces it — and
/// there should not be, because `firestore.rules` deliberately refuses to let
/// any client read across other people's profiles. The scan has to happen
/// somewhere the client cannot reach, with the Admin SDK, and the client has
/// to receive a finished answer.
///
/// This is the same shape `gov_aggregates` already uses, for the same reason,
/// and it is what makes the privacy story tractable: the decision about who
/// may appear on a board is made once, server-side, by the code that builds
/// it — never by a filter on the reading device.
///
/// ## The two audiences
///
/// Boards come in two variants, distinguished by [BoardAudience]:
///
/// - **public** — adults who chose `ProfileVisibility.public`. Anyone may
///   read these. This is the "Rising Talent" feed in the app.
/// - **scout** — the same computation including minors, readable only by an
///   account holding the `scout` (or `admin`) claim.
///
/// Splitting them is what lets the feature serve the population it was
/// designed for without publishing children to the open internet. A
/// fifteen-year-old who is the best kabaddi raider in her district does need
/// to be findable — that is the whole premise of §6 feeding §7 — but she
/// needs to be findable *by a scout*, through a surface that is gated and
/// auditable, not by anyone who installs the app. Appearing on a scout board
/// still reveals nothing beyond what a board row carries; contacting her
/// remains gated by `guardianConsents` exactly as it was before.
library;

import '../gov/age_group.dart';

/// Who is allowed to read a board.
enum BoardAudience {
  /// Adults with a public profile. World-readable.
  public('public'),

  /// Includes minors. Requires the `scout` or `admin` claim.
  scout('scout');

  const BoardAudience(this.wire);
  final String wire;

  static BoardAudience fromWire(String? w) => BoardAudience.values.firstWhere(
        (e) => e.wire == w,
        // The stricter of the two. An unrecognised value must never widen an
        // audience — a board written by a newer function than this client
        // understands is treated as scout-only until this client is updated.
        orElse: () => BoardAudience.scout,
      );
}

/// The sentinel used in a board key for "not narrowed on this axis".
///
/// A literal rather than an empty string or a missing segment, because a
/// document id is parsed by splitting on `__` and an empty segment there is
/// indistinguishable from a malformed key. Chosen with a leading underscore
/// so it cannot collide with a real state, district or age-band label.
const String kBoardAny = '_any';

/// Identifies one board. Serialises to and from the Firestore document id.
///
/// ## Why the id is composite rather than a random one plus fields
///
/// The client knows exactly which board it wants before it asks — sport,
/// place, age band, audience are all chosen in the UI. A composite id turns
/// that into a single `doc().get()`, with no index, no query and no rules
/// evaluation beyond the one on the document itself. A random id would force
/// a `where`-query across a collection of boards, which needs a composite
/// index per filter combination and hands the rules engine a much harder
/// question than "may this reader see this document".
class TalentBoardKey {
  const TalentBoardKey({
    required this.sportId,
    required this.audience,
    this.state = kBoardAny,
    this.district = kBoardAny,
    this.ageGroup,
  });

  final String sportId;
  final BoardAudience audience;

  /// [kBoardAny] for a national board.
  final String state;

  /// [kBoardAny] for a state-wide board. Meaningless unless [state] is set —
  /// [isCoherent] rejects the combination.
  final String district;

  /// Null for an all-ages board.
  final AgeGroup? ageGroup;

  /// A district cannot be narrowed while the state above it is not. The
  /// builder never emits such a key; this guards the parse path, where a
  /// hand-typed or corrupted id could otherwise produce a board that silently
  /// matches nothing.
  bool get isCoherent => !(state == kBoardAny && district != kBoardAny);

  /// Slugs a free-text place name into something safe for a document id.
  ///
  /// Firestore ids may not contain `/`, and the key parser splits on `__`, so
  /// both have to go. Case is folded because district names arrive from
  /// hand-entered org profiles where "Nalgonda" and "nalgonda" are the same
  /// place and must not become two boards.
  static String slug(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) return kBoardAny;
    final cleaned = trimmed
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return cleaned.isEmpty ? kBoardAny : cleaned;
  }

  /// `{sport}__{state}__{district}__{age}__{audience}`.
  String get docId => [
        slug(sportId),
        state,
        district,
        ageGroup?.name ?? kBoardAny,
        audience.wire,
      ].join('__');

  static TalentBoardKey? parse(String docId) {
    final parts = docId.split('__');
    if (parts.length != 5) return null;
    final age = parts[3] == kBoardAny
        ? null
        : AgeGroup.values.where((a) => a.name == parts[3]).firstOrNull;
    if (parts[3] != kBoardAny && age == null) return null;
    final key = TalentBoardKey(
      sportId: parts[0],
      state: parts[1],
      district: parts[2],
      ageGroup: age,
      audience: BoardAudience.fromWire(parts[4]),
    );
    return key.isCoherent ? key : null;
  }

  /// How this board describes its own scope, for a screen header.
  String get scopeLabel {
    final place = district != kBoardAny
        ? _titleCase(district)
        : state != kBoardAny
            ? _titleCase(state)
            : 'All India';
    final age = ageGroup?.label ?? 'All ages';
    return '$place · $age';
  }

  static String _titleCase(String slug) => slug
      .split('-')
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

/// One player on a rising-talent board.
///
/// Carries only what a board row renders. Notably it does **not** carry a
/// date of birth, a precise location, or any contact detail — a board is a
/// discovery surface, and everything past discovery goes through the existing
/// consent path. [ageGroupLabel] is a band, computed server-side at build
/// time, not a birth date the reader could work an age back from.
class RisingPlayerEntry {
  const RisingPlayerEntry({
    required this.uid,
    required this.displayName,
    required this.rank,
    required this.score,
    required this.ratingDelta,
    required this.matchesInWindow,
    required this.ageGroupLabel,
    this.photoUrl,
    this.districtLabel,
    this.clubName,
    this.provisional = false,
    this.truncatedSpan = false,
  });

  final String uid;
  final String displayName;

  /// 1-based position on this board.
  final int rank;

  final double score;

  /// Glicko points gained over the window. The number a row actually shows —
  /// "+64 in 90 days" is legible in a way a shrunk composite score is not.
  final double ratingDelta;

  final int matchesInWindow;
  final String ageGroupLabel;
  final String? photoUrl;
  final String? districtLabel;

  /// The club this player most recently represented, if any.
  final String? clubName;

  /// The rating behind this climb is still unsettled — see
  /// `RisingSignal.provisional`.
  final bool provisional;

  /// The rating trail did not reach the full window, so [ratingDelta] covers
  /// a shorter interval. See `TrendSpan.truncated`.
  final bool truncatedSpan;

  Map<String, Object?> toMap() => {
        'uid': uid,
        'displayName': displayName,
        'rank': rank,
        'score': score,
        'ratingDelta': ratingDelta,
        'matchesInWindow': matchesInWindow,
        'ageGroupLabel': ageGroupLabel,
        'photoUrl': photoUrl,
        'districtLabel': districtLabel,
        'clubName': clubName,
        'provisional': provisional,
        'truncatedSpan': truncatedSpan,
      };

  static RisingPlayerEntry? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final uid = raw['uid'];
    if (uid is! String || uid.isEmpty) return null;
    return RisingPlayerEntry(
      uid: uid,
      displayName: (raw['displayName'] as String?) ?? 'Player',
      rank: (raw['rank'] as num?)?.toInt() ?? 0,
      score: (raw['score'] as num?)?.toDouble() ?? 0,
      ratingDelta: (raw['ratingDelta'] as num?)?.toDouble() ?? 0,
      matchesInWindow: (raw['matchesInWindow'] as num?)?.toInt() ?? 0,
      ageGroupLabel: (raw['ageGroupLabel'] as String?) ?? 'Senior',
      photoUrl: raw['photoUrl'] as String?,
      districtLabel: raw['districtLabel'] as String?,
      clubName: raw['clubName'] as String?,
      provisional: raw['provisional'] == true,
      truncatedSpan: raw['truncatedSpan'] == true,
    );
  }
}

/// One club on a rising-teams board.
class RisingTeamEntry {
  const RisingTeamEntry({
    required this.orgId,
    required this.orgName,
    required this.rank,
    required this.score,
    required this.matchesInWindow,
    required this.winsInWindow,
    required this.recentWinRate,
    required this.momentum,
    this.logoUrl,
    this.districtLabel,
    this.tournamentWins = 0,
  });

  final String orgId;
  final String orgName;
  final int rank;
  final double score;
  final int matchesInWindow;
  final int winsInWindow;

  /// 0..1.
  final double recentWinRate;

  /// Change against the club's own lifetime rate. See `TeamFormSignal`.
  final double momentum;

  final String? logoUrl;
  final String? districtLabel;

  /// Tournaments won inside the window, from `rankingEntries`. Shown rather
  /// than scored — a knockout title and a league title carry very different
  /// numbers of matches, and folding that into [score] would double-count the
  /// wins already in [winsInWindow].
  final int tournamentWins;

  Map<String, Object?> toMap() => {
        'orgId': orgId,
        'orgName': orgName,
        'rank': rank,
        'score': score,
        'matchesInWindow': matchesInWindow,
        'winsInWindow': winsInWindow,
        'recentWinRate': recentWinRate,
        'momentum': momentum,
        'logoUrl': logoUrl,
        'districtLabel': districtLabel,
        'tournamentWins': tournamentWins,
      };

  static RisingTeamEntry? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final orgId = raw['orgId'];
    if (orgId is! String || orgId.isEmpty) return null;
    return RisingTeamEntry(
      orgId: orgId,
      orgName: (raw['orgName'] as String?) ?? 'Club',
      rank: (raw['rank'] as num?)?.toInt() ?? 0,
      score: (raw['score'] as num?)?.toDouble() ?? 0,
      matchesInWindow: (raw['matchesInWindow'] as num?)?.toInt() ?? 0,
      winsInWindow: (raw['winsInWindow'] as num?)?.toInt() ?? 0,
      recentWinRate: (raw['recentWinRate'] as num?)?.toDouble() ?? 0,
      momentum: (raw['momentum'] as num?)?.toDouble() ?? 0,
      logoUrl: raw['logoUrl'] as String?,
      districtLabel: raw['districtLabel'] as String?,
      tournamentWins: (raw['tournamentWins'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A whole board document.
class TalentBoard {
  const TalentBoard({
    required this.key,
    required this.players,
    required this.teams,
    required this.windowDays,
    this.computedAt,
    this.playerPoolSize = 0,
    this.teamPoolSize = 0,
  });

  /// How many rows a board keeps. A discovery feed is read top-down and
  /// abandoned; the hundredth rising player in a district is not a result
  /// anybody scrolls to, and an unbounded array would eventually breach
  /// Firestore's 1 MiB document limit on a board for a large sport.
  static const maxEntries = 50;

  final TalentBoardKey key;
  final List<RisingPlayerEntry> players;
  final List<RisingTeamEntry> teams;

  /// The measurement window these rankings were computed over.
  final int windowDays;

  final DateTime? computedAt;

  /// How many candidates were considered before the top [maxEntries] were
  /// kept. Shown in the UI so "3 rising players" reads as a real count of a
  /// small district rather than as a truncated list.
  final int playerPoolSize;
  final int teamPoolSize;

  bool get isEmpty => players.isEmpty && teams.isEmpty;

  Map<String, Object?> toMap() => {
        'sportId': key.sportId,
        'state': key.state,
        'district': key.district,
        'ageGroup': key.ageGroup?.name ?? kBoardAny,
        'audience': key.audience.wire,
        'windowDays': windowDays,
        'playerPoolSize': playerPoolSize,
        'teamPoolSize': teamPoolSize,
        'players': [for (final p in players) p.toMap()],
        'teams': [for (final t in teams) t.toMap()],
      };

  /// Decodes a board document. [docId] is authoritative for the key — the
  /// mirrored fields in the body exist for server-side querying and are not
  /// trusted to agree.
  static TalentBoard? fromMap(
    Map<String, dynamic>? d,
    String docId, {
    DateTime? computedAt,
  }) {
    final key = TalentBoardKey.parse(docId);
    if (key == null) return null;
    final data = d ?? const <String, dynamic>{};
    final players = <RisingPlayerEntry>[];
    for (final raw in (data['players'] as List? ?? const [])) {
      final e = RisingPlayerEntry.fromMap(raw);
      if (e != null) players.add(e);
    }
    final teams = <RisingTeamEntry>[];
    for (final raw in (data['teams'] as List? ?? const [])) {
      final e = RisingTeamEntry.fromMap(raw);
      if (e != null) teams.add(e);
    }
    players.sort((a, b) => a.rank.compareTo(b.rank));
    teams.sort((a, b) => a.rank.compareTo(b.rank));
    return TalentBoard(
      key: key,
      players: players,
      teams: teams,
      windowDays: (data['windowDays'] as num?)?.toInt() ?? 90,
      computedAt: computedAt,
      playerPoolSize:
          (data['playerPoolSize'] as num?)?.toInt() ?? players.length,
      teamPoolSize: (data['teamPoolSize'] as num?)?.toInt() ?? teams.length,
    );
  }
}
