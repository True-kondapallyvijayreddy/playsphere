import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/scoring/scoring_plugin.dart';
import 'enums.dart';
import 'firestore_codec.dart';
import 'match_official.dart';
import 'match_player.dart';

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
    this.tossWonByEntrantId,
    this.tossDecision,
    this.feedsWinnerToFixtureId,
    this.feedsWinnerToSlot,
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

  final DateTime? startedAt;
  final DateTime? completedAt;

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
      tossWonByEntrantId: Fs.strOrNull(d['tossWonByEntrantId']),
      tossDecision: Fs.strOrNull(d['tossDecision']),
      feedsWinnerToFixtureId: Fs.strOrNull(d['feedsWinnerToFixtureId']),
      feedsWinnerToSlot: Fs.strOrNull(d['feedsWinnerToSlot']),
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
        'tossWonByEntrantId': tossWonByEntrantId,
        'tossDecision': tossDecision,
        'feedsWinnerToFixtureId': feedsWinnerToFixtureId,
        'feedsWinnerToSlot': feedsWinnerToSlot,
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
      tossWonByEntrantId: tossWonByEntrantId,
      tossDecision: tossDecision,
      feedsWinnerToFixtureId: feedsWinnerToFixtureId,
      feedsWinnerToSlot: feedsWinnerToSlot,
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
