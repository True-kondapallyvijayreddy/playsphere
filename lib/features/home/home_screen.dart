import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/competition.dart';
import '../../core/models/enums.dart';
import '../../core/models/fixture.dart';
import '../../core/models/scoring_request.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/confirm_exit.dart';
import '../../shared/live_dot.dart';
import '../scoring/widgets/live_score_card.dart';
import 'home_providers.dart';

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
    final user = ref.watch(currentUserProvider).valueOrNull;
    final uid = ref.watch(currentUidProvider);
    final memberships = ref.watch(myActiveMembershipsProvider);
    final clubs = memberships.valueOrNull ?? const [];

    final liveAsync = ref.watch(myLiveFixturesProvider);
    final live = liveAsync.valueOrNull ?? const <Fixture>[];
    final eventsAsync = ref.watch(myUpcomingEventsProvider);
    final events = eventsAsync.valueOrNull ?? const <Competition>[];

    final scoringAsync = ref.watch(myScoringAssignmentsProvider);
    final scoring = scoringAsync.valueOrNull ?? const <Fixture>[];
    final challengesAsync = ref.watch(myIncomingChallengesProvider);
    final challenges = challengesAsync.valueOrNull ?? const [];
    final approvalsAsync = ref.watch(myPendingApprovalsProvider);
    final approvals = approvalsAsync.valueOrNull ?? const [];
    final scoreAsksAsync = ref.watch(myScoringRequestsProvider);
    final scoreAsks = scoreAsksAsync.valueOrNull ?? const <ScoringRequest>[];

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
                        name: user?.displayName,
                        clubCount: activeClubs.length,
                        liveCount: live.length,
                      ),
                      const SizedBox(height: 16),

                      _QuickActions(organizingOrgId: organizingOrgId),
                      const SizedBox(height: 20),

                      _StatTiles(
                        clubs: activeClubs.length,
                        live: live.length,
                        events: events.length,
                        matches: matchesPlayed,
                        sports: sportsPlayed,
                        primaryOrgId: ref.watch(primaryOrgIdProvider),
                      ),
                      const SizedBox(height: 24),

                      // --- What is waiting on this person ---------------------
                      AsyncErrorStrip(
                        value: scoringAsync,
                        what: 'the matches you are scoring',
                      ),
                      AsyncErrorStrip(
                        value: challengesAsync,
                        what: 'challenges from other clubs',
                      ),
                      AsyncErrorStrip(
                        value: approvalsAsync,
                        what: 'join requests',
                      ),
                      AsyncErrorStrip(
                        value: scoreAsksAsync,
                        what: 'requests to score a match',
                      ),
                      if (scoring.isNotEmpty ||
                          challenges.isNotEmpty ||
                          approvals.isNotEmpty ||
                          scoreAsks.isNotEmpty) ...[
                        const _SectionHeader(
                          icon: Icons.pending_actions_outlined,
                          title: 'Waiting on you',
                          subtitle: 'Nothing here moves until somebody acts',
                        ),
                        for (final f in scoring)
                          _ActionCard(
                            icon: Icons.sports_cricket_outlined,
                            tone: _Tone.primary,
                            title: f.isLive
                                ? 'You are scoring ${f.entrantAName} v '
                                    '${f.entrantBName}'
                                : 'You are down to score ${f.entrantAName} v '
                                    '${f.entrantBName}',
                            subtitle: [
                              if (f.roundLabel != null) f.roundLabel!,
                              if (f.venue != null) f.venue!,
                              if (f.scheduledAt != null)
                                _friendlyDate(f.scheduledAt!),
                            ].join(' · '),
                            actionLabel: f.isLive ? 'Resume' : 'Open',
                            onTap: () => context
                                .push(Routes.scoring(f.orgId, f.compId, f.id)),
                          ),
                        for (final c in challenges)
                          _ActionCard(
                            icon: Icons.sports_kabaddi_outlined,
                            tone: _Tone.tertiary,
                            title: 'A club has challenged you',
                            subtitle: '${c.fromOrgName} · '
                                '${SportCatalog.byId(c.sportId).name}',
                            actionLabel: 'Answer',
                            onTap: () =>
                                context.push(Routes.challenges(c.toOrgId)),
                          ),
                        // Above join requests on purpose: a match may be about
                        // to start, and an unanswered request to score it means
                        // a match nobody records. A join request can wait a day.
                        for (final r in scoreAsks)
                          _ScoringRequestCard(request: r),
                        if (approvals.isNotEmpty)
                          _ActionCard(
                            icon: Icons.person_add_alt,
                            tone: _Tone.tertiary,
                            title: '${approvals.length} '
                                '${approvals.length == 1 ? 'person is' : 'people are'}'
                                ' waiting to join',
                            subtitle: 'They cannot play or be picked until you '
                                'approve them',
                            actionLabel: 'Review',
                            onTap: () => context
                                .push(Routes.members(approvals.first.orgId)),
                          ),
                        const SizedBox(height: 20),
                      ],

                      // --- Live now -------------------------------------------
                      _SectionHeader(
                        icon: Icons.sensors,
                        title: 'Live now',
                        subtitle: 'Every match your clubs are playing, ball by '
                            'ball',
                        trailing: live.isEmpty ? null : const LiveDot(),
                      ),
                      AsyncErrorStrip(value: liveAsync, what: 'live matches'),
                      if (live.isEmpty)
                        const _QuietCard(
                          icon: Icons.sensors_off_outlined,
                          title: 'Nothing is being played right now',
                          message: 'The moment a scorer starts a match it '
                              'appears here — and anyone you send the link to '
                              'can follow it without installing anything.',
                        )
                      else
                        for (final f in live)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _LiveFixture(fixture: f),
                          ),
                      const SizedBox(height: 24),

                      // --- The clubs they belong to ---------------------------
                      _SectionHeader(
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
                      const _SectionHeader(
                        icon: Icons.emoji_events_outlined,
                        title: 'Events & tournaments',
                        subtitle:
                            'Open for entries, scheduled, or being played',
                      ),
                      AsyncErrorStrip(value: eventsAsync, what: 'events'),
                      if (events.isEmpty)
                        _QuietCard(
                          icon: Icons.calendar_month_outlined,
                          title: 'No events on right now',
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
                      else
                        for (final c in events.take(8))
                          _EventCard(competition: c),
                      const SizedBox(height: 24),

                      // --- Everything else the product does -------------------
                      const _SectionHeader(
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

class _Greeting extends StatelessWidget {
  const _Greeting({
    required this.name,
    required this.clubCount,
    required this.liveCount,
  });

  final String? name;
  final int clubCount;
  final int liveCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hour = DateTime.now().hour;
    final part = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    final first = (name ?? '').split(' ').first;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      decoration: BoxDecoration(
        gradient: AppTheme.brandGradient,
        borderRadius: BorderRadius.circular(18),
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
          const SizedBox(height: 6),
          Text(
            first.isEmpty ? part : '$part, $first',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
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
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends ConsumerWidget {
  const _QuickActions({required this.organizingOrgId});

  final String? organizingOrgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Any club will do, not only one this person can organize in: a quick
    // match needs no authority beyond membership, which is the whole point of
    // it. `organizingOrgId` still exists for the event actions above.
    final anyOrgId = ref.watch(primaryOrgIdProvider);

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        if (anyOrgId != null)
          ActionChip(
            avatar: const Icon(Icons.sports_score, size: 18),
            label: const Text('Play a match now'),
            onPressed: () => context.push(Routes.quickMatch(anyOrgId)),
          ),
        ActionChip(
          avatar: const Icon(Icons.vpn_key_outlined, size: 18),
          label: const Text('Join a club'),
          onPressed: () => context.push(Routes.joinOrg),
        ),
        ActionChip(
          avatar: const Icon(Icons.add_business_outlined, size: 18),
          label: const Text('Create a club'),
          onPressed: () => context.push(Routes.createOrg),
        ),
        ActionChip(
          avatar: const Icon(Icons.campaign_outlined, size: 18),
          label: const Text('Looking for players'),
          onPressed: () => context.push(Routes.lookingFor),
        ),
        ActionChip(
          avatar: const Icon(Icons.menu_book_outlined, size: 18),
          label: const Text('Rules'),
          onPressed: () => context.push(Routes.rules),
        ),
        ActionChip(
          avatar: const Icon(Icons.badge_outlined, size: 18),
          label: const Text('My profile'),
          onPressed: () => context.push(Routes.myProfile),
        ),
      ],
    );
  }
}

/// The counters under the greeting.
///
/// Each one is a door, not an ornament: a number that says "3 live" and does
/// nothing when pressed reads as a broken button, and every one of these has
/// an obvious page behind it. The two that are org-scoped are inert only when
/// the person has no club for them to point at, in which case the number is
/// zero anyway.
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
          onTap: orgId == null ? null : () => context.push(Routes.live(orgId)),
        ),
        _Tile(
          icon: Icons.emoji_events_outlined,
          value: '$events',
          label: 'Events',
          onTap: orgId == null ? null : () => context.push(Routes.org(orgId)),
        ),
        _Tile(
          icon: Icons.sports_score,
          value: '$matches',
          label: 'Matches',
          onTap: () => context.push(Routes.myProfile),
        ),
        _Tile(
          icon: Icons.sports_handball_outlined,
          value: '$sports',
          label: sports == 1 ? 'Sport' : 'Sports',
          onTap: () => context.push(Routes.myProfile),
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

enum _Tone { primary, tertiary }

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
    required this.tone,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onTap;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (tone) {
      _Tone.primary => (scheme.primaryContainer, scheme.onPrimaryContainer),
      _Tone.tertiary => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: bg,
      child: ListTile(
        leading: Icon(icon, color: fg),
        title: Text(
          title,
          style: TextStyle(color: fg, fontWeight: FontWeight.w600),
        ),
        subtitle: subtitle.isEmpty
            ? null
            : Text(subtitle, style: TextStyle(color: fg)),
        trailing: TextButton(onPressed: onTap, child: Text(actionLabel)),
        onTap: onTap,
      ),
    );
  }
}

/// "Ravi wants to score Blue House v Red House" — approve or not, from here.
///
/// Deliberately decided in place rather than behind a tap through to the
/// match. The admin is often not at the ground and the match may be starting;
/// making them navigate two screens to say yes is how a request goes
/// unanswered until after the game.
class _ScoringRequestCard extends ConsumerStatefulWidget {
  const _ScoringRequestCard({required this.request});

  final ScoringRequest request;

  @override
  ConsumerState<_ScoringRequestCard> createState() =>
      _ScoringRequestCardState();
}

class _ScoringRequestCardState extends ConsumerState<_ScoringRequestCard> {
  bool _busy = false;

  Future<void> _decide({required bool approve}) async {
    final me = ref.read(currentUidProvider);
    if (me == null || _busy) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(competitionRepositoryProvider);
      if (approve) {
        await repo.approveScoringRequest(
          request: widget.request,
          decidedByUid: me,
        );
      } else {
        await repo.declineScoringRequest(
          request: widget.request,
          decidedByUid: me,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              approve
                  ? '${widget.request.displayName} can now score this match.'
                  : 'Request declined.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = widget.request;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sports_outlined, color: scheme.onPrimaryContainer),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${r.displayName} wants to score',
                        style: TextStyle(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        r.matchLabel.isEmpty ? 'a match' : r.matchLabel,
                        style: TextStyle(color: scheme.onPrimaryContainer),
                      ),
                      if (r.note != null && r.note!.isNotEmpty)
                        Text(
                          '“${r.note}”',
                          style: TextStyle(
                            color: scheme.onPrimaryContainer,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Wrap, not Row: "Let them score" is a long label next to a
            // second button on a 420px screen, and it has to survive both a
            // narrow phone and a reader who has turned their font size up.
            // It stacks rather than overflowing.
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => _decide(approve: false),
                  child: const Text('Not now'),
                ),
                FilledButton(
                  onPressed: _busy ? null : () => _decide(approve: true),
                  child: Text(_busy ? 'Working…' : 'Let them score'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

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
    final open = comps
        .where((c) => c.status == CompetitionStatus.registrationOpen)
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

class _EventCard extends ConsumerWidget {
  const _EventCard({required this.competition});

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
            if (c.startDate != null) _friendlyDate(c.startDate!),
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        trailing: _StatusChip(status: c.status),
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
    return _QuietCard(
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
class _QuietCard extends StatelessWidget {
  const _QuietCard({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.hintColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(message, style: theme.textTheme.bodySmall),
            if (action != null) ...[
              const SizedBox(height: 14),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

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
        _ExploreTile(
          icon: Icons.menu_book_outlined,
          title: 'Rules library',
          body: 'ICC, FIFA, FIBA, BWF, PKL and more, searchable',
          onTap: () => context.push(Routes.rules),
        ),
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
String _friendlyDate(DateTime when) {
  final now = DateTime.now();
  final day = DateTime(when.year, when.month, when.day);
  final today = DateTime(now.year, now.month, now.day);
  final delta = day.difference(today).inDays;

  final time = DateFormat.jm().format(when);
  return switch (delta) {
    0 => 'Today, $time',
    1 => 'Tomorrow, $time',
    -1 => 'Yesterday, $time',
    _ => DateFormat('d MMM').format(when),
  };
}
