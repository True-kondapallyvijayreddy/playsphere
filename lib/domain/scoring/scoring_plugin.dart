import 'package:flutter/foundation.dart';

import '../../core/models/fixture.dart' show MatchEvent;
import '../../core/models/match_player.dart';
import 'player_stats.dart';
import 'rule_config.dart';

/// Which side of the match a control or event belongs to.
enum Side {
  a('a'),
  b('b'),
  neutral('neutral');

  const Side(this.wire);
  final String wire;

  static Side fromWire(String? w) =>
      Side.values.firstWhere((e) => e.wire == w, orElse: () => Side.neutral);

  Side get opposite => switch (this) {
        Side.a => Side.b,
        Side.b => Side.a,
        Side.neutral => Side.neutral,
      };
}

/// Visual weight of a scoring button. Kept abstract so the plugin describes
/// *intent* and the widget layer owns the actual colours and theming.
enum ControlStyle { primary, secondary, danger, subtle }

/// A person the pad must name before an action can be applied.
///
/// This exists because the engines and the pad disagreed, silently and
/// completely. Eleven of the thirteen engines refuse an action that names
/// nobody — `'Who scored?'`, `'Who made the tag?'`, `'Who raided?'` — and the
/// pad only ever asked on three cricket actions, which it recognised from a
/// hard-coded set of action names. So tapping Goal in a football match, or
/// Tag in kho-kho, produced a rejection and no score. Those sports were not
/// partially built; they were unscorable.
///
/// The fix has to be declarative rather than another list of action names in
/// the screen, because the screen must not know what a raid is. A plugin
/// states which people an action involves; the pad asks, in order, from the
/// right line-up. Adding a sport stays a plugin, never a screen change.
@immutable
class PlayerPrompt {
  const PlayerPrompt({
    required this.key,
    required this.label,
    this.from = PromptSource.actingSide,
    this.optional = false,
    this.multiple = false,
    this.only,
  });

  /// Restricts the pool to specific players, computed by the plugin from the
  /// current state.
  ///
  /// [from] answers "which side", which is all most prompts need. Substitution
  /// is the case it cannot express: "who comes off" is drawn from whoever is
  /// on the field right now and "who comes on" from whoever is not, and both
  /// pools change with every event. Neither is a side.
  ///
  /// The alternative — teaching the pad what a substitution is — is the same
  /// mistake the hard-coded cricket action names were. The plugin already
  /// holds the state when it builds its controls, so it names the candidates
  /// and the screen stays ignorant of what it is asking about.
  ///
  /// Null means no restriction; an empty list means nobody is eligible, and
  /// the pad shows that rather than offering a choice that cannot be made.
  final List<String>? only;

  /// Whether this names SEVERAL people, written as a list rather than an id.
  ///
  /// Kabaddi is why: a tackle is made by whoever got hold of the raider, which
  /// is routinely three or four defenders, and the engine splits the tackle
  /// points between all of them. Modelling it as one person would hand a
  /// super-tackle to a single player and quietly falsify everyone's High 5
  /// count.
  final bool multiple;

  /// Payload key the chosen player's id is written to — `playerId`,
  /// `assistId`, `defenderId`. Matches what the engine reads in `apply`.
  final String key;

  /// Asked as the engine would ask it: "Who scored?", "Who assisted?".
  final String label;

  final PromptSource from;

  /// Whether the scorer may skip it. An assist is optional — plenty of goals
  /// have none, and forcing a name would make the scorer invent one. A goal
  /// scorer is not: the engine rejects the event without them.
  final bool optional;
}

/// A NUMBER the pad must collect before an action can be applied.
///
/// Athletics is why this exists, and until it did, athletics and swimming
/// could not be scored at all. Every other sport's events are countable —
/// a goal is one goal, a six is six runs — so a button and a payload constant
/// carry the whole event. A track event is not: the thing being recorded IS
/// the measurement, and 10.94 cannot be a button. The engine asked for a
/// `value` and the pad had no way to supply one, so every mark was rejected
/// with "A mark needs a time or a distance".
///
/// Deliberately generic rather than an athletics special case. A wind
/// reading, a lane, a shot-clock correction and a dart score are the same
/// shape, and the next sport that needs a number should not need a screen
/// change either.
@immutable
class ValuePrompt {
  const ValuePrompt({
    required this.key,
    required this.label,
    this.unit,
    this.decimals = 2,
    this.min,
    this.max,
    this.optional = false,
  });

  /// Payload key the number is written to — `value`, `wind`, `lane`.
  final String key;

  /// Asked as the official would ask it: "Time", "Distance", "Wind".
  final String label;

  /// Shown beside the field: "seconds", "metres". Comes from the sport
  /// catalogue's `unit`, so a swimming pad says seconds and a shot-put pad
  /// says metres without either being written here.
  final String? unit;

  /// How precise the measurement is. Times are hundredths; a lane is an
  /// integer. Zero means the field only accepts whole numbers.
  final int decimals;

  /// Bounds the pad enforces before the engine sees it. A negative wind
  /// reading is legal; a negative time is not.
  final double? min;
  final double? max;

  final bool optional;

  bool get isInteger => decimals == 0;
}

/// A fixed set of answers the pad must choose between before an action can be
/// applied.
///
/// The case that forced it is the retirement reason. A retirement is not one
/// outcome — injury, walkover and disqualification are three different facts
/// about a match — and the record has to keep them apart. The alternatives
/// were both bad: a free-text field is unusable by somebody standing beside a
/// court holding a phone and produces four spellings of "injury", and one
/// button per reason per side puts ten red chips in a tray that has room for
/// about four.
///
/// So the plugin states the question and its legal answers, and the pad asks
/// it in the dialog it already opens for players and numbers. Nothing about
/// retirement, or any other sport vocabulary, reaches the screen.
@immutable
class ChoicePrompt {
  const ChoicePrompt({
    required this.key,
    required this.label,
    required this.options,
    this.optional = false,
  });

  /// Payload key the chosen value is written to — `reason`.
  final String key;

  /// Asked as an official would ask it: "Why is the match ending?".
  final String label;

  /// The legal answers, in the order the scorer should meet them. Each is a
  /// wire value and the words shown for it.
  final List<ChoiceOption> options;

  final bool optional;
}

/// One answer to a [ChoicePrompt].
@immutable
class ChoiceOption {
  const ChoiceOption(this.value, this.label);

  /// What is stored in the event payload. Stable — it outlives the wording.
  final String value;

  /// What the scorer reads.
  final String label;
}

