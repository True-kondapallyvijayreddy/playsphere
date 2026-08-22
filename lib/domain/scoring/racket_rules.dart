/// The rules every racket sport shares, in one place.
///
/// ## Why this exists
///
/// Badminton, table tennis, tennis and pickleball are four different scoring
/// systems that agree on a surprising amount: a match is won in games or sets,
/// somebody serves, the players change ends on a schedule the laws fix, and a
/// player who cannot continue retires and hands the match over. The engines
/// were each written against their own sport's laws — correctly — and then
/// each stopped short in a different place. Tennis and table tennis had no way
/// to retire a match AT ALL, so an injury on court left the scorer with a
/// fixture that could never be closed. Badminton could retire but recorded no
/// reason, so "retired" and "walked over" and "disqualified" were one
/// indistinguishable outcome in the record.
///
/// Change of ends was worse: three presets in `rule_config.dart` had been
/// carrying `decidingGameSwitchAt`, `tiebreakChangeEndsEvery` and
/// `expediteAfterMinutes` for as long as they existed, and no engine ever read
/// a single one of them. The numbers were written down, reviewed and shipped,
/// and meant nothing.
///
/// So the shared parts live here and the sports keep only what genuinely
/// differs. The split is deliberate: [RacketMatch] owns retirement and the
/// end-change *protocol*, and each engine answers [endsChangeDue] from its own
/// laws, because "when do we change ends" is precisely the question the four
/// sports answer differently.
library;

import 'scoring_plugin.dart';

/// Why a match ended without being played out.
///
/// A retirement is not one outcome. A player who pulls a hamstring at 19-17,
/// an opponent who never arrived, and a player sent off by the referee all
/// produce "the other side won", and they are three completely different
/// facts about the match — for the standings, for a disciplinary record, and
/// for the player whose ranking is about to move. Storing only "retired"
/// throws that away at the moment it is known and it can never be recovered.
///
/// Presented as buttons rather than as a text field on purpose. The scorer is
/// standing beside a court holding a phone, and a keyboard is the one thing
/// they cannot use quickly; four taps-worth of choice is both faster and more
/// analysable than free text that will be spelled four different ways.
enum RetireReason {
  injury('injury', 'Injury / unable to continue'),
  illness('illness', 'Illness'),
  walkover('walkover', 'Walkover — did not appear'),
  conceded('conceded', 'Conceded'),
  disqualified('disqualified', 'Disqualified'),
  unspecified('unspecified', 'Retired');

  const RetireReason(this.wire, this.label);

  final String wire;
  final String label;

  static RetireReason fromWire(String? w) => RetireReason.values.firstWhere(
        (r) => r.wire == w,
        orElse: () => RetireReason.unspecified,
      );

  /// The reasons a scoring pad offers, in the order a scorer meets them.
  /// [unspecified] is not among them — it is the fallback for a log written
  /// before reasons were recorded, never something anyone should pick.
  static const offered = [injury, illness, walkover, conceded, disqualified];
}

/// State keys owned by this mixin. Namespaced under the same flat map the
/// engines already use, because the persisted state is one JSON document and
/// nesting it now would strand every match already in play.
const _kRetired = 'retired';
const _kRetiredReason = 'retiredReason';
const _kEndsSwapped = 'endsSwapped';
const _kEndsAckAt = 'endsAcknowledgedAt';

