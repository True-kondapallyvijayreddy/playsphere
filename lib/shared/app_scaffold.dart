import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/errors/app_exception.dart';
import '../core/layout/responsive.dart';
import '../core/permissions/capability.dart';
import '../core/providers.dart';
import '../core/router/app_router.dart';
import '../features/home/home_providers.dart';
import 'account_button.dart';
import 'identity.dart';
import 'module_drawer.dart';
import 'playsphere_logo.dart';

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
/// Every signed-in screen wears the same three things: the PlaySphere mark at
/// the top left, the module menu — the "three lines" — behind it, and the
/// account button at the top right. Underneath that it renders a bottom bar on
/// phones, a navigation rail on tablets and an extended rail on laptops, from
/// one declaration. Screens never think about which they are getting, which is
/// what keeps Android, iOS and web the same product rather than three that
/// slowly diverge.
class AppScaffold extends ConsumerWidget {
  const AppScaffold({
    super.key,
    this.orgId,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.subtitle,
  });

  /// The club this screen belongs to, or null on the screens that belong to
  /// the person rather than to any one club — home, and the profile. The
  /// module menu falls back to their most recent club for org-scoped links.
  final String? orgId;

  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orgId = this.orgId;
    final caps = orgId == null
        ? const <Capability>{}
        : ref.watch(myCapabilitiesProvider(orgId));
    final org =
        orgId == null ? null : ref.watch(organizationProvider(orgId)).valueOrNull;
    final window = context.windowSize;

    // See profileOrgMirrorProvider: keeps this user's club mirror current so
    // `profileVisibility: community` can actually be honoured. Mounted on the
    // shell so it runs on every in-app screen, not only the landing one.
    ref.watch(profileOrgMirrorProvider);

    // Backfills this account's PSOS code if it predates codes existing. Same
    // placement and same reasoning as the mirror above.
    ref.watch(playerCodeProvider);

    // Registers this device for push. Mounted here for the same reason: a
    // token has to be registered on a cold start where the session was
    // restored and no sign-in ever happened, not only at the moment somebody
    // taps Sign in.
    ref.watch(pushRegistrationProvider);

    final items = (orgId == null
            ? _globalItems(ref)
            : _clubItems(ref, orgId))
        .where((i) => i.requires == null || caps.contains(i.requires))
        .toList();

    final currentPath = GoRouterState.of(context).uri.path;
    var selected = items.indexWhere((i) => i.path == currentPath);
    if (selected < 0) selected = 0;

    // Neither `go` nor a plain `push`.
    //
    // `go` was the bug: it rebuilds the whole stack from the target path, so
    // a person who reached a club from home was left with a history one entry
    // deep and a back press that closed the app.
    //
    // A plain `push` is the opposite mistake — tapping between two
    // destinations six times leaves six screens to walk back through.
    //
    // So: leaving the section's own root pushes, which makes "back" return to
    // the club rather than skipping it; moving between two non-root siblings
    // replaces the top. The stack stays at most one deeper than where the
    // person started, and every back press undoes exactly one thing.
    void go(int index) {
      final target = items[index].path;
      if (target == currentPath) return;
      if (currentPath == items.first.path) {
        context.push(target);
      } else {
        context.replace(target);
      }
    }

    // A screen that was pushed needs a way back that is not the system
    // button. Scaffold will not offer one here: it renders the hamburger
    // whenever a drawer is present and never looks at whether the route can
    // pop, so every inner screen in this app showed a menu icon and nothing
    // else. The menu does not disappear — it moves to the right, next to the
    // account button, so it is still reachable from every screen.
    final canPop = context.canPop();