/// Which line-up a [PlayerPrompt] draws its candidates from.
///
/// Relative rather than absolute, because a control is built for a side and
/// the same declaration has to work for both. A tackle is made by the side
/// that did not raid; a save is made by the side that was not shooting.
enum PromptSource {
  /// The side whose button this is.
  actingSide,

  /// The other side. Kho-kho's defender, football's fouled player.
  opposingSide,

  /// Either — used where the pad cannot know, e.g. a neutral control.
  eitherSide,
}

/// A single button on the scoring pad, declared by the plugin rather than
/// hand-built per sport in the UI.
///
/// This inversion is what makes the product genuinely "an OS for all sports":
/// adding a sport means writing a plugin, not editing a scoring screen. It
/// also guarantees a scorer can never press a button that the rules do not
/// allow, because the plugin only emits controls that are legal right now.
@immutable
class ScoreControl {
  const ScoreControl({
    required this.action,
    required this.label,
    this.side = Side.neutral,
    this.style = ControlStyle.secondary,
    this.payload = const {},
    this.shortcut,
    this.tooltip,
    this.prompts = const [],
    this.values = const [],
    this.choices = const [],
    this.variants = const [],
  });

  /// Fuller versions of the same event, hidden behind this one.
  ///
  /// ## Why a control can have a drawer
  ///
  /// Cricket's extras are the case that forced this. A wide can be worth one
  /// run or five; a no-ball can be hit for six; every one of those values
  /// occurs and every one has to go somewhere, so the engine offers all
  /// sixteen of them. Laid out flat that is sixteen buttons of identical
  /// weight in front of a scorer who, ninety-five times in a hundred, wants
  /// the plain wide — and the plain wide is no easier to find than Wd+3.
  ///
  /// The frequencies are not close to equal, so the layout should not be
  /// either. The common one is a button; the rest are behind it. A pad draws
  /// this as the control plus a second `+` tile that opens the drawer (see
  /// `CreasePad`), so the ordinary case stays one tap and the rare one costs
  /// two, instead of every case costing a search.
  ///
  /// Deliberately generic. Nothing here is about cricket: any sport with one
  /// common event and a tail of graded versions of it — a penalty corner
  /// converted for one, two or three — declares the tail this way and gets
  /// the same treatment. A variant is an ordinary [ScoreControl] and is
  /// applied by exactly the same path, so nothing downstream needs to know a
  /// drawer was involved.
  final List<ScoreControl> variants;

  /// People the pad must name before this action can be applied, in the order
  /// the scorer should be asked. Empty for anything that names nobody — a
  /// period boundary, an interval, a change of ends. See [PlayerPrompt].
  final List<PlayerPrompt> prompts;

  /// Numbers the pad must collect. Asked in the same dialog as [prompts],
  /// after them, because "who" comes before "how fast". See [ValuePrompt].
  final List<ValuePrompt> values;

  /// Fixed-answer questions the pad must put, asked after the people and the
  /// numbers. See [ChoicePrompt].
  final List<ChoicePrompt> choices;

  /// Whether this button needs anything asked before it can be applied.
  bool get needsInput =>
      prompts.isNotEmpty || values.isNotEmpty || choices.isNotEmpty;

  /// Action type handed back to [ScoringPlugin.apply].
  final String action;

  /// Short face text: "+1", "4", "W", "Goal".
  final String label;

  final Side side;
  final ControlStyle style;
  final Map<String, dynamic> payload;

  /// Single keyboard character that triggers this control on a laptop.
  /// School and college scorers overwhelmingly work on a laptop at the desk
  /// beside the court, and a keyboard-driven pad is several times faster than
  /// aiming a mouse at buttons during a rally.
  final String? shortcut;

  final String? tooltip;
}

/// How the scoring pad should lay itself out for a sport.
///
/// ## Why the plugin decides this and the screen does not
///
/// The pad is generated from [ScoringPlugin.controls] precisely so that
/// adding a sport is writing a plugin, never editing a screen. A layout
/// switch in the UI keyed on `sportId` would put the sports back into the
/// screen through the side door — one `if (sport == 'badminton')` and the
/// inversion is gone.
///
/// So the plugin says what SHAPE its match has, in the vocabulary of matches
/// rather than of widgets, and the pad decides how to draw that shape.
enum PadLayout {
  /// A scoreboard with grouped controls beneath it. The right answer for a
  /// sport whose events are many and varied — cricket's twelve kinds of
  /// delivery, football's cards and substitutions — where what the scorer
  /// needs is to find the right button quickly.
  stacked,

  /// Two opposed halves, one per side, each the size of half the screen.
  ///
  /// The right answer for a rally sport, and it is a different kind of pad
  /// rather than a prettier one. In badminton, tennis and table tennis every
  /// single event is "that side won the rally" — a 21-point game is forty
  /// taps of one of two buttons, made by somebody watching the court and not
  /// the phone. A half-screen target can be hit without looking; a 44pt
  /// button in a row of six cannot.
  duel,

  /// A mat with two rosters on it, a turn clock, and a queue of details the
  /// scorer has not had time to fill in.
  ///
  /// The right answer for kabaddi and kho-kho, and a different kind of pad
  /// again rather than a prettier stacked one. What the scorer needs here is
  /// not to find a button — it is to see who is still on the mat, because
  /// that number is what decides whether the next tackle is worth one point
  /// or two and whether the bonus line exists at all. A stacked pad can show
  /// the score and the buttons; it cannot show the mat, so the scorer counts
  /// players by eye under a thirty-second clock and gets it wrong.
  ///
  /// See [MatBoard].
  mat,

  /// A crease: who is batting, who is bowling, what the last balls were, and
  /// a keypad of deliveries.
  ///
  /// The right answer for cricket, and a fourth kind of pad rather than a
  /// tidier stacked one, because cricket's scorer is tracking a different
  /// kind of thing from anybody else's. Every other sport's pad answers "what
  /// just happened". Cricket's has to answer "what just happened, **to which
  /// of two named batters, off which named bowler**" — and the answer moves
  /// on its own: strike rotates on an odd run, again at the end of every
  /// over, and the bowler is replaced every six balls. A scorer who loses
  /// track of who is on strike puts the runs on the wrong player, and no
  /// amount of care later can separate them again.
  ///
  /// So the pad states the crease continuously — the striker marked, their
  /// figures beside them, the bowler's under them — and shows the recent
  /// deliveries as a strip, because "what have the last six balls been" is
  /// the question the scorer, the captain and the crowd all ask and a running
  /// total cannot answer.
  ///
  /// See [CreaseBoard].
  crease,
}

