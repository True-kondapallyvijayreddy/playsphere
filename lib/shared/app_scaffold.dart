import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/errors/app_exception.dart';
import '../core/layout/responsive.dart';
import '../core/models/app_user.dart';
import '../core/permissions/capability.dart';
import '../core/providers.dart';
import '../core/router/app_router.dart';
import '../features/family/profile_switcher.dart';
import '../features/home/home_providers.dart';
import 'account_button.dart';
import 'club_switcher.dart';
import 'identity.dart';
import 'live_dot.dart';
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
/// the top left, which is always a tap back to the dashboard, and the
/// notification bell and account button at the top right. Underneath that it
/// renders a bottom bar on phones, a navigation rail on tablets and an
/// extended rail on laptops, from one declaration.
///
/// There is deliberately no drawer. One used to hang off every route in the
/// app carrying twenty-seven destinations, most of them also on the bar, on
/// the dashboard or on the More screen — and the club-scoped half of it
/// pointed at whichever club the person had joined most recently rather than
/// the one they were reading. Its contents now live in exactly one place
/// each: `MoreMenuScreen` for the product's index, and `ClubSectionsGrid` on
/// a club's own page for that club's sections. Screens never think about which they are getting, which is
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
  /// the person rather than to any one club — home, More, and the profile.
  /// It decides which of the two bars this screen gets, and nothing else.
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

    // The other half of the same job: keeps the list of clubs this person is
    // waiting on a decision from current, which is what lets those clubs'
    // admins see who they are being asked to admit — and what withdraws that
    // the moment the decision is made.
    ref.watch(profilePendingMirrorProvider);

    // Backfills this account's PSOS code if it predates codes existing. Same
    // placement and same reasoning as the mirror above.
    ref.watch(playerCodeProvider);

    // Registers this device for push. Mounted here for the same reason: a
    // token has to be registered on a cold start where the session was
    // restored and no sign-in ever happened, not only at the moment somebody
    // taps Sign in.
    ref.watch(pushRegistrationProvider);

    // Resets "Managing as X" the moment X stops being a still-managed
    // child — see the provider's own doc comment. Same placement logic as
    // the two above: every screen, not only the participation ones.
    ref.watch(actingProfileGuardProvider);
    final actingChildUid = ref.watch(actingProfileUidProvider);
    final resolvedActing = ref.watch(actingProfileProvider);
    // Only actually "in a child's profile" once resolution confirms it — the
    // guard clears the selection the moment it stops being valid, and the
    // banner must disappear in that same instant rather than a build later.
    final actingChild =
        (actingChildUid != null && resolvedActing?.uid == actingChildUid)
            ? resolvedActing
            : null;

    // Walking into one of your own clubs IS being in it.
    //
    // Without this the app could hold two answers at once: the chip in the
    // bar naming the club you selected, and a create form three taps deeper
    // creating for the club whose pages you happened to be reading. Adopting
    // the club on arrival collapses that to one — the selection follows you,
    // so "which club am I acting as" has the same answer in the bar, on the
    // dashboard and in every form that writes something.
    //
    // Only your own clubs. Reading a club you do not belong to is browsing,
    // not joining, and `switchTo` refuses a club you are not an active member
    // of — which is also what keeps a public club page from quietly
    // reassigning you. Deferred a frame because it writes provider state, and
    // a write during build is a build that depends on its own outcome.
    if (orgId != null &&
        ref.watch(currentClubIdProvider) != orgId &&
        ref.watch(myActiveOrgIdsProvider).contains(orgId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(currentClubIdProvider.notifier).switchTo(orgId);
      });
    }

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
    // button — Android has one, iOS and the web do not.
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
        // Which club this person is in, immediately left of the bell.
        //
        // The app acts as one club at a time — the matches it shows, the game
        // it starts, the event it creates — and before this it never said
        // which, because the choice was made silently from whichever club was
        // joined last. Stating it in the chrome makes it checkable at a
        // glance from any screen, and tapping it switches without a trip to a
        // club page. See [ClubChip].
        ClubChip(orgId: orgId),
        // Bell immediately beside the profile photo, on every screen and at
        // a fixed position: the pair a person reaches for by muscle memory
        // must not move with how deep they have navigated.
        const _NotificationBell(),
        const AccountButton(),
        const SizedBox(width: 4),
      ],
    );

    // Both banners, in the order they were earned: "this is your child's
    // profile" changes who every screen is ABOUT and so stays on top; "you
    // are scoring" is a door back to work in progress.
    final banners = <Widget>[
      if (actingChild != null) _ActingAsBanner(child: actingChild),
      const ScoringNowBanner(),
    ];

    final content = Column(
      children: [
        ...banners,
        Expanded(child: body),
      ],
    );

    if (window.isCompact) {
      return Scaffold(
        appBar: appBar,
        body: content,
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
          Expanded(child: content),
        ],
      ),
    );
  }
}

/// The standing reminder that this is somebody else's profile.
///
/// The profile switch is total — every screen, every list, every action is
/// the child's — and it survives closing the app, so nothing else on screen
/// would ever tell a parent that the notifications they are reading are not
/// theirs. Persistent rather than a snackbar for exactly that reason, and on
/// every screen rather than only the participation ones, because the switch
/// outlives whichever screen made it.
///
/// Tapping it opens the switcher; the trailing button is the one-tap way
/// straight back to the account holder's own profile, which is the thing
/// people want from it nine times out of ten.
class _ActingAsBanner extends ConsumerWidget {
  const _ActingAsBanner({required this.child});

