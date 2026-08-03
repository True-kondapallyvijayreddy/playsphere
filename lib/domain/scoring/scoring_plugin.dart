import 'package:flutter/foundation.dart';

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
  });

  /// People the pad must name before this action can be applied, in the order
  /// the scorer should be asked. Empty for anything that names nobody — a
  /// period boundary, an interval, a change of ends. See [PlayerPrompt].
  final List<PlayerPrompt> prompts;

  /// Numbers the pad must collect. Asked in the same dialog as [prompts],
  /// after them, because "who" comes before "how fast". See [ValuePrompt].
  final List<ValuePrompt> values;

  /// Whether this button needs anything asked before it can be applied.
  bool get needsInput => prompts.isNotEmpty || values.isNotEmpty;

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

  /// Result so far. [MatchOutcome.isComplete] flipping to true is what lets
  /// the scoring screen offer "finalize".
  MatchOutcome outcome(Map<String, dynamic> state, ScoringContext ctx);

  /// The buttons to render right now, given current state.
  List<ScoreControlGroup> controls(
    Map<String, dynamic> state,
    ScoringContext ctx,
  );

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
