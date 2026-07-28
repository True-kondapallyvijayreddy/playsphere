import 'package:flutter/foundation.dart';

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
  });

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
  });

  final String entrantAName;
  final String entrantBName;

  /// Per-competition overrides: overs per innings, points per set, match
  /// duration. Frozen onto the fixture at generation time so changing the
  /// competition later cannot rewrite a finished match.
  final Map<String, dynamic> config;

  int intConfig(String key, int fallback) {
    final v = config[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return fallback;
  }

  bool boolConfig(String key, bool fallback) {
    final v = config[key];
    return v is bool ? v : fallback;
  }

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
