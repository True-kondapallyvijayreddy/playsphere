import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/competition.dart';
import '../../core/models/enums.dart';
import '../../core/models/organization.dart';
import '../../core/models/sub_group.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/live_dot.dart';
import '../../shared/ui_kit.dart';
import '../home/event_feed.dart';
import '../scoring/widgets/live_score_card.dart';

class OrgHomeScreen extends ConsumerWidget {
  const OrgHomeScreen({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(myCapabilitiesProvider(orgId));
    final canCreate = caps.contains(Capability.manageCompetitions);
    // Owner or admin — matches what `firestore.rules` actually lets write
    // descriptive fields like the home ground; `manageOrganization` alone
    // would hide the button from an admin whose write the rule permits.
    final canManage = caps.contains(Capability.manageOrganization) ||
        caps.contains(Capability.manageMembers);
    final competitions = ref.watch(competitionsProvider(orgId));
    final liveAsync = ref.watch(liveFixturesProvider(orgId));
    final pendingAsync = ref.watch(pendingMembersProvider(orgId));
    final org = ref.watch(organizationProvider(orgId)).valueOrNull;
    final live = liveAsync.valueOrNull ?? const [];
    final pending = pendingAsync.valueOrNull ?? const [];

    return AppScaffold(
      orgId: orgId,
      title: 'Home',
      actions: canManage
          ? [
              IconButton(
                tooltip: 'Club settings',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => context.push(Routes.clubSettings(orgId)),
              ),
            ]
          : null,
      // Two buttons, and the smaller one is the more used. Starting a match
      // between people who are already standing on the ground is the single
      // most common thing a club does; running a tournament is the rarer,
      // heavier act, so it keeps the labelled button and quick match takes the
      // one beside it.
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'quick-match',
            tooltip: 'Quick match — play now',
            onPressed: () => context.push(Routes.quickMatch(orgId)),
            child: const Icon(Icons.sports_score),
          ),
          const SizedBox(height: 12),
          if (canCreate)
            FloatingActionButton.extended(
              heroTag: 'new-event',
              onPressed: () => context.push(Routes.createCompetition(orgId)),
              icon: const Icon(Icons.add),
              label: const Text('New event'),
            ),
        ],
      ),
      body: AsyncView(
        value: competitions,
        builder: (comps) {
          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              ContentBounds(
                maxWidth: 980,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (org != null)
                      _ClubHeader(
                        orgId: orgId,
                        org: org,
                        competitions: comps,
                      ),
                    AsyncErrorStrip(
                      value: liveAsync,
                      what: 'live matches',
                    ),
                    if (caps.contains(Capability.manageMembers))
                      AsyncErrorStrip(
                        value: pendingAsync,
                        what: 'join requests',
                      ),
                    if (pending.isNotEmpty &&
                        caps.contains(Capability.manageMembers))
                      Card(
                        color: Theme.of(context).colorScheme.tertiaryContainer,
                        child: ListTile(
                          leading: const Icon(Icons.person_add_alt),
                          title: Text(
                            '${pending.length} '
                            '${pending.length == 1 ? 'person is' : 'people are'} '
                            'waiting to join',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push(Routes.members(orgId)),
                        ),
                      ),
                    if (org != null && org.hasHomeGround)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.stadium_outlined),
                          title: Text(org.homeGroundName ?? 'Home ground'),
                          subtitle: const Text('Home ground'),
                          trailing: org.homeGroundId != null
                              ? const Icon(Icons.chevron_right)
                              : null,
                          onTap: org.homeGroundId == null
                              ? null
                              : () => context
                                  .push(Routes.ground(org.homeGroundId!)),
                        ),
                      ),
                    if (live.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const LiveDot(),
                          const SizedBox(width: 8),
                          Text(
                            'Live now',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      for (final f in live)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: LiveScoreCard(
                            fixture: f,
                            onTap: () => context.push(
                              Routes.watch(orgId, f.compId, f.id),
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),
                    ],
                    Text(
                      'Events',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    if (comps.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 32),
                        child: EmptyState(
                          icon: Icons.emoji_events_outlined,
                          title: 'No events yet',
                          message: canCreate
                              ? 'Create your first competition — pick a sport, '
                                  'set the age category, and open entries.'
                              : 'Nothing has been scheduled here yet.',
                          action: !canCreate
                              ? null
                              : FilledButton.icon(
                                  onPressed: () => context
                                      .push(Routes.createCompetition(orgId)),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Create an event'),
                                ),
                        ),
                      )
                    else
                      // A season's sports gather behind one card here instead
                      // of one each — see [groupEventFeed] — so a club that
                      // just ran through `CreateSeasonScreen` sees the season
                      // it created, not a wall of same-named sport rows.
                      for (final item in groupEventFeed(comps))
                        switch (item) {
                          EventFeedSingle(:final competition) =>
                            _CompetitionTile(
                              orgId: orgId,
                              competition: competition,
                            ),
                          EventFeedSeason(
                            :final tournamentId,
                            :final competitions
                          ) =>
                            SeasonCard(
                              orgId: orgId,
                              tournamentId: tournamentId,
                              competitions: competitions,
                              showOrg: false,
                            ),
                        },
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The club's identity block: crest, who they are, and the four numbers that
/// describe them.
///
/// Two things the mockup shows are deliberately absent. There is no "Verified
/// Club" tick because nothing in `Organization` records verification — a badge
/// every club renders unconditionally is not a badge, it is decoration that
/// claims a trust signal the platform does not actually make. And there is no
/// "Est. 2018": `createdAt` is when the club was created *on PlaySphere*, not
/// when it was founded, and a school side from 1974 showing "Est. 2026" is
/// worse than showing nothing. The join year is rendered as what it is.
class _ClubHeader extends ConsumerWidget {
  const _ClubHeader({
    required this.orgId,
    required this.org,
    required this.competitions,
  });

  final String orgId;
  final Organization org;
  final List<Competition> competitions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teams = ref.watch(subGroupsProvider(orgId)).valueOrNull ?? const [];
    // Distinct sports the club has actually run something in — not the
    // catalogue, and not what anyone declared. A club is a cricket club
    // because it runs cricket.
    final sportIds = <String>{for (final c in competitions) c.sportId}.toList();
    final place = [org.city, org.geo.state]
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .join(', ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Crest(org: org),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        org.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Ps.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          org.orgType.label,
                          if (place.isNotEmpty) place,
                        ].join(' • '),
                        style: const TextStyle(fontSize: 12.5, color: Ps.muted),
                      ),
                      if (org.createdAt != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'On PlaySphere since ${org.createdAt!.year}',
                          style: const TextStyle(fontSize: 12, color: Ps.faint),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            PsStatRow(
              stats: [
                // Both open the members screen: that's where a club's real,
                // rostered teams actually live and get raised from — see
                // `_TeamsSection` there. This card's own "Teams" preview
                // below is the lighter-weight sub-group list and stays as
                // it was; the count and the tap target agree with the page
                // they lead to rather than with each other.
                PsStat(
                  value: psGrouped(teams.length),
                  label: 'Teams',
                  onTap: () => context.push(Routes.members(orgId)),
                ),
                PsStat(
                  value: psGrouped(org.memberCount),
                  label: 'Members',
                  onTap: () => context.push(Routes.members(orgId)),
                ),
                PsStat(
                  value: psGrouped(sportIds.length),
                  label: 'Sports',
                  onTap: sportIds.isEmpty
                      ? null
                      : () => context.push(Routes.clubStats(orgId)),
                ),
                PsStat(
                  value: psGrouped(competitions.length),
                  label: 'Tournaments',
                  onTap: () => context.push(Routes.tournaments(orgId)),
                ),
              ],
            ),
            _FollowButton(orgId: orgId, org: org),
            if (org.description != null &&
                org.description!.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'About Club',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Ps.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                org.description!,
                style: const TextStyle(
                  fontSize: 13,
                  color: Ps.muted,
                  height: 1.45,
                ),
              ),
            ],
            if (sportIds.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Sports',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Ps.ink,
                ),
              ),
              const SizedBox(height: 8),
              _SportsStrip(orgId: orgId, sportIds: sportIds),
            ],
            if (teams.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Teams',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Ps.ink,
                ),
              ),
              const SizedBox(height: 8),
              // Capped, like every other preview on the dashboard: a club with
              // thirty age-group sides would otherwise push its live matches
              // off the screen.
              for (final team in teams.take(3)) _TeamRow(team: team),
            ],
          ],
        ),
      ),
    );
  }
}

