import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/competition.dart';
import '../../core/models/enums.dart';
import '../../core/models/organization.dart';
import '../../core/models/team.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../data/image_composer.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/club_id_chip.dart';
import '../../shared/identity.dart';
import '../../shared/image_upload.dart';
import '../../shared/live_dot.dart';
import '../../shared/ui_kit.dart';
import '../../domain/club_events.dart';
import '../home/event_feed.dart';
import '../network/club_network_providers.dart';
import '../scoring/widgets/live_score_card.dart';
import 'club_events_screen.dart';
import 'widgets/club_sections_grid.dart';
import 'widgets/club_stats_section.dart';

class OrgHomeScreen extends ConsumerWidget {
  const OrgHomeScreen({super.key, required this.orgId});

  final String orgId;

  /// How many event rows the dashboard shows before handing over to
  /// `ClubEventsScreen`.
  static const _eventsPreview = 6;

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

    // A visiting club owner, looking at somebody else's club. The one thing
    // they want that a member never does is a way to write to it — see
    // `ClubNetworkScreen`. Offered only to the owner of a DIFFERENT club, so
    // it never appears on an owner's own page, where it would be an invitation
    // to talk to themselves.
    final asClubId = ref.watch(actingClubIdProvider);
    final canMessage = asClubId != null && asClubId != orgId;