/// Everything a [PadLayout.duel] pad draws, described by the plugin.
///
/// Deliberately presentation-shaped rather than state-shaped: the three
/// racket sports keep their scores under different keys ('currentA' in
/// badminton, 'pointsA' in tennis) and count different things (points, games
/// and sets in tennis; points and games in table tennis). A pad that read the
/// state map directly would need to know all of that, which is exactly the
/// sport knowledge that must not live in the UI.
@immutable
class DuelBoard {
  const DuelBoard({
    required this.a,
    required this.b,
    this.periods = const [],
    this.status,
    this.matchScore,
    this.pipTarget,
    this.pointsNote,
    this.endsNote,
  });

  /// Points that take the period — 21 in badminton, 11 in table tennis, 25 in
  /// a volleyball set. Drives the grid of boxes under each score, which is how
  /// a scorer sees "six more" without doing arithmetic during a rally.
  ///
  /// Null for a sport whose period is not won by counting to a fixed number:
  /// a tennis game is 15/30/40, not 4 points, and drawing four boxes for it
  /// would be a diagram of a rule tennis does not have.
  final int? pipTarget;

  /// The format in the sport's own words — '21 points per set, best of 3'.
  /// Sits under the match score, where it answers the question every spectator
  /// asks first and no scoreboard usually answers.
  final String? pointsNote;

  /// Where each side is standing, and when they next swap — 'Change ends at
  /// 11 · Anand left, Ravi right'. Null when the sport has no ends protocol or
  /// none is due.
  final String? endsNote;

  final DuelSide a;
  final DuelSide b;

  /// Sets or games won, drawn as the headline above the two halves.
  ///
  /// Separate from the point score on each half because they answer two
  /// different questions and a scorer needs both at once: "who is winning
  /// this rally exchange" is the number in the half, "who is winning the
  /// match" is this. A pad that shows only the points makes a player at
  /// 2 sets to 0 down look like they are 19-17 up, and a pad that shows only
  /// the sets cannot be scored on at all.
  ///
  /// Null for a sport with no tier above the running score.
  final DuelMatchScore? matchScore;

  /// Completed sets/games, oldest first, plus the one in play. Drawn as the
  /// strip of boxes between the two halves.
  final List<DuelPeriod> periods;

  /// One line of context under the strip: "Set 2 · to 21", "Deuce",
  /// "Tie-break". Falls back to [ScoringPlugin.statusLine] when null.
  final String? status;

  DuelSide operator [](Side side) => side == Side.a ? a : b;
}

/// One half of a duel pad.
@immutable
class DuelSide {
  const DuelSide({
    required this.name,
    required this.score,
    this.sub,
    this.serving = false,
    this.serverName,
    this.tag,
    this.pips,
  });

  /// How many boxes of [DuelBoard.pipTarget] are filled — the point count as a
  /// number, where [score] is the same thing as the sport says it.
  ///
  /// Separate from [score] because they are not always the same value: tennis
  /// shows '40' for its third point, and a grid drawn from that string would
  /// need forty boxes. Null wherever the sport has no countable pips.
  final int? pips;

  /// Who this half belongs to — the entrant name, or the pair in doubles.
  final String name;

  /// The number that fills the half: '19' in badminton, '40' or 'AD' in
  /// tennis. A string because tennis's ladder is not a count.
  final String score;

  /// The smaller line beneath: 'Sets 1', 'Games 4'. Null when the sport has
  /// nothing above the point to show.
  final String? sub;

  /// Whether this side is serving. Drives the only piece of state a scorer
  /// checks constantly and can never derive from the numbers alone.
  final bool serving;

  /// The individual serving, when the sport tracks it and a line-up names
  /// them — badminton's four-player rotation, where "who serves next" is a
  /// genuine question even to the players.
  final String? serverName;

  /// 'Game point', 'Set point', 'Match point'. The thing a crowd knows and a
  /// scoreboard usually does not.
  final String? tag;
}

/// The tier above the running score — sets in badminton, sets in tennis,
/// games in a table-tennis match.
@immutable
class DuelMatchScore {
  const DuelMatchScore({
    required this.a,
    required this.b,
    this.label = 'SETS WON',
  });

  final int a;
  final int b;

  /// What the pair of numbers ARE. Spelled out under them because "3 - 2" on
  /// a badminton scoreboard is otherwise ambiguous with the point score
  /// directly beneath it, and the whole reason this row exists is to stop the
  /// two being confused.
  final String label;
}

/// One set or game in the strip.
@immutable
class DuelPeriod {
  const DuelPeriod({
    required this.label,
    required this.a,
    required this.b,
    this.current = false,
  });

  final String label;
  final int a;
  final int b;

  /// The set being played now, drawn highlighted.
  final bool current;
}

/// Everything a [PadLayout.crease] pad draws, described by the plugin.
///
/// Presentation-shaped rather than state-shaped, for the same reason
/// [DuelBoard] and [MatBoard] are — but the pressure here is different and
/// worth naming. Cricket's projection is deeply nested (innings → batting →
/// per-player tallies) and its derived numbers are all conventions rather
/// than arithmetic: overs are `balls ~/ 6 . balls % 6` and never a decimal,
/// a strike rate is per hundred balls, an economy is per over, balls faced
/// includes no-balls but excludes wides. A pad that computed any of that from
/// the state map would be a pad that knows the laws of cricket, and the next
/// sport with a crease — the next FORMAT of this sport, with eight-ball overs
/// — would have to be taught to it a second time.
///
/// So the engine does the arithmetic in the one place that already has to be
/// right, and hands over strings.
@immutable
class CreaseBoard {
  const CreaseBoard({
    required this.battingTeam,
    required this.score,
    required this.overs,
    this.inningsLabel,
    this.oversOf,
    this.extras,
    this.runRate,
    this.chaseLine,
    this.chaseNeed,
    this.batters = const [],
    this.bowler,
    this.timeline = const [],
    this.notes = const [],
  });

  /// Who is batting, by name. The top line, because on a phone held up at a
  /// ground it is the only thing that says which half of the match this is.
  final String battingTeam;

  /// '1st Innings', '2nd Innings', 'Super Over'. Null in a format with one.
  final String? inningsLabel;

  /// The number everybody is looking at — '70-1'. Formatted by the sport:
  /// India writes 70-1 and England writes 1-70, and that is a preference the
  /// engine can hold and the pad cannot.
  final String score;

  /// Overs bowled in the sport's own notation — '6.4', never 6.67.
  final String overs;

  /// The allotment, drawn as '/ 20'. Null for a format with no limit.
  final String? oversOf;

  /// Extras conceded so far. Null where the format does not track them
  /// separately.
  final int? extras;

  /// Current run rate, already rounded — '10.5'.
  final String? runRate;

