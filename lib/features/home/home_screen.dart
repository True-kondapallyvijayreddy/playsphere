import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ads/promo.dart';
import '../../core/layout/responsive.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../arena/arena_providers.dart';
import '../../core/router/app_router.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/confirm_exit.dart';
import '../../shared/identity.dart';
import '../../shared/live_dot.dart';
import '../../shared/promo_strip.dart';
import '../../shared/ui_kit.dart';
import '../community/widgets/match_rsvp_section.dart';
import 'home_providers.dart';
import 'open_registrations.dart';

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
/// The three big buttons underneath draw the distinction the product turns on:
/// **Play sport** is intent — I want a game, now — **Challenge** is us against
/// them on a day we agree, and **Explore sport** is discovery. Explore is not a
/// second menu: it opens the sport directory, and picking a sport there scopes
/// the whole of PlaySphere to it — clubs, teams, grounds, events, rankings,
/// sponsorship. See `SportHubScreen`.
///
/// ## And a second rule: **home holds no menu**
///
/// Under the three buttons there used to be an "Explore" list of seven more
/// destinations — Find players, Find coaches, Find grounds, Find events,
/// Sponsorship, Career profile, Sports analytics. Every one of the seven was
/// already in the More index, five of them were also in the drawer, and three
/// wore a different name in each place. It is gone. The dashboard now ends
/// where the member's own business ends, and the product's index is the More
/// tab — one screen, one name per destination. See `MoreMenuScreen`.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberships = ref.watch(myActiveMembershipsProvider);

    final rsvp = ref.watch(rsvpCountProvider);
    final live = ref.watch(liveCountProvider);

    // The club "New event" creates in: the one named in the app bar whenever
    // it can host an event, and only otherwise the first club where this
    // person could actually create something. Offering "New event" to a
    // member who cannot create one is offering a permission error; opening it
    // on a club other than the one the chip names is worse, because the
    // person has no reason to look. See [actingOrgIdProvider].
    final organizingOrgId =
        ref.watch(actingOrgIdProvider(Capability.manageCompetitions));

    // Quick match needs a club to hang the match off, but not the right to
    // run events — a plain member starting a game between two people already
    // on the ground is the commonest thing in the app. So it is simply the
    // club they are in, with no capability to satisfy and nothing to fall
    // back from.
    final playOrgId = ref.watch(actingOrgIdProvider(null));

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

                      _PrimaryActions(
                        organizingOrgId: organizingOrgId,
                        clubOrgId: playOrgId,
                      ),
                      const SizedBox(height: 26),

                      // Directly under the three doors, and above Explore.
                      //
                      // Play, Challenge and Explore are the three things a
                      // person can START; these two buttons are the fourth,
                      // and the only one with a deadline attached. They sit
                      // with them rather than in the Explore list below
                      // because what they count expires — an entry that
                      // closes on Friday is not a destination that will still
                      // be there next week, and burying it under seven
                      // permanent doors is how an open season closes with
                      // nobody from this club in it.
                      //
                      // Draws nothing at all when there is nothing open, so on
                      // an ordinary day the dashboard is exactly the screen it
                      // was. See [ActiveSeasonsSection].
                      const ActiveSeasonsSection(),
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
///
/// ## Why each one carries a picture rather than a line icon
///
/// The six used to be a grey outline glyph in the corner of a white box, and a
/// grid of those is a grid of one thing. Nothing told them apart at a glance,
/// so reaching for "Live" meant reading six labels — which is the opposite of
/// what a dashboard of counters is for.
///
/// They now carry a [PsEmblem]: the same generated squircle the app already
/// draws for a club with no logo and a player with no photo, in the colour
/// this tile owns. That buys two things at once. Colour makes the six
/// distinguishable without reading, so the grid becomes navigable by position
/// AND by hue. And because it is the same component as the crest and the
/// avatar, the dashboard looks like the rest of the product rather than like a
/// screen that invented its own decoration.
///
/// The colours are one family on purpose — the same saturated mid band the
/// sport palette uses (see [SportVisual]) — so six emblems side by side read
/// as a set rather than as six unrelated apps. Live and RSVP take the two
/// colours the product already owns, [Ps.live] and [Ps.primary], because those
/// two mean something everywhere else in the app and a dashboard that gave
/// "Live" its own private red would be teaching a second vocabulary.
class _CounterColors {
  const _CounterColors._();

