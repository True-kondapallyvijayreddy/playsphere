import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/errors/app_exception.dart';
import '../core/layout/responsive.dart';
import '../core/permissions/capability.dart';
import '../core/providers.dart';
import '../core/router/app_router.dart';

/// Width of the extended navigation rail.
///
/// Shared between the rail itself and its leading widget so the two cannot
/// drift apart — the leading slot needs a definite width to lay out at all.
const double _railExtendedWidth = 208;

/// One navigation destination, filtered by capability.
class NavItem {
  const NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.path,
    this.requires,
    this.badgeCount,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String path;

  /// Shown as a count on the icon. Null or zero renders nothing.
  ///
  /// Exists for the challenge inbox: an incoming challenge is the one thing in
  /// this product that expires if nobody looks at it, and a club that never
  /// notices an invitation reads to the other club as a club that refused.
  final int? badgeCount;

  /// Absent means everyone sees it. Present means it is hidden entirely
  /// unless the caller holds the capability — hidden, not disabled, so a
  /// scorer's navigation genuinely contains only what a scorer does.
  final Capability? requires;
}

/// The application shell.
///
/// Renders a drawer on phones, a navigation rail on tablets and a permanent
/// sidebar on laptops, from one declaration. Screens never think about which
/// they are getting, which is what keeps Android, iOS and web the same
/// product rather than three that slowly diverge.
class AppScaffold extends ConsumerWidget {
  const AppScaffold({
    super.key,
    required this.orgId,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.subtitle,
  });

  final String orgId;
  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(myCapabilitiesProvider(orgId));
    final org = ref.watch(organizationProvider(orgId)).valueOrNull;
    final window = context.windowSize;

    final items = <NavItem>[
      NavItem(
        icon: Icons.home_outlined,
        selectedIcon: Icons.home,
        label: 'Home',
        path: Routes.org(orgId),
      ),
      NavItem(
        icon: Icons.sensors_outlined,
        selectedIcon: Icons.sensors,
        label: 'Live now',
        path: Routes.live(orgId),
      ),
      NavItem(
        icon: Icons.sports_kabaddi_outlined,
        selectedIcon: Icons.sports_kabaddi,
        label: 'Challenges',
        path: Routes.challenges(orgId),
        // Any member can watch who their club is playing; only an event
        // manager sees the accept/decline controls on the screen itself.
        badgeCount: ref.watch(incomingChallengesProvider(orgId)).valueOrNull
            ?.length,
      ),
      NavItem(
        icon: Icons.groups_outlined,
        selectedIcon: Icons.groups,
        label: 'Members',
        path: Routes.members(orgId),
        requires: Capability.manageMembers,
      ),
      const NavItem(
        icon: Icons.menu_book_outlined,
        selectedIcon: Icons.menu_book,
        label: 'Rules',
        path: Routes.rules,
      ),
    ].where((i) => i.requires == null || caps.contains(i.requires)).toList();

    final currentPath = GoRouterState.of(context).uri.path;
    var selected = items.indexWhere((i) => i.path == currentPath);
    if (selected < 0) selected = 0;

    void go(int index) => context.go(items[index].path);

    final appBar = AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, overflow: TextOverflow.ellipsis),
          if (subtitle != null || org != null)
            Text(
              subtitle ?? org!.name,
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      actions: [
        ...?actions,
        IconButton(
          icon: const Icon(Icons.menu_book_outlined),
          tooltip: 'Official Rules (ICC, FIFA, FIBA, PKL)',
          onPressed: () => context.push(Routes.rules),
        ),
        const _AccountButton(),
        const SizedBox(width: 8),
      ],
    );

    if (window.isCompact) {
      return Scaffold(
        appBar: appBar,
        body: body,
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: items.length < 2
            ? null
            : NavigationBar(
                selectedIndex: selected,
                onDestinationSelected: go,
                destinations: [
                  for (final i in items)
                    NavigationDestination(
                      icon: _NavIcon(item: i, icon: i.icon),
                      selectedIcon: _NavIcon(item: i, icon: i.selectedIcon),
                      label: i.label,
                    ),
                ],
              ),
      );
    }

    return Scaffold(
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selected,
            onDestinationSelected: go,
            // A laptop has the room to label things; a tablet does not.
            extended: window.isExpanded,
            minExtendedWidth: _railExtendedWidth,
            labelType: window.isExpanded
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            leading: window.isExpanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    // The explicit width is load-bearing, not cosmetic. A Row
                    // lays out its non-flex children with an UNBOUNDED main
                    // axis constraint, so the rail — and everything in its
                    // leading slot — is measured unbounded. An Expanded under
                    // an unbounded width throws in performLayout, which takes
                    // out the whole render tree and renders as a blank page.
                    // Giving the Row a definite width restores a bounded
                    // constraint, so Expanded is legal and the name can
                    // ellipsize instead of overflowing.
                    child: SizedBox(
                      width: _railExtendedWidth - 24, // minus the padding above
                      child: Row(
                        children: [
                          const Icon(Icons.sports_score, size: 22),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              org?.name ?? 'PlaySphere',
                              style: Theme.of(context).textTheme.titleSmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : null,
            destinations: [
              for (final i in items)
                NavigationRailDestination(
                  icon: _NavIcon(item: i, icon: i.icon),
                  selectedIcon: _NavIcon(item: i, icon: i.selectedIcon),
                  label: Text(i.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _AccountButton extends ConsumerWidget {
  const _AccountButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;

    return PopupMenuButton<String>(
      tooltip: 'Account',
      icon: CircleAvatar(
        radius: 15,
        backgroundImage:
            user?.photoUrl != null ? NetworkImage(user!.photoUrl!) : null,
        child: user?.photoUrl == null
            ? Text(
                (user?.displayName ?? '?').characters.first.toUpperCase(),
                style: const TextStyle(fontSize: 13),
              )
            : null,
      ),
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(user?.displayName ?? 'Signed in'),
            subtitle: Text(user?.email ?? ''),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'profile',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.person_outline),
            title: Text('My career profile'),
          ),
        ),
        const PopupMenuItem(
          value: 'switch',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.swap_horiz),
            title: Text('Switch organization'),
          ),
        ),
        const PopupMenuItem(
          value: 'signout',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout),
            title: Text('Sign out'),
          ),
        ),
      ],
      onSelected: (value) async {
        if (value == 'profile') {
          context.push(Routes.myProfile);
        } else if (value == 'switch') {
          context.go(Routes.orgs);
        } else if (value == 'signout') {
          await ref.read(authServiceProvider).signOut();
        }
      },
    );
  }
}