/// The club crest, or its initial where no logo has been uploaded.
class _Crest extends StatelessWidget {
  const _Crest({required this.org});

  final Organization org;

  @override
  Widget build(BuildContext context) {
    final logo = org.logoUrl;
    if (logo != null && logo.trim().isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(Ps.radiusSm),
        child: Image.network(
          logo,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          // A club whose logo host is down must still render a club header.
          errorBuilder: (_, __, ___) => _InitialCrest(name: org.name),
        ),
      );
    }
    return _InitialCrest(name: org.name);
  }
}

class _InitialCrest extends StatelessWidget {
  const _InitialCrest({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Ps.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Ps.radiusSm),
      ),
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: Ps.primary,
        ),
      ),
    );
  }
}

/// The run of sport badges, with a "+N" once there are more than fit.
class _SportsStrip extends StatelessWidget {
  const _SportsStrip({required this.orgId, required this.sportIds});

  final String orgId;
  final List<String> sportIds;

  /// Six, then overflow. Seven 32pt badges and their gaps is the point where
  /// the strip stops fitting a 320pt screen.
  static const _visible = 6;

  @override
  Widget build(BuildContext context) {
    final shown = sportIds.take(_visible).toList();
    final extra = sportIds.length - shown.length;
    return Row(
      children: [
        for (final id in shown)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => context.push(Routes.clubSportStats(orgId, id)),
              child: SportBadge(sportId: id, size: 34),
            ),
          ),
        if (extra > 0)
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Ps.canvas,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Ps.border),
            ),
            child: Text(
              '+$extra',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Ps.muted,
              ),
            ),
          ),
      ],
    );
  }
}

