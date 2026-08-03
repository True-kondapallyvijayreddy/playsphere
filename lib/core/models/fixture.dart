import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/scoring/match_award.dart';
import '../../domain/scoring/scoring_plugin.dart';
import 'draw_slot.dart';
import 'enums.dart';
import 'firestore_codec.dart';
import 'match_official.dart';
import 'match_player.dart';
import 'squad_entry.dart';

/// One scheduled contest between two entrants, at
/// `orgs/{orgId}/competitions/{compId}/fixtures/{fixtureId}`.
///
/// The fixture document deliberately carries a denormalized copy of the live
/// score in [scoreState] and [summary]. That is what lets a parent in an
/// office, or a class watching on a laptop, follow a match by holding open
/// exactly ONE document listener — not a listener over a growing event
/// collection. At a thousand concurrent spectators that difference is the
/// difference between a free tier and a bill.
///
/// The authoritative record is still the append-only `events` subcollection.
/// [scoreState] is a projection of it and can always be rebuilt by replaying
/// events through the sport's scoring plugin.
class Fixture {
  const Fixture({
    required this.id,
    required this.orgId,
    required this.compId,
    required this.entrantAId,
    required this.entrantBId,
    required this.entrantAName,
    required this.entrantBName,
    required this.status,
    this.round = 1,
    this.matchIndex = 0,
    this.roundLabel,
    this.scheduledAt,
    this.venue,
    this.scorerUids = const [],
    this.participantOrgIds,
    this.officials = const [],
    this.scoreState = const {},
    this.summary = '',
    this.lastSeq = 0,
    this.winnerEntrantId,
    this.isDraw = false,
    this.rulesetVersion = 1,
    this.scoringPluginKey = 'simple_points',
    this.sportId,
    this.scoringConfig = const {},
    this.lineupA = const [],
    this.lineupB = const [],
    this.squadLockedA = false,
    this.squadLockedB = false,
    this.mvp,
    this.squadCallA = const SquadCall(),
    this.squadCallB = const SquadCall(),
    this.tossWonByEntrantId,
    this.tossDecision,
    this.feedsWinnerToFixtureId,
    this.feedsWinnerToSlot,
    this.feedsLoserToFixtureId,
    this.feedsLoserToSlot,
    this.bracket = Bracket.knockout,
    this.groupId,
    this.qualifierA,
    this.qualifierB,
    this.courtId,
    this.resultType = MatchResultType.normal,
    this.resultNote,
    this.startedAt,
    this.completedAt,
  });

  final String id;
  final String orgId;
  final String compId;

  final String entrantAId;
  final String entrantBId;

  /// Denormalized names so a fixture list renders without N extra reads.
  final String entrantAName;
  final String entrantBName;

  final FixtureStatus status;
  final int round;
  final int matchIndex;

  /// "Quarter-final", "Round 3" — set by the generator so the bracket reads
  /// correctly without the UI having to infer it from round numbers.
  final String? roundLabel;

  final DateTime? scheduledAt;
  final String? venue;

  /// Who may score this match. Security rules check membership of this list
  /// on every event write, so an unrelated member cannot alter a score.
  final List<String> scorerUids;

  /// The two organizations contesting an inter-club match, mirrored from the
  /// parent competition.
  ///
  /// Duplicated deliberately: the rules that guard fixtures, events and the
  /// public spectator view all evaluate per-document, and reaching up to the
  /// parent competition would cost an extra `get()` on every single score
  /// event. Copying two ids onto the fixture keeps ball-by-ball writes to one
  /// document read, which is what makes rural scoring affordable.
  ///
  /// Null for ordinary internal fixtures.
  final List<String>? participantOrgIds;

  /// Assigned match officials / umpires / referees.
  final List<MatchOfficial> officials;

  /// Plugin-specific projected state. Opaque here on purpose — the fixture
  /// model must not know how cricket differs from badminton.
  final Map<String, dynamic> scoreState;

  /// Short human-readable score, e.g. "21-18, 19-21, 15-11". Kept so list
  /// views and notifications never need to load a plugin to show a score.
  final String summary;

  /// Sequence number of the most recent applied event. Security rules require
  /// this to strictly increase, so a stale client cannot overwrite a newer
  /// score with an older projection.
  final int lastSeq;

  final String? winnerEntrantId;
  final bool isDraw;
  final int rulesetVersion;
  final String scoringPluginKey;