    final appBar = AppBar(
      titleSpacing: 4,
      leading: canPop
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => context.pop(),
            )
          : null,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Bug #13: tapping the logo navigates to the home page.
          GestureDetector(
            onTap: () => context.go(Routes.home),
            child: const PlaySphereLogo(markSize: 24, fontSize: 16),
          ),
          // Suppressed when it would only repeat the wordmark directly above
          // it. The dashboard passes `title: 'PlaySphere'` and no subtitle, so
          // the bar read "PlaySphere" twice, one under the other — a whole
          // line of the most valuable vertical space on the screen spent
          // saying the thing the logo had just said.
          if (_caption(title, subtitle, org?.name) case final caption?)
            Text(
              caption,
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      actions: [
        ...?actions,
        // Whether anything scored is still waiting to reach the server, on
        // EVERY screen rather than only on the pad that queued it. A scorer
        // who has walked away from the match has no reason to reopen it, and
        // until this was app-wide the only honest signal that work was still
        // held locally lived on the one screen they had already left.
        const SyncStatusIcon(),
        // Bell immediately beside the profile photo, on every screen. The
        // module menu used to sit between them once a back arrow appeared,
        // so the pair a user reaches for by muscle memory moved depending on
        // how deep they had navigated.
        if (canPop) const _ModuleMenuButton(),
        const _NotificationBell(),
        const AccountButton(),
        const SizedBox(width: 4),
      ],
    );

    final drawer = ModuleDrawer(orgId: orgId);

    if (window.isCompact) {
      return Scaffold(
        appBar: appBar,
        drawer: drawer,
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
      drawer: drawer,
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
                          const PlaySphereMark(size: 22),
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

/// The small line under the wordmark: where you are, and in which club.
///
/// Null when there is nothing to add. "PlaySphere" alone is not a caption —
/// it is the logo, already drawn above — so the dashboard gets no line at
/// all rather than a duplicate of its own brand.
String? _caption(String title, String? subtitle, String? orgName) {
  final parts = [
    title,
    if (subtitle != null) subtitle else if (orgName != null) orgName,
  ];
  if (parts.length == 1 && parts.first == 'PlaySphere') return null;
  return parts.join(' \u00b7 ');
}


/// The bell, with a count of what is waiting on this person.
///
/// This is where "Waiting on you" went when it came off the home screen. The
/// badge is what makes that move safe: an obligation that is no longer on the
/// first screen has to be visible from every screen, or it is an obligation
/// nobody discharges.
class _NotificationBell extends ConsumerWidget {
  const _NotificationBell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(waitingOnYouCountProvider);
    final button = IconButton(
      icon: const Icon(Icons.notifications_outlined),
      tooltip: count == 0 ? 'Notifications' : '$count waiting on you',
      onPressed: () => context.push(Routes.notifications),
    );

    if (count == 0) return button;
    return Badge.count(count: count, child: button);
  }
}

/// Opens the module menu from the app bar's right side.
///
/// Only rendered when the back arrow has taken the leading slot. Without it
/// the "three lines" would vanish the moment anyone navigated one level in,
/// which is where most of the product actually lives.
class _ModuleMenuButton extends StatelessWidget {
  const _ModuleMenuButton();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.menu),
      tooltip: 'Modules',
      onPressed: Scaffold.of(context).openDrawer,
    );
  }
}

/// The four destinations a person uses on a match day inside one club.
///
/// Deliberately short. Everything else the product does lives in the module
/// menu — a bottom bar with seven items is a bar nobody reads, and the rail
/// mirrors it so the two never say different things.
List<NavItem> _clubItems(WidgetRef ref, String orgId) => [
      NavItem(
        icon: Icons.home_outlined,
        selectedIcon: Icons.home,
        label: 'Club',
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
        badgeCount:
            ref.watch(incomingChallengesProvider(orgId)).valueOrNull?.length,
      ),
      NavItem(
        icon: Icons.photo_library_outlined,
        selectedIcon: Icons.photo_library,
        label: 'Gallery',
        path: Routes.gallery(orgId),
      ),
      NavItem(
        icon: Icons.groups_outlined,
        selectedIcon: Icons.groups,
        label: 'Members',
        path: Routes.members(orgId),
        requires: Capability.manageMembers,
      ),
      const NavItem(
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard,
        label: 'Home',
        path: Routes.home,
      ),
    ];