    return AppScaffold(
      orgId: orgId,
      title: 'Home',
      actions: [
        if (canMessage)
          IconButton(
            tooltip: 'Message this club',
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: () =>
                context.push(Routes.clubThreadWith(asClubId, orgId)),
          ),
        if (canManage)
          IconButton(
            tooltip: 'Club settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(Routes.clubSettings(orgId)),
          ),
      ],
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
          // Grouped once. A season's sports collapse behind one card — see
          // [groupEventFeed] — and the count, the preview and the "all N
          // events" button all have to be talking about the same rows.
          final feed = groupEventFeed(comps);
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
                    // Outside the header on purpose. The header needs a
                    // loaded [Organization] and draws nothing without one,
                    // and these ten doors are the only way to this club's
                    // gallery, files and venues now that the app-wide drawer
                    // is gone. Nesting them inside the header would mean a
                    // club whose document is slow — or unreadable — became a
                    // club with no sections at all.
                    const SizedBox(height: 18),
                    ClubSectionsGrid(orgId: orgId),
                    const SizedBox(height: 8),
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
                    // The club's record, between who it is and what it is
                    // running — see [ClubStatsSection] for why it earns the
                    // place above the events list.
                    ClubStatsSection(orgId: orgId, competitions: comps),
                    PsSectionHeader(
                      title: 'Events',
                      actionLabel: 'View All',
                      onAction: comps.isEmpty
                          ? null
                          : () => context.push(Routes.clubEvents(orgId)),
                    ),
                    const SizedBox(height: 10),
                    if (comps.isNotEmpty) ...[
                      _EventKindStrip(orgId: orgId, competitions: comps),
                      const SizedBox(height: 12),
                    ],
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
                      // Capped. This is the club's dashboard, not its
                      // archive: the full, sorted, filterable list is one tap
                      // away behind "View All", and a club three years in was
                      // otherwise scrolling past two hundred cards to reach
                      // anything below the events section.
                      for (final item
                          in feed.take(_eventsPreview))
                        switch (item) {
                          EventFeedSingle(:final competition) =>
                            // The same tile the full events list uses, so a
                            // finished single match opens its scorecard from
                            // here too rather than a one-match bracket page.
                            ClubEventTile(competition: competition),
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
                    if (feed.length > _eventsPreview)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () =>
                              context.push(Routes.clubEvents(orgId)),
                          icon: const Icon(Icons.list_alt_outlined, size: 18),
                          label: Text(
                            'All ${feed.length} events',
                          ),
                        ),
                      ),
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
    // `clubTeamsProvider`, not the sub-group list this used to read.
    //
    // Two different things were both called "Teams": `orgs/{id}/subgroups`,
    // the club's own age-group/house buckets, and `teams/` filtered by
    // `clubId`, which is where `CreateTeamScreen` and every squad the members
    // screen shows actually write. Nothing in the app has written a subgroup
    // for a long time, so this counter read an empty collection and showed
    // "0 Teams" to a club with eleven of them — while the members screen one
    // tap below, reading `clubTeamsProvider`, showed all eleven. The counter
    // now reads the same collection as the screen it links to.
    final teams = ref.watch(clubTeamsProvider(orgId)).valueOrNull ?? const [];
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
                _Crest(
                  org: org,
                  // The same capability that shows the settings cog. A member
                  // who cannot manage the club is not shown a camera badge
                  // whose write `firestore.rules` would refuse.
                  canEdit: ref
                      .watch(myCapabilitiesProvider(orgId))
                      .contains(Capability.manageOrganization),
                ),
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
                      // The full form here rather than the bare code: this is
                      // the club's own page, and sharing it is something a
                      // member arrives here to do.
                      const SizedBox(height: 4),
                      ClubIdChip(org: org),
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
                // Both open the members screen: that's where a club's
                // rostered teams live and get raised from. The count, the
                // preview below and that screen now all read
                // `clubTeamsProvider`, so the three agree — see the note on
                // `teams` above for what they used to disagree about.
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
                // Counted the way the events list below counts them: a
                // five-sport season is one thing this club ran, not five.
                // The label follows suit — it was "Tournaments" over a
                // number that included every single match and challenge.
                PsStat(
                  value: psGrouped(groupEventFeed(competitions).length),
                  label: 'Events',
                  onTap: () => context.push(Routes.clubEvents(orgId)),
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
///
/// Tappable for an admin, which is the only route to setting a crest in the
/// app. `OrgRepository.uploadClubLogo` had existed, complete and correct, with
/// no caller at all — three screens read `logoUrl` and nothing could write it.
/// Putting the affordance on the crest itself rather than burying it in club
/// settings is deliberate: the thing you want to change is the thing you tap.
class _Crest extends ConsumerWidget {
  const _Crest({required this.org, this.canEdit = false});

  final Organization org;
  final bool canEdit;

  Future<void> _change(BuildContext context, WidgetRef ref) {
    final me = ref.read(currentUserProvider).valueOrNull;
    if (me == null) return Future.value();
    final repo = ref.read(orgRepositoryProvider);
    return pickAndUploadImage(
      context: context,
      title: 'Club crest',
      shape: ImageShape.square,
      successMessage: 'Crest updated.',
      removedMessage: 'Crest removed.',
      onUpload: (image) => repo.uploadClubLogo(
        orgId: org.id,
        uid: me.uid,
        bytes: image.bytes,
        contentType: image.contentType,
      ),
      onRemove:
          org.logoUrl == null ? null : () => repo.removeClubLogo(org.id),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return EditableImage(
      shape: BoxShape.rectangle,
      tooltip: 'Change the club crest',
      onTap: canEdit ? () => _change(context, ref) : null,
      // The bespoke `Image.network` + initials pair this replaced was a
      // near-duplicate of the one on the rankings ladder, and the two
      // disagreed about corner radius and about whether initials meant one
      // letter or two — so the same club looked like two clubs.
      child: PsCrest(
        name: org.name,
        logoUrl: org.logoUrl,
        seed: org.id,
        size: 56,
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

  final Team team;

  @override
  Widget build(BuildContext context) {
    final sportId = team.sportId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SportBadge(sportId: sportId, size: 32),
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
                    SportCatalog.byId(sportId).name,
                    team.type.label,
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

/// The four shapes a club's events come in, each carrying its count, each a
/// way straight into that slice of the list.
///
/// The club's events used to be one column ordered by date, which answers
/// "what is next" and nothing else. An owner hunting an unfinished draft, a
/// player looking for the tournament still taking entries, and a visitor
/// wanting to know whether this club actually plays anybody else were all
/// reading the whole list to find out. Each of those is now one tap — the
/// counts here are the same ones `ClubEventsScreen` puts on its tabs,
/// because both come from [ClubEventIndex].
///
/// Kinds the club has none of are dropped rather than shown as a zero. A new
/// club would otherwise open on four empty buckets, which describes the
/// product rather than the club.
class _EventKindStrip extends StatelessWidget {
  const _EventKindStrip({required this.orgId, required this.competitions});

  final String orgId;
  final List<Competition> competitions;

  @override
  Widget build(BuildContext context) {
    final index = ClubEventIndex.of(competitions);
    final kinds = [
      for (final kind in ClubEventKind.values)
        if (index.has(kind)) kind,
    ];
    // Nothing to segregate. One kind means the strip would be a single chip
    // restating the list directly underneath it.
    if (kinds.length < 2) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final kind in kinds)
          ActionChip(
            avatar: Icon(kind.icon, size: 16),
            label: Text('${kind.label} ${index.count(kind)}'),
            onPressed: () =>
                context.push(Routes.clubEvents(orgId, kind: kind)),
          ),
      ],
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