  /// Which catalogue sport this is.
  ///
  /// Distinct from [scoringPluginKey] because several sports share an engine:
  /// badminton and throwball both run the set-based plugin, and swimming and
  /// both athletics disciplines share the athletics engine. Keying anything
  /// player-facing on the plugin merges those into one pool — a chess rating
  /// and a carrom rating are not the same number.
  ///
  /// Nullable for fixtures written before this field existed; [sport] falls
  /// back to the plugin key so old data still resolves to something stable.
  final String? sportId;

  String get sport => sportId ?? scoringPluginKey;

  /// The key a Glicko-2 rating is stored under.
  ///
  /// Chess is rated per time control, per §7.11 — bullet and classical
  /// measure different skills and merging them makes both meaningless. Every
  /// other sport rates as itself.
  String get ratingKey {
    if (sport != 'chess') return sport;
    final tc = scoringConfig['timeControl'];
    return tc is String && tc.isNotEmpty ? 'chess:$tc' : 'chess';
  }

  /// The sport's scoring configuration, frozen onto the fixture when the draw
  /// was generated — points per set, overs per innings, whether draws are
  /// allowed.
  ///
  /// It lives here rather than being looked up from the sport catalogue at
  /// render time for two reasons. It is what the competition was actually
  /// played under, so improving a catalogue default next season cannot
  /// retroactively change how a finished match reads. And every surface that
  /// renders a score — the spectator screen, the live card in a list — can
  /// then do so from the fixture alone, with no second read. Without it those
  /// surfaces silently fell back to plugin defaults and showed a volleyball
  /// set as "to 21" instead of "to 25".
  final Map<String, dynamic> scoringConfig;

  /// Who is playing, per side.
  ///
  /// Set before the first ball. Every player-level statistic the spec calls
  /// for — batting figures, goal scorers, raid points — depends on the engine
  /// being able to name people, and this is where the names live.
  final List<MatchPlayer> lineupA;
  final List<MatchPlayer> lineupB;

  bool get hasLineups => lineupA.isNotEmpty && lineupB.isNotEmpty;

  /// Whether each club has declared its side final.
  ///
  /// In an inter-club match the two squads are chosen by two different clubs
  /// who do not answer to each other, and "we are done picking" is a real
  /// event in that negotiation — the flow calls it locking the final squad.
  /// Until a side is locked the other club is looking at a list that may
  /// still change; once it is locked, only that club can reopen it.
  ///
  /// Not a substitute for the match itself locking. A squad lock is a
  /// statement by a club before the toss; the scorecard freezing at the end
  /// is a different thing entirely.
  final bool squadLockedA;
  final bool squadLockedB;

  bool get bothSquadsLocked => squadLockedA && squadLockedB;

  /// The best performer, decided at the final ball.
  ///
  /// Written into the same batch as the result it belongs to, so a scorecard
  /// never exists in a state where the match is over but the award is still
  /// being worked out — and so it is decided offline, on the ground, like
  /// everything else on the scoring path.
  ///
  /// Null when there is nothing to judge on: a sport whose engine records no
  /// per-player statistics, or a match where nobody's tally moved.
  final MatchAward? mvp;

  /// How each club is filling its own side — whether registration is open to
  /// its members, how many places there are, and how many are taken.
  ///
  /// Lives on the fixture rather than the competition because in a challenge
  /// there are two of them, owned by two different clubs. See [SquadCall].
  final SquadCall squadCallA;
  final SquadCall squadCallB;

  SquadCall squadCallFor(String side) => side == 'a' ? squadCallA : squadCallB;

  /// Whether the squad for [entrantId] has been declared final.
  bool squadLockedFor(String entrantId) {
    if (entrantId == entrantAId) return squadLockedA;
    if (entrantId == entrantBId) return squadLockedB;
    return false;
  }

  /// Which side of this fixture [orgId] is, in an inter-club match.
  ///
  /// A challenge fixture puts the two clubs' own ids in `entrantAId` and
  /// `entrantBId` (see `CommunityRepository.acceptChallenge`), which is what
  /// makes "this club may only pick its own players" answerable without a
  /// second lookup — here, and identically in `firestore.rules`.
  ///
  /// Returns null for an ordinary internal competition, where the entrants
  /// are players or club teams rather than clubs, and the hosting club's
  /// organizers manage both sides as before.
  String? sideForOrg(String orgId) {
    if (participantOrgIds == null) return null;
    if (entrantAId == orgId) return 'a';
    if (entrantBId == orgId) return 'b';
    return null;
  }

