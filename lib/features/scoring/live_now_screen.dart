import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/fixture.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/live_dot.dart';
import '../../shared/section_header.dart';
import '../home/home_providers.dart';
import 'widgets/live_score_card.dart';

/// Every match live right now, across every club this person belongs to.
///
/// The home screen shows a short preview of this same list and stops at
/// three so "Live now" does not push everything else on the dashboard off
/// the first screen — this is where "More" sends you when there is more
/// going on than that preview can show. Tapping any match here opens its
/// full scorecard, same as it does everywhere else in the product.
class LiveNowScreen extends ConsumerWidget {
  const LiveNowScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveAsync = ref.watch(myLiveFixturesProvider);
    final live = liveAsync.valueOrNull ?? const <Fixture>[];
    final clubmateLive =
        ref.watch(clubmateLiveFixturesProvider).valueOrNull ??
            const <Fixture>[];
    final liveFailures = ref.watch(myLiveFixtureFailuresProvider);

    return AppScaffold(
      title: 'Live now',
      subtitle: live.isEmpty && clubmateLive.isEmpty
          ? 'Nothing on right now'
          : '${live.length + clubmateLive.length} match'
              '${live.length + clubmateLive.length == 1 ? '' : 'es'} live',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          ContentBounds(
            maxWidth: 980,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                AsyncErrorStrip(value: liveAsync, what: 'live matches'),
                // A club whose read was refused no longer blanks the whole
                // screen — see myLiveFixturesPartialProvider — but it must
                // not vanish silently either.
                if (liveFailures > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: QuietCard(
                      icon: Icons.cloud_off_outlined,
                      title: liveFailures == 1
                          ? 'One club’s matches could not be loaded'
                          : '$liveFailures clubs’ matches could not be loaded',
                      message: 'Everything below is up to date. If this '
                          'keeps happening, please report it.',
                    ),
                  ),
                if (live.isEmpty && clubmateLive.isEmpty && liveFailures == 0)
                  const QuietCard(
                    icon: Icons.sensors_off_outlined,
                    title: 'Nothing is being played right now',
                    message: 'The moment a scorer starts a match at any of '
                        'your clubs it appears here, live, for everyone.',
                  ),
                if (live.isNotEmpty) ...[
                  const SectionHeader(
                    icon: Icons.sensors,
                    title: 'Your clubs',
                    subtitle: 'Ball by ball, from every club you are in',
                    trailing: LiveDot(),
                  ),
                  for (final f in live)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _LiveFixtureWithClub(fixture: f),
                    ),
                ],
                if (clubmateLive.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const SectionHeader(
                    icon: Icons.groups_2_outlined,
                    title: 'Your clubmates, elsewhere',
                    subtitle: 'Playing for other clubs and teams right now',
                    trailing: LiveDot(),
                  ),
                  for (final f in clubmateLive)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _LiveFixtureWithClub(fixture: f),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A live match with the club it belongs to named above it — the piece the
/// shared, single-club screens can leave out and this cross-club one cannot.
class _LiveFixtureWithClub extends ConsumerWidget {
  const _LiveFixtureWithClub({required this.fixture});

  final Fixture fixture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final org = ref.watch(organizationProvider(fixture.orgId)).valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (org != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(org.name, style: Theme.of(context).textTheme.labelSmall),
          ),
        LiveScoreCard(
          fixture: fixture,
          onTap: () => context.push(
            Routes.watch(fixture.orgId, fixture.compId, fixture.id),
          ),
        ),
      ],
    );
  }
}