  static const clubs = Color(0xFF6366F1);
  static const events = Color(0xFFF59E0B);
  static const matches = Color(0xFF3B82F6);
  static const sports = Color(0xFF8B5CF6);
  static const live = Ps.live;
  static const rsvp = Ps.primary;
}

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

    // Every club this person can call a match for. Same capability pair
    // `MatchRsvpScreen` uses for its FAB, so the "+" here and the button
    // there are never offered to different people.
    final organizingOrgIds = <String>[
      for (final m in ref.watch(myActiveMembershipsProvider).valueOrNull ??
          const [])
        if (ref.watch(myCapabilitiesProvider(m.orgId)).any((c) =>
            c == Capability.manageCompetitions ||
            c == Capability.manageOrganization))
          m.orgId,
    ];

    final tiles = <Widget>[
      _CounterTile(
        label: 'Clubs',
        count: clubs,
        // People, not a heraldic shield. A shield is what a club puts ON its
        // crest; the thing being counted here is the clubs themselves, and
        // every other list in the app draws one as a group of people.
        icon: Icons.groups,
        colour: _CounterColors.clubs,
        onTap: () => context.push(Routes.orgs),
      ),
      _CounterTile(
        label: 'Events',
        count: events,
        icon: Icons.emoji_events,
        colour: _CounterColors.events,
        onTap: hasFeed ? () => context.push(Routes.myEvents) : null,
      ),
      _CounterTile(
        label: 'Live',
        count: live,
        icon: Icons.sensors,
        colour: _CounterColors.live,
        // Only when something IS live. A permanently red emblem on a
        // dashboard where nothing is being played is an alarm that means
        // nothing, and people stop seeing it within a week.
        muted: live.unknown || live.value == 0,
        accent: live.unknown ? null : (live.value > 0 ? Ps.live : null),
        showLiveDot: !live.unknown && live.value > 0,
        onTap: () => context.push(Routes.liveNow),
      ),
      _CounterTile(
        label: 'Matches',
        count: matches,
        // A scoreboard, not a cricket bat. This counts matches across every
        // sport a person plays, and dressing that number in one sport's
        // equipment tells a footballer the tile is not for them.
        icon: Icons.scoreboard,
        colour: _CounterColors.matches,
        onTap: () => context.push(Routes.myMatches),
      ),
      _CounterTile(
        label: 'Sports',
        count: sports,
        // A whistle: the one mark that means sport in general without
        // belonging to any single one. `category` meant "a taxonomy", which
        // is a developer's word for it.
        icon: Icons.sports,
        colour: _CounterColors.sports,
        onTap: () => context.push(uid == null ? Routes.sports : Routes.mySports),
      ),
      // Always here, like the five above it.
      //
      // It used to appear only when the count was above zero, on the argument
      // that a tile reading "0 RSVP" is a slot on the most valuable screen in
      // the product spent saying nothing. That argument is wrong twice over.
      //
      // A tile that comes and goes is a tile nobody learns the position of —
      // the six counters are a fixed grid people reach into by muscle memory,
      // and one of them blinking in and out relocates the other five. Worse,
      // a disappearing door means the screen behind it is unreachable exactly
      // when somebody wants to go looking: an organizer with nothing pending
      // could not get to the screen that holds "Call a match", and a member
      // could not check what they had already answered.
      //
      // The "+" stays organizer-only, because asking is a thing only they can
      // do.
      _CounterTile(
        label: 'RSVP',
        count: rsvp,
        icon: Icons.event_available,
        colour: _CounterColors.rsvp,
        accent: Ps.primary,
        onTap: () => context.push(Routes.matchRsvps),
        onAdd: organizingOrgIds.isEmpty
            ? null
            : () => showCreateMatchRsvpSheet(
                  context: context,
                  ref: ref,
                  orgIds: organizingOrgIds,
                ),
        addTooltip: 'Call a match',
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

/// One counter: a picture, a number, a word, and a reason to tap.
///
/// ## Why it is centred
///
/// The tile used to be left-aligned with the glyph in the top-left corner, and
/// on a 92pt-wide phone tile that put three differently-sized things — a 15pt
/// icon, a 23pt number and a 12.5pt label — on three different optical left
/// edges. Six of those side by side is a ragged column of starts.
///
/// Centred, the emblem and the number share one axis, and the number lands in
/// the middle of the box it belongs to. That is what makes a grid of counters
/// scannable: the eye travels down the centres, not along the text.
class _CounterTile extends StatelessWidget {
  const _CounterTile({
    required this.label,
    required this.count,
    required this.icon,
    required this.colour,
    required this.onTap,
    this.accent,
    this.muted = false,
    this.showLiveDot = false,
    this.onAdd,
    this.addTooltip,
  });

  final String label;
  final HomeCount count;

  /// The white shape inside the emblem. Filled, for the reason [PsEmblem]
  /// gives.
  final IconData icon;

  /// This counter's own colour. See [_CounterColors].
  final Color colour;

  /// Null when this counter has nothing to open — see the Events tile.
  final VoidCallback? onTap;

  /// Tints the border, the number and the detail line. Distinct from [colour],
  /// which is always the emblem's: an emblem is an identity and is the same
  /// whatever the count says, while an accent is a state and appears only when
  /// there is something to be in a state about.
  final Color? accent;

  /// Drains the emblem to grey. For a counter whose colour is a signal rather
  /// than a label — see the Live tile.
  final bool muted;

  final bool showLiveDot;

  /// A second, smaller action in the tile's top-right: *create one of these*.
  /// Null on every tile whose count this person can only read.
  final VoidCallback? onAdd;
  final String? addTooltip;

  @override
  Widget build(BuildContext context) {
    final numberColour = accent ?? Ps.ink;
    return Material(
      color: Ps.surface,
      borderRadius: BorderRadius.circular(Ps.radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Ps.radius),
        child: Container(
          // Sized to the content, not to a ratio. The grid this replaced sized
          // a tile by width:height, so dropping to one column on a phone made
          // each one 162px tall and pushed the six counters over three rows.
          // Every extent here is fixed, so the tile is the same compact height
          // at 320pt as at 900 — and inside the budget `home_screen_test`
          // holds it to.
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Ps.radius),
            border: Border.all(
              color: accent == null ? Ps.border : accent!.withValues(alpha: 0.4),
            ),
          ),
          // The dot and the "+" float over the tile rather than occupying a
          // row of their own. In a row they cost every tile 20pt of height for
          // an affordance only two of them carry; overlaid they cost nothing
          // and cannot pull the RSVP tile out of line with the other five.
          child: Stack(
            // The badge below hangs 2pt past the content box on two sides so
            // it sits ON the tile's corner rather than inside it. A `Stack`
            // clips to its own bounds by default, which would shave exactly
            // that overhang off.
            clipBehavior: Clip.none,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  PsEmblem(
                    icon: icon,
                    // Grey, not a faded version of the colour: a washed-out
                    // red still reads as red, which is the thing a quiet Live
                    // tile must not do.
                    color: muted ? Ps.faint : colour,
                    size: 26,
                  ),
                  const SizedBox(height: 5),
                  // An em dash, not a zero, when the number could not be read —
                  // see [HomeCount.unknown]. A tile that says "0 Live" because a
                  // club refused the read is worse than one that admits it does
                  // not know.
                  Text(
                    count.unknown ? '—' : '${count.value}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      height: 1.05,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                      color: count.unknown ? Ps.faint : numberColour,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Ps.ink,
                    ),
                  ),
                  // The line that turns a number into a reason to tap.
                  // Reserved even when empty so the six tiles stay the same
                  // height.
                  SizedBox(
                    height: 13,
                    child: count.detail == null
                        ? null
                        : Text(
                            count.detail!,
                            maxLines: 1,
                            textAlign: TextAlign.center,
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
              if (showLiveDot)
                const Positioned(top: 0, right: 0, child: LiveDot()),
              // A filled badge, not a bare glyph.
              //
              // It was a 17pt hairline "+" in the tile's own ink colour,
              // floating in the corner over white with nothing behind it. On a
              // phone that does not read as a button — it reads as part of the
              // border, and the first report of this was "the + is missing on
              // the RSVP tile" from somebody looking straight at it. A solid
              // disc in the tile's colour with a white glyph is the same
              // affordance the rest of the app uses for *create*, and it is
              // unmistakably a thing to press.
              if (onAdd != null)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Tooltip(
                    message: addTooltip ?? 'Add',
                    child: Material(
                      color: accent ?? colour,
                      shape: const CircleBorder(),
                      // The disc sits on the tile's own border. Ringing it in
                      // the surface colour keeps the two shapes apart instead
                      // of letting the badge merge into the outline.
                      elevation: 0,
                      child: InkWell(
                        onTap: onAdd,
                        customBorder: const CircleBorder(),
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Ps.surface, width: 1.5),
                          ),
                          child: const Icon(
                            Icons.add_rounded,
                            size: 15,
                            color: Colors.white,
                          ),
                        ),
                      ),
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

/// **Play**, **Challenge** and **Explore** — the three things a person opens
/// this app to start.
///
/// Play is intent: I want a game, now. It goes straight to starting one where
/// the person can, and to finding one where they cannot.
///
/// Challenge is the middle one on purpose, and it is the middle one in meaning
/// too: not "a game today" and not "look around", but *us against them on
/// Saturday*. It was the flow buried deepest in the product — four taps down a
/// club page, on a screen that was not reachable at all until recently — and
/// it is the one CLAUDE.md calls the heart of the OS. A village club deciding
/// to play the next village should not have to know which club page it lives
/// behind.
///
/// Explore is discovery: I want to look around. It opens the sport directory,
/// and from there a sport becomes a scope — every list on `SportHubScreen`
/// means that one sport, and nothing on it is the whole platform filtered
/// down to nothing.
///
/// ## Why three across and not a second row
///
/// The row is the fork, and a fork with one branch on a line of its own is not
/// read as part of the same choice. Three fit because [_BigButton] drops to a
/// tighter type scale when it is narrow — see `compact` — and the labels wrap
/// to two lines rather than shrinking to unreadable. `IntrinsicHeight` keeps
/// the three the same height when one of them wraps and another does not.
class _PrimaryActions extends ConsumerWidget {
  const _PrimaryActions({
    required this.organizingOrgId,
    required this.clubOrgId,
  });

  /// A club where this person may run events, if any. Only the "New event"
  /// door needs it — see [actingOrgIdProvider].
  final String? organizingOrgId;

  /// The club they are in: what the app bar names, and what these buttons
  /// act as. Both Play and Challenge belong to it, because neither needs a
  /// permission the club grants — a plain member starting a game, and a
  /// member reading their club's fixtures against other clubs.
  final String? clubOrgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Both are the club in the bar. This used to prefer a club the person
    // ORGANIZES for, which is the bug: a player in a school and a coach at an
    // academy saw "Nizampet High School" at the top of the screen and started
    // a match that went onto the academy's record.
    final challengeOrgId = clubOrgId ?? organizingOrgId;
    // Whether the challenge board they are opening will let them issue one,
    // asked of the club they are actually opening rather than inferred from
    // whether they organize somewhere else entirely.
    final canChallenge = challengeOrgId != null &&
        ref
            .watch(myCapabilitiesProvider(challengeOrgId))
            .contains(Capability.manageCompetitions);

    // Arena games waiting on this person — an invitation to answer or a board
    // where it is their move. Shown as the button's own subtitle rather than a
    // badge, because "2 waiting" says what a red dot only hints at.
    final arenaWaiting = ref.watch(arenaWaitingCountProvider);

    final buttons = <_BigButton>[
      _BigButton(
        icon: Icons.sports_handball_outlined,
        label: 'Play sport',
        hint: clubOrgId == null ? 'Find a game' : 'Start a match',
        filled: true,
        onTap: () => context.push(
          clubOrgId == null
              ? Routes.lookingFor
              : Routes.quickMatch(clubOrgId!),
        ),
      ),
      _BigButton(
        icon: Icons.sports_kabaddi_outlined,
        label: 'Challenge',
        // A member with no club at all is not being sent to a challenge board
        // that would refuse them — they are sent to the club directory, which
        // is the actual first step.
        hint: challengeOrgId == null
            ? 'Join a club first'
            : canChallenge
                ? 'Play another club'
                : "Your club's fixtures",
        filled: false,
        onTap: () => context.push(
          challengeOrgId == null
              ? Routes.orgs
              : Routes.challenges(challengeOrgId),
        ),
      ),
      _BigButton(
        icon: Icons.psychology_outlined,
        label: 'Arena',
        hint: arenaWaiting > 0
            ? '$arenaWaiting waiting on you'
            : 'Chess, go, and more',
        filled: false,
        highlighted: arenaWaiting > 0,
        onTap: () => context.push(Routes.arena),
      ),
      _BigButton(
        icon: Icons.travel_explore_outlined,
        label: 'Explore sport',
        hint: 'Pick a sport, see it all',
        filled: false,
        onTap: () => context.push(Routes.sports),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Four buttons do not fit across a phone. Below this width they go
          // two-by-two, which keeps each one at a size worth tapping instead
          // of shrinking all four until the labels are unreadable.
          final compact = constraints.maxWidth < 560;
          final perRow = compact ? 2 : 4;

          final rows = <Widget>[];
          for (var start = 0; start < buttons.length; start += perRow) {
            final slice = buttons.skip(start).take(perRow).toList();
            rows.add(
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < slice.length; i++) ...[
                      Expanded(child: slice[i].withCompact(compact)),
                      if (i != slice.length - 1) const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            );
          }

          return Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                rows[i],
                if (i != rows.length - 1) const SizedBox(height: 8),
              ],
            ],
          );
        },
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
    this.compact = false,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final String hint;
  final bool filled;
  final VoidCallback onTap;

  /// Draws the outline in brand green rather than the hairline grey. Used
  /// where the button has something waiting behind it, so a glance at the
  /// home screen shows there is something to answer.
  final bool highlighted;

  /// The row decides the scale, and it only knows that once it has measured
  /// itself — so the buttons are built first and told afterwards.
  _BigButton withCompact(bool value) => _BigButton(
        icon: icon,
        label: label,
        hint: hint,
        filled: filled,
        onTap: onTap,
        compact: value,
        highlighted: highlighted,
      );

  /// Narrow enough that a two-word label has to wrap. Shrinks the padding and
  /// the type rather than the words: "Explore sport" over two lines is still
  /// "Explore sport", and auto-scaling it to fit one line at this width would
  /// put it below the size of its own subtitle.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? Ps.primary : Ps.surface,
      borderRadius: BorderRadius.circular(Ps.radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Ps.radius),
        child: Container(
          padding: compact
              ? const EdgeInsets.fromLTRB(11, 12, 9, 12)
              : const EdgeInsets.fromLTRB(16, 15, 14, 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Ps.radius),
            border: Border.all(
              color: filled
                  ? Colors.transparent
                  : highlighted
                      ? Ps.primary
                      : Ps.border,
              width: highlighted ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: compact ? 20 : 22,
                color: filled ? Colors.white : Ps.primary,
              ),
              SizedBox(height: compact ? 8 : 10),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 14 : 16,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  color: filled ? Colors.white : Ps.ink,
                ),
              ),
              Text(
                hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 10.5 : 11.5,
                  fontWeight: highlighted ? FontWeight.w700 : FontWeight.w400,
                  color: filled
                      ? Colors.white.withValues(alpha: 0.85)
                      : highlighted
                          ? Ps.primary
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
