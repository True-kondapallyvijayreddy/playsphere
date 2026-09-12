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
    this.entrantAUid,
    this.entrantBUid,
    this.round = 1,
    this.matchIndex = 0,
    this.roundLabel,
    this.scheduledAt,
    this.venue,
    this.streamUrl,
    this.scorerUids = const [],
    this.activeScorerUid,
    this.activeScorerDeviceId,
    this.penGrantedByUid,
    this.penGrantedAt,
    this.lastRestartSeq,
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
    this.venueId,
    this.courtRefId,
    this.tournamentId,
    this.resultType = MatchResultType.normal,
    this.resultNote,
    this.startedAt,
    this.completedAt,
    this.lastEventAt,
    this.startedEarly = const {},
    this.isDraft = false,
    this.ratingSettledAt,
    this.readiness = MatchReadiness.scheduled,
    this.resultState = MatchResultState.none,
    this.sourceType,
    this.sourceId,
  });

  final String id;
  final String orgId;
  final String compId;

  final String entrantAId;
  final String entrantBId;

  /// Denormalized names so a fixture list renders without N extra reads.
  final String entrantAName;
  final String entrantBName;

  /// The registered account behind a side, when that side IS one person.
  ///
  /// Null for every team entrant, and that asymmetry is the point. An
  /// individual event — badminton singles, chess, a tennis draw — names its
  /// competitors on the *entrant* document and never fills a line-up
  /// (`TournamentRepository.assignOfficialsAcrossTournament` says so at
  /// length, and the scheduler already reaches into `entrants` to work around
  /// it). So for those matches [lineupA]/[lineupB] are empty forever, and
  /// anything derived from them — [playerUids], [sideForUid], every screen
  /// that queries a career — silently skipped the match while the settlement
  /// trigger counted it. A career total and a match list computed from the
  /// same season disagreed, which is exactly the drift this pair closes.
  ///
  /// Deliberately NOT the team roster for a team entrant. `Entrant.memberUids`
  /// is a squad, not a team sheet: folding twenty-five names in would credit
  /// a match to fourteen people who watched it, and `firestore.rules` gates
  /// career-stat writes on [playerUids], so it would hand a scorer the right
  /// to write results onto their profiles. A team's line-up stays the only
  /// evidence that a team's player played.
  final String? entrantAUid;
  final String? entrantBUid;

  /// [entrantAUid]/[entrantBUid] as a set, skipping the nulls.
  List<String> get entrantUids => <String>{
        if (entrantAUid != null) entrantAUid!,
        if (entrantBUid != null) entrantBUid!,
      }.toList(growable: false);

  final FixtureStatus status;
  final int round;
  final int matchIndex;

  /// "Quarter-final", "Round 3" — set by the generator so the bracket reads
  /// correctly without the UI having to infer it from round numbers.
  final String? roundLabel;

  final DateTime? scheduledAt;
  final String? venue;

  /// Where this match is being broadcast, if anywhere.
  ///
  /// A pasted link and nothing more — see `StreamLink`, which is the only
  /// thing allowed to interpret it. Stored raw rather than as a parsed video
  /// id on purpose: the id is a derivation of the link, and a club that
  /// corrects a typo should see the correction rather than a stale id nobody
  /// can trace back to what was typed.
  ///
  /// Null is the ordinary state and is not a gap to apologise for. Almost no
  /// grassroots match is streamed, and the one that is has a volunteer with a
  /// phone on a tripod behind the bowler's arm — which is exactly why the
  /// field is a link to somebody else's platform and not a video pipeline of
  /// our own.
  final String? streamUrl;

  /// Who may score this match. Security rules check membership of this list
  /// on every event write, so an unrelated member cannot alter a score.
  final List<String> scorerUids;

  /// Who holds the pen right now — the ONE person whose taps are the match.
  ///
  /// ## Why `scorerUids` was not enough
  ///
  /// `scorerUids` answers "who is allowed to score this match", and a list is
  /// the right shape for that: a club assigns two umpires to a final, one
  /// takes the first half, the other the second, and both need the right for
  /// the whole match. What it cannot say is which of them is scoring *now*.
  /// So both pads were live at once, both were authoritative, and the loser
  /// of each race for a sequence number had their tap discarded — which the
  /// scorer sees as the score jumping backwards under their thumb.
  ///
  /// This field is the answer to the second question, and it holds exactly
  /// one uid or none. An owner GRANTS it (see `UmpireRepository.grantPen`)
  /// and can take it back at any time; while it is held, nobody else — the
  /// owner very much included — may advance the score. An organizer who
  /// wants the pen back has to say so, and that reassignment is recorded.
  /// The alternative is an owner who can silently overwrite the official
  /// standing at the ground, which is the thing every scoring dispute is
  /// actually about.
  ///
  /// Null means the pen is free: the first eligible person to open the pad
  /// claims it.
  final String? activeScorerUid;

  /// Which device the pen holder is scoring on. See [DeviceId] for why a uid
  /// alone cannot express this.
  ///
  /// Claimed by the first device the holder opens the pad on, and only
  /// cleared by a grant or a release — so the same person signed in on a
  /// phone and a tablet still has exactly one live pad, and the second one
  /// has to take over deliberately rather than by being opened.
  final String? activeScorerDeviceId;

  /// The organizer who handed the pen over, and when. This is the audit
  /// trail a disputed result is argued from: who was authorised to score,
  /// by whom, from what moment.
  final String? penGrantedByUid;
  final DateTime? penGrantedAt;

  /// The sequence number of the restart the match is currently running from,
  /// or null if the match has never been restarted (or the restart has since
  /// been withdrawn).
  ///
  /// Derived state — [ScoringPlugin.rebuild] would tell you the same thing
  /// from the log — kept on the fixture so a reader can offer "continue the
  /// previous score" without opening a second listener on the event log. The
  /// screen that needs to offer it is the one a reassigned official opens
  /// after somebody restarted the match by mistake, which is exactly the
  /// moment you do not want to be asking the network extra questions.
  final int? lastRestartSeq;

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

  /// True when players or registered entrants are available.
  /// Registered teams / players start immediately without blocking for line-up selection.
  bool get hasLineups =>
      (lineupA.isNotEmpty && lineupB.isNotEmpty) ||
      (entrantAName.isNotEmpty &&
          entrantBName.isNotEmpty &&
          entrantAName != 'To be decided' &&
          entrantBName != 'To be decided') ||
      (entrantAUid != null &&
          entrantAUid!.isNotEmpty &&
          entrantBUid != null &&
          entrantBUid!.isNotEmpty);

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
  ///
  /// Includes [entrantUids] because an individual event has no line-up to
  /// summarise — see [entrantAUid]. Both sources are unioned rather than
  /// chosen between: a mixed draw where one side is a club team and the other
  /// a lone qualifier is a real shape, and taking only one source would drop
  /// half of it.
  List<String> get playerUids => <String>{
        for (final p in lineupA) ...[if (p.uid != null) p.uid!],
        for (final p in lineupB) ...[if (p.uid != null) p.uid!],
        ...entrantUids,
      }.toList(growable: false);

  /// Everyone whose individual performance this match recorded, keyed the way
  /// the scoring engine keyed them.
  ///
  /// The line-ups, plus a stand-in for a side that IS one person. An
  /// individual event never fills a line-up, so anything that walked
  /// `lineupA + lineupB` to find per-player figures — the tournament's batting
  /// and bowling charts, most obviously — found nobody and drew an empty
  /// board for a draw that had been played to a final.
  ///
  /// The stand-in's [MatchPlayer.id] is the ENTRANT id, not the uid, because
  /// that is the key `scoreState.players` is written under for these matches.
  /// The two are equal by construction today — `closeEntries` gives an
  /// individual entrant its own uid as a document id — and keying on the
  /// entrant id keeps this correct if that ever stops being true.
  List<MatchPlayer> get scoredPlayers => [
        ...lineupA,
        ...lineupB,
        if (lineupA.isEmpty && entrantAUid != null)
          MatchPlayer(id: entrantAId, name: entrantAName, uid: entrantAUid),
        if (lineupB.isEmpty && entrantBUid != null)
          MatchPlayer(id: entrantBId, name: entrantBName, uid: entrantBUid),
      ];

  /// The registered accounts of everyone officiating — umpires, referees,
  /// the third umpire.
  ///
  /// Deliberately NOT folded into [playerUids]: that list is what
  /// `firestore.rules` checks before letting a scorer write ratings and career
  /// statistics onto somebody's profile, and an umpire did not play, so a
  /// result must never accrue to them.
  List<String> get officialUids => <String>{
        for (final o in officials) ...[if (o.uid.isNotEmpty) o.uid],
      }.toList(growable: false);

  /// Everyone who was actually at this match — both line-ups and the
  /// officials.
  ///
  /// This is the "detected participants" set a memory tags. An umpire who
  /// stood for a district final was there; the photo is as much theirs as
  /// anyone's, and before this they could not even be offered as a tag
  /// because only line-up entries were listed.
  ///
  /// Order is stable — side A, then side B, then officials — so a tag dialog
  /// does not reshuffle its chips between builds.
  List<String> get participantUids => <String>{
        ...playerUids,
        ...officialUids,
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
        lineupA: lineupA.isNotEmpty
            ? lineupA
            : [
                MatchPlayer(
                  id: entrantAUid ??
                      (entrantAId.isNotEmpty ? entrantAId : 'entrant_a'),
                  name: entrantAName.isNotEmpty ? entrantAName : 'Side A',
                  uid: entrantAUid,
                ),
              ],
        lineupB: lineupB.isNotEmpty
            ? lineupB
            : [
                MatchPlayer(
                  id: entrantBUid ??
                      (entrantBId.isNotEmpty ? entrantBId : 'entrant_b'),
                  name: entrantBName.isNotEmpty ? entrantBName : 'Side B',
                  uid: entrantBUid,
                ),
              ],
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

  /// The ids behind [venue] and [courtId], when the match was placed against
  /// real venue documents.
  ///
  /// ## Why the names are not enough
  ///
  /// [venue] and [courtId] are what a player reads on their card, and they
  /// have to stay strings: a club event still types "Court 1" and a historic
  /// fixture must keep naming the place it was played even after the venue is
  /// renamed. But *checking* a timetable — is this court open at this hour, is
  /// it inside its blackout, has it hit its daily maximum — needs the resource
  /// back, and resolving a resource by matching two display names is wrong the
  /// first time two grounds each have a "Court 1", which is the normal case.
  ///
  /// Null for every fixture placed by hand or before this existed, and every
  /// reader treats null as "cannot check", never as "no venue".
  final String? venueId;
  final String? courtRefId;

  /// What to show on a side with no entrant yet — the qualifier it is waiting
  /// on, if it is waiting on one, rather than a bare "To be decided".
  String displayNameA() => entrantAId.isNotEmpty
      ? entrantAName
      : (qualifierA?.label ?? entrantAName);

  String displayNameB() => entrantBId.isNotEmpty
      ? entrantBName
      : (qualifierB?.label ?? entrantBName);

  /// Whether both sides are known, so this match can actually be played.
  /// A knockout placeholder still waiting on a feeder is not playable, and
  /// the scheduler must not call it to a court.
  bool get hasBothEntrants => entrantAId.isNotEmpty && entrantBId.isNotEmpty;

  /// The tournament this match belongs to, denormalized from its competition.
  ///
  /// Carried on the fixture so a tournament-wide order of play is one
  /// collection-group query rather than one query per event. A district
  /// championship has fifteen draws, and fifteen listeners to render one
  /// "what is on court now" screen is the difference between a free tier and
  /// a bill.
  final String? tournamentId;

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

  /// When the scoreboard last actually moved — written on every scoring
  /// action, including undos.
  ///
  /// Exists because [status] alone cannot answer "is this match live *now*".
  /// A fixture enters [FixtureStatus.live] on its first ball and only leaves
  /// on the event the plugin calls complete, so any match a scorer walks away
  /// from — a phone dies, rain stops play, the last over is never entered —
  /// stays `live` in Firestore forever. Those abandoned matches were showing a
  /// red LIVE badge days later, which is what made the badge worthless: if
  /// half the LIVE matches are not live, nobody trusts any of them.
  final DateTime? lastEventAt;

  /// The record of a match that was pulled forward and played ahead of its
  /// scheduled time — who agreed to it, when, and how the sport's pre-match
  /// questions were answered.
  ///
  /// Empty for the overwhelming majority of fixtures, which were played when
  /// they said they would be. Present, it is the only place that records that
  /// a Tuesday fixture was actually played on Saturday with a different ball,
  /// which is exactly the context a disputed scorecard turns on. See
  /// `CompetitionRepository.startMatchEarly`.
  final Map<String, dynamic> startedEarly;

  /// Whether this match was played ahead of its original slot.
  bool get wasStartedEarly => startedEarly.isNotEmpty;

  /// True for a fixture built by [CompetitionRepository.generateDraftSchedule]
  /// against placeholder teams — "Team A", "Team B" — before real entrants
  /// exist, so an organizer can lay out rounds, courts, times and officials
  /// ahead of registration instead of waiting for it to close.
  ///
  /// Everywhere a real schedule is counted, watched or offered as a match to
  /// join — the tournament progress bar, "on court now", "running late" —
  /// this must be excluded: nobody is really playing it, and telling a
  /// spectator to show up for a placeholder is worse than showing nothing.
  /// Editing it — venue, time, court, officials — is exactly the point and
  /// stays open, same as any other unplayed fixture. Once real entrants
  /// close, `generateDraw` deletes every draft fixture and writes the real
  /// draw in its place, same as it already replaces any unscored draw.
  final bool isDraft;

  // --- The match's own lifecycle, alongside [status] ------------------------
  //
  // See `MatchReadiness` and `MatchResultState` for why these are separate
  // axes rather than extra values on [FixtureStatus].

  /// How prepared this match is — officials named, organizer satisfied.
  final MatchReadiness readiness;

  /// Whether a finished result has been verified.
  final MatchResultState resultState;

  /// When the finalize trigger settled ratings and career statistics for this
  /// match, or null if it has not run yet.
  ///
  /// Written by `functions/index.js` in the same batch as the ratings it
  /// accounts for, so the marker and the payment cannot come apart. It is the
  /// only honest answer to "have this match's statistics been applied" — the
  /// trigger is asynchronous, and a result screen that claimed stats were
  /// updated the instant the scorer pressed end would be guessing.
  final DateTime? ratingSettledAt;

  /// Where this match came from — `docs/Heart_of_the_playsphere.md` §12.
  ///
  /// Null on fixtures written before the field existed. [resolvedSource]
  /// derives one for those rather than showing a match with no origin.
  final MatchSource? sourceType;

  /// The id of the thing in [sourceType] — a tournament id, a challenge id.
  final String? sourceId;

  /// This match's source, derived when it was not recorded.
  ///
  /// Every fixture predating the field still has an origin; it simply was not
  /// written down. A fixture under a tournament is a tournament match, and
  /// one without is a standalone game — which is what a "Single Match" is.
  /// This keeps §20's match history complete rather than leaving years of
  /// matches unlabelled while a backfill catches up.
  MatchSource get resolvedSource =>
      sourceType ??
      (tournamentId != null ? MatchSource.tournament : MatchSource.singleMatch);

  /// Which side [uid] played for — 'a', 'b', or null if they did not play.
  ///
  /// Reads the line-ups, not `participantOrgIds`: a person can be a member of
  /// both contesting clubs (a coach, a player who moved mid-season), so club
  /// membership cannot decide which side they were on. Being named on a team
  /// sheet can.
  String? sideForUid(String uid) {
    if (lineupA.any((p) => p.uid == uid)) return 'a';
    if (lineupB.any((p) => p.uid == uid)) return 'b';
    // An individual entrant is their own team sheet. Checked after the
    // line-ups, not before, so a player who somehow appears in both keeps the
    // answer the line-up gives — that is the one a scorer actually typed.
    if (entrantAUid == uid) return 'a';
    if (entrantBUid == uid) return 'b';
    return null;
  }

  /// How this match went for [uid] — won, lost, drawn, or null when it cannot
  /// be told.
  ///
  /// Null rather than a guess in three real cases: the match has no result
  /// yet, the person is not on either team sheet (a quick match scored
  /// without line-ups), or it was drawn — which is reported as its own
  /// outcome rather than folded into a loss.
  PlayerResult? outcomeForUid(String uid) {
    if (!status.isResulted) return null;
    if (isDraw) return PlayerResult.drawn;
    final side = sideForUid(uid);
    if (side == null) return null;
    final theirEntrantId = side == 'a' ? entrantAId : entrantBId;
    final winner = winnerEntrantId;
    if (winner == null) return null;
    return winner == theirEntrantId ? PlayerResult.won : PlayerResult.lost;
  }

  /// Whether the result is settled enough to project into leaderboards,
  /// career statistics and rankings.
  ///
  /// A match awaiting an umpire's verification has a score on the sheet but
  /// is not yet a fact — §23. Everything else keeps the behaviour it had:
  /// [FixtureStatus.isResulted] alone decided this before verification
  /// existed, and still does for every competition that does not ask for it.
  bool get countsTowardsRecords =>
      status.isResulted && !resultState.blocksProjection;

  /// How long a scoreboard may sit untouched before it stops claiming to be
  /// live.
  ///
  /// Six hours, chosen to be longer than any single grassroots session — a
  /// full-day cricket match has a lunch break, a badminton court waits on the
  /// previous rubber — while still being far shorter than the days-long
  /// staleness users actually reported. A match legitimately paused this long
  /// has, for a spectator's purposes, stopped.
  static const Duration liveStaleAfter = Duration(hours: 6);

  /// Whether this result should award league points. See
  /// [MatchResultType.countsForStandings].
  bool get countsForStandings =>
      status.isResulted && resultType.countsForStandings;

  /// The stored lifecycle claim: what the document says about itself.
  ///
  /// Use this for scoring permissions and state transitions. For anything a
  /// spectator READS — a badge, a live list, a blinking dot — use
  /// [isLiveAt] instead, which also requires the scoreboard to be warm.
  bool get isLive => status == FixtureStatus.live;

  /// Whether this match should be presented as Live at [now].
  ///
  /// Three things must all hold, matching how a person on the ground would
  /// answer the question:
  ///
  /// - the fixture claims to be live,
  /// - scoring has actually begun (a fixture with no events has not started,
  ///   whatever its status field says), and
  /// - the scoreboard moved recently enough to still be running.
  bool isLiveAt(DateTime now) {
    if (status != FixtureStatus.live) return false;
    if (lastSeq <= 0) return false;
    final beat = lastEventAt ?? startedAt;
    if (beat == null) return false;
    // A negative difference means the heartbeat is ahead of this device's
    // clock, which happens routinely: the beat is a server timestamp and the
    // reader is a cheap phone with a drifting clock. That is still a live
    // match, so the comparison is deliberately one-sided.
    return now.difference(beat) < liveStaleAfter;
  }

  /// Claims to be live but has gone quiet — an abandoned or forgotten
  /// scoreboard. Shown as paused, and offered to organizers to close out.
  bool isStaleLiveAt(DateTime now) =>
      status == FixtureStatus.live && !isLiveAt(now);

  bool get hasResult => status.isResulted;

  /// Ended by an official's ruling rather than by the score.
  ///
  /// A walkover, an abandonment, a dispute, a retirement, a disqualification.
  /// The defining property is that NONE of it is in the event log: the ruling
  /// lives on the fixture document and the projection knows nothing about it.
  /// So a rebuild — a replay on reconnect, or simply the next tap on the pad,
  /// which derives `status` from `plugin.outcome` — computes `live` and
  /// overwrites the ruling without anybody touching it. That is the whole
  /// reason the pad has to lock rather than merely look different: the only
  /// safe way back into scoring is to withdraw the ruling first, which is
  /// what [ScoringService.clearFixtureOutcome] is.
  ///
  /// A normally completed match is deliberately NOT included. It is frozen by
  /// `acceptsScoring`, its ending IS in the log, and the engines already
  /// offer Reopen as the way back.
  bool get endedByDecision =>
      status.isDecision || resultType != MatchResultType.normal;

  /// What [ScoringService.clearFixtureOutcome] should put the match back to.
  ///
  /// Derived, never remembered. Storing "the status before the ruling" would
  /// be one more field to keep honest across offline replay; the event log
  /// already knows — a match with events was live, one without was scheduled,
  /// and if the engine had finished it the outcome recomputes from
  /// `scoreState` at the call site.
  FixtureStatus get statusWithoutDecision =>
      lastSeq > 0 ? FixtureStatus.live : FixtureStatus.scheduled;

  /// Feature #17: Dynamic role-based scoring access.
  /// A fixture can be scored if the user is in [scorerUids] OR holds manager access.
  bool canBeScoredBy(String uid, {bool isOrgManager = false}) =>
      status.acceptsScoring && (scorerUids.contains(uid) || isOrgManager);

  /// True when somebody has been handed the pen for this match.
  bool get penIsHeld => activeScorerUid != null && activeScorerUid!.isNotEmpty;

  /// True when [uid] is the person the pen was handed to.
  ///
  /// Says nothing about the device — see [penIsLiveOn]. An owner deciding
  /// whether to show "reassign" wants this one; the pad deciding whether to
  /// accept a tap wants that one.
  bool penHeldBy(String uid) => penIsHeld && activeScorerUid == uid;

  /// True when this exact device is the one the pen was claimed on.
  ///
  /// An unclaimed pen ([activeScorerDeviceId] null) is live on whichever
  /// device the holder opens first — that is the claim. A pen already claimed
  /// elsewhere is not live here, and the pad shows the live view with a
  /// "take over on this device" path rather than a set of buttons whose taps
  /// would lose every race they entered.
  bool penIsLiveOn(String uid, String? deviceId) =>
      penHeldBy(uid) &&
      (activeScorerDeviceId == null ||
          activeScorerDeviceId!.isEmpty ||
          (deviceId != null && activeScorerDeviceId == deviceId));

  /// Whether [uid] on [deviceId] may write a score right now.
  ///
  /// The single question the pad, the service and `firestore.rules` all ask,
  /// so they cannot drift apart. An unheld pen falls back to [eligible] —
  /// the older role-based test — because a match nobody was ever assigned to
  /// still has to be scoreable by the organizer who walks up to it.
  bool mayScoreNow({
    required String uid,
    String? deviceId,
    required bool eligible,
  }) {
    if (!status.acceptsScoring) return false;
    if (!penIsHeld) return eligible;
    return penIsLiveOn(uid, deviceId);
  }

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
      entrantAUid: Fs.strOrNull(d['entrantAUid']),
      entrantBUid: Fs.strOrNull(d['entrantBUid']),
      status: FixtureStatus.fromWire(Fs.str(d['status'])),
      round: Fs.integer(d['round'], 1),
      matchIndex: Fs.integer(d['matchIndex']),
      roundLabel: Fs.strOrNull(d['roundLabel']),
      scheduledAt: Fs.dateOrNull(d['scheduledAt']),
      venue: Fs.strOrNull(d['venue']),
      streamUrl: Fs.strOrNull(d['streamUrl']),
      scorerUids: Fs.strList(d['scorerUids']),
      activeScorerUid: Fs.strOrNull(d['activeScorerUid']),
      activeScorerDeviceId: Fs.strOrNull(d['activeScorerDeviceId']),
      penGrantedByUid: Fs.strOrNull(d['penGrantedByUid']),
      penGrantedAt: Fs.dateOrNull(d['penGrantedAt']),
      lastRestartSeq: d['lastRestartSeq'] is num
          ? (d['lastRestartSeq'] as num).toInt()
          : null,
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
      venueId: Fs.strOrNull(d['venueId']),
      courtRefId: Fs.strOrNull(d['courtRefId']),
      tournamentId: Fs.strOrNull(d['tournamentId']),
      resultType: MatchResultType.fromWire(Fs.strOrNull(d['resultType'])),
      resultNote: Fs.strOrNull(d['resultNote']),
      startedAt: Fs.dateOrNull(d['startedAt']),
      completedAt: Fs.dateOrNull(d['completedAt']),
      lastEventAt: Fs.dateOrNull(d['lastEventAt']),
      startedEarly: Fs.map(d['startedEarly']),
      isDraft: Fs.boolean(d['isDraft']),
      ratingSettledAt: Fs.dateOrNull(d['ratingSettledAt']),
      readiness: MatchReadiness.fromWire(Fs.strOrNull(d['readiness'])),
      resultState: MatchResultState.fromWire(Fs.strOrNull(d['resultState'])),
      sourceType: MatchSource.fromWire(Fs.strOrNull(d['sourceType'])),
      sourceId: Fs.strOrNull(d['sourceId']),
    );
  }

  Map<String, Object?> toCreate() => {
        'orgId': orgId,
        'compId': compId,
        'entrantAId': entrantAId,
        'entrantBId': entrantBId,
        'entrantAName': entrantAName,
        'entrantBName': entrantBName,
        'entrantAUid': entrantAUid,
        'entrantBUid': entrantBUid,
        'status': status.wire,
        'round': round,
        'matchIndex': matchIndex,
        'roundLabel': roundLabel,
        'scheduledAt': Fs.ts(scheduledAt),
        'venue': venue,
        'streamUrl': streamUrl,
        'scorerUids': scorerUids,
        'activeScorerUid': activeScorerUid,
        'activeScorerDeviceId': activeScorerDeviceId,
        'penGrantedByUid': penGrantedByUid,
        'penGrantedAt': Fs.ts(penGrantedAt),
        'lastRestartSeq': null,
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
        'venueId': venueId,
        'courtRefId': courtRefId,
        'tournamentId': tournamentId,
        'resultType': resultType.wire,
        'resultNote': resultNote,
        'isDraft': isDraft,
        'readiness': readiness.wire,
        'resultState': resultState.wire,
        'sourceType': sourceType?.wire,
        'sourceId': sourceId,
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
    String? activeScorerUid,
    String? activeScorerDeviceId,

    /// Same reason as [clearWinner]: `?? this.activeScorerUid` cannot say
    /// "nobody holds the pen any more", and releasing it is the whole point
    /// of the handover flow.
    bool clearPen = false,
    int? lastRestartSeq,
    bool clearRestart = false,
    List<MatchOfficial>? officials,
    DateTime? scheduledAt,
    String? venue,

    /// `?? this.streamUrl` cannot say "the stream is over" — same reason as
    /// [clearWinner]. A match whose organizer takes the link down must lose
    /// it, or the spectator screen keeps offering a dead broadcast.
    String? streamUrl,
    bool clearStreamUrl = false,
    String? courtId,
    String? venueId,
    String? courtRefId,
    MatchResultType? resultType,
    String? resultNote,

    /// Same reason as [clearWinner]: `?? this.resultNote` cannot say "there
    /// is no longer a reason on file", and withdrawing a ruling has to take
    /// the ruling's note with it or the next screen explains the result with
    /// a sentence about a decision that no longer stands.
    bool clearResultNote = false,
    DateTime? lastEventAt,
    Map<String, dynamic>? startedEarly,
    MatchReadiness? readiness,
    MatchResultState? resultState,
  }) {
    return Fixture(
      id: id,
      orgId: orgId,
      compId: compId,
      entrantAId: entrantAId,
      entrantBId: entrantBId,
      entrantAName: entrantAName,
      entrantBName: entrantBName,
      // Carried through, not a parameter, for the same reason the entrant ids
      // are: who is playing is decided when the slot is filled, and a copy
      // made to record a score must never be able to change it.
      entrantAUid: entrantAUid,
      entrantBUid: entrantBUid,
      status: status ?? this.status,
      round: round,
      matchIndex: matchIndex,
      roundLabel: roundLabel,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      venue: venue ?? this.venue,
      streamUrl: clearStreamUrl ? null : (streamUrl ?? this.streamUrl),
      scorerUids: scorerUids ?? this.scorerUids,
      activeScorerUid:
          clearPen ? null : (activeScorerUid ?? this.activeScorerUid),
      activeScorerDeviceId:
          clearPen ? null : (activeScorerDeviceId ?? this.activeScorerDeviceId),
      penGrantedByUid: clearPen ? null : penGrantedByUid,
      penGrantedAt: clearPen ? null : penGrantedAt,
      lastRestartSeq:
          clearRestart ? null : (lastRestartSeq ?? this.lastRestartSeq),
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
      venueId: venueId ?? this.venueId,
      courtRefId: courtRefId ?? this.courtRefId,
      tournamentId: tournamentId,
      resultType: resultType ?? this.resultType,
      resultNote: clearResultNote ? null : (resultNote ?? this.resultNote),
      startedAt: startedAt,
      completedAt: completedAt,
      lastEventAt: lastEventAt ?? this.lastEventAt,
      startedEarly: startedEarly ?? this.startedEarly,
      // Not a parameter: nothing that runs through copyWith — scoring events,
      // reschedules — is how a draft fixture is meant to stop being one. That
      // only happens by `generateDraw` deleting it outright and writing a
      // real fixture in its place, so carrying this through explicitly is
      // what stops some other write path silently laundering a placeholder
      // match into a real one.
      isDraft: isDraft,
      readiness: readiness ?? this.readiness,
      resultState: resultState ?? this.resultState,
      // Not parameters, for the same reason as `isDraft` above: where a match
      // came from is fixed when it is created. A scoring event must not be
      // able to relabel a challenge as a tournament match, which is what
      // would happen the first time some caller passed a fresh Fixture
      // through here without them.
      sourceType: sourceType,
      sourceId: sourceId,
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
