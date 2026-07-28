import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/layout/responsive.dart';
import '../core/permissions/capability.dart';
import '../core/providers.dart';
import '../core/router/app_router.dart';

/// One navigation destination, filtered by capability.
class NavItem {
  const NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.path,
    this.requires,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String path;

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
        icon: Icons.groups_outlined,
        selectedIcon: Icons.groups,
        label: 'Members',
        path: Routes.members(orgId),
        requires: Capability.manageMembers,
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
                      icon: Icon(i.icon),
                      selectedIcon: Icon(i.selectedIcon),
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
            minExtendedWidth: 208,
            labelType: window.isExpanded
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            leading: window.isExpanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
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
                  )
                : null,
            destinations: [
              for (final i in items)
                NavigationRailDestination(
                  icon: Icon(i.icon),
                  selectedIcon: Icon(i.selectedIcon),
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
        if (value == 'switch') {
          context.go(Routes.orgs);
        } else if (value == 'signout') {
          await ref.read(authServiceProvider).signOut();
        }
      },
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
        message: error.toString(),
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

/// Shows an [AppException]'s message, or a generic fallback for anything
/// unexpected, without ever leaking a stack trace to a user.
void showError(BuildContext context, Object error) {
  final message = error is Exception && error.toString().contains(': ')
      ? error.toString().split(': ').skip(1).join(': ')
      : 'Something went wrong. Please try again.';
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
