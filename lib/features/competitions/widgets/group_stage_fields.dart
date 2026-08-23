import 'package:flutter/material.dart';

import '../../../core/models/draw_config.dart';
import '../../../core/models/enums.dart';
import '../../../domain/draw/group_bounds.dart';

/// The group-stage half of a draw's setup, as one reusable block.
///
/// ## Why this had to leave [DrawSetupSheet]
///
/// The draw generator has always been able to split a field into groups, run
/// a round robin inside each, and cross-seed the top one or two of every
/// group into a knockout — and `DrawSetupSheet` was the only screen in the
/// product that could ask for it. That sheet opens at "Make the draw", on one
/// competition at a time.
///
/// A season does not go through it. `TournamentRepository.setUpWholeSeason`
/// draws fourteen events in a loop, each one with whatever [DrawConfig] its
/// competition document happens to carry — and every season-creation screen
/// wrote competitions without one. The default is `useGroups: false`, and the
/// default format a category is created with is Round Robin, so "Set up the
/// whole season" produced one flat table per event and no group stage
/// anywhere, however many teams turned up. The organizer had no screen on
/// which to say otherwise.
///
/// So the controls live here, and the screens that *create* a competition ask
/// the question at creation time — which is also when an organizer is
/// actually thinking about it. The bounds come from [GroupBounds], the same
/// rule the generator obeys, so no screen can promise a shape the draw will
/// not produce.
///
/// ## Planning against a field that does not exist yet
///
/// At season-creation time nobody has entered. [entrantCount] is then the
/// organizer's expected size (`maxEntrants`), and [DrawConfig.numGroups] is
/// recorded as a *request*: `GroupBounds.resolve` re-clamps it against the
/// real field when the draw is finally generated, so a season planned for 16
/// that draws 11 still gets a legal shape rather than a broken one.
class GroupStageFields extends StatelessWidget {
  const GroupStageFields({
    super.key,
    required this.format,
    required this.entrantCount,
    required this.config,
    required this.onChanged,
    this.showSummary = true,
  });

  /// The draw format the organizer has chosen. Decides whether groups are
  /// available at all, whether they are implied, and whether they feed a
  /// knockout.
  final CompetitionFormat format;

  /// Entrants to plan against — confirmed at draw time, expected at creation
  /// time. See the class doc.
  final int entrantCount;

  final DrawConfig config;
  final ValueChanged<DrawConfig> onChanged;

  /// The "4 groups of 4, 8 into the knockout stage" line. Suppressed on
  /// screens too tight to carry it.
  final bool showSummary;

  /// The four questions about a grouped draw, answered by [DrawConfig] so
  /// that this sheet and every screen that renders a group table are reading
  /// one rule rather than four copies of it.
  static bool supportsGroups(CompetitionFormat format) =>
      DrawConfig.formatSupportsGroups(format);

  static bool groupsImplied(CompetitionFormat format) =>
      DrawConfig.groupsImplied(format);

  static bool isGrouped(CompetitionFormat format, DrawConfig config) =>
      config.isGroupedUnder(format);

  static bool feedsKnockout(CompetitionFormat format, DrawConfig config) =>
      config.feedsKnockoutUnder(format);

  /// Qualifiers to bound group size against: a pool promotes nobody, so the
  /// only floor on a group there is what makes a group a group.
  static int _qualifierFloor(CompetitionFormat format, DrawConfig config) =>
      feedsKnockout(format, config) ? config.qualifiersPerGroup : 1;

  static int minGroups(int entrantCount) => GroupBounds.minGroups(entrantCount);

  static int maxGroups({
    required CompetitionFormat format,
    required int entrantCount,
    required DrawConfig config,
  }) =>
      GroupBounds.maxGroups(
        entrantCount,
        qualifiersPerGroup: _qualifierFloor(format, config),
      );

  /// The group count the generator will actually use — so a summary line
  /// cannot promise something different from what gets drawn.
  static int resolvedGroups({
    required CompetitionFormat format,
    required int entrantCount,
    required DrawConfig config,
  }) =>
      GroupBounds.resolve(
        entrants: entrantCount,
        requested: config.numGroups,
        qualifiersPerGroup: _qualifierFloor(format, config),
      );