  /// Every registered account that actually played, flattened across both
  /// sides. Guests (no account) contribute nothing here — nothing accrues to
  /// them.
  ///
  /// Denormalized onto the document because `firestore.rules` has to answer
  /// "did this player play in this match" when a scorer settles ratings and
  /// career stats onto other people's profiles, and rules cannot reach inside
  /// the lineup maps to find out. Derived rather than stored as a field so it
  /// can never drift from the line-ups it summarises.
  List<String> get playerUids => <String>{
        for (final p in lineupA) ...[if (p.uid != null) p.uid!],
        for (final p in lineupB) ...[if (p.uid != null) p.uid!],
      }.toList(growable: false);

  /// Who won the toss, and what they chose — 'bat' or 'field'.
  ///
  /// Every match starts with one, and until now the app simply assumed side A
  /// batted first. Recording it makes the scorecard honest and is what a
  /// cricket engine needs to know which innings belongs to whom.
  final String? tossWonByEntrantId;
  final String? tossDecision;

  bool get tossDone => tossWonByEntrantId != null;

  /// The context needed to render or score this fixture, built from the
  /// fixture alone. One definition, so a score can never read differently on
  /// the scoring pad than it does for a spectator.
  ScoringContext scoringContext() => ScoringContext(
        entrantAName: entrantAName,
        entrantBName: entrantBName,
        config: scoringConfig,
        lineupA: lineupA,
        lineupB: lineupB,
      );

  /// For knockout draws: where this match's winner advances to.
  final String? feedsWinnerToFixtureId;

  /// Which side of that fixture the winner fills — 'a' or 'b'. Set by the
  /// draw generator so advancement never has to guess.
  final String? feedsWinnerToSlot;

  /// Where this match's *loser* is sent — populated only inside a
  /// double-elimination draw, where losing a winners-bracket match drops a
  /// player into the losers bracket instead of eliminating them outright.
  ///
  /// Null everywhere else, including on every losers-bracket match itself: a
  /// losers-bracket loss is a real elimination and goes nowhere. Until this
  /// field existed the generator wired the whole losers bracket correctly and
  /// the persistence layer dropped it, so the bracket was written and nobody
  /// ever arrived in it.
  final String? feedsLoserToFixtureId;
  final String? feedsLoserToSlot;

  /// Which sub-bracket this match belongs to. Defaults to [Bracket.knockout],
  /// which is what every fixture written before this field existed was.
  final Bracket bracket;

  /// Set on [Bracket.group] matches — "A", "B", … — and null everywhere else.
  ///
  /// This is the field a group table is computed over. Without it the
  /// standings calculator can only produce one table across the whole draw,
  /// which for a groups+knockout competition is a table nobody wants and no
  /// group table at all — so qualifiers could never be resolved.
  final String? groupId;

  /// On a knockout fixture whose entrant is not yet known, which table
  /// position will fill this side once the groups finish. Null once the real
  /// entrant is known, and null for a side that is genuinely empty (a bye).
  final QualifierSource? qualifierA;
  final QualifierSource? qualifierB;

  /// Which playing area within [venue] this match is on — court 3 of a
  /// badminton hall, pitch 2 of a ground.
  ///
  /// Distinct from [venue] because capacity lives here: a venue with six
  /// courts runs six matches at once, and a schedule that cannot say which
  /// court a match is on is not a schedule, it is a start time.
  final String? courtId;

  /// What to show on a side with no entrant yet — the qualifier it is waiting
  /// on, if it is waiting on one, rather than a bare "To be decided".
  String displayNameA() =>
      entrantAId.isNotEmpty ? entrantAName : (qualifierA?.label ?? entrantAName);

  String displayNameB() =>
      entrantBId.isNotEmpty ? entrantBName : (qualifierB?.label ?? entrantBName);

  /// Whether both sides are known, so this match can actually be played.
  /// A knockout placeholder still waiting on a feeder is not playable, and
  /// the scheduler must not call it to a court.
  bool get hasBothEntrants => entrantAId.isNotEmpty && entrantBId.isNotEmpty;

  /// How the match ended — see [MatchResultType]. Defaults to [normal], which
  /// is what every fixture written before this field existed was.
  final MatchResultType resultType;

  /// Why, in the organizer's or referee's own words: "opponent did not arrive
  /// by the 20-minute cut-off", "retired at 11-6 in game 2, ankle".
  ///
  /// `forceResult` has always written this field and no model has ever read
  /// it, so every explanation an organizer typed went into Firestore and was
  /// visible nowhere — which is exactly the record a protest needs weeks
  /// later.
  final String? resultNote;