/// Retirement, change of ends, and the controls for both.
mixin RacketMatch on ScoringPlugin {
  /// The action a pad sends to retire a side. The side is the one RETIRING,
  /// not the one being awarded the match — the button sits under the player
  /// who is walking off, which is the only reading a scorer will not get
  /// backwards under pressure.
  static const retireAction = 'retire';

  /// Acknowledges that the players have changed ends. Separate from the
  /// engine's own detection because the engine knows when they are DUE and
  /// only the scorer knows when they have actually swapped.
  static const changeEndsAction = 'change_ends';

  // --- Retirement ---------------------------------------------------------

  /// Applies a retirement, recording who stopped and why.
  ///
  /// Rejects a retirement that names no reason. This is the one place the
  /// engines are deliberately stricter than they were: the whole point of the
  /// change is that the record distinguishes an injury from a walkover, and a
  /// reason that is optional is a reason that will be absent exactly when the
  /// match mattered.
  ScoringResult retireResult(
    Map<String, dynamic> state,
    ScoreAction action,
  ) {
    if (action.side == Side.neutral) {
      return const ScoringResult.rejected('Which side retired?');
    }
    final raw = action.payload['reason'] as String?;
    if (raw == null || raw.isEmpty) {
      return const ScoringResult.rejected(
        'A retirement needs a reason before it can be recorded.',
      );
    }
    final reason = RetireReason.fromWire(raw);
    return ScoringResult.ok(mutate(state, (s) {
      s['complete'] = true;
      s['draw'] = false;
      s['winner'] = action.side.opposite.wire;
      s[_kRetired] = action.side.wire;
      s[_kRetiredReason] = reason.wire;
    }));
  }

  /// Reopens a finished match for correction, clearing any retirement with it.
  ///
  /// Clearing the reason matters as much as clearing the flag: a match
  /// reopened and then played out would otherwise stay stamped "injury"
  /// forever, and the reason is what the standings and the disciplinary
  /// record read.
  ScoringResult reopenResult(Map<String, dynamic> state) =>
      ScoringResult.ok(mutate(state, (s) {
        s['complete'] = false;
        s['winner'] = null;
        s['draw'] = false;
        s.remove(_kRetired);
        s.remove(_kRetiredReason);
      }));

  /// The side that retired, or null if the match was played out.
  Side? retiredSide(Map<String, dynamic> state) {
    final w = state[_kRetired];
    return w is String ? Side.fromWire(w) : null;
  }

  RetireReason? retireReasonOf(Map<String, dynamic> state) {
    final w = state[_kRetiredReason];
    if (w is! String) {
      // A match retired before reasons were recorded still reads as retired;
      // it simply cannot say why.
      return retiredSide(state) == null ? null : RetireReason.unspecified;
    }
    return RetireReason.fromWire(w);
  }

  /// One line naming the retirement, for a status bar or a result list.
  /// Null when nobody retired.
  String? retirementLine(Map<String, dynamic> state, ScoringContext ctx) {
    final side = retiredSide(state);
    if (side == null) return null;
    final reason = retireReasonOf(state) ?? RetireReason.unspecified;
    final who = ctx.nameFor(side);
    return switch (reason) {
      RetireReason.walkover => '$who did not appear — walkover',
      RetireReason.disqualified => '$who disqualified',
      RetireReason.conceded => '$who conceded',
      RetireReason.unspecified => '$who retired',
      _ => '$who retired — ${reason.label.toLowerCase()}',
    };
  }

  /// The retirement buttons: one per side, each asking for the reason.
  ///
  /// One button rather than one per reason. A button per reason would put ten
  /// red chips on a pad whose tray comfortably holds about four, and would
  /// bury the two controls a scorer actually reaches for. The side is on the
  /// button — that is the half a scorer must not get wrong under pressure and
  /// the half a dropdown would obscure — and the reason, which nobody taps by
  /// accident, is asked in the dialog the pad already opens for players and
  /// numbers.
  List<ScoreControlGroup> retireControls(ScoringContext ctx) => [
        ScoreControlGroup(
          title: 'Retire',
          controls: [
            for (final side in [Side.a, Side.b])
              ScoreControl(
                action: retireAction,
                label: '${ctx.nameFor(side)} retires',
                side: side,
                style: ControlStyle.danger,
                tooltip: 'Awards the match to ${ctx.nameFor(side.opposite)}.',
                choices: [
                  ChoicePrompt(
                    key: 'reason',
                    label: 'Why is ${ctx.nameFor(side)} not continuing?',
                    options: [
                      for (final r in RetireReason.offered)
                        ChoiceOption(r.wire, r.label),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ];

  // --- Change of ends -----------------------------------------------------

  /// Whether the players are due to change ends right now, and what to call
  /// it. Answered by each engine from its own laws — see the class comment.
  ///
  /// Returning null means "nothing is due", which is the answer for the vast
  /// majority of the points in a match.
  EndsChange? endsChangeDue(Map<String, dynamic> state, ScoringContext ctx);

  /// True once the scorer has confirmed the swap that is currently due.
  bool endsAcknowledged(Map<String, dynamic> state, ScoringContext ctx) {
    final due = endsChangeDue(state, ctx);
    if (due == null) return true;
    return state[_kEndsAckAt] == due.id;
  }

  /// Records that the players have swapped ends.
  ///
  /// Stamps WHICH change was acknowledged rather than a bare boolean. A game
  /// to 21 with an interval at 11 and a deciding-game swap can raise two
  /// separate prompts, and a boolean cleared by the first one silently
  /// swallows the second.
  ScoringResult acknowledgeEndsResult(
    Map<String, dynamic> state,
    ScoringContext ctx,
  ) {
    final due = endsChangeDue(state, ctx);
    if (due == null) {
      return const ScoringResult.rejected(
        'No change of ends is due at this score.',
      );
    }
    return ScoringResult.ok(mutate(state, (s) {
      s[_kEndsAckAt] = due.id;
      s[_kEndsSwapped] = !(s[_kEndsSwapped] == true);
    }));
  }

  /// Which physical end each side currently occupies, as a flag the pad can
  /// use to mirror itself. False means the sides are as they started.
  bool endsSwapped(Map<String, dynamic> state) => state[_kEndsSwapped] == true;

  /// Clears only the acknowledgement, leaving the current ends alone.
  ///
  /// This is the tennis shape rather than the badminton one. Tennis does not
  /// swap ends after every game — it swaps after the odd ones — so the swap
  /// is derived from the score and all a set boundary has to do is let the
  /// next due change be raised. Toggling here instead would swap the ends on
  /// every single game.
  void clearEndsAcknowledgement(Map<String, dynamic> s) {
    s[_kEndsAckAt] = null;
  }

  /// Clears the end-change bookkeeping at a game boundary.
  ///
  /// Called by the engines from their own game-settling code. Ends change
  /// after every game in all four sports, so the swap flag is toggled here
  /// rather than being something the scorer has to confirm forty times a
  /// match — only the MID-game changes are worth a prompt.
  void resetEndsForNewGame(Map<String, dynamic> s) {
    s[_kEndsAckAt] = null;
    s[_kEndsSwapped] = !(s[_kEndsSwapped] == true);
  }

  /// The control that confirms a due change of ends, or an empty list.
  List<ScoreControlGroup> endsControls(
    Map<String, dynamic> state,
    ScoringContext ctx,
  ) {
    final due = endsChangeDue(state, ctx);
    if (due == null || endsAcknowledged(state, ctx)) return const [];
    return [
      ScoreControlGroup(
        title: due.label,
        controls: [
          ScoreControl(
            action: changeEndsAction,
            label: due.confirmLabel,
            style: ControlStyle.secondary,
            shortcut: 'e',
            tooltip: due.detail,
          ),
        ],
      ),
    ];
  }
}

/// A change of ends the laws require at this exact moment.
class EndsChange {
  const EndsChange({
    required this.id,
    required this.label,
    this.confirmLabel = 'Ends changed',
    this.detail,
  });

  /// Stable identity for this particular change within the match, so an
  /// acknowledgement cannot be mistaken for a later one. Engines build it
  /// from the game number and the trigger — 'g3@11'.
  final String id;

  /// What to call it on the pad: 'Change ends', 'Interval — change ends'.
  final String label;

  final String confirmLabel;

  /// Optional second line: 'Deciding game, at 11 points.'
  final String? detail;
}