  /// The chase, on one line: 'Target 133 · Req 4.7'. Null in the first
  /// innings, where there is nothing to chase.
  final String? chaseLine;

  /// The same chase in the words a player uses: 'Need 63 runs off 80 balls'.
  /// Deliberately separate from [chaseLine] — one is the scoreboard's phrasing
  /// and one is the dressing room's, and the pad draws them on two lines
  /// because a scorer reading out the situation reads the second.
  final String? chaseNeed;

  /// The two at the crease, striker first. One entry between a wicket and the
  /// next batter walking out; empty before the innings starts.
  final List<CreaseBatter> batters;

  /// Who is bowling. Null between overs, before a replacement is named — and
  /// the pad says so rather than drawing an empty row.
  final CreaseBowler? bowler;

  /// Recent deliveries, oldest first, newest last. The pad shows the tail of
  /// this and scrolls to it.
  final List<BallChip> timeline;

  /// Short states the scorer must not miss: 'FREE HIT', 'NEW BATTER'. Drawn
  /// as chips beside the score, where a line of prose would be skimmed past.
  final List<String> notes;
}

/// One batter at the crease.
@immutable
class CreaseBatter {
  const CreaseBatter({
    required this.name,
    required this.runs,
    required this.balls,
    required this.fours,
    required this.sixes,
    required this.strikeRate,
    this.onStrike = false,
  });

  final String name;
  final int runs;
  final int balls;
  final int fours;
  final int sixes;

  /// Already formatted — '152.6'. A rate of nothing off nothing is not zero,
  /// it is undefined, and the sport decides what to print for it.
  final String strikeRate;

  /// Drawn with the asterisk every scorecard in the world uses, and
  /// highlighted. This is the single most consequential fact on the pad: it
  /// decides whose column the next four goes in.
  final bool onStrike;
}

/// Who is bowling, with the figures a captain checks between overs.
@immutable
class CreaseBowler {
  const CreaseBowler({
    required this.name,
    required this.overs,
    required this.maidens,
    required this.runs,
    required this.wickets,
    required this.economy,
  });

  final String name;

  /// '1.4' — the same notation as [CreaseBoard.overs].
  final String overs;
  final int maidens;
  final int runs;
  final int wickets;

  /// Already formatted — '12.0'.
  final String economy;
}

/// One delivery in the recent-balls strip.
///
/// A ball is not a number: a wide is a run that did not come off the bat and
/// did not use up a delivery, a wicket is not a quantity at all, and a dot is
/// drawn as a dot because that is what a scorer's eye is trained to count. So
/// the chip carries what to print and what KIND of thing it was, and the pad
/// colours it from the kind rather than from parsing the label.
@immutable
class BallChip {
  const BallChip({
    required this.label,
    required this.kind,
    this.endsOver = false,
  });

  /// '4', 'W', 'Wd', 'Nb+2', '•'.
  final String label;
  final BallKind kind;

  /// Whether this delivery completed an over. The pad draws a separator after
  /// it, which is what turns a row of numbers into "that over went 1, 4, 0,
  /// wide, 6, out" — the unit everybody at a cricket ground actually thinks
  /// in.
  final bool endsOver;
}

/// What a delivery was, for the pad to colour by. Deliberately about the
/// SHAPE of the outcome rather than about cricket's names for it, so another
/// sport with a ball-by-ball strip can reuse the strip.
enum BallKind {
  /// Nothing scored.
  dot,

  /// Ordinary runs.
  runs,

  /// The lesser boundary — cricket's four.
  boundary,

  /// The greater boundary — cricket's six.
  maximum,

  /// A dismissal.
  wicket,

  /// Runs that were not scored off the bat.
  extra,
}

/// Everything a [PadLayout.mat] pad draws, described by the plugin.
///
/// ## Why this is a third board and not a dressed-up duel
///
/// A duel pad answers one question forty times: which side won the rally. A
/// mat sport asks a different one, and asks it under a thirty-second clock —
/// *what just happened, and to whom.* A raid ends in a touch, a bonus, an
/// empty, a tackle, a super tackle or a do-or-die failure; players leave the
/// mat and come back in the order they left; and the scorer must be able to
/// enter every one of those without stopping, because the next raid has
/// already started.
///
/// So the board carries three things a duel board has no notion of: **who is
/// on the mat right now** ([MatSide.active] and [MatSide.out]), **whose turn
/// it is** ([turn]), and **what has not been filled in yet** ([pending]).
/// That last one is the whole design: a pad that refuses a point until the
/// scorer names a player is a pad that loses the next raid, so the point goes
/// in immediately and the missing detail waits here until there is time.
///
/// Presentation-shaped rather than state-shaped, for the same reason
/// [DuelBoard] is: kho-kho's turn is a chase and kabaddi's is a raid, and a
/// pad that read either engine's state map directly would be a pad that knows
/// what a raid is.
@immutable
class MatBoard {
  const MatBoard({
    required this.a,
    required this.b,
    this.periodLabel,
    this.clock,
    this.clockOf,
    this.actionClockSeconds = 0,
    this.actionClockLabel,
    this.turn,
    this.history = const [],
    this.pending = const [],
    this.scorecard = const [],
    this.scorecardColumns = const [],
    this.status,
  });

  final MatSide a;
  final MatSide b;

  MatSide operator [](Side side) => side == Side.a ? a : b;

  /// "1st Half", "2nd Half" — drawn above the clock.
  final String? periodLabel;

  /// Elapsed match time, already formatted by the sport. Null for an untimed
  /// competition, in which case the pad draws no clock rather than a zero.
  final String? clock;

  /// The scheduled length, drawn under [clock] as "of 40:00".
  final String? clockOf;

  /// Length of the per-turn clock — kabaddi's thirty-second raid. The PAD
  /// runs this countdown, not the engine: a wall clock inside a reducer would
  /// make replay non-deterministic, and the same match would rebuild to a
  /// different score depending on when it was rebuilt. Zero draws no timer.
  final int actionClockSeconds;

  /// What that clock is called: "RAID TIMER".
  final String? actionClockLabel;

  /// Whose turn it is and who is taking it. Null between turns.
  final MatTurn? turn;

  /// The play-by-play, newest last. The pad shows the tail.
  final List<MatPlay> history;

  /// Details entered late or not at all. See the class doc.
  final List<MatDetail> pending;

  /// The team scorecard: one row per side, one value per [scorecardColumns].
  final List<MatTotals> scorecard;

  /// Column headings for [scorecard] — "Raid Pts", "Tackle Pts", "Total".
  final List<String> scorecardColumns;

  /// One line of context under the board. Falls back to
  /// [ScoringPlugin.statusLine] when null.
  final String? status;
}