  final DateTime? startedAt;
  final DateTime? completedAt;

  /// Whether this result should award league points. See
  /// [MatchResultType.countsForStandings].
  bool get countsForStandings =>
      status.isResulted && resultType.countsForStandings;

  bool get isLive => status == FixtureStatus.live;
  bool get hasResult => status.isResulted;

  bool canBeScoredBy(String uid) =>
      status.acceptsScoring && scorerUids.contains(uid);

  factory Fixture.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Fixture(
      id: doc.id,
      orgId: Fs.str(d['orgId']),
      compId: Fs.str(d['compId']),
      entrantAId: Fs.str(d['entrantAId']),
      entrantBId: Fs.str(d['entrantBId']),
      entrantAName: Fs.str(d['entrantAName'], 'Entrant A'),
      entrantBName: Fs.str(d['entrantBName'], 'Entrant B'),
      status: FixtureStatus.fromWire(Fs.str(d['status'])),
      round: Fs.integer(d['round'], 1),
      matchIndex: Fs.integer(d['matchIndex']),
      roundLabel: Fs.strOrNull(d['roundLabel']),
      scheduledAt: Fs.dateOrNull(d['scheduledAt']),
      venue: Fs.strOrNull(d['venue']),
      scorerUids: Fs.strList(d['scorerUids']),
      participantOrgIds: d['participantOrgIds'] is List
          ? Fs.strList(d['participantOrgIds'])
          : null,
      officials: MatchOfficial.listFrom(d['officials']),
      scoreState: Fs.map(d['scoreState']),
      summary: Fs.str(d['summary']),
      lastSeq: Fs.integer(d['lastSeq']),
      winnerEntrantId: Fs.strOrNull(d['winnerEntrantId']),
      isDraw: Fs.boolean(d['isDraw']),
      rulesetVersion: Fs.integer(d['rulesetVersion'], 1),
      scoringPluginKey: Fs.str(d['scoringPluginKey'], 'simple_points'),
      sportId: Fs.strOrNull(d['sportId']),
      scoringConfig: Fs.map(d['scoringConfig']),
      lineupA: MatchPlayer.listFrom(d['lineupA']),
      lineupB: MatchPlayer.listFrom(d['lineupB']),
      squadLockedA: Fs.boolean(d['squadLockedA']),
      squadLockedB: Fs.boolean(d['squadLockedB']),
      squadCallA: SquadCall.fromMap(
        d['squadCallA'] is Map
            ? Map<String, dynamic>.from(d['squadCallA'] as Map)
            : null,
      ),
      squadCallB: SquadCall.fromMap(
        d['squadCallB'] is Map
            ? Map<String, dynamic>.from(d['squadCallB'] as Map)
            : null,
      ),
      mvp: MatchAward.fromMap(
        d['mvp'] is Map ? Map<String, dynamic>.from(d['mvp'] as Map) : null,
      ),
      tossWonByEntrantId: Fs.strOrNull(d['tossWonByEntrantId']),
      tossDecision: Fs.strOrNull(d['tossDecision']),
      feedsWinnerToFixtureId: Fs.strOrNull(d['feedsWinnerToFixtureId']),
      feedsWinnerToSlot: Fs.strOrNull(d['feedsWinnerToSlot']),
      feedsLoserToFixtureId: Fs.strOrNull(d['feedsLoserToFixtureId']),
      feedsLoserToSlot: Fs.strOrNull(d['feedsLoserToSlot']),
      bracket: Bracket.fromWire(Fs.strOrNull(d['bracket'])),
      groupId: Fs.strOrNull(d['groupId']),
      qualifierA: QualifierSource.fromWire(Fs.strOrNull(d['qualifierA'])),
      qualifierB: QualifierSource.fromWire(Fs.strOrNull(d['qualifierB'])),
      courtId: Fs.strOrNull(d['courtId']),
      resultType: MatchResultType.fromWire(Fs.strOrNull(d['resultType'])),
      resultNote: Fs.strOrNull(d['resultNote']),
      startedAt: Fs.dateOrNull(d['startedAt']),
      completedAt: Fs.dateOrNull(d['completedAt']),
    );
  }

  Map<String, Object?> toCreate() => {
        'orgId': orgId,
        'compId': compId,
        'entrantAId': entrantAId,
        'entrantBId': entrantBId,
        'entrantAName': entrantAName,
        'entrantBName': entrantBName,
        'status': status.wire,
        'round': round,
        'matchIndex': matchIndex,
        'roundLabel': roundLabel,
        'scheduledAt': Fs.ts(scheduledAt),
        'venue': venue,
        'scorerUids': scorerUids,
        'participantOrgIds': participantOrgIds,
        'officials': MatchOfficial.listTo(officials),
        'scoreState': scoreState,
        'summary': summary,
        'lastSeq': 0,
        'winnerEntrantId': null,
        'isDraw': false,
        'rulesetVersion': rulesetVersion,
        'scoringPluginKey': scoringPluginKey,
        'sportId': sportId,
        'scoringConfig': scoringConfig,
        'lineupA': MatchPlayer.listTo(lineupA),
        'lineupB': MatchPlayer.listTo(lineupB),
        'squadLockedA': squadLockedA,
        'squadLockedB': squadLockedB,
        'mvp': mvp?.toMap(),
        'squadCallA': squadCallA.toMap(),
        'squadCallB': squadCallB.toMap(),
        'playerUids': playerUids,
        'tossWonByEntrantId': tossWonByEntrantId,
        'tossDecision': tossDecision,
        'feedsWinnerToFixtureId': feedsWinnerToFixtureId,
        'feedsWinnerToSlot': feedsWinnerToSlot,
        'feedsLoserToFixtureId': feedsLoserToFixtureId,
        'feedsLoserToSlot': feedsLoserToSlot,
        'bracket': bracket.wire,
        'groupId': groupId,
        'qualifierA': qualifierA?.wire,
        'qualifierB': qualifierB?.wire,
        'courtId': courtId,
        'resultType': resultType.wire,
        'resultNote': resultNote,
        'createdAt': FieldValue.serverTimestamp(),
      };

  /// [clearWinner] exists because `winnerEntrantId ?? this.winnerEntrantId`
  /// cannot express "there is no longer a winner". Reopening a finished match
  /// to correct it passed null and silently kept the old winner, so the
  /// fixture went back to live still flagged as won — and the spectator card
  /// bolded a winner's name mid-match.
  Fixture copyWith({
    FixtureStatus? status,
    Map<String, dynamic>? scoreState,
    String? summary,
    int? lastSeq,
    String? winnerEntrantId,
    bool clearWinner = false,
    bool? isDraw,
    List<String>? scorerUids,
    List<MatchOfficial>? officials,
    DateTime? scheduledAt,
    String? venue,
    String? courtId,
    MatchResultType? resultType,
    String? resultNote,
  }) {
    return Fixture(
      id: id,
      orgId: orgId,
      compId: compId,
      entrantAId: entrantAId,
      entrantBId: entrantBId,
      entrantAName: entrantAName,
      entrantBName: entrantBName,
      status: status ?? this.status,
      round: round,
      matchIndex: matchIndex,
      roundLabel: roundLabel,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      venue: venue ?? this.venue,
      scorerUids: scorerUids ?? this.scorerUids,
      // Not a parameter: which two clubs are contesting the match is fixed when
      // the challenge is accepted. It is carried through explicitly because
      // `copyWith` runs on every single score event, and dropping it there
      // would revoke the away club's access somewhere around the first ball.
      participantOrgIds: participantOrgIds,
      officials: officials ?? this.officials,
      scoreState: scoreState ?? this.scoreState,
      summary: summary ?? this.summary,
      lastSeq: lastSeq ?? this.lastSeq,
      winnerEntrantId:
          clearWinner ? null : (winnerEntrantId ?? this.winnerEntrantId),
      isDraw: isDraw ?? this.isDraw,
      rulesetVersion: rulesetVersion,
      scoringPluginKey: scoringPluginKey,
      sportId: sportId,
      scoringConfig: scoringConfig,
      lineupA: lineupA,
      lineupB: lineupB,
      squadLockedA: squadLockedA,
      squadLockedB: squadLockedB,
      mvp: mvp,
      squadCallA: squadCallA,
      squadCallB: squadCallB,
      tossWonByEntrantId: tossWonByEntrantId,
      tossDecision: tossDecision,
      feedsWinnerToFixtureId: feedsWinnerToFixtureId,
      feedsWinnerToSlot: feedsWinnerToSlot,
      // Carried through explicitly, never a parameter: where a result sends
      // the two sides is fixed by the draw. `copyWith` runs on every score
      // event, and dropping any of these would quietly unwire the bracket
      // somewhere around the first point of the first match.
      feedsLoserToFixtureId: feedsLoserToFixtureId,
      feedsLoserToSlot: feedsLoserToSlot,
      bracket: bracket,
      groupId: groupId,
      qualifierA: qualifierA,
      qualifierB: qualifierB,
      courtId: courtId ?? this.courtId,
      resultType: resultType ?? this.resultType,
      resultNote: resultNote ?? this.resultNote,
      startedAt: startedAt,
      completedAt: completedAt,
    );
  }
}