/// A navigation icon that carries [NavItem.badgeCount] when there is one.
///
/// Also supplies the `semanticLabel` the count needs: a bare red dot conveys
/// nothing to a screen reader, and the number is the entire point.
class _NavIcon extends StatelessWidget {
  const _NavIcon({required this.item, required this.icon});

  final NavItem item;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final count = item.badgeCount ?? 0;
    if (count <= 0) return Icon(icon);
    return Badge.count(
      count: count,
      child: Icon(
        icon,
        semanticLabel: '${item.label}, $count waiting',
      ),
    );
  }
}

/// Consistent empty state, so "nothing here yet" always tells the user what
/// to do next rather than leaving a blank panel.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 44, color: Theme.of(context).hintColor),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(
                  message!,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: 20),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders an [AsyncValue] with a real error message rather than a spinner
/// that never resolves — the failure mode users actually hit.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: builder,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => EmptyState(
        icon: Icons.error_outline,
        title: 'Could not load this',
        message: errorMessage(error),
        action: onRetry == null
            ? null
            : FilledButton.tonal(
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
      ),
    );
  }
}

/// A compact inline failure notice for a *secondary* stream on a screen that
/// already has a primary [AsyncView].
///
/// Screens here composed several streams and defaulted the side ones to
/// `?? const []`, which meant a rejected read removed a whole section — the
/// live-matches strip, the pending-approvals prompt — with no trace. An absent
/// section is indistinguishable from "nothing is happening", so an organizer
/// could not tell a quiet ground from a broken query.
///
/// Renders nothing when [value] has not failed, so it is safe to place
/// unconditionally above any section it guards.
class AsyncErrorStrip extends StatelessWidget {
  const AsyncErrorStrip({super.key, required this.value, required this.what});

  final AsyncValue<Object?> value;

  /// What could not be loaded, lowercase, e.g. `'live matches'`. Named so the
  /// notice says which section is missing rather than a generic apology.
  final String what;

  @override
  Widget build(BuildContext context) {
    if (!value.hasError) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        color: scheme.errorContainer,
        child: ListTile(
          dense: true,
          leading: Icon(Icons.cloud_off, color: scheme.onErrorContainer),
          title: Text(
            'Could not load $what',
            style: TextStyle(color: scheme.onErrorContainer),
          ),
          subtitle: Text(
            errorMessage(value.error!),
            style: TextStyle(color: scheme.onErrorContainer),
          ),
        ),
      ),
    );
  }
}

/// The sentence to show a user for any failure.
///
/// [AppException] exists precisely so this is a field access rather than
/// string surgery. The previous implementation split `toString()` on ': ',
/// which meant a raw FirebaseException — anything reaching the UI without
/// passing through `guard`, such as a rules rejection on a direct write —
/// was rendered to the user as
/// "[cloud_firestore/permission-denied] The caller does not have permission",
/// the exact leak the class was introduced to prevent.
String errorMessage(Object error) {
  if (error is AppException) return error.message;
  // Anything else is a bug rather than a condition we modelled, so the user
  // gets a sentence they can act on and the detail goes to the log.
  debugPrint('[PlaySphere] unmapped error surfaced to UI: $error');
  return 'Something went wrong. Please try again.';
}

/// Shows a failure to the user without ever leaking internals.
void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(errorMessage(error))));
}