/// One side of a mat board.
@immutable
class MatSide {
  const MatSide({
    required this.name,
    required this.score,
    this.chips = const [],
    this.active = const [],
    this.out = const [],
    this.strength = 0,
    this.fullStrength = 0,
    this.onTheAttack = false,
    this.alert,
  });

  final String name;
  final int score;

  /// The headline breakdown beside the score: "Raid Pts 12", "Tackle Pts 6".
  final List<MatChip> chips;

  /// Who is on the mat, when the scorer entered a line-up. Empty is normal at
  /// a ground where nobody did, and the pad falls back to [strength].
  final List<MatPlayerChip> active;

  /// Who is off, in the order they will come back.
  final List<MatPlayerChip> out;

  /// How many are on the mat, and how many a full side is — drawn as the row
  /// of dots. Always exact, even when [active] is empty: the count is what the
  /// rules are decided from and the names are best effort.
  final int strength;
  final int fullStrength;

  /// Whether this side is raiding/chasing right now.
  final bool onTheAttack;

  /// A state the scorer must see without reading: "DO OR DIE".
  final String? alert;
}

/// One labelled number beside a side's score.
@immutable
class MatChip {
  const MatChip(this.label, this.value);
  final String label;
  final String value;
}

/// One player on a roster strip.
@immutable
class MatPlayerChip {
  const MatPlayerChip({
    required this.id,
    required this.name,
    this.number,
    this.isActor = false,
  });

  final String id;
  final String name;

  /// Jersey number, drawn in the square. Null for a squad entered without
  /// numbers, which is most of them.
  final String? number;

  /// The raider/chaser right now, drawn marked.
  final bool isActor;
}

/// Whose turn it is, and the one number that decides what it is worth.
@immutable
class MatTurn {
  const MatTurn({
    required this.side,
    required this.title,
    this.actorName,
    this.actorNumber,
    this.counterLabel,
    this.counterValue,
    this.nextTitle,
    this.nextName,
    this.change,
  });

  final Side side;

  /// "CURRENT RAIDER".
  final String title;

  /// Null when the scorer has not named them — which is allowed, and common.
  final String? actorName;
  final String? actorNumber;

  /// The number opposite: "DEFENDERS ON MAT", 4. This is what turns a tackle
  /// into a super tackle and a bonus into nothing, so it is on the board
  /// rather than left for the scorer to count under a raid clock.
  final String? counterLabel;
  final int? counterValue;

  /// "NEXT RAID", and who takes it.
  final String? nextTitle;
  final String? nextName;

  /// The control that names the actor. Null when the sport has no such
  /// concept, or when there is no line-up to choose from.
  final ScoreControl? change;
}

/// One line of the play-by-play.
@immutable
class MatPlay {
  const MatPlay({
    required this.no,
    required this.side,
    required this.result,
    required this.points,
    required this.scoreA,
    required this.scoreB,
    this.at,
    this.actor,
    this.isTurn = true,
  });

  /// The turn number — raid #27. Shared with the events that happened during
  /// that turn, which is what [isTurn] distinguishes.
  final int no;

  final Side side;

  /// As the sport says it: "Super Tackle", "Empty Raid", "Do-or-Die failed".
  final String result;

  final int points;

  /// The running score this line produced, which is what makes the ledger
  /// checkable against a disputed board.
  final int scoreA;
  final int scoreB;

  /// Match time, already formatted. Null when untimed.
  final String? at;

  /// Who did it, when anybody was named.
  final String? actor;

  /// False for something that happened between turns — a technical point, an
  /// all-out, a substitution — so the pad does not number it as a turn.
  final bool isTurn;
}

/// One thing the scorer skipped, waiting to be filled in.
@immutable
class MatDetail {
  const MatDetail({
    required this.id,
    required this.title,
    required this.question,
    required this.side,
    required this.complete,
  });

  /// Identifies the parked event. Already carried in [complete]'s payload.
  final String id;

  /// What was scored: "Raid #27 — Super Tackle (+2)".
  final String title;

  /// What is still missing: "Tackler?", "Players out?".
  final String question;

  final Side side;

  /// The control that completes it, prompts and all. The pad asks the
  /// question the same way it asks every other prompt, so nothing about
  /// raids or tackles reaches the screen.
  final ScoreControl complete;
}

/// One side's row in the team scorecard.
@immutable
class MatTotals {
  const MatTotals({
    required this.side,
    required this.name,
    required this.values,
  });

  final Side side;
  final String name;

  /// One per [MatBoard.scorecardColumns], in the same order.
  final List<int> values;
}

/// One line of the match timeline — the running audit trail of everything the
/// scorer entered, in the order they entered it.
///
/// ## Why the plugin writes this and not the screen
///
/// The timeline is the one place a match can be checked against what actually
/// happened: a disputed point, a score that looks wrong two sets later, a
/// player insisting they were on 19. That check is only worth anything if the
/// line says what the sport means — "Team A +1" in badminton, "4 runs" in
/// cricket, "Yellow card" in football.
///
/// The spectator screen used to do this with a hard-coded `switch` over event
/// types, which is the plugin inversion this codebase is built to avoid coming
/// back through the side door: it knew cricket's vocabulary and nothing else,
/// so every rally sport's timeline read `point` forty times in a column, and
/// adding a sport meant editing a screen. The sport owns its own vocabulary,
/// so the sport writes its own lines.
@immutable
class MatchEventLine {
  const MatchEventLine({
    required this.text,
    this.side = Side.neutral,
    this.detail,
    this.isMilestone = false,
  });

  /// What happened, in the sport's own words: 'Team A +1', 'Wicket!'.
  final String text;

  /// Whose event it was. Colours the row, so a scorer scanning back through a
  /// game reads the pattern of who won what without reading any words.
  final Side side;

  /// The score after it, or who did it — the second, quieter column.
  final String? detail;

  /// Whether this closed something: a set, an innings, a period. Drawn as a
  /// full-width divider rather than a row, because a timeline of forty
  /// identical points is unreadable without the breaks that give it shape.
  final bool isMilestone;
}

/// One row of the rendered timeline: the event, how it reads, and whether it
/// still counts.
@immutable
class MatchTimelineEntry {
  const MatchTimelineEntry({
    required this.event,
    required this.line,
    this.withdrawn = false,
  });

  final MatchEvent event;
  final MatchEventLine line;

  /// True when a later undo withdrew this event.
  ///
  /// Shown struck through rather than removed. The log is append-only
  /// precisely so that a mistake and its correction are both on the record —
  /// hiding the withdrawn entry would give back exactly the thing the
  /// append-only design was protecting, which is the ability to show a
  /// disputing captain what was entered and what was taken back.
  final bool withdrawn;
}