/// One immutable fact about a match, at `.../fixtures/{fixtureId}/events/{seq}`.
///
/// The document id is the zero-padded [seq]. Because a Firestore `create`
/// fails when the document already exists, two scorers acting on the same
/// ball cannot both succeed — the loser is rejected and re-syncs. That gives
/// us a concurrency guard with no locks, no transactions and no server code.
///
/// Events are never updated or deleted. A mistake is corrected by appending a
/// reversal, which is what keeps the record defensible when a result is
/// protested weeks later.
class MatchEvent {
  const MatchEvent({
    required this.seq,
    required this.type,
    required this.payload,
    required this.byUid,
    this.at,
    this.clientEventId = '',
    this.note,
  });

  final int seq;

  /// Plugin-defined, e.g. `point`, `wicket`, `wide`, `goal`, `undo`.
  final String type;

  final Map<String, dynamic> payload;
  final String byUid;
  final DateTime? at;

  /// Stable id generated on the device before the write. Survives an offline
  /// queue replaying after reconnect, so a flaky network cannot double-count
  /// a delivery.
  final String clientEventId;

  final String? note;

  /// Ids sort lexicographically in Firestore, so padding is what makes
  /// `orderBy(documentId)` agree with numeric order past event 9.
  static String docId(int seq) => seq.toString().padLeft(9, '0');

