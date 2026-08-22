import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ads/promo.dart';
import '../../core/layout/responsive.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/confirm_exit.dart';
import '../../shared/live_dot.dart';
import '../../shared/promo_strip.dart';
import '../../shared/ui_kit.dart';
import 'home_providers.dart';

/// The dashboard: what is happening in this person's sports world, in one
/// screen they never have to scroll.
///
/// ## What this replaced, and why
///
/// The previous home screen stacked seven full sections — greeting, search,
/// live matches, upcoming events, my clubs, career stats, an explore grid —
/// each with its own heading, its own empty state and its own list. It was
/// two and a half screenfuls before a member reached anything they could act
/// on, and it answered every question except the one they opened the app to
/// ask: *what do I do now?*
///
/// The rule here is that **home holds counts, not lists**. A list belongs on
/// the screen devoted to it, where it has room to be complete and sortable.
/// A count belongs here, because a count is a question — "12 events, 3 this
/// week" — and tapping it is how you get the answer. That collapses five
/// sections into six tiles, and the whole dashboard fits above the fold.
///
/// The two big buttons underneath draw the one distinction the product turns
/// on: **Play sport** is intent — I want a game, now — and **Explore sport**
/// is discovery. Explore is not a second menu: it opens the sport directory,
/// and picking a sport there scopes the whole of PlaySphere to it — clubs,
/// teams, grounds, events, rankings, sponsorship. See `SportHubScreen`.
/// Everything else lives in the short list below them.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberships = ref.watch(myActiveMembershipsProvider);
    final clubs = memberships.valueOrNull ?? const [];

    final rsvp = ref.watch(rsvpCountProvider);
    final live = ref.watch(liveCountProvider);

    // The first club where this person could actually create something.
    // Offering "New event" to a member who cannot create one is offering a
    // permission error.
    final organizingOrgId = clubs
        .map((m) => m.orgId)
        .where(
          (id) => ref
              .watch(myCapabilitiesProvider(id))
              .contains(Capability.manageCompetitions),
        )
        .firstOrNull;

    // Quick match needs a club to hang the match off, but not the right to
    // run events — a plain member starting a game between two people already
    // on the ground is the commonest thing in the app. Prefer the club this
    // person organizes for, so both buttons land in the same place, and fall
    // back to any club they belong to.
    final playOrgId = organizingOrgId ??
        (clubs.isEmpty ? null : clubs.first.orgId);

    return ConfirmExit(
      child: AppScaffold(
        title: 'PlaySphere',
        // The same pair the club home carries, for the same reason: the two
        // things a person comes here to *start* should be reachable without
        // first picking a club. Small button on top is quick match — play
        // now — and the labelled one below runs the heavier event flow, which
        // only an organizer sees.
        floatingActionButton: (playOrgId == null && organizingOrgId == null)
            ? null
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (playOrgId != null)
                    FloatingActionButton.small(
                      heroTag: 'home-quick-match',
                      tooltip: 'Quick match — play now',
                      onPressed: () =>
                          context.push(Routes.quickMatch(playOrgId)),
                      child: const Icon(Icons.sports_score),
                    ),
                  if (playOrgId != null && organizingOrgId != null)
                    const SizedBox(height: 12),
                  if (organizingOrgId != null)
                    FloatingActionButton.extended(
                      heroTag: 'home-new-event',
                      onPressed: () => context
                          .push(Routes.createCompetition(organizingOrgId)),
                      icon: const Icon(Icons.add),
                      label: const Text('New event'),
                    ),
                ],
              ),
        body: AsyncView(
          value: memberships,
          onRetry: () => ref.invalidate(myMembershipsProvider),
          builder: (_) {
            return ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                ContentBounds(
                  maxWidth: 900,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _Hero(),
                      const SizedBox(height: 16),

                      _Counters(
                        rsvp: rsvp,
                        live: live,
                      ),
                      const SizedBox(height: 18),

                      _PrimaryActions(organizingOrgId: organizingOrgId),
                      const SizedBox(height: 26),

                      const _ExploreList(),
                    ],
                  ),
                ),

                // Bottom, and nowhere else on this screen.
                //
                // Everything above is the member's own business; this is
                // somebody else's. Putting it last means the dashboard is
                // read before an advertiser is, and a person who never
                // scrolls this far is never interrupted — which is also why
                // impressions bill per card built rather than per strip
                // shown. See [PromoStrip].
                const SizedBox(height: 26),
                const PromoStrip(slot: PromoSlot.home),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero
// ---------------------------------------------------------------------------