  final AppUser child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: InkWell(
        onTap: () => showProfileSwitcher(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              PsAvatar(
                name: child.displayName,
                photoUrl: child.photoUrl,
                seed: child.uid,
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "You're in ${child.displayName}'s profile",
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSecondaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () => switchToProfile(context, ref, null),
                child: Text(
                  'Switch back',
                  style: TextStyle(color: scheme.onSecondaryContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The way back to the match you are in the middle of scoring.
///
/// ## The gap this fills
///
/// Scoring is the one job in the app that is interrupted by default. The
/// scorer looks up a rule, answers a message, takes a photo of the team
/// sheet, or the phone simply locks — and the pad is now several screens
/// deep in a stack that the next tap on any navigation destination throws
/// away. Getting back meant remembering which club, which event and which
/// fixture, then walking down through three lists, all while a game carried
/// on in front of them. "Live now" is not that door either: it lists every
/// match on at their clubs, which is a spectator's question.
///
/// So the match a person is NAMED as scorer of follows them across every
/// screen until it is finished. One tap and they are back on the pad, with
/// the score they queued still queued — the pad's own local projection is
/// unaffected by having been left.
///
/// Hidden on the pad itself, which would otherwise be a button that
/// re-navigates to the screen you are reading it on. Hidden, too, for anyone
/// who is not a scorer: see [myScoringFixturesProvider] for why an org
/// manager's blanket permission does not count as being mid-job.
class ScoringNowBanner extends ConsumerWidget {
  const ScoringNowBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scoring = ref.watch(myScoringFixturesProvider);
    if (scoring.isEmpty) return const SizedBox.shrink();

    // Everything except the pad being read right now. Subtracting the current
    // one before counting is what keeps the tail honest: a scorer standing on
    // court one's pad with two matches open is owed "court two", not "court
    // two and one more" — the one more is the screen in front of them.
    final path = GoRouterState.of(context).uri.path;
    final elsewhere = [
      for (final f in scoring)
        if (Routes.scoring(f.orgId, f.compId, f.id) != path) f,
    ];
    if (elsewhere.isEmpty) return const SizedBox.shrink();

    // The oldest still-running one, which is the one somebody scoring two
    // courts is furthest behind on.
    final next = elsewhere.first;
    final target = Routes.scoring(next.orgId, next.compId, next.id);

    final scheme = Theme.of(context).colorScheme;
    final more = elsewhere.length - 1;

    return Material(
      color: scheme.errorContainer,
      child: InkWell(
        onTap: () => context.push(target),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              const LiveDot(),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'You are scoring',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onErrorContainer,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                    ),
                    Text(
                      '${next.entrantAName} v ${next.entrantBName}'
                      '${more > 0 ? '  ·  +$more more' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onErrorContainer,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => context.push(target),
                icon: const Icon(Icons.sports_score, size: 18),
                label: const Text('Resume'),
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.onErrorContainer,
                  foregroundColor: scheme.errorContainer,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
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

/// The bar, in both of the shapes it takes.
///
/// ## The rule the two lists follow
///
/// **The first slot is the section's own root, and the last slot is always
/// More.** That is the whole contract, and it is what makes the bar readable
/// without being memorised: whatever screen you are on, the leftmost item is
/// "back to the top of where I am" and the rightmost is "everything else".
///
/// The club bar used to break the second half of it. It carried six items —
/// Club, Live now, Challenges, Gallery, Members, Home — and **no More at
/// all**, so stepping into a club silently took the product's index away and
/// replaced it with a different set of five. The way back to the rest of
/// PlaySphere was a drawer behind a hamburger that had moved to the right of
/// the app bar. That is the single worst thing the old navigation did, and it
/// is why this file no longer builds a drawer.
///
/// Gallery and Members left the bar rather than More: both are sections OF a
/// club, and a club's sections now sit on the club's own page where they are
/// one tap from it and unambiguously scoped to it — see `ClubSectionsGrid`.
/// The bar keeps only what a person reaches for repeatedly during a match.

/// Inside one club: the club, what is being played, who wants to play us, and
/// the index.
List<NavItem> _clubItems(WidgetRef ref, String orgId) => [
      // First, and load-bearing: `go()` treats `items.first.path` as the root
      // of the section, which is what makes "back" from a sibling return to
      // the club instead of leaving it.
      NavItem(
        icon: Icons.shield_outlined,
        selectedIcon: Icons.shield,
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
      // The escape hatch, in the same slot it occupies everywhere else.
      // Opening it lands on a screen with no club behind it, so the bar there
      // is the global one — which is how a person inside a club gets back to
      // their own dashboard in one further tap.
      const NavItem(
        icon: Icons.apps_outlined,
        selectedIcon: Icons.apps,
        label: 'More',
        path: Routes.more,
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
    // "My clubs" here, in the More index and nowhere else under a third name.
    // `/orgs` used to answer to "My clubs" on the bar, "Clubs" on the
    // dashboard counter and "All clubs" in the index, which made one screen
    // look like three.
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
      icon: Icons.apps_outlined,
      selectedIcon: Icons.apps,
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
  // A caller that already has the sentence — a form's own validation message,
  // "Pick a start date." — passes the String itself. Those were being turned
  // into "Something went wrong. Please try again." here, which is how a
  // create form could refuse to submit without ever saying which field was
  // wrong. Shown as written, and only when written for a person: an empty or
  // suspiciously long string falls through to the generic sentence.
  if (error is String && error.trim().isNotEmpty && error.length <= 200) {
    return error;
  }
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