  factory MatchEvent.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return MatchEvent(
      seq: Fs.integer(d['seq']),
      type: Fs.str(d['type']),
      payload: Fs.map(d['payload']),
      byUid: Fs.str(d['byUid']),
      at: Fs.dateOrNull(d['at']),
      clientEventId: Fs.str(d['clientEventId']),
      note: Fs.strOrNull(d['note']),
    );
  }

  Map<String, Object?> toCreate() => {
        'seq': seq,
        'type': type,
        'payload': payload,
        'byUid': byUid,
        'at': FieldValue.serverTimestamp(),
        'clientEventId': clientEventId,
        'note': note,
      };
}

/// A row of the league table, at `.../competitions/{compId}/standings/{entrantId}`.
class Standing {
  const Standing({
    required this.entrantId,
    required this.displayName,
    this.played = 0,
    this.won = 0,
    this.drawn = 0,
    this.lost = 0,
    this.points = 0,
    this.scoreFor = 0,
    this.scoreAgainst = 0,
    this.rank = 0,
    this.netRunRate,
    this.buchholz = 0,
  });

  final String entrantId;
  final String displayName;
  final int played;
  final int won;
  final int drawn;
  final int lost;
  final int points;
  final int scoreFor;
  final int scoreAgainst;
  final int rank;

  /// Cricket only, and null until the entrant has both batted and bowled a
  /// completed innings. Null is deliberately not zero: a side with no
  /// completed innings has no rate, and showing 0.000 would rank it above
  /// every side with a negative one.
  final double? netRunRate;

  /// Sum of the points of every opponent faced — the standard Swiss tiebreak.
  final int buchholz;

  int get scoreDifference => scoreFor - scoreAgainst;

  factory Standing.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Standing(
      entrantId: doc.id,
      displayName: Fs.str(d['displayName'], 'Entrant'),
      played: Fs.integer(d['played']),
      won: Fs.integer(d['won']),
      drawn: Fs.integer(d['drawn']),
      lost: Fs.integer(d['lost']),
      points: Fs.integer(d['points']),
      scoreFor: Fs.integer(d['scoreFor']),
      scoreAgainst: Fs.integer(d['scoreAgainst']),
      rank: Fs.integer(d['rank']),
      netRunRate: (d['netRunRate'] as num?)?.toDouble(),
      buchholz: Fs.integer(d['buchholz']),
    );
  }

  Map<String, Object?> toMap() => {
        'displayName': displayName,
        'played': played,
        'won': won,
        'drawn': drawn,
        'lost': lost,
        'points': points,
        'scoreFor': scoreFor,
        'scoreAgainst': scoreAgainst,
        'scoreDifference': scoreDifference,
        'rank': rank,
        'netRunRate': netRunRate,
        'buchholz': buchholz,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}
