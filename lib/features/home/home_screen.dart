import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/ads/promo.dart';
import '../../core/layout/responsive.dart';
import '../../core/models/competition.dart';
import '../../core/models/enums.dart';
import '../../core/models/fixture.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/confirm_exit.dart';
import '../../shared/live_dot.dart';
import '../../shared/promo_banner.dart';
import '../../shared/section_header.dart';
import '../community/widgets/match_rsvp_section.dart';
import '../../shared/ui_kit.dart';
import '../scoring/widgets/live_score_card.dart';
import 'event_feed.dart';
import 'home_providers.dart';

/// How many live matches the home dashboard shows before it hands off to
/// [Routes.liveNow] with a "More" button. Three, not the whole list: this is
/// the top of a dashboard with clubs, events and the rest of the product
/// still to come, not the live screen itself.
const _liveHomePreviewCap = 3;

/// How many open-for-entry events the home dashboard shows before it hands
/// off to [Routes.myEvents] with a "More" button. Five: enough that a member
/// in one or two clubs sees everything without scrolling, but a person in a
/// busy multi-club season does not get their clubs and live matches pushed
/// off the first screen by a long list of entry windows.
const _eventsHomePreviewCap = 5;

/// The screen a member lands on after signing in.
///
/// It answers, in order: what is happening right now, what is waiting on me,
/// which clubs am I in, and what is coming up — across every club at once,
/// because a person is one player with several clubs rather than several
/// separate accounts. Everything else the product does is one tap away in the
/// module menu behind the three lines at the top left.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final uid = ref.watch(currentUidProvider);
    final memberships = ref.watch(myActiveMembershipsProvider);
    final clubs = memberships.valueOrNull ?? const [];

    final liveAsync = ref.watch(myLiveFixturesProvider);
    final live = liveAsync.valueOrNull ?? const <Fixture>[];
    // Deliberately tolerant of its own failure: this is a bonus section, and
    // an error here must never take the club's own live list down with it.
    final clubmateLive =
        ref.watch(clubmateLiveFixturesProvider).valueOrNull ??
            const <Fixture>[];
    final liveFailures = ref.watch(myLiveFixtureFailuresProvider);
    final eventsAsync = ref.watch(myUpcomingEventsProvider);
    final events = eventsAsync.valueOrNull ?? const <Competition>[];
    // The home dashboard only ever shows what a member can act on today —
    // open for entries — not everything scheduled or already running.
    // displayStatus(), not the stored status field: an event whose deadline
    // has quietly passed must stop counting as open the moment it does,
    // same derivation _ClubCard's "open" pill already uses.
    final openEvents = events
        .where((c) => c.displayStatus() == CompetitionStatus.registrationOpen)
        .toList();
    // A season's sports fold into one card here — see [groupEventFeed] — so a
    // five-sport sports week takes one slot in this preview instead of five.
    final openFeed = groupEventFeed(openEvents);

    final career = uid == null ? null : ref.watch(careerProvider(uid));
    final lines = career?.valueOrNull ?? const [];
    final matchesPlayed = lines.fold<int>(0, (s, l) => s + l.matchesPlayed);
    final sportsPlayed = lines.where((l) => l.matchesPlayed > 0).length;

    // The first club where this person could actually create something. Drives
    // the quick action and the floating button: offering "New event" to a
    // member who cannot create one is offering a permission error.
    final organizingOrgId = clubs
        .map((m) => m.orgId)
        .where(
          (id) => ref
              .watch(myCapabilitiesProvider(id))
              .contains(Capability.manageCompetitions),
        )
        .firstOrNull;

    return ConfirmExit(
      child: AppScaffold(
        title: 'Home',
        subtitle: clubs.isEmpty
            ? 'Your sports, in one place'
            : '${clubs.length} ${clubs.length == 1 ? 'club' : 'clubs'}',
        floatingActionButton: organizingOrgId == null
            ? null
            : FloatingActionButton.extended(
                onPressed: () =>
                    context.push(Routes.createCompetition(organizingOrgId)),
                icon: const Icon(Icons.add),
                label: const Text('New event'),
              ),
        body: AsyncView(
          value: memberships,
          onRetry: () => ref.invalidate(myMembershipsProvider),
          builder: (activeClubs) {
            return ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                ContentBounds(
                  maxWidth: 1100,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Greeting(
                        clubCount: activeClubs.length,
                        liveCount: live.length,
                      ),
                      const SizedBox(height: 14),

                      // Directly under the banner, above everything else on
                      // the dashboard — including the live ticker.
                      //
                      // Position is the feature here. Every other section
                      // reports something that has already happened or is
                      // happening without you; this one is a question
                      // addressed to this person that expires. A member who
                      // scrolls past it on Friday has not delayed a decision,
                      // they have missed Sunday's game — which is precisely
                      // the failure the WhatsApp poll it replaces does not
                      // have, because a phone puts that at the top by itself.
                      //
                      // Draws nothing at all for a member whose clubs do not
                      // use it, so the cost of the position is zero for
                      // everybody it does not serve. See [MatchRsvpSection].
                      const MatchRsvpSection(),

                      // Points at the talent search rather than at a global
                      // one. There is no index behind "matches, teams,
                      // players and clubs" yet, and a box that accepts a
                      // query and returns nothing is worse than a box that
                      // says what it actually searches.
                      PsSearchField(
                        hint: 'Search players, teams and clubs...',
                        readOnly: true,
                        onTap: () => context.push(Routes.scoutSearch),
                      ),
                      const SizedBox(height: 4),

                      // --- PS-007: Live Matches Ticker at top (Cricbuzz style) ---
                      //
                      // Capped at 3: a member in half a dozen clubs during a
                      // busy weekend could otherwise push everything else on
                      // this dashboard — clubs, events, the rest of the
                      // product — below several screens of scorecards. The
                      // "More" button is not a consolation prize for what got
                      // cut; every match still live is one tap away on
                      // Routes.liveNow, in full, grouped the same way.
                      SectionHeader(
                        icon: Icons.sensors,
                        title: 'Live now',
                        subtitle: 'Every match your clubs are playing, ball by ball',
                        trailing: live.isEmpty ? null : const LiveDot(),
                      ),
                      AsyncErrorStrip(value: liveAsync, what: 'live matches'),
                      // A club whose read was refused no longer blanks the
                      // whole section (Bug #4) — but it must not vanish
                      // either, or a player is told nothing is on at a club
                      // where a match is being played.
                      if (liveFailures > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: QuietCard(
                            icon: Icons.cloud_off_outlined,
                            title: liveFailures == 1
                                ? 'One club’s matches could not be loaded'
                                : '$liveFailures clubs’ matches could not be '
                                    'loaded',
                            message: 'Everything below is up to date. If this '
                                'keeps happening, please report it.',
                          ),
                        ),
                      if (live.isEmpty)
                        const QuietCard(
                          icon: Icons.sensors_off_outlined,
                          title: 'No live matches right now',
                          message: 'Matches scored by your clubs appear here live for everyone.',
                        )
                      else ...[
                        for (final f in live.take(_liveHomePreviewCap))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _LiveFixture(fixture: f),
                          ),
                        if (live.length > _liveHomePreviewCap)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: OutlinedButton.icon(
                              onPressed: () => context.push(Routes.liveNow),
                              icon: const Icon(Icons.sensors, size: 18),
                              label: Text(
                                'More · ${live.length - _liveHomePreviewCap} '
                                'more live',
                              ),
                            ),
                          ),
                      ],

                      // Below the live scores, never above them.
                      //
                      // The first thing on this screen has to be the person's
                      // own sport. An advert that pushes a match somebody is
                      // playing right now further down the page is not worth
                      // whatever it earns — and the "More live" button ending
                      // up below the fold because of a banner is exactly the
                      // kind of harm that never shows up in ad revenue.
                      //
                      // Renders nothing at all for Premium members.
                      const PromoBanner(
                        slot: PromoSlot.home,
                        margin: EdgeInsets.only(top: 4, bottom: 8),
                      ),

                      // Clubmates playing somewhere else — a member turning
                      // out for a district side or a college team. Scoped by
                      // who is on the team sheet rather than by whose
                      // competition it is, which is the only way these ever
                      // reach the people who know them.
                      if (clubmateLive.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const SectionHeader(
                          icon: Icons.groups_2_outlined,
                          title: 'Your clubmates, elsewhere',
                          subtitle: 'Playing for other clubs and teams '
                              'right now',
                          trailing: LiveDot(),
                        ),
                        for (final f in clubmateLive)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _LiveFixture(fixture: f),
                          ),
                      ],

                      // Below the live scores, deliberately — the same rule
                      // the promo banner above follows. The sample design put
                      // this grid directly under the banner, which on a 320pt
                      // phone pushes a match being played right now off the
                      // first screen. Browsing sports is something a member
                      // does when nothing of theirs is on; it must not cost
                      // them the thing they opened the app for.
                      PsSectionHeader(
                        title: 'Explore Sports',
                        onAction: () => context.push(Routes.sports),
                      ),
                      const _ExploreSportsGrid(),
                      const SizedBox(height: 16),

                      // --- PS-006 & PS-009: Primary Hero Action CTA ("Play Match Now") ---
                      //
                      // No side icon: it was a fixed cricket bat-and-ball
                      // glyph shown to every sport's players regardless of
                      // what they actually play — wrong far more often than
                      // right, and a decoration, not information. The text
                      // and the button carry the card on their own.
                      // The whole card is the target, not just the button on
                      // its right. The tagline underneath — "Score a casual
                      // match or tournament game in seconds" — is gone for the
                      // same reason: `Play Match Now` beside a play glyph
                      // already says it, and the sentence was the only thing
                      // making the card tall enough to look like it needed a
                      // separate button to act on.
                      Builder(
                        builder: (context) {
                          void start() {
                            final pId = ref.read(primaryOrgIdProvider);
                            if (pId != null) {
                              context.push(Routes.quickMatch(pId));
                            } else if (activeClubs.isNotEmpty) {
                              context.push(
                                Routes.quickMatch(activeClubs.first.orgId),
                              );
                            } else {
                              context.push(Routes.orgs);
                            }
                          }

                          return Material(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              onTap: start,
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(18, 16, 16, 16),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.play_circle_fill,
                                      size: 26,
                                      color: theme
                                          .colorScheme.onPrimaryContainer,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Play Match Now',
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: theme
                                              .colorScheme.onPrimaryContainer,
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      Icons.chevron_right,
                                      size: 20,
                                      color: theme
                                          .colorScheme.onPrimaryContainer,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),

                      _StatTiles(
                        clubs: activeClubs.length,
                        live: live.length,
                        events: events.length,
                        matches: matchesPlayed,
                        sports: sportsPlayed,
                        primaryOrgId: ref.watch(primaryOrgIdProvider),
                      ),
                      const SizedBox(height: 24),

                      // --- The clubs they belong to ---------------------------
                      SectionHeader(
                        icon: Icons.groups_2_outlined,
                        title: 'My clubs',
                        subtitle: 'Your record follows you across every one of '
                            'them, for life',
                        trailing: TextButton.icon(
                          onPressed: () => context.push(Routes.joinOrg),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Join'),
                        ),
                      ),
                      if (activeClubs.isEmpty)
                        const _NoClubsCard()
                      else
                        for (final m in activeClubs)
                          _ClubCard(orgId: m.orgId, role: m.role),
                      const SizedBox(height: 24),

                      // --- What is coming up ----------------------------------
                      const SectionHeader(
                        icon: Icons.emoji_events_outlined,
                        title: 'Events & tournaments',
                        subtitle: 'Open for entries, right now',
                      ),
                      AsyncErrorStrip(value: eventsAsync, what: 'events'),
                      if (openEvents.isEmpty)
                        QuietCard(
                          icon: Icons.calendar_month_outlined,
                          title: 'Nothing open for entries right now',
                          message: organizingOrgId == null
                              ? 'When your club opens entries for something, it '
                                  'shows up here.'
                              : 'Create one — pick a sport, set the age '
                                  'category, and open entries.',
                          action: organizingOrgId == null
                              ? null
                              : FilledButton.icon(
                                  onPressed: () => context.push(
                                    Routes.createCompetition(organizingOrgId),
                                  ),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Create an event'),
                                ),
                        )
                      else ...[
                        for (final item in openFeed.take(_eventsHomePreviewCap))
                          switch (item) {
                            EventFeedSingle(:final competition) =>
                              EventCard(competition: competition),
                            EventFeedSeason(
                              :final orgId,
                              :final tournamentId,
                              :final competitions
                            ) =>
                              SeasonCard(
                                orgId: orgId,
                                tournamentId: tournamentId,
                                competitions: competitions,
                              ),
                          },
                        if (openFeed.length > _eventsHomePreviewCap)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: OutlinedButton.icon(
                              onPressed: () => context.push(Routes.myEvents),
                              icon: const Icon(Icons.emoji_events_outlined,
                                  size: 18),
                              label: Text(
                                'More · ${openFeed.length - _eventsHomePreviewCap} '
                                'more open',
                              ),
                            ),
                          ),
                      ],
                      const SizedBox(height: 24),

                      // --- Everything else the product does -------------------
                      const SectionHeader(
                        icon: Icons.explore_outlined,
                        title: 'Explore',
                        subtitle: 'The rest of PlaySphere — also in the menu, '
                            'top left',
                      ),
                      _ExploreGrid(
                        primaryOrgId: ref.watch(primaryOrgIdProvider),
                        canSeeAnalytics: activeClubs.any(
                          (m) => ref
                              .watch(myCapabilitiesProvider(m.orgId))
                              .contains(Capability.viewAnalytics),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

/// The date and a one-line status — deliberately not a "Good evening, Name"
/// salutation. That used to be the single largest thing on the dashboard
/// (a headline-sized line plus a name that can run long) for a fact the
/// member already knows: who they are. The date and what is live now are
/// the two things actually worth the space.
class _Greeting extends StatelessWidget {
  const _Greeting({
    required this.clubCount,
    required this.liveCount,
  });

  final int clubCount;
  final int liveCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: AppTheme.brandGradient,
        borderRadius: BorderRadius.circular(Ps.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat('EEEE, d MMMM').format(DateTime.now()),
            style: theme.textTheme.labelMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          // The mockup's masthead line. Kept to two short words a line so it
          // holds its shape at 320pt — the banner is the first thing on the
          // screen, and a headline that reflows to four ragged lines on a
          // small phone is the first thing anyone sees go wrong.
          Text(
            'ALL SPORTS\nONE SPACE',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              height: 1.1,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Play. Compete. Achieve.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          // The status sentence stays. The mockup's banner is pure brand
          // copy, but this line is the one piece of the old header that told
          // a member something they did not already know — how many of their
          // matches are being played right now.
          Text(
            clubCount == 0
                ? 'Join a club with an invite code and everything you play '
                    'starts counting.'
                : liveCount > 0
                    ? '$liveCount ${liveCount == 1 ? 'match is' : 'matches are'}'
                        ' being played right now across your clubs.'
                    : 'Nothing live at the moment. Your clubs, events and '
                        'record are all below.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.92),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// The five-across run of sport tiles under the banner.
///
/// Nine sports and a "More", not the whole catalogue. The catalogue is
/// fifteen entries and growing, and a grid that runs to three rows pushes the
/// live scores — the thing a member opened the app for — off the first
/// screen. "More" opens the full directory, where the counts and the filters
/// live.
class _ExploreSportsGrid extends StatelessWidget {
  const _ExploreSportsGrid();

  /// Deliberately hand-picked rather than `SportCatalog.all.take(9)`. The
  /// catalogue is ordered by how the scoring engines group sports — bat and
  /// ball, racquet, goal-scoring — so taking the first nine yields an
  /// arbitrary set that changes whenever a sport is added. These are the nine
  /// played most widely across Indian schools and clubs.
  static const _featured = [
    'cricket',
    'football',
    'badminton',
    'volleyball',
    'basketball',
    'table_tennis',
    'tennis',
    'kabaddi',
    'chess',
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Five across on a phone, more on a tablet where the same tile size
        // would otherwise leave half the row empty.
        final columns = (constraints.maxWidth / 78).floor().clamp(4, 8);
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 14,
          crossAxisSpacing: 8,
          childAspectRatio: 0.82,
          children: [
            for (final id in _featured)
              _SportTile(
                sportId: id,
                label: SportCatalog.byId(id).name,
                onTap: () => context.push(Routes.sports),
              ),
            _SportTile(
              sportId: null,
              label: 'More',
              onTap: () => context.push(Routes.sports),
            ),
          ],
        );
      },
    );
  }
}

class _SportTile extends StatelessWidget {
  const _SportTile({
    required this.sportId,
    required this.label,
    required this.onTap,
  });

  /// Null renders the neutral "More" tile that opens the directory.
  final String? sportId;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final id = sportId;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Ps.radiusSm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (id == null)
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Ps.border,
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(Icons.more_horiz, color: Ps.muted, size: 22),
            )
          else
            SportBadge(sportId: id, size: 46),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Ps.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTiles extends StatelessWidget {
  const _StatTiles({
    required this.clubs,
    required this.live,
    required this.events,
    required this.matches,
    required this.sports,
    required this.primaryOrgId,
  });

  final int clubs;
  final int live;
  final int events;
  final int matches;
  final int sports;
  final String? primaryOrgId;

  @override
  Widget build(BuildContext context) {
    final orgId = primaryOrgId;
    return AdaptiveGrid(
      // Three across on a phone rather than two, at a fixed height rather
      // than an aspect ratio: five counters used to run to three rows and
      // ~290px before the first piece of actual content.
      minTileWidth: 116,
      tileHeight: 82,
      spacing: 10,
      children: [
        _Tile(
          icon: Icons.groups_2_outlined,
          value: '$clubs',
          label: 'Clubs',
          onTap: () => context.push(Routes.orgs),
        ),
        _Tile(
          icon: Icons.sensors,
          value: '$live',
          label: 'Live now',
          highlight: live > 0,
          // Global, not the primary club's own live page: this counter is a
          // sum across every club, so it must open the same cross-club list
          // it is counting rather than just one of them.
          onTap: () => context.push(Routes.liveNow),
        ),
        _Tile(
          icon: Icons.emoji_events_outlined,
          value: '$events',
          label: 'Events',
          onTap: orgId == null ? null : () => context.push(Routes.org(orgId)),
        ),
        // Two counters, two destinations. Both of these pushed `/me` — so a
        // tile reading "31 Matches" and a tile reading "4 Sports" opened the
        // same profile page and neither showed what it had just counted.
        _Tile(
          icon: Icons.sports_score,
          value: '$matches',
          label: 'Matches',
          onTap: () => context.push(Routes.myMatches),
        ),
        _Tile(
          icon: Icons.sports_handball_outlined,
          value: '$sports',
          label: sports == 1 ? 'Sport' : 'Sports',
          onTap: () => context.push(Routes.mySports),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.value,
    required this.label,
    this.highlight = false,
    this.onTap,
  });

  final IconData icon;
  final String value;
  final String label;
  final bool highlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tint = highlight ? scheme.onErrorContainer : null;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: highlight ? scheme.errorContainer : null,
      child: InkWell(
        onTap: onTap,
        child: Semantics(
          label: '$value $label',
          button: onTap != null,
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            // The tile is a fixed height, so its contents must be prepared to
            // be shrunk rather than to overflow. That is not only about
            // getting the arithmetic right here: a player who has set their
            // phone's font size to 1.5x — on a ₹8k device with a small screen,
            // a common setting rather than an edge case — grows every line in
            // this column and would otherwise strike out the whole row.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: tint ?? theme.hintColor),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: tint,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(color: tint),
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sections
// ---------------------------------------------------------------------------

/// A live match with the club it belongs to named above it.
///
/// The club name is the part the shared org-scoped screens can leave out and
/// this one cannot: on a dashboard spanning four clubs, a scoreline with no
/// club attached is a scoreline you cannot place.
class _LiveFixture extends ConsumerWidget {
  const _LiveFixture({required this.fixture});

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
            child: Text(
              org.name,
              style: Theme.of(context).textTheme.labelSmall,
            ),
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

/// One club, with enough on it to be worth reading: what type it is, what this
/// person is in it, how many people are in it, and what it has on right now.
class _ClubCard extends ConsumerWidget {
  const _ClubCard({required this.orgId, required this.role});

  final String orgId;
  final MembershipRole role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final org = ref.watch(organizationProvider(orgId)).valueOrNull;
    final live = ref.watch(liveFixturesProvider(orgId)).valueOrNull ?? const [];
    final comps =
        ref.watch(competitionsProvider(orgId)).valueOrNull ?? const [];
    final caps = ref.watch(myCapabilitiesProvider(orgId));

    final running =
        comps.where((c) => c.status == CompetitionStatus.inProgress).length;
    // Derived status, so an event whose deadline has passed stops being
    // counted as open for entries the moment it passes (Bug #6).
    final open = comps
        .where((c) => c.displayStatus() == CompetitionStatus.registrationOpen)
        .length;

    final where = [
      org?.geo.district ?? org?.district,
      org?.geo.state,
    ].whereType<String>().where((s) => s.isNotEmpty).join(', ');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(Routes.org(orgId)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundImage: org?.logoUrl != null
                        ? NetworkImage(org!.logoUrl!)
                        : null,
                    child: org?.logoUrl != null
                        ? null
                        : Text(
                            (org?.name ?? '?').characters.first.toUpperCase(),
                            style: theme.textTheme.titleMedium,
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          org?.name ?? 'Loading…',
                          style: theme.textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          [
                            if (org != null) org.orgType.label,
                            if (where.isNotEmpty) where,
                          ].join(' · '),
                          style: theme.textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (live.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${live.length} LIVE',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Pill(label: role.label, icon: Icons.badge_outlined),
                  if (org != null)
                    _Pill(
                      label: '${org.memberCount} members',
                      icon: Icons.people_outline,
                    ),
                  _Pill(
                    label: '${comps.length} events',
                    icon: Icons.emoji_events_outlined,
                  ),
                  if (running > 0)
                    _Pill(label: '$running running', icon: Icons.play_arrow),
                  if (open > 0)
                    _Pill(
                      label: '$open open for entries',
                      icon: Icons.how_to_reg_outlined,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => context.push(Routes.org(orgId)),
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: const Text('Open club'),
                  ),
                  TextButton.icon(
                    onPressed: () => context.push(Routes.live(orgId)),
                    icon: const Icon(Icons.sensors, size: 18),
                    label: const Text('Live'),
                  ),
                  if (caps.contains(Capability.manageMembers))
                    TextButton.icon(
                      onPressed: () => context.push(Routes.members(orgId)),
                      icon: const Icon(Icons.people_outline, size: 18),
                      label: const Text('Members'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.hintColor),
          const SizedBox(width: 5),
          Text(label, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

/// An event or tournament card: sport, category, entry count and status.
///
/// Public — [MyEventsScreen] reuses it verbatim for the full cross-club list
/// the home screen's "More" button opens, so the two never drift apart.
class EventCard extends ConsumerWidget {
  const EventCard({super.key, required this.competition});

  final Competition competition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = competition;
    final org = ref.watch(organizationProvider(c.orgId)).valueOrNull;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          child: Text(
            SportCatalog.byId(c.sportId).icon,
            style: const TextStyle(fontSize: 18),
          ),
        ),
        title: Text(c.name),
        subtitle: Text(
          [
            if (org != null) org.name,
            c.sportName,
            c.category.label,
            '${c.entrantCount} entered',
            if (c.startDate != null) friendlyDate(c.startDate!),
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        trailing: _StatusChip(status: c.displayStatus()),
        onTap: () => context.push(Routes.competition(c.orgId, c.id)),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final CompetitionStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (status) {
      CompetitionStatus.registrationOpen => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer
        ),
      CompetitionStatus.inProgress => (
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer
        ),
      _ => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _NoClubsCard extends StatelessWidget {
  const _NoClubsCard();

  @override
  Widget build(BuildContext context) {
    return QuietCard(
      icon: Icons.groups_outlined,
      title: 'You are not in a club yet',
      message: 'Join your school, college, village or community with the '
          'six-letter invite code — or create one and invite people with a '
          'code of your own. Everything you play from then on is recorded '
          'against your name for good.',
      action: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          FilledButton.icon(
            onPressed: () => context.push(Routes.joinOrg),
            icon: const Icon(Icons.vpn_key_outlined),
            label: const Text('Join with a code'),
          ),
          OutlinedButton.icon(
            onPressed: () => context.push(Routes.createOrg),
            icon: const Icon(Icons.add),
            label: const Text('Create a club'),
          ),
        ],
      ),
    );
  }
}

/// A "nothing here yet" card that still says what would put something here.
/// The modules that are not on the bar: what they are, and where they go.
class _ExploreGrid extends StatelessWidget {
  const _ExploreGrid({
    required this.primaryOrgId,
    required this.canSeeAnalytics,
  });

  final String? primaryOrgId;
  final bool canSeeAnalytics;

  @override
  Widget build(BuildContext context) {
    return AdaptiveGrid(
      // A fixed 64 rather than a 2.4 ratio. One column on a phone meant a
      // 388px-wide tile was 162px tall — six of them ran to a thousand
      // pixels of near-empty card for what is a list of six links.
      minTileWidth: 250,
      tileHeight: 64,
      spacing: 10,
      children: [
        if (canSeeAnalytics && primaryOrgId != null)
          _ExploreTile(
            icon: Icons.insights_outlined,
            title: 'Analytics',
            body: 'Who plays what, how often, and how your club is growing',
            onTap: () => context.push(Routes.analytics(primaryOrgId!)),
          ),
        _ExploreTile(
          icon: Icons.badge_outlined,
          title: 'Career profile',
          body: 'Every match, rating and memory — portable for life',
          onTap: () => context.push(Routes.myProfile),
        ),
        _ExploreTile(
          icon: Icons.campaign_outlined,
          title: 'Looking for',
          body: 'Find players, teams, scorers, umpires and grounds',
          onTap: () => context.push(Routes.lookingFor),
        ),
        _ExploreTile(
          icon: Icons.sports,
          title: 'Officials registry',
          body: 'Register as an umpire or scorer, or find one',
          onTap: () => context.push(Routes.umpireRegistry),
        ),
        // Rules library is deliberately NOT here (Bug #7). It is reference
        // material somebody consults once a season, not something a home
        // screen should spend a tile on. It lives in the module menu behind
        // the three lines, which is where the entry already was — this tile
        // was a duplicate of it competing for the most valuable space in the
        // app.
        if (primaryOrgId != null)
          _ExploreTile(
            icon: Icons.sports_kabaddi_outlined,
            title: 'Challenges',
            body: 'Play another club — propose, accept, schedule',
            onTap: () => context.push(Routes.challenges(primaryOrgId!)),
          ),
      ],
    );
  }
}

class _ExploreTile extends StatelessWidget {
  const _ExploreTile({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
          child: Row(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      body,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Says "this opens something" without costing a line of text.
              Icon(Icons.chevron_right, size: 20, color: theme.hintColor),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Today", "Tomorrow", or a date — a scorer reading a fixture list at a
/// ground cares which of those it is far more than the calendar date.
