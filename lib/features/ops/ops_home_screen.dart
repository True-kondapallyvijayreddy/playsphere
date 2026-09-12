/// The control room — where everything the product collects from the outside
/// world actually arrives.
///
/// ## The problem this screen exists to fix
///
/// PlaySphere had four inbound queues and no inbox. An advertiser submitted a
/// campaign, a donor handed over a bag of kit, a club raised a shortfall, a
/// ground owner claimed a listing — and every one of those landed in a
/// Firestore document in a `pending`/`submitted`/`unverified` state that
/// nothing inside the app could see or move. `firestore.rules` had allowed the
/// staff writes since the day each feature shipped; what was missing was
/// somewhere for a human to stand.
///
/// So the honest answer to "who receives this?" was, until now, "nobody, until
/// somebody opens the Firebase console and remembers to look". This screen and
/// the queues it links to are that answer made real, and
/// `functions/index.js`'s staff triggers are what stop it depending on
/// somebody remembering.
///
/// ## Why the counts are on the hub and not only inside each queue
///
/// One person runs all four of these, and the scarce thing is not their
/// ability to act, it is knowing which queue is on fire this morning. A hub
/// that makes you open three screens to discover two of them were empty has
/// spent the attention the queues needed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui_kit.dart';

class OpsHomeScreen extends ConsumerWidget {
  const OpsHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isPlatformAdminProvider);

    return AppScaffold(
      title: 'Operations',
      subtitle: 'Everything waiting on a decision',
      body: isAdmin.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => AsyncErrorStrip(value: isAdmin, what: 'your access'),
        data: (admin) => admin
            ? const _Console()
            : const EmptyState(
                icon: Icons.lock_outline,
                title: 'PlaySphere staff only',
                message:
                    'This is where advertising, donations, needs and ground '
                    'listings are reviewed.',
              ),
      ),
    );
  }
}

class _Console extends ConsumerWidget {
  const _Console();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pendingAds = ref.watch(pendingAdCountProvider);
    final give = ref.watch(giveOpsBacklogProvider);
    final roster = ref.watch(staffRosterProvider).valueOrNull ?? const [];
    final me = ref.watch(myStaffMembershipProvider).valueOrNull;

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        ContentBounds(
          maxWidth: 760,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The prompt that makes the notification wiring real. Somebody
              // holding the claim but absent from the roster is exactly the
              // state a fresh deployment starts in, and the consequence —
              // every staff notification in the product going to an empty
              // recipient list — is invisible unless it is said out loud.
              if (me == null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: Card(
                    color: theme.colorScheme.tertiaryContainer,
                    child: ListTile(
                      leading: Icon(Icons.notifications_off_outlined,
                          color: theme.colorScheme.onTertiaryContainer),
                      title: const Text(
                        'You are not on the notification roster',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text(
                        'Nothing that lands on these queues will reach your '
                        'phone until somebody is on the team list.',
                      ),
                      trailing: FilledButton(
                        onPressed: () => context.push(Routes.opsTeam),
                        child: const Text('Fix'),
                      ),
                    ),
                  ),
                ),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Waiting on you',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              _QueueTile(
                icon: Icons.ads_click_outlined,
                tint: const Color(0xFF7C3AED),
                title: 'Advertising requests',
                subtitle: 'Campaigns advertisers have submitted for approval',
                count: pendingAds,
                onTap: () => context.push(Routes.opsAds),
              ),
              _QueueTile(
                icon: Icons.volunteer_activism_outlined,
                tint: const Color(0xFFEA580C),
                title: 'Give — new donations',
                subtitle: 'Kit and money pledged, not yet collected',
                count: give.newDonations,
                onTap: () => context.push(Routes.opsGive),
              ),
              _QueueTile(
                icon: Icons.fact_check_outlined,
                tint: const Color(0xFF0891B2),
                title: 'Give — needs to verify',
                subtitle: 'Shortfalls raised by clubs, invisible until checked',
                count: give.unverifiedNeeds,
                onTap: () => context.push(Routes.opsGiveNeeds),
              ),
              _QueueTile(
                icon: Icons.stadium_outlined,
                tint: const Color(0xFF16A34A),
                title: 'Ground listings',
                subtitle: 'Claims, verifications and reports',
                // Deliberately no count: the ground queue sorts by risk, not
                // by arrival, and a number here would invite triage by
                // volume — the exact ordering `GroundReviewScreen`'s doc
                // explains it is built to avoid.
                count: null,
                onTap: () => context.push(Routes.groundReview),
              ),

              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  'The team',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              _QueueTile(
                icon: Icons.groups_outlined,
                tint: const Color(0xFF2563EB),
                title: 'Who gets told',
                subtitle: roster.isEmpty
                    ? 'Nobody yet — add yourself and your team'
                    : '${roster.length} '
                        'member${roster.length == 1 ? '' : 's'} on the roster',
                count: null,
                onTap: () => context.push(Routes.opsTeam),
              ),
              _QueueTile(
                icon: Icons.query_stats_outlined,
                tint: const Color(0xFF475569),
                title: 'Government dashboard',
                subtitle: 'District-level participation aggregates',
                count: null,
                onTap: () => context.push(Routes.govDashboard),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: Text(
                  'Approving, verifying and advancing anything here is written '
                  'straight to the record everybody else reads. There is no '
                  'second review behind you.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.hintColor),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
    required this.count,
    required this.onTap,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String subtitle;

  /// Null draws no badge at all, which is different from `0` — zero means
  /// "checked, and empty", null means "this queue is not counted".
  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = count;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: tint.withValues(alpha: 0.14),
          child: Icon(icon, color: tint),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (n != null && n > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Ps.live,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$n',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              )
            else if (n == 0)
              Text('Clear',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.hintColor)),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