  /// [config] with the group choices clamped to what this format and field
  /// allow, ready to be written onto a competition.
  ///
  /// Every screen that persists a [DrawConfig] runs it through this, so an
  /// out-of-range group count cannot reach Firestore and be silently
  /// re-decided by the generator months later.
  static DrawConfig normalize({
    required CompetitionFormat format,
    required int entrantCount,
    required DrawConfig config,
  }) {
    // Not a grouped draw. Any group count left over from a format the
    // organizer changed their mind about is inert — the generator only reads
    // it down a grouped branch — so it is left alone rather than cleared,
    // which also means switching back to Groups+Knockout restores the
    // numbers they had chosen.
    if (!isGrouped(format, config)) return config;
    return config.copyWith(
      numGroups: resolvedGroups(
        format: format,
        entrantCount: entrantCount,
        config: config,
      ),
    );
  }

  /// Plain-language description of the shape these settings produce.
  static String summary({
    required CompetitionFormat format,
    required int entrantCount,
    required DrawConfig config,
  }) {
    final groups = resolvedGroups(
      format: format,
      entrantCount: entrantCount,
      config: config,
    );
    final smallest = GroupBounds.smallestGroupSize(entrantCount, groups);
    final largest = GroupBounds.largestGroupSize(entrantCount, groups);
    // "About four" hid the uneven split that an organizer has to explain to
    // whoever drew the group of five.
    final size = smallest == largest ? '$smallest' : '$smallest–$largest';
    if (!feedsKnockout(format, config)) {
      return '$groups groups of $size, each playing its own table.';
    }
    final qualifiers = groups * config.qualifiersPerGroup;
    return '$groups groups of $size — everyone plays everyone in their own '
        'group, then the top ${config.qualifiersPerGroup} of each '
        '($qualifiers sides) go into the knockout.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!supportsGroups(format)) return const SizedBox.shrink();

    final grouped = isGrouped(format, config);
    final knockout = feedsKnockout(format, config);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!groupsImplied(format))
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Split into groups'),
            subtitle: Text(
              format == CompetitionFormat.knockout
                  ? 'A group stage first, with the top of each group going '
                      'through to the knockout.'
                  : 'Pools — everyone plays everyone in their own group '
                      'instead of one table of $entrantCount.',
            ),
            value: config.useGroups,
            onChanged: (v) => onChanged(
              normalize(
                format: format,
                entrantCount: entrantCount,
                config: config.copyWith(useGroups: v),
              ),
            ),
          ),
        if (grouped) ...[
          // The field the arithmetic is against, said before the stepper
          // rather than left for the organizer to remember. "Number of
          // groups: 4" means nothing without it, and it is the number they
          // are dividing.
          Text(
            'Splitting $entrantCount ${entrantCount == 1 ? 'entrant' : 'entrants'}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          CountStepper(
            label: 'Number of groups',
            // Bounded so the organizer cannot choose a group size the draw is
            // not allowed to have, rather than accepting the number and
            // quietly generating something else.
            value: resolvedGroups(
              format: format,
              entrantCount: entrantCount,
              config: config,
            ),
            min: minGroups(entrantCount),
            max: maxGroups(
              format: format,
              entrantCount: entrantCount,
              config: config,
            ),
            onChanged: (v) => onChanged(config.copyWith(numGroups: v)),
          ),
          if (knockout)
            CountStepper(
              label: 'Qualifiers from each group',
              value: config.qualifiersPerGroup,
              min: 1,
              max: 4,
              // Raising the qualifier count can shrink the maximum group
              // count below the chosen one, so the whole config is
              // re-normalized rather than left invalid until some later
              // rebuild notices.
              onChanged: (v) => onChanged(
                normalize(
                  format: format,
                  entrantCount: entrantCount,
                  config: config.copyWith(qualifiersPerGroup: v),
                ),
              ),
            ),
          if (showSummary)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                summary(
                  format: format,
                  entrantCount: entrantCount,
                  config: config,
                ),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ],
    );
  }
}

/// A bounded integer picker: label, minus, value, plus.
///
/// Public because three screens now set group counts and they must all
/// disable at the same edges — a stepper that lets one screen pick a number
/// another screen forbids is how the draw and the sheet describing it drift
/// apart.
class CountStepper extends StatelessWidget {
  const CountStepper({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed:
                value - step >= min ? () => onChanged(value - step) : null,
          ),
          SizedBox(
            width: 44,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed:
                value + step <= max ? () => onChanged(value + step) : null,
          ),
        ],
      ),
    );
  }
}