/// What the bar carries on the screens that belong to the person rather than
/// to a club. "Live now" points at their most recent club, and drops out
/// entirely for someone who has not joined one — a destination that leads to
/// an error is worse than one that is absent.
List<NavItem> _globalItems(WidgetRef ref) {
  final primaryOrgId = ref.watch(primaryOrgIdProvider);
  final live = ref.watch(myLiveFixturesProvider).valueOrNull?.length;

  return [
    const NavItem(
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
      label: 'Home',
      path: Routes.home,
    ),
    const NavItem(
      icon: Icons.groups_2_outlined,
      selectedIcon: Icons.groups_2,
      label: 'My clubs',
      path: Routes.orgs,
    ),
    if (primaryOrgId != null)
      NavItem(
        icon: Icons.sensors_outlined,
        selectedIcon: Icons.sensors,
        label: 'Live now',
        path: Routes.live(primaryOrgId),
        badgeCount: live == 0 ? null : live,
      ),
    const NavItem(
      icon: Icons.menu_outlined,
      selectedIcon: Icons.menu,
      label: 'More',
      path: Routes.more,
    ),
  ];
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
///
/// The glyph sits inside [PsEmptyArt] — two soft tinted discs in the brand
/// green — rather than floating as a bare grey icon. That is one edit, and it
/// reaches the 88 empty states across 70 files that all previously rendered as
/// a 44pt grey Material icon in the middle of a white screen. Nothing about
/// the API changed, so no caller had to be touched.
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
              PsEmptyArt(icon: icon),
              const SizedBox(height: 18),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
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
    this.skeleton,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;

  /// Drawn instead of the spinner while the value is loading.
  ///
  /// Optional, and defaulted to the spinner, so all 65 existing call sites
  /// keep working untouched and a screen opts in where the shape of what is
  /// coming is actually known. A spinner says "wait"; a skeleton in the shape
  /// of the list says "this is what is coming", which is the shorter-feeling
  /// wait and the more honest one. [PsListSkeleton] covers the common case.
  final Widget? skeleton;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: builder,
      loading: () =>
          skeleton ?? const Center(child: CircularProgressIndicator()),
      error: (error, _) => EmptyState(
        icon: Icons.error_outline,
        title: 'Could not load this',
        message: errorMessage(error),
        // Offered only where it can actually work. A missing index is
        // rejected identically on every attempt, and with offline
        // persistence the cache answers first — so each tap repainted the
        // screen for a frame and then failed again, which reads as the app
        // taunting you rather than as a server that is not set up.
        action: onRetry == null || error is BackendNotReadyException
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

/// A live, app-wide answer to "has everything I scored actually left this
/// phone?".
///
/// ## Why this is in the app bar and not on the scoring pad
///
/// The pad already had a pending banner, and it was the wrong place for it:
/// the moment a scorer finishes a match they close the pad and never open it
/// again, so the one surface that could tell them work was still held locally
/// was the one surface they had left. Sitting in the shell's app bar, this is
/// on every screen of the product — including the club home an organizer
/// stares at while asking why the points table has not moved.
///
/// Renders nothing at all when the queue is empty, which is almost always.
/// A permanent "synced ✓" badge trains people to stop reading it, and then
/// the one time it matters it is invisible for being familiar.
class SyncStatusIcon extends ConsumerWidget {
  const SyncStatusIcon({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingScoreEventsProvider).valueOrNull ?? 0;
    if (pending == 0) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: '$pending scoring ${pending == 1 ? 'action is' : 'actions are'} '
          'saved on this phone and waiting to upload. Tap to retry now.',
      child: InkWell(
        // A manual retry, because the person holding the phone often knows
        // something the app cannot: they have just walked into the pavilion
        // and onto the wi-fi. Waiting out the retry timer for that is a
        // needless few seconds of doubt.
        onTap: () => ref.read(syncDriverProvider).syncNow(),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_upload_outlined,
                  size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                '$pending',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