/// The date, and the product's one-line claim.
///
/// One line, on purpose. "All sports. One OS." wrapped to two lines on every
/// phone narrower than a Pixel, which cost a whole line of vertical space at
/// the very top of the screen for no information at all. It is auto-scaled to
/// fit instead, so it holds its line on a 320pt phone.
class _Hero extends ConsumerWidget {
  const _Hero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final date =
        '${days[(now.weekday - 1) % 7]} ${now.day} ${months[now.month - 1]}';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F3D24), Color(0xFF157F3D)],
        ),
        borderRadius: BorderRadius.circular(Ps.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            date.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 6),
          // Scaled down rather than wrapped. `FittedBox` keeps it on one line
          // at any width the app supports.
          const FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              'ALL SPORTS. ONE OS.',
              maxLines: 1,
              style: TextStyle(
                fontSize: 26,
                height: 1.1,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The six counters
// ---------------------------------------------------------------------------

/// Six tiles: Clubs, Events, Live, Matches, Sports, RSVP.
///
/// Every one is a live number and a destination. Three across on a phone,
/// which is the sketch's own grid and also the widest a 320pt screen holds
/// without the numbers shrinking.
class _Counters extends ConsumerWidget {
  const _Counters({required this.rsvp, required this.live});

  final HomeCount rsvp;
  final HomeCount live;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clubs = ref.watch(clubCountProvider);
    final events = ref.watch(eventCountProvider);
    final matches = ref.watch(matchCountProvider);
    final sports = ref.watch(sportCountProvider);
    final uid = ref.watch(currentUidProvider);

    // Events are read from the clubs this person is in or follows. With no
    // club behind it the tile still shows its zero — a member deciding
    // whether to join something should see that the number exists — but it
    // has nowhere to go, and `/events/mine` on an empty feed is a blank
    // screen reached by a tap that promised otherwise.
    final hasFeed = ref.watch(myFeedOrgIdsProvider).isNotEmpty;

    final tiles = <Widget>[
      _CounterTile(
        label: 'Clubs',
        count: clubs,
        icon: Icons.shield_outlined,
        onTap: () => context.push(Routes.orgs),
      ),
      _CounterTile(
        label: 'Events',
        count: events,
        icon: Icons.emoji_events_outlined,
        onTap: hasFeed ? () => context.push(Routes.myEvents) : null,
      ),
      _CounterTile(
        label: 'Live',
        count: live,
        icon: Icons.sensors,
        accent: live.unknown ? null : (live.value > 0 ? Ps.live : null),
        showLiveDot: !live.unknown && live.value > 0,
        onTap: () => context.push(Routes.liveNow),
      ),
      _CounterTile(
        label: 'Matches',
        count: matches,
        icon: Icons.sports_cricket_outlined,
        onTap: () => context.push(Routes.myMatches),
      ),
      _CounterTile(
        label: 'Sports',
        count: sports,
        icon: Icons.category_outlined,
        onTap: () => context.push(uid == null ? Routes.sports : Routes.mySports),
      ),
      // Only when somebody is actually waiting on an answer.
      //
      // A tile permanently reading "0 RSVP" is a slot on the most valuable
      // screen in the product spent saying nothing. When it appears it means
      // something, which is what makes it worth looking at.
      if (rsvp.value > 0)
        _CounterTile(
          label: 'RSVP',
          count: rsvp,
          icon: Icons.event_available_outlined,
          accent: Ps.primary,
          onTap: () => context.push(Routes.matchRsvps),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth > 640 ? 6 : 3;
          const gap = 10.0;
          final width =
              (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final t in tiles) SizedBox(width: width, child: t),
            ],
          );
        },
      ),
    );
  }
}

class _CounterTile extends StatelessWidget {
  const _CounterTile({
    required this.label,
    required this.count,
    required this.icon,
    required this.onTap,
    this.accent,
    this.showLiveDot = false,
  });

  final String label;
  final HomeCount count;
  final IconData icon;

  /// Null when this counter has nothing to open — see the Events tile.
  final VoidCallback? onTap;
  final Color? accent;
  final bool showLiveDot;

