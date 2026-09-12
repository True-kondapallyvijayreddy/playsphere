import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/router/app_router.dart';
import '../../domain/event_type.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui_kit.dart';

/// Step one of creating anything: what kind of event is this?
///
/// Feature #8. Before this, "New event" opened directly onto the
/// single-sport competition form, so a school running a multi-sport season
/// had to create each sport as an unrelated event, a single match was asked
/// for a registration limit and a waitlist it would never use, and a
/// challenge had no route through this screen at all.
///
/// All four are shown at once rather than behind a dropdown: the choice
/// decides the shape of everything that follows and cannot be changed
/// afterwards, so it is worth a screen. What it is NOT worth is a paragraph
/// each — the screen used to open with a sentence about how to use it and
/// then give every type three more, which is four hundred words in front of a
/// decision an organizer makes in a second and has usually already made
/// before opening the app.
class ChooseEventTypeScreen extends ConsumerWidget {
  const ChooseEventTypeScreen({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppScaffold(
      orgId: orgId,
      title: 'New event',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          ContentBounds(
            maxWidth: 640,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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

  /// An alternative route into the same event type. Rendered as a small
  /// trailing button rather than a line of its own, so the shortcut for
  /// somebody who already knows what they want costs the row no height.
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final secondary = onSecondary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PsCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Ps.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(Ps.radiusSm),
              ),
              child: Icon(type.icon, size: 20, color: Ps.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    type.label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Ps.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // The tagline stays and the paragraph goes. "Several
                  // sports, one calendar" is the distinction between the four
                  // types; the paragraph underneath it was restating that at
                  // length and then listing what the next screen will ask,
                  // which the next screen is about to do anyway.
                  Text(
                    type.tagline,
                    style: const TextStyle(fontSize: 12.5, color: Ps.muted),
                  ),
                ],
              ),
            ),
            if (secondaryLabel != null && secondary != null)
              Tooltip(
                message: secondaryLabel!,
                child: IconButton(
                  tooltip: 'Quick actions',
                  onPressed: secondary,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.bolt_outlined, size: 20),
                  color: Ps.primary,
                ),
              ),
            const Icon(Icons.chevron_right, size: 18, color: Ps.faint),
          ],
        ),
      ),
    );
  }
}
