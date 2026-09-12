import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/coach.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui_kit.dart';

/// One coach's page — everything they have said about themselves, and the
/// two things they did not say.
///
/// The two are the point of the screen. A directory of self-declared coaches
/// is only safe to publish if it is honest about what it has and has not
/// checked, so this page states in words what the verified badge means and
/// what it does not, and it links to the coach's own playing record so a
/// claim about a career can be read against the matches behind it.
class CoachDetailScreen extends ConsumerWidget {
  const CoachDetailScreen({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coach = ref.watch(coachProvider(uid));
    final isMe = ref.watch(authUidProvider) == uid;

    return AsyncView(
      value: coach,
      onRetry: () => ref.invalidate(coachProvider(uid)),
      builder: (c) {
        if (c == null) {
          return const AppScaffold(
            title: 'Coach',
            body: EmptyState(
              icon: Icons.person_off_outlined,
              title: 'No listing here',
              message: 'This coach has not published a profile.',
            ),
          );
        }
        return AppScaffold(
          title: c.displayName,
          subtitle: c.city.isEmpty ? 'Coach' : c.city,
          actions: isMe
              ? [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Edit listing',
                    onPressed: () => context.push(Routes.myCoachProfile),
                  ),
                ]
              : null,
          body: ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              ContentBounds(
                maxWidth: 700,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // A delisted profile is still reachable by anybody
                      // holding the link, so it has to say so at the top
                      // rather than read as a live listing.
                      if (!c.isActive)
                        const _Notice(
                          icon: Icons.visibility_off_outlined,
                          text: 'This listing is switched off and does not '
                              'appear in searches.',
                        ),

                      if (c.headline?.isNotEmpty == true) ...[
                        Text(
                          c.headline!,
                          style: const TextStyle(
                            fontSize: 17,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                            color: Ps.ink,
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],

                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final id in c.sportIds)
                            Chip(
                              label: Text(SportCatalog.byId(id).name),
                              onDeleted: null,
                            ),
                          if (c.isVerified)
                            const Chip(
                              avatar: Icon(Icons.verified, size: 16),
                              label: Text('Verified'),
                            ),
                          Chip(
                            label: Text(
                              c.acceptingStudents
                                  ? 'Taking students'
                                  : 'Not taking students',
                            ),
                          ),
                          Chip(label: Text(c.rateLabel)),
                          if (c.yearsExperience > 0)
                            Chip(
                              label: Text('${c.yearsExperience} years coaching'),
                            ),
                        ],
                      ),

                      if (c.bio?.isNotEmpty == true) ...[
                        const SizedBox(height: 18),
                        Text(
                          c.bio!,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: Ps.ink,
                          ),
                        ),
                      ],

                      _Facts(coach: c),

                      const SizedBox(height: 18),
                      // The player record behind the coaching claim. A coach
                      // who says they played Ranji has a career profile that
                      // either shows matches or does not, and letting a
                      // parent look is worth more than any badge.
                      Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: const Icon(Icons.badge_outlined),
                          title: const Text('Playing record'),
                          subtitle: const Text(
                            'Their own career profile on PlaySphere',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push(Routes.profile(c.uid)),
                        ),
                      ),

                      if (c.contactPhone?.isNotEmpty == true) ...[
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                          ),
                          onPressed: () => launchUrl(
                            Uri(scheme: 'tel', path: c.contactPhone),
                          ),
                          icon: const Icon(Icons.call_outlined),
                          label: Text('Call ${c.displayName.split(' ').first}'),
                        ),
                      ],

                      const SizedBox(height: 22),
                      _Notice(
                        icon: Icons.info_outline,
                        text: c.isVerified
                            ? 'PlaySphere has checked this coach’s '
                                'identity and at least one credential. It is '
                                'not a background check, and it is not a '
                                'recommendation — meet at a public '
                                'ground and speak to their current students.'
                            : 'Everything on this page was written by the '
                                'coach and has not been checked by '
                                'PlaySphere. Meet at a public ground, and '
                                'speak to their current students before '
                                'committing.',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The list-shaped claims: who they take, how they teach, what they hold.
class _Facts extends StatelessWidget {
  const _Facts({required this.coach});

  final CoachProfile coach;

  @override
  Widget build(BuildContext context) {
    final rows = <(IconData, String, List<String>)>[
      (Icons.groups_outlined, 'Coaches', coach.ageGroups),
      (Icons.schedule_outlined, 'Sessions', coach.formats),
      (Icons.workspace_premium_outlined, 'Certifications', coach.certifications),
      (
        Icons.place_outlined,
        'Based in',
        [
          if (coach.city.isNotEmpty) coach.city,
          if (coach.district?.isNotEmpty == true) coach.district!,
        ],
      ),
    ];

    final shown = [for (final r in rows) if (r.$3.isNotEmpty) r];
    if (shown.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        Container(
          decoration: BoxDecoration(
            color: Ps.surface,
            borderRadius: BorderRadius.circular(Ps.radius),
            border: Border.all(color: Ps.border),
          ),
          child: Column(
            children: [
              for (final (icon, label, values) in shown)
                ListTile(
                  dense: true,
                  leading: Icon(icon, size: 19, color: Ps.muted),
                  title: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: Ps.faint,
                    ),
                  ),
                  subtitle: Text(
                    values.join('  ·  '),
                    style: const TextStyle(fontSize: 13.5, color: Ps.ink),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Ps.canvas,
        borderRadius: BorderRadius.circular(Ps.radiusSm),
        border: Border.all(color: Ps.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Ps.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: Ps.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