  @override
  Widget build(BuildContext context) {
    final colour = accent ?? Ps.ink;
    return Material(
      color: Ps.surface,
      borderRadius: BorderRadius.circular(Ps.radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Ps.radius),
        child: Container(
          // Sized to the content, not to a ratio.
          //
          // The grid this replaced sized a tile by width:height, so dropping
          // to one column on a phone made each one 162px tall and pushed the
          // six counters over three rows. Every extent here is fixed, so the
          // tile is the same compact height at 320pt as at 900.
          padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Ps.radius),
            border: Border.all(
              color: accent == null ? Ps.border : accent!.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(icon, size: 15, color: accent ?? Ps.faint),
                  const Spacer(),
                  if (showLiveDot) const LiveDot(),
                ],
              ),
              const SizedBox(height: 4),
              // An em dash, not a zero, when the number could not be read —
              // see [HomeCount.unknown]. A tile that says "0 Live" because a
              // club refused the read is worse than one that admits it does
              // not know.
              Text(
                count.unknown ? '—' : '${count.value}',
                style: TextStyle(
                  fontSize: 23,
                  height: 1.05,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                  color: count.unknown ? Ps.faint : colour,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Ps.ink,
                ),
              ),
              // The line that turns a number into a reason to tap. Reserved
              // even when empty so the six tiles stay the same height.
              SizedBox(
                height: 13,
                child: count.detail == null
                    ? null
                    : Text(
                        count.detail!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: accent ?? Ps.muted,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The two doors
// ---------------------------------------------------------------------------

/// **Play** and **Explore** — the product's one real fork.
///
/// Play is intent: I want a game, now. It goes straight to starting one where
/// the person can, and to finding one where they cannot.
///
/// Explore is discovery: I want to look around. It opens the sport directory,
/// and from there a sport becomes a scope — every list on `SportHubScreen`
/// means that one sport, and nothing on it is the whole platform filtered
/// down to nothing.
class _PrimaryActions extends StatelessWidget {
  const _PrimaryActions({required this.organizingOrgId});

  final String? organizingOrgId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: _BigButton(
              icon: Icons.sports_handball_outlined,
              label: 'Play sport',
              hint: organizingOrgId == null ? 'Find a game' : 'Start a match',
              filled: true,
              onTap: () => context.push(
                organizingOrgId == null
                    ? Routes.lookingFor
                    : Routes.quickMatch(organizingOrgId!),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _BigButton(
              icon: Icons.travel_explore_outlined,
              label: 'Explore sport',
              hint: 'Pick a sport, see it all',
              filled: false,
              onTap: () => context.push(Routes.sports),
            ),
          ),
        ],
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.icon,
    required this.label,
    required this.hint,
    required this.filled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String hint;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? Ps.primary : Ps.surface,
      borderRadius: BorderRadius.circular(Ps.radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Ps.radius),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 15, 14, 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Ps.radius),
            border: Border.all(color: filled ? Colors.transparent : Ps.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: filled ? Colors.white : Ps.primary),
              const SizedBox(height: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: filled ? Colors.white : Ps.ink,
                ),
              ),
              Text(
                hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: filled
                      ? Colors.white.withValues(alpha: 0.85)
                      : Ps.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Explore
// ---------------------------------------------------------------------------

/// The rest of the product, as a short labelled list rather than a 23-item
/// drawer.
///
/// These are the destinations a member actually reaches for. Everything else
/// the app can do is still in the module menu; what changed is that the six
/// most-wanted are now on the screen instead of behind three lines nobody
/// opens.
class _ExploreList extends ConsumerWidget {
  const _ExploreList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUidProvider);

    final entries = <(IconData, String, String, String)>[
      (Icons.query_stats, 'Sports analytics', 'Numbers across the platform',
          Routes.sports),
      if (uid != null)
        // `/me`, not `/player/$uid`. They resolve to the same profile, but
        // the self route is the one that survives a sign-out and back in as
        // somebody else — and it is what the rest of the app links to.
        (Icons.badge_outlined, 'Career profile', 'Your record, every sport',
            Routes.myProfile),
      (Icons.person_search_outlined, 'Find players', 'Scout by sport and skill',
          Routes.scoutSearch),
      (Icons.school_outlined, 'Find coaches', 'Learn from someone nearby',
          Routes.coaches),
      (Icons.stadium_outlined, 'Find grounds', 'Book a pitch near you',
          Routes.grounds),
      (Icons.event_outlined, 'Find events', 'Open for entry now',
          Routes.globalEvents),
      (Icons.handshake_outlined, 'Sponsorship', 'Back a team, or find backing',
          Routes.sponsor),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Text(
            'EXPLORE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: Ps.faint,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Ps.surface,
            borderRadius: BorderRadius.circular(Ps.radius),
            border: Border.all(color: Ps.border),
          ),
          child: Column(
            children: [
              for (final (icon, title, subtitle, route) in entries)
                ListTile(
                  leading: Icon(icon, size: 20, color: Ps.primary),
                  title: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: Ps.muted),
                  ),
                  trailing:
                      const Icon(Icons.chevron_right, size: 18, color: Ps.faint),
                  onTap: () => context.push(route),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