/// Grouping of controls so the pad can lay out rows sensibly.
@immutable
class ScoreControlGroup {
  const ScoreControlGroup({required this.title, required this.controls});
  final String title;
  final List<ScoreControl> controls;
}

/// What the scorer pressed.
@immutable
class ScoreAction {
  const ScoreAction({
    required this.type,
    this.side = Side.neutral,
    this.payload = const {},
  });

  final String type;
  final Side side;
  final Map<String, dynamic> payload;

  Map<String, dynamic> toEventPayload() => {
        'side': side.wire,
        ...payload,
      };
}

/// Final result of a match, once the plugin says it is over.
@immutable
class MatchOutcome {
  const MatchOutcome({
    required this.isComplete,
    this.winnerSide,
    this.isDraw = false,
    this.scoreForA = 0,
    this.scoreForB = 0,
  });

  static const inProgress = MatchOutcome(isComplete: false);

  final bool isComplete;
  final Side? winnerSide;
  final bool isDraw;

  /// Scalar totals fed into the league table's score difference column.
  final int scoreForA;
  final int scoreForB;
}

/// Outcome of applying an action: either new state, or a rejection.
///
/// Rejection is a first-class result rather than an exception because the
/// scoring pad must show "you cannot bowl a 7th ball in this over" as a
/// message, not crash mid-match in front of a crowd.
@immutable
class ScoringResult {
  const ScoringResult.ok(this.state)
      : rejection = null,
        isAccepted = true;
  const ScoringResult.rejected(this.rejection)
      : state = const {},
        isAccepted = false;

  final Map<String, dynamic> state;
  final String? rejection;
  final bool isAccepted;
}

/// Immutable facts a plugin needs that live outside its own state.
@immutable
class ScoringContext {
  const ScoringContext({
    required this.entrantAName,
    required this.entrantBName,
    this.config = const {},
    this.lineupA = const [],
    this.lineupB = const [],
  });

  final String entrantAName;
  final String entrantBName;

  /// Who is available to play for each side.
  ///
  /// Engines that record player-level facts — every one of them, per the
  /// spec — resolve ids to names through these. Empty for a sport or a match
  /// where nobody has entered a line-up, in which case an engine records
  /// side-level totals only and no scorecard can be produced.
  final List<MatchPlayer> lineupA;
  final List<MatchPlayer> lineupB;

  List<MatchPlayer> lineupFor(Side side) =>
      side == Side.a ? lineupA : (side == Side.b ? lineupB : const []);

  /// Resolves a player id from either side. Returns null for an unknown id
  /// rather than throwing: a replay of an old log must never crash because a
  /// player was later removed from a squad.
  MatchPlayer? player(String? id) {
    if (id == null) return null;
    for (final p in lineupA) {
      if (p.id == id) return p;
    }
    for (final p in lineupB) {
      if (p.id == id) return p;
    }
    return null;
  }

  String playerName(String? id, [String fallback = 'Player']) =>
      player(id)?.name ?? fallback;

  /// Which side takes the first turn, as decided by the toss.
  ///
  /// `CompetitionRepository.recordToss` writes `startingSide` into the frozen
  /// config for EVERY sport — it has done so for a while — and cricket was
  /// the only engine that ever read it, under its own `battingFirst` key.
  /// Every other sport therefore opened with side A serving, raiding or
  /// chasing regardless of who had just won the toss and what they had
  /// chosen, and the scorer had to correct it by hand on the first rally.
  ///
  /// Defaults to A, which is the behaviour of a match whose toss was skipped
  /// and the only sensible answer when nothing recorded one.
  /// Never [Side.neutral]: `fromWire` falls back to neutral for anything it
  /// does not recognise, and "neither side starts" is not a state any of
  /// these engines can open in.
  Side get startingSide {
    final side = Side.fromWire(config['startingSide'] as String?);
    return side == Side.neutral ? Side.a : side;
  }

  /// Per-competition overrides: overs per innings, points per set, match
  /// duration. Frozen onto the fixture at generation time so changing the
  /// competition later cannot rewrite a finished match.
  ///
  /// Read this through [rules] rather than directly. The raw map stays public
  /// only because it is what gets persisted.
  final Map<String, dynamic> config;

  /// Typed view over [config]. Every rule parameter an engine reads must come
  /// through here — see CLAUDE.md §2.3 and §12.2.
  RuleConfig get rules => RuleConfig(config);

  int intConfig(String key, int fallback) => rules.getInt(key, fallback);

  bool boolConfig(String key, bool fallback) => rules.getBool(key, fallback);

  double doubleConfig(String key, double fallback) =>
      rules.getDouble(key, fallback);

  String stringConfig(String key, String fallback) =>
      rules.getString(key, fallback);

  List<int> intListConfig(String key, List<int> fallback) =>
      rules.getIntList(key, fallback);

  String nameFor(Side side) => switch (side) {
        Side.a => entrantAName,
        Side.b => entrantBName,
        Side.neutral => '',
      };
}

/// Contract every sport's scoring implementation satisfies.
///
/// Implementations must be **pure**: [apply] takes state plus an action and
/// returns new state, touching nothing else. Purity is not stylistic here —
/// it is what allows the same code to run on the scorer's phone for instant
/// feedback, replay the stored event log to rebuild a match from scratch,
/// and later run server-side to make results tamper-proof, all with
/// guaranteed identical answers.
abstract class ScoringPlugin {
  const ScoringPlugin();

  /// Stable identifier persisted on every competition and fixture. Never
  /// rename one of these; add a new plugin instead.
  String get key;

  String get displayName;

  /// Opening state for a fresh match.
  Map<String, dynamic> initialState(ScoringContext ctx);

  /// Pure reducer. Must not mutate [state].
  ScoringResult apply(
    Map<String, dynamic> state,
    ScoreAction action,
    ScoringContext ctx,
  );

  /// Large, glanceable score for the top of the screen, e.g. "21 - 18".
  String headline(Map<String, dynamic> state, ScoringContext ctx);

  /// Compact full score for lists and notifications, e.g. "21-18, 19-21".
  String summary(Map<String, dynamic> state, ScoringContext ctx);

  /// Secondary line of context: overs bowled, current set, period.
  String? statusLine(Map<String, dynamic> state, ScoringContext ctx) => null;