class _TeamRow extends StatelessWidget {
  const _TeamRow({required this.team});

  final SubGroup team;

  @override
  Widget build(BuildContext context) {
    final sportId = team.sportId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          if (sportId != null)
            SportBadge(sportId: sportId, size: 32)
          else
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Ps.canvas,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.groups, size: 16, color: Ps.muted),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  team.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Ps.ink,
                  ),
                ),
                Text(
                  [
                    if (sportId != null) SportCatalog.byId(sportId).name,
                    if (team.ageGroup != null) team.ageGroup!,
                  ].join(' • '),
                  style: const TextStyle(fontSize: 11.5, color: Ps.muted),
                ),
              ],
            ),
          ),
          Text(
            '${team.memberUids.length} '
            '${team.memberUids.length == 1 ? 'Player' : 'Players'}',
            style: const TextStyle(fontSize: 11.5, color: Ps.muted),
          ),
        ],
      ),
    );
  }
}

class _CompetitionTile extends StatelessWidget {
  const _CompetitionTile({required this.orgId, required this.competition});

  final String orgId;
  final Competition competition;

  @override
  Widget build(BuildContext context) {
    final c = competition;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Text(
            _sportEmoji(c.sportId),
            style: const TextStyle(fontSize: 18),
          ),
        ),
        title: Text(c.name),
        subtitle: Text(
          [
            c.sportName,
            c.category.label,
            '${c.entrantCount} entered',
          ].join(' · '),
        ),
        trailing: _StatusChip(status: c.displayStatus()),
        onTap: () => context.push(Routes.competition(orgId, c.id)),
      ),
    );
  }

  static String _sportEmoji(String sportId) => switch (sportId) {
        'cricket' => '🏏',
        'badminton' => '🏸',
        'table_tennis' => '🏓',
        'volleyball' => '🏐',
        'football' => '⚽',
        'basketball' => '🏀',
        'kabaddi' => '🤼',
        'hockey' => '🏑',
        'chess' => '♟️',
        'tennis' => '🎾',
        _ => '🏅',
      };
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
      CompetitionStatus.completed => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant
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

/// Follow / Following, on a club's own page.
///
/// ## What following does, and what it deliberately does not
///
/// It puts this club's events on your home feed. That is the whole feature —
/// see `myFeedOrgIdsProvider`. It is not a lightweight membership: it grants
/// no roster seat, no capability, and no read that was not already public,
/// which is exactly why it needs no approval queue where joining does.
///
/// Hidden for members and for the club's own people. A member already gets
/// every one of these events on their dashboard, so offering them a control
/// whose only effect they already have is offering them nothing. Hidden for
/// private clubs too, because `firestore.rules` refuses the write and a button
/// that always fails is worse than no button.
class _FollowButton extends ConsumerWidget {
  const _FollowButton({required this.orgId, required this.org});

  final String orgId;
  final Organization org;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUidProvider);
    if (uid == null) return const SizedBox.shrink();
    if (org.visibility != OrgVisibility.public) return const SizedBox.shrink();

    final membership = ref.watch(myMembershipProvider(orgId)).valueOrNull;
    if (membership != null && membership.isActive) return const SizedBox.shrink();

    final following = ref.watch(isFollowingOrgProvider(orgId)).valueOrNull;
    // Nothing until the answer is known. A button that says "Follow" and then
    // flips to "Following" a moment later reads as having been pressed by
    // itself.
    if (following == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: SizedBox(
        width: double.infinity,
        child: following
            ? OutlinedButton.icon(
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Following'),
                onPressed: () => _set(context, ref, uid, follow: false),
              )
            : FilledButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Follow Club'),
                onPressed: () => _set(context, ref, uid, follow: true),
              ),
      ),
    );
  }

  Future<void> _set(
    BuildContext context,
    WidgetRef ref,
    String uid, {
    required bool follow,
  }) async {
    final repo = ref.read(orgRepositoryProvider);
    try {
      if (follow) {
        await repo.followOrg(orgId: orgId, uid: uid);
      } else {
        await repo.unfollowOrg(orgId: orgId, uid: uid);
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            follow
                ? 'Following ${org.name}. Their events are on your home screen.'
                : 'Unfollowed ${org.name}.',
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}
