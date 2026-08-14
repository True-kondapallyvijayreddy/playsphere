import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/router/app_router.dart';
import '../../domain/event_type.dart';
import '../../shared/app_scaffold.dart';

/// Step one of creating anything: what kind of event is this?
///
/// Feature #8. Before this, "New event" opened directly onto the
/// single-sport competition form, so a school running a multi-sport season
/// had to create each sport as an unrelated event, a single match was asked
/// for a registration limit and a waitlist it would never use, and a
/// challenge had no route through this screen at all.
///
/// The screen deliberately shows all four with a sentence each rather than a
/// dropdown. The choice decides the shape of everything that follows and
/// cannot be changed afterwards, so it is worth a screen.
class ChooseEventTypeScreen extends ConsumerWidget {
  const ChooseEventTypeScreen({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return AppScaffold(
      orgId: orgId,
      title: 'New event',
      subtitle: 'What are you setting up?',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ContentBounds(
            maxWidth: 640,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Text(
                  'Each type asks for different things, so pick this first '
                  'and you will only be asked what actually applies.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                for (final type in EventType.values)
                  _TypeCard(
                    type: type,
                    onTap: () => _open(context, type),
                    // The one-page form, kept one tap away rather than
                    // replaced. An organizer setting up eight events for a
                    // sports day should not walk six steps eight times — see
                    // `CreateCompetitionScreen`'s own doc comment. The guided
                    // flow is the default because most people create one
                    // tournament, not eight.
                    secondaryLabel: switch (type) {
                      EventType.tournament ||
                      EventType.season =>
                        'Quick create',
                      _ => null,
                    },
                    onSecondary: switch (type) {
                      EventType.tournament => () => context.push(
                            Routes.createTournamentEvent(orgId),
                          ),
                      // The one-page season form does something the guided
                      // flow deliberately does not: the same sport twice
                      // under different age bands, which a school sports week
                      // genuinely needs. So this is not merely a shortcut —
                      // it is the only route to that.
                      EventType.season => () => context.push(
                            Routes.createSeason(orgId),
                          ),
                      _ => null,
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Hands over to the flow that fits the chosen type.
  ///
  /// `push`, not `pushReplacement`: the type is a real decision and backing
  /// out of the next screen should return here to change it, not to whatever
  /// the organizer was doing before.
  void _open(BuildContext context, EventType type) {
    switch (type) {
      case EventType.season:
        context.push(Routes.createSeasonGuided(orgId));
      case EventType.tournament:
        context.push(Routes.createTournamentGuided(orgId));
      case EventType.singleMatch:
        // The quick-match screen writes the competition and its one fixture
        // together — a single match created through the ordinary event form
        // would leave an event with no fixture, which cannot be played.
        context.push(Routes.quickMatch(orgId));
      case EventType.challenge:
        context.push(Routes.challenges(orgId));
    }
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.type,
    required this.onTap,
    this.secondaryLabel,
    this.onSecondary,
  });

  final EventType type;
  final VoidCallback onTap;

  /// An alternative route into the same event type, shown as a text button
  /// under the description. Absent for types that have only one.
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(type.icon, size: 28, color: theme.colorScheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(type.label, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      type.tagline,
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: theme.colorScheme.primary),
                    ),
                    const SizedBox(height: 8),
                    Text(type.description, style: theme.textTheme.bodySmall),
                    if (secondaryLabel != null && onSecondary != null) ...[
                      const SizedBox(height: 4),
                      // Aligned left under the description and visually
                      // quieter than the card itself: it is the shortcut for
                      // somebody who already knows what they want, not a
                      // choice a first-time organizer has to weigh.
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: onSecondary,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(secondaryLabel!),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.hintColor),
            ],
          ),
        ),
      ),
    );
  }
}