  /// How one recorded event should read in the match timeline.
  ///
  /// See [MatchEventLine] for why this is the sport's job. The default is
  /// deliberately plain rather than clever — a humanised event type and the
  /// side that caused it — so an engine that has not overridden this produces
  /// a legible timeline instead of an empty one, and overriding it is a
  /// straight improvement rather than a repair.
  ///
  /// Returning null hides the event. That is the right answer for the
  /// bookkeeping ones — an undo, a state correction — which are real entries
  /// in the log and noise in a human's reading of it.
  MatchEventLine? describeEvent(MatchEvent event, ScoringContext ctx) {
    if (event.type == 'undo') return null;
    final side = Side.fromWire(event.payload['side'] as String?);

    // The lifecycle events every sport shares. Named here so twelve engines do
    // not each have to spell "Match ended" for themselves, and so an engine
    // that overrides nothing still produces a readable line for them.
    final universal = switch (event.type) {
      'finish' => 'Match ended',
      'next_period' => 'Next period',
      'end_innings' => 'End of innings',
      'reopen' => 'Reopened to correct',
      ScoringPlugin.restartActionType => 'Match restarted',
      _ => null,
    };
    if (universal != null) {
      return MatchEventLine(text: universal, side: side, isMilestone: true);
    }

    final words = event.type.replaceAll('_', ' ');
    return MatchEventLine(
      text: side == Side.neutral
          ? '${words[0].toUpperCase()}${words.substring(1)}'
          : '${ctx.nameFor(side)} — $words',
      side: side,
    );
  }

  /// The whole match as a readable list, oldest first.
  ///
  /// Separate from [describeEvent] because some sports need to have replayed
  /// the match to describe one line of it: "SET 1 — 21-18" is not a fact about
  /// the point that ended the set, it is a fact about every point before it.
  /// An engine that wants running scores or period breaks in its timeline
  /// overrides this and replays; an engine that does not gets the cheap
  /// per-event mapping and no replay cost.
  ///
  /// Withdrawn events stay in the list, flagged. See [MatchTimelineEntry].
  List<MatchTimelineEntry> timeline(
    List<MatchEvent> events,
    ScoringContext ctx,
  ) {
    final sorted = [...events]..sort((x, y) => x.seq.compareTo(y.seq));
    final withdrawn = resolveWithdrawn([
      for (final e in sorted)
        LoggedAction(seq: e.seq, action: actionOf(e)),
    ]);

    return [
      for (final e in sorted)
        if (describeEvent(e, ctx) case final line?)
          MatchTimelineEntry(
            event: e,
            line: line,
            withdrawn: withdrawn.contains(e.seq),
          ),
    ];
  }

  /// The action a logged event represents.
  ///
  /// Lives here rather than in the service so that [timeline] — and any engine
  /// overriding it — can replay a log without depending on the data layer.
  static ScoreAction actionOf(MatchEvent e) => ScoreAction(
        type: e.type,
        side: Side.fromWire(e.payload['side'] as String?),
        payload: e.payload,
      );

  /// One side's per-player box score, or null for a sport that keeps no
  /// per-player tally (a two-player rally game has nothing to break down).
  ///
  /// Declared on the contract rather than left as a convention across the
  /// engines because the UI has to be able to ask for a scorecard without
  /// knowing which sport it is holding. Twelve engines already computed a
  /// [BoxScore] and no screen could reach one: the method existed only on the
  /// concrete classes, so every spectator and every scorer saw a headline and
  /// nothing else. Overriding it is the only thing an engine has to do to get
  /// a rendered scorecard.
  BoxScore? boxScore(
    Map<String, dynamic> state,
    ScoringContext ctx,
    Side side,
  ) =>
      null;

  /// The 1-2 tally keys, largest-first, that stand for "the" stat in this
  /// sport for a leaderboard — cricket's `runs`, kabaddi's `raidPoints` then
  /// `tacklePoints`. Always a plugin's own [StatColumn] key, never a
  /// [StatColumn.derive]d one: a leaderboard is built by summing career
  /// totals across every finished match, and a derived value (a percentage,
  /// an average) does not sum into anything meaningful the way a raw counter
  /// does.
  ///
  /// Empty by default, which quietly opts a sport out of ranking rather than
  /// guessing. Athletics is the deliberate case: its headline number is a
  /// personal best, not a count, and summing best marks across meets would
  /// produce a number that means nothing — so it stays unranked rather than
  /// leaderboarding a value that was never meant to be added up.
  List<String> get headlineStats => const [];

  /// Result so far. [MatchOutcome.isComplete] flipping to true is what lets
  /// the scoring screen offer "finalize".
  MatchOutcome outcome(Map<String, dynamic> state, ScoringContext ctx);

  /// The control that ends the match, once play has reached its end.
  ///
  /// Null while there is still a match to play, and null for the sports that
  /// finish themselves — a badminton match ends when somebody wins the last
  /// game, and nobody has to be asked. This exists for the OTHER kind: a
  /// football match, a kabaddi match, a game of basketball. Nothing in those
  /// engines can know the referee has blown, because no clock in this app
  /// runs on its own — the minute only moves when an event carries one — so
  /// the match sat on "Live" until somebody thought to open the tray under
  /// the pad and press a button they had no reason to look for. Matches were
  /// left in progress for days that way, and a league table missing its last
  /// round is indistinguishable from one nobody has played.
  ///
  /// Returning a control is not a claim that the match IS over. It means the
  /// last period is under way and the next thing to happen is the final
  /// whistle, so the pad should stop hiding the button that records it. The
  /// scorer still presses it, and still confirms — see `_FinishBar`.
  ScoreControl? finishControl(Map<String, dynamic> state, ScoringContext ctx) =>
      null;

  /// The buttons to render right now, given current state.
  List<ScoreControlGroup> controls(
    Map<String, dynamic> state,
    ScoringContext ctx,
  );

  /// The shape of this sport's match, which decides how the pad draws itself.
  /// See [PadLayout]. Stacked unless a plugin says otherwise.
  PadLayout get padLayout => PadLayout.stacked;

  /// The live board for a [PadLayout.duel] pad, or null.
  ///
  /// A plugin that declares `duel` must return one; a plugin that returns
  /// null gets the stacked pad whatever it declared, so a half-finished
  /// implementation degrades to the older layout rather than to a blank
  /// screen.
  DuelBoard? duelBoard(Map<String, dynamic> state, ScoringContext ctx) => null;

  /// The live board for a [PadLayout.mat] pad, or null.
  ///
  /// Same contract as [duelBoard]: a plugin that declares `mat` and returns
  /// null gets the stacked pad, so a half-finished implementation degrades to
  /// the older layout rather than to a blank screen in front of a crowd.
  MatBoard? matBoard(Map<String, dynamic> state, ScoringContext ctx) => null;

