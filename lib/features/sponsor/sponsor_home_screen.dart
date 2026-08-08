import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../shared/app_scaffold.dart';

/// Sponsor an Athlete / Sponsor a Team — the front door.
///
/// A hub, not a feed, same posture as [GiveHomeScreen]: it exists to route a
/// visitor to exactly one of "find someone to back", "see who I'm already
/// backing" or "publish a listing of my own", never to render the listings
/// itself. See `SponsorshipListing`'s class doc for how this differs from
/// Give — this is a named, ongoing, credited relationship, not an anonymous
/// one-off donation.
class SponsorHomeScreen extends ConsumerWidget {
  const SponsorHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final myPledges = ref.watch(myPledgesProvider).valueOrNull ?? const [];
    final myListings =
        ref.watch(mySponsorshipListingsProvider).valueOrNull ?? const [];

    return AppScaffold(
      title: 'Sponsor',
      subtitle: 'Back a rising athlete or team, directly.',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ContentBounds(
            maxWidth: 900,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    'A village team on a 27-match winning streak, or a state '
                    'U-16 champion who trains without a coach — talent like '
                    'this rarely lacks talent. Sponsor them directly, and get '
                    'credited for it.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.hintColor),
                  ),
                ),
                const SizedBox(height: 12),
                _SponsorTile(
                  icon: Icons.travel_explore_outlined,
                  title: 'Find someone to sponsor',
                  subtitle: 'Browse athletes and teams looking for backing',
                  onTap: () => context.push(Routes.sponsorBrowse),
                ),
                if (myPledges.isNotEmpty)
                  _SponsorTile(
                    icon: Icons.volunteer_activism_outlined,
                    title: 'My sponsorships',
                    subtitle:
                        '${myPledges.length} offer${myPledges.length == 1 ? '' : 's'} made',
                    onTap: () => context.push(Routes.sponsorMyPledges),
                  ),
                _SponsorTile(
                  icon: Icons.campaign_outlined,
                  title: myListings.isEmpty ? 'Publish a listing' : 'My listings',
                  subtitle: myListings.isEmpty
                      ? 'For yourself, or for your team'
                      : '${myListings.length} listing${myListings.length == 1 ? '' : 's'} published',
                  onTap: () => context.push(
                    myListings.isEmpty ? Routes.sponsorCreate : Routes.sponsorMine,
                  ),
                ),
                const SizedBox(height: 20),
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('How this stays private',
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Text(
                          'A listing never shows a phone number, an exact '
                          'address, or a birth date. A sponsor\'s offer goes '
                          'through PlaySphere, and the listing owner decides '
                          'whether to accept — nothing is shared until they do.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SponsorTile extends StatelessWidget {
  const _SponsorTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