  /// The live board for a [PadLayout.crease] pad, or null.
  ///
  /// Same contract as [duelBoard] and [matBoard]: declaring the layout and
  /// returning null degrades to the stacked pad rather than to a blank screen.
  CreaseBoard? creaseBoard(Map<String, dynamic> state, ScoringContext ctx) =>
      null;

  /// The control a duel pad's half triggers when tapped: the first PRIMARY
  /// control declared for that side.
  ///
  /// Resolved from the controls the plugin has already emitted rather than
  /// declared separately, so it cannot describe a button the pad is not also
  /// showing — and so a plugin that stops offering a side's point (a finished
  /// match, an innings break) automatically stops that half accepting taps.
  static ScoreControl? primaryFor(List<ScoreControlGroup> groups, Side side) {
    for (final g in groups) {
      for (final c in g.controls) {
        if (c.side == side && c.style == ControlStyle.primary) return c;
      }
    }
    return null;
  }

  /// The control a duel pad's half triggers on a long press — the correction
  /// for that side, when the sport offers one.
  ///
  /// A long press rather than a button, because taking a point back is rare
  /// and putting it anywhere near a target the scorer hits without looking is
  /// how a correction becomes the mistake. It is still in the tray as a
  /// labelled control for anyone who never discovers the gesture.
  static ScoreControl? correctionFor(
    List<ScoreControlGroup> groups,
    Side side,
  ) {
    for (final g in groups) {
      for (final c in g.controls) {
        if (c.side == side && c.action == 'correct') return c;
      }
    }
    return null;
  }

  /// Rebuilds state from the authoritative event log. Used to recover after
  /// a conflict, to audit a disputed result, and to verify that the stored
  /// projection matches what the events actually say.
  Map<String, dynamic> replay(
    Iterable<ScoreAction> actions,
    ScoringContext ctx,
  ) {
    var state = initialState(ctx);
    for (final action in actions) {
      final result = apply(state, action, ctx);
      // A rejected action in a replay means the log contains something the
      // current rules refuse. Skip it rather than aborting: an old match
      // scored under previous rules must still be readable.
      if (result.isAccepted) state = result.state;
    }
    return state;
  }

  /// Rebuilds state from a log that may contain corrections.
  ///
  /// This is the whole of the UNDO model, and it is why the log can stay
  /// append-only. A mistake is never edited or deleted; the scorer appends an
  /// [undoActionType] event naming the sequence number it reverses, and the
  /// projection is recomputed by replaying every event *except* the reversed
  /// ones. Nothing is mutated and nothing is lost — the log still records
  /// that the error was made and then withdrawn, which is what a disputed
  /// scorecard needs to be able to show.
  ///
  /// Undoing an undo is supported: an undo is itself reversible, which is
  /// what makes a mis-tapped correction recoverable.
  Map<String, dynamic> rebuild(
    Iterable<LoggedAction> log,
    ScoringContext ctx,
  ) {
    final entries = log.toList()..sort((x, y) => x.seq.compareTo(y.seq));
    final withdrawn = resolveWithdrawn(entries);

    var state = initialState(ctx);
    for (final e in entries) {
      if (withdrawn.contains(e.seq)) continue;
      // A restart wipes the board and keeps the log. See [restartActionType]:
      // everything before it stays in the ledger and simply stops counting,
      // which is what makes a restart tapped by mistake recoverable — undo
      // the restart event and the old score rebuilds itself.
      if (e.action.type == restartActionType) {
        state = initialState(ctx);
        continue;
      }
      // An undo is bookkeeping, not a scoring action. Handing it to an
      // engine's `apply` would be rejected as unknown.
      if (e.action.type == undoActionType) continue;
      final result = apply(state, e.action, ctx);
      if (result.isAccepted) state = result.state;
    }
    return state;
  }

  /// Which sequence numbers a log's corrections have withdrawn.
  ///
  /// Resolved by walking the log **backwards**. An undo can itself be undone,
  /// and a forward pass cannot express that: by the time it reaches the
  /// second undo it has already applied the first one's effect, and
  /// un-marking the undo event does not restore what that undo removed.
  /// Going backwards, the newest correction wins and cancels any older one it
  /// targets before that older one is ever consulted.
  static Set<int> resolveWithdrawn(List<LoggedAction> sortedEntries) {
    final cancelled = <int>{};
    for (final e in sortedEntries.reversed) {
      if (e.action.type != undoActionType) continue;
      // An undo that has itself been withdrawn does nothing.
      if (cancelled.contains(e.seq)) continue;
      final target = e.reversesSeq;
      if (target != null) cancelled.add(target);
    }
    return cancelled;
  }

  /// The action type that withdraws an earlier event.
  ///
  /// Handled by [rebuild] rather than by any engine's `apply`, so every sport
  /// gets correction for free and no engine can implement it inconsistently.
  static const undoActionType = 'undo';

  /// The action type that starts the match again from nothing.
  ///
  /// ## Why this is an event and not a wipe
  ///
  /// "Restart" is what a scorer taps when the match they were recording did
  /// not really happen — the wrong fixture, a game abandoned and replayed
  /// from the top, a pad opened on the next court by mistake. The obvious
  /// implementation is to blank `scoreState` and set `lastSeq` back to zero,
  /// and it is the wrong one twice over: it destroys the ledger the whole
  /// design rests on, and it is unrecoverable — a restart tapped by accident
  /// on a match that was forty minutes old has thrown that match away.
  ///
  /// Appending a marker instead costs one event and gives both back. The log
  /// still holds every point of the original match; [rebuild] simply starts
  /// counting again from the marker. And because the marker is an ordinary
  /// event, the correction machinery already handles taking it back: undo the
  /// restart and the previous score rebuilds exactly as it stood, because it
  /// was never deleted. That is the "continue the old score" the organizer
  /// asks for the moment they realise what they just tapped.
  static const restartActionType = 'restart';
}

/// One event from the log, as replay sees it: an action plus the sequence
/// number it was written under.
@immutable
class LoggedAction {
  const LoggedAction({required this.seq, required this.action});

  final int seq;
  final ScoreAction action;

  /// For an undo event, the sequence number being withdrawn.
  int? get reversesSeq {
    final v = action.payload['reversesSeq'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return null;
  }
}

/// Helper for plugins: shallow-copies a state map so [apply] stays pure.
Map<String, dynamic> mutate(
  Map<String, dynamic> state,
  void Function(Map<String, dynamic> next) update,
) {
  final next = Map<String, dynamic>.from(state);
  update(next);
  return next;
}

/// Deep-copies a list of maps nested inside state (innings, sets, periods).
List<Map<String, dynamic>> copyList(Object? value) {
  if (value is! List) return [];
  return value
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
}
