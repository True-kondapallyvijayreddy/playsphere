import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/competition.dart';
import '../../core/models/enums.dart';
import '../../core/models/fixture.dart';
import '../../core/models/tournament.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../domain/tournament/tournament_overview.dart';
import '../competitions/widgets/invited_club_block.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui_kit.dart';
import '../../core/models/draw_config.dart';
import '../competitions/widgets/group_stage_fields.dart';
import '../competitions/widgets/suspend_sheet.dart';
import '../../data/image_composer.dart';
import '../../shared/image_upload.dart';
import '../../shared/live_dot.dart';
import '../../shared/ps_banner.dart';
import 'tournaments_screen.dart' show TournamentEditor;
import '../competitions/widgets/schedule_export.dart';
import '../scoring/open_match.dart';
import 'widgets/invite_clubs_sheet.dart';
import 'widgets/leaderboard_cards.dart';
import 'widgets/running_late_card.dart';
import 'widgets/share_season_sheet.dart';
import 'widgets/venue_selector_dialog.dart';
import 'tournament_schedule_screen.dart';
import 'widgets/graphical_schedule_view.dart';
import '../../core/l10n/result_labels.dart';

/// One tournament at a glance: how far through it is, what is on court right
/// now, what is next, every event with its table, and who has won what.
///
/// The screen an organizer keeps open all weekend and a parent refreshes from
/// the car park. Everything on it is derived from the matches — nothing here
/// is a stored figure that could drift from the results it summarises.
class TournamentDetailScreen extends ConsumerWidget {
  const TournamentDetailScreen({
    super.key,
    required this.orgId,
    required this.tournamentId,
  });

  final String orgId;
  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (orgId: orgId, tournamentId: tournamentId);
    final tAsync = ref.watch(tournamentProvider(key));
    final canManage = ref
        .watch(myCapabilitiesProvider(orgId))
        .contains(Capability.manageCompetitions);

    return AppScaffold(
      orgId: orgId,
      title: 'Tournament',
      body: AsyncView(
        value: tAsync,
        builder: (tournament) {
          if (tournament == null) {
            return const EmptyState(
              icon: Icons.search_off,
              title: 'This tournament no longer exists',
            );
          }

          final overview = ref.watch(tournamentOverviewProvider(key));

          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              ContentBounds(
                maxWidth: 960,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(
                      orgId: orgId,
                      tournament: tournament,
                      canManage: canManage,
                    ),
                    const SizedBox(height: 16),
                    // Above everything derived from the matches, because
                    // "this season is not running" changes how every number
                    // below it should be read.
                    if (tournament.isSuspended)
                      OnHoldBanner(
                        what: 'season',
                        reason: tournament.suspendReason,
                        resumeLabel: 'Resume season',
                        onResume: !canManage
                            ? null
                            : () => resumeSeason(
                                  context: context,
                                  ref: ref,
                                  orgId: orgId,
                                  tournamentId: tournamentId,
                                ),
                      ),
                    // A failure here is one panel's worth of data, not the
                    // tournament. The matches feed can be down — a missing
                    // index, a dropped connection — while the events, the
                    // dates and the invite actions above are all perfectly
                    // readable, so the notice replaces only what it covers
                    // and the rest of the screen carries on rendering from
                    // whatever did load.
                    AsyncErrorStrip(
                      value: overview,
                      what: 'the matches',
                    ),
                    // For a member of a club this season's host invited: the
                    // whole of what they can do here. Above the schedule
                    // because they are deciding whether to be in it, not
                    // reading it — and invisible to everybody else, which is
                    // almost everybody. See [InvitedClubBlock].
                    InvitedClubBlock(
                      hostOrgId: orgId,
                      tournamentId: tournamentId,
                    ),
                    // Directly under the header, above everything about
                    // matches: until entries are open there are no matches,
                    // and this is the only thing the organizer should be
                    // doing next.
                    if (canManage)
                      _OpenEntriesCard(
                        orgId: orgId,
                        tournamentId: tournamentId,
                        events: ref
                                .watch(tournamentEventsProvider(key))
                                .valueOrNull ??
                            const [],
                      ),
                    _Progress(
                      tournament: tournament,
                      overview: overview.valueOrNull,
                    ),
                    const SizedBox(height: 16),
                    // Graphical Schedule & Timetable View
                    GraphicalScheduleView(
                      tournament: tournament,
                      events: ref
                              .watch(tournamentEventsProvider(key))
                              .valueOrNull ??
                          const [],
                      fixtures: ref
                              .watch(tournamentFixturesProvider(key))
                              .valueOrNull ??
                          const [],
                      canManage: canManage,
                      onOpenFullPage: () => context
                          .push(Routes.tournamentSchedule(orgId, tournamentId)),
                      onSetUpWholeSeason: (timings) => setUpWholeSeason(
                        context: context,
                        ref: ref,
                        orgId: orgId,
                        tournamentId: tournamentId,
                        timings: timings,
                      ),
                      onRegenerateDraft: (timings) =>
                          regenerateTournamentSchedule(
                        context: context,
                        ref: ref,
                        orgId: orgId,
                        tournamentId: tournamentId,
                        timings: timings,
                      ),
                      onLockSchedule: () => lockTournamentSchedule(
                        context: context,
                        ref: ref,
                        orgId: orgId,
                        tournamentId: tournamentId,
                      ),
                      // Moving a match belongs on the schedule page, where the
                      // venue calendars are; opening one belongs everywhere the
                      // match is drawn. Without this the season's own timetable
                      // was the one place a match could not be opened.
                      onOpenMatch: (fixture) => openMatch(
                        context,
                        fixture: fixture,
                        myUid: ref.read(currentUidProvider),
                        canManage: canManage,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // The sentence under this used to say "Build the
                    // umpiring panel and assign it across the bracket, before
                    // match day". The row is labelled `Officials` and leads to
                    // a screen headed `Officials`; the sentence was a third
                    // telling, and it doubled the row's height to do it.
                    // Above Officials because it comes first in the work: a
                    // panel is assigned to a timetable, and the timetable
                    // cannot be right until the grounds have said when they
                    // are open.
                    if (canManage)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: PsLinkTile(
                          icon: Icons.event_available_outlined,
                          label: 'Venue planner',
                          onTap: () => context.push(
                            Routes.venuePlanner(orgId, tournamentId),
                          ),
                        ),
                      ),
                    if (canManage)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: PsLinkTile(
                          icon: Icons.sports_outlined,
                          label: 'Officials',
                          onTap: () => context.push(
                            Routes.tournamentOfficials(orgId, tournamentId),
                          ),
                        ),
                      ),
                    if (canManage)
                      RunningLateCard(
                        // Draft placeholders are never "running late" — see
                        // `Fixture.isDraft`.
                        fixtures: (ref
                                    .watch(tournamentFixturesProvider(key))
                                    .valueOrNull ??
                                const [])
                            .where((f) => !f.isDraft)
                            .toList(),
                        onShift: ({by, newStart}) => ref
                            .read(tournamentRepositoryProvider)
                            .shiftSchedule(
                              orgId: orgId,
                              tournamentId: tournamentId,
                              by: by,
                              newStart: newStart,
                            ),
                      ),
                    _OnCourtNow(
                      orgId: orgId,
                      overview: overview.valueOrNull,
                    ),
                    _UpNext(orgId: orgId, overview: overview.valueOrNull),
                    GroupsSummaryCard(
                      leaderboard: ref
                          .watch(tournamentLeaderboardProvider(key))
                          .valueOrNull,
                    ),
                    LeaderboardCard(
                      leaderboard: ref
                          .watch(tournamentLeaderboardProvider(key))
                          .valueOrNull,
                      onTapEntrant: (record) => context.push(
                        Routes.seasonEntrant(
                          orgId,
                          tournamentId,
                          record.entrantId,
                        ),
                      ),
                    ),
                    // Directly under the leaderboard: that board says who had
                    // the best tournament, this one says what they actually
                    // did. Reading one without the other is the gap between
                    // "Rahul won five" and "Rahul scored 642".
                    PlayerBoardsCard(
                      bySport: ref
                          .watch(tournamentPlayerBoardsBySportProvider(key))
                          .valueOrNull,
                    ),
                    _Events(
                      orgId: orgId,
                      tournamentId: tournamentId,
                      canManage: canManage,
                      overview: overview.valueOrNull,
                    ),
                    _Honours(overview: overview.valueOrNull),
                    if ((overview.valueOrNull?.completedEvents ?? 0) > 0) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: PsLinkTile(
                          icon: Icons.workspace_premium_outlined,
                          label: 'Certificates',
                          onTap: () => context.push(
                            Routes.certificates(orgId, tournamentId),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: PsLinkTile(
                          icon: Icons.photo_library_outlined,
                          label: 'Season memories',
                          onTap: () => context.push(
                            Routes.seasonMemories(orgId, tournamentId),
                          ),
                        ),
                      ),
                    ],
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

class _Header extends ConsumerWidget {
  const _Header({
    required this.orgId,
    required this.tournament,
    required this.canManage,
  });

  final String orgId;
  final Tournament tournament;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = tournament;
    final venues = ref.watch(venuesProvider(orgId)).valueOrNull ?? const [];
    final named = [
      for (final v in venues)
        if (t.venueIds.contains(v.id)) v,
    ];
    final courtCount = named.fold<int>(0, (sum, v) => sum + v.capacity);

    // A season is only "a cricket season" when every event in it is cricket.
    // Five sports under one banner have no single colour, and picking the
    // first event's would be a lie the artwork tells about the season.
    final sports = <String>{
      for (final e in ref
              .watch(tournamentEventsProvider(
                (orgId: orgId, tournamentId: t.id),
              ))
              .valueOrNull ??
          const [])
        e.sportId,
    };
    final seasonSportId = sports.length == 1 ? sports.first : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: PsBanner(
            imageUrl: t.bannerUrl,
            // The season's own badge, on the artwork beside its name. Drawn
            // only when there is one — see [PsBanner.logoUrl].
            logoUrl: t.logoUrl,
            logoName: t.name,
            sportId: seasonSportId,
            seed: t.id,
            height: 156,
            // A multi-sport season gets the trophy rather than the generic
            // "unknown sport" mark, which would be both duller and untrue.
            fallbackIcon: Icons.emoji_events_outlined,
            fallbackColor: const Color(0xFF0F766E),
            trailing: canManage
                ? _SeasonBannerButton(
                    onTap: () => _changeBanner(context, ref),
                  )
                : null,
            child: Text(
              t.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1.15,
              ),
            ),
          ),
        ),
        PsCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // The season's name moved up onto the banner, where it is
                  // laid over the artwork. Repeating it here read as a bug —
                  // the same words twice, 12pt apart — so this slot keeps the
                  // row balanced and says what the card below it is about.
                  const Expanded(
                    child: Text(
                      'SEASON',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.9,
                        color: Ps.muted,
                      ),
                    ),
                  ),
                  // Share stays on the surface and the management tools go into
                  // the menu. Not an arbitrary split: sharing the public link is
                  // what everyone on this screen does, including the members who
                  // cannot manage anything, while venues, invitations, editing
                  // and the timetable are each touched once or twice in a
                  // tournament's life. Five unlabelled glyphs had been squeezing
                  // the tournament's own name into a third of the header.
                  IconButton(
                    icon: const Icon(Icons.share_outlined),
                    tooltip: 'Share the public link',
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      builder: (_) => ShareSeasonSheet(tournament: t),
                    ),
                  ),
                  // Beside share, and outside the manage-only menu, for the
                  // same reason share is: a coach or a parent wants the
                  // timetable on paper at least as much as the organiser
                  // does. Renders nothing until there are matches.
                  ScheduleDownloadButton(
                    fixtures: ref
                            .watch(tournamentFixturesProvider(
                                (orgId: orgId, tournamentId: t.id)))
                            .valueOrNull ??
                        const [],
                    title: t.name,
                    byDay: true,
                    sectionOf: (f) => {
                          for (final e in ref
                                  .watch(tournamentEventsProvider(
                                      (orgId: orgId, tournamentId: t.id)))
                                  .valueOrNull ??
                              const [])
                            e.id: e.name,
                        }[f.compId] ??
                        'Matches',
                    compact: true,
                  ),
                  if (canManage)
                    PsOverflowMenu(
                      actions: [
                        PsAction(
                          label: 'Schedule',
                          icon: Icons.calendar_view_week_outlined,
                          // Was a second "generate now" button that re-solved the
                          // timetable without asking anything. Two buttons that
                          // schedule the same tournament, one of which skips the
                          // timings dialog, is how an organizer loses a changeover
                          // they had just set. Scheduling has one door.
                          onSelected: () => context
                              .push(Routes.tournamentSchedule(orgId, t.id)),
                        ),
                        PsAction(
                          label: 'Venues & courts',
                          icon: Icons.stadium_outlined,
                          onSelected: () => showDialog<void>(
                            context: context,
                            builder: (_) => VenueSelectorDialog(tournament: t),
                          ),
                        ),
                        PsAction(
                          label: 'Invite clubs',
                          icon: Icons.groups_outlined,
                          onSelected: () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            showDragHandle: true,
                            builder: (_) => InviteClubsSheet(tournament: t),
                          ),
                        ),
                        PsAction(
                          label: 'Edit',
                          icon: Icons.edit_outlined,
                          onSelected: () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            showDragHandle: true,
                            builder: (_) =>
                                TournamentEditor(orgId: orgId, existing: t),
                          ),
                        ),
                        // Named, in the menu, as well as reachable by tapping
                        // the artwork. The camera badge in the corner of the
                        // banner is only discoverable to somebody who already
                        // suspects it is a button, and the crest has no badge
                        // at all until a season has one — so a season with no
                        // logo had no affordance anywhere for adding one.
                        PsAction(
                          label:
                              t.logoUrl == null ? 'Add logo' : 'Change logo',
                          icon: Icons.shield_outlined,
                          onSelected: () => _changeLogo(context, ref),
                        ),
                        PsAction(
                          label: t.bannerUrl == null
                              ? 'Add banner'
                              : 'Change banner',
                          icon: Icons.image_outlined,
                          onSelected: () => _changeBanner(context, ref),
                        ),
                        // Reversible, so it is not marked destructive and does
                        // not sort down with the ones that end things. A season
                        // can go on hold and come back as often as the weather
                        // makes it.
                        if (t.isSuspended)
                          PsAction(
                            label: 'Resume season',
                            icon: Icons.play_circle_outline,
                            onSelected: () => resumeSeason(
                              context: context,
                              ref: ref,
                              orgId: orgId,
                              tournamentId: t.id,
                            ),
                          )
                        else
                          PsAction(
                            label: 'Put on hold',
                            icon: Icons.pause_circle_outline,
                            onSelected: () => SuspendSheet.showForSeason(
                              context,
                              tournament: t,
                              eventCount: t.eventCount,
                            ),
                          ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 2),
              // Four chips and a venue row became one line. The dates and the
              // court count are facts about the tournament, not controls, and
              // they were drawn as pills that look pressable and are not.
              PsMetaRow(
                items: [
                  t.grade.label,
                  // The lifecycle status and the hold are two different facts —
                  // a paused season is still `in_progress` — so both are shown.
                  if (t.isSuspended) 'On hold',
                  t.status.label,
                  _dateRange(t),
                  if (courtCount > 0) '$courtCount courts',
                  if (named.isNotEmpty) named.map((v) => v.name).join(', '),
                ],
              ),
              if (t.description != null) ...[
                const SizedBox(height: 8),
                Text(
                  t.description!,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// The public tournament page is the one thing a club sends to people who
  /// do not have PlaySphere, and it opened with an app bar reading
  /// "Tournament". This is what a season's own artwork is for.
  Future<void> _changeBanner(BuildContext context, WidgetRef ref) {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return Future.value();
    final repo = ref.read(tournamentRepositoryProvider);
    return pickAndUploadImage(
      context: context,
      title: 'Season banner',
      shape: ImageShape.banner,
      successMessage: 'Banner updated.',
      removedMessage: 'Banner removed.',
      onUpload: (image) => repo.uploadSeasonBanner(
        orgId: orgId,
        tournamentId: tournament.id,
        uid: uid,
        bytes: image.bytes,
        contentType: image.contentType,
      ),
      onRemove: tournament.bannerUrl == null
          ? null
          : () => repo.removeSeasonBanner(
                orgId: orgId,
                tournamentId: tournament.id,
              ),
    );
  }

  /// The season's badge, which is the picture a club usually has ready long
  /// before it has a header photograph.
  Future<void> _changeLogo(BuildContext context, WidgetRef ref) {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return Future.value();
    final repo = ref.read(tournamentRepositoryProvider);
    return pickAndUploadImage(
      context: context,
      title: 'Season logo',
      shape: ImageShape.square,
      note: 'Shown on the header, in the season list, and on the public link.',
      successMessage: 'Logo updated.',
      removedMessage: 'Logo removed.',
      onUpload: (image) => repo.uploadSeasonLogo(
        orgId: orgId,
        tournamentId: tournament.id,
        uid: uid,
        bytes: image.bytes,
        contentType: image.contentType,
      ),
      onRemove: tournament.logoUrl == null
          ? null
          : () => repo.removeSeasonLogo(
                orgId: orgId,
                tournamentId: tournament.id,
              ),
    );
  }

  static String _dateRange(Tournament t) {
    String fmt(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    final start = t.startDate;
    if (start == null) return 'Dates not set';
    final end = t.endDate;
    if (end == null ||
        (end.year == start.year &&
            end.month == start.month &&
            end.day == start.day)) {
      return '${fmt(start)}/${start.year}';
    }
    return '${fmt(start)} – ${fmt(end)}/${end.year}';
  }
}

/// The one control that sits on top of a season banner.
///
/// Filled circle rather than a bare glyph: it has to stay legible over an
/// uploaded photograph of unknown brightness.
class _SeasonBannerButton extends StatelessWidget {
  const _SeasonBannerButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x8A000000),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: 'Change the banner',
        iconSize: 18,
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.photo_camera_outlined, color: Colors.white),
        onPressed: onTap,
      ),
    );
  }
}

/// "Nobody can enter this season yet" — and the one tap that fixes it.
///
/// ## Why a card and not a menu item
///
/// A season is published as a set of drafts (see
/// `TournamentRepository.openEntriesForSeason` for why creation cannot do
/// otherwise), and a draft event takes no registrations. Nothing said so. An
/// organizer finished the creation flow, sent the link round, and the people
/// who followed it found events they could not enter — with the organizer's
/// next step buried one page deep inside each of twelve events.
///
/// So the season page states the situation in a sentence and offers the
/// action beside it. It disappears the moment there is no draft left, which
/// is the only state in which it has anything to say.
class _OpenEntriesCard extends ConsumerStatefulWidget {
  const _OpenEntriesCard({
    required this.orgId,
    required this.tournamentId,
    required this.events,
  });

  final String orgId;
  final String tournamentId;
  final List<Competition> events;

  @override
  ConsumerState<_OpenEntriesCard> createState() => _OpenEntriesCardState();
}

class _OpenEntriesCardState extends ConsumerState<_OpenEntriesCard> {
  bool _busy = false;

  Future<void> _open(int count) async {
    setState(() => _busy = true);
    try {
      final opened =
          await ref.read(tournamentRepositoryProvider).openEntriesForSeason(
                orgId: widget.orgId,
                tournamentId: widget.tournamentId,
              );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            opened == 1
                ? 'Entries are open. People can register now.'
                : 'Entries are open on all $opened events. People can '
                    'register now.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final drafts = [
      for (final e in widget.events)
        if (e.status == CompetitionStatus.draft) e,
    ];
    if (drafts.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final all = drafts.length == widget.events.length;

    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.how_to_reg_outlined,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    all
                        ? 'Nobody can enter this season yet'
                        : '${drafts.length} '
                            '${drafts.length == 1 ? 'event is' : 'events are'} '
                            'not open yet',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              all
                  ? 'Every event was created as a draft so you could check it '
                      'first. Open entries and players can start registering.'
                  : 'These were created as drafts. Open them and players can '
                      'register for them too.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _busy ? null : () => _open(drafts.length),
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_open, size: 18),
                label: Text(
                  drafts.length == 1
                      ? 'Open entries'
                      : 'Open entries on all ${drafts.length} events',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.tournament, required this.overview});

  final Tournament tournament;
  final TournamentOverview? overview;

  @override
  Widget build(BuildContext context) {
    final o = overview;
    if (o == null || o.totalMatches == 0) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Progress', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: o.progress,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 20,
              runSpacing: 12,
              children: [
                _Stat(label: 'Matches played', value: '${o.playedMatches}'),
                _Stat(label: 'Remaining', value: '${o.remainingMatches}'),
                _Stat(
                  label: 'Events',
                  value: '${o.completedEvents} / ${o.events.length} done',
                ),
                if (o.liveMatches > 0)
                  _Stat(label: 'Live now', value: '${o.liveMatches}'),
                if (o.scheduledThrough != null)
                  _Stat(
                    label: 'Last match starts',
                    value: _stamp(o.scheduledThrough!),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _stamp(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style:
              theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _OnCourtNow extends StatelessWidget {
  const _OnCourtNow({required this.orgId, required this.overview});

  final String orgId;
  final TournamentOverview? overview;

  @override
  Widget build(BuildContext context) {
    final live = overview?.onCourtNow ?? const <Fixture>[];
    if (live.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                // Feature #16: blinking LiveDot instead of a static red circle
                // to clearly indicate ongoing matches.
                const LiveDot(size: 10),
                const SizedBox(width: 8),
                Text('On court now', style: theme.textTheme.titleMedium),
              ],
            ),
          ),
          for (final f in live) _MatchRow(orgId: orgId, fixture: f),
        ],
      ),
    );
  }
}

class _UpNext extends StatelessWidget {
  const _UpNext({required this.orgId, required this.overview});

  final String orgId;
  final TournamentOverview? overview;

  @override
  Widget build(BuildContext context) {
    final next = overview?.upNext ?? const <Fixture>[];
    if (next.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Up next', style: theme.textTheme.titleMedium),
          ),
          for (final f in next) _MatchRow(orgId: orgId, fixture: f),
        ],
      ),
    );
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.orgId, required this.fixture});

  final String orgId;
  final Fixture fixture;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = fixture;
    final when = f.scheduledAt;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        onTap: () => context.push(Routes.competition(orgId, f.compId)),
        title: Text(
          // The qualifier label rather than "To be decided": a bracket slot
          // waiting on a group should say which group.
          '${f.displayNameA()}  v  ${f.displayNameB()}',
          style: theme.textTheme.bodyMedium,
        ),
        subtitle: Text(
          [
            if (f.roundLabel != null) f.roundLabel!,
            if (f.courtId != null)
              f.courtId!
            else if (f.venue != null)
              f.venue!,
            if (when != null)
              '${when.hour.toString().padLeft(2, '0')}:'
                  '${when.minute.toString().padLeft(2, '0')}',
          ].join(' · '),
          style: theme.textTheme.bodySmall,
        ),
        // Feature #16: show the live score summary alongside the blinking
        // indicator, so users see current scores without clicking through.
        trailing: f.isLiveAt(DateTime.now())
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (f.summary.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        localizedSummary(context, f.summary),
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  const LiveDot(size: 10),
                ],
              )
            : f.hasResult && f.summary.isNotEmpty
                ? Text(
                    localizedSummary(context, f.summary),
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.hintColor,
                    ),
                  )
                : null,
      ),
    );
  }
}

/// Every event, with its own points table where the format has one.
class _Events extends ConsumerWidget {
  const _Events({
    required this.orgId,
    required this.tournamentId,
    required this.canManage,
    required this.overview,
  });

  final String orgId;
  final String tournamentId;
  final bool canManage;
  final TournamentOverview? overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The summaries need the matches; the LIST of events does not. When the
    // matches feed is unavailable the events are still worth showing — a
    // season's five sports exist whether or not anything has been drawn yet,
    // and "No events yet" under a season somebody just created with five of
    // them reads as data loss. So this falls back to the draws themselves,
    // with the played/live counts left at zero because they are genuinely
    // unknown rather than genuinely nil.
    final events = overview?.events ??
        [
          for (final c in ref
                  .watch(tournamentEventsProvider(
                      (orgId: orgId, tournamentId: tournamentId)))
                  .valueOrNull ??
              const <Competition>[])
            EventSummary(
              competition: c,
              total: 0,
              played: 0,
              live: 0,
              champion: null,
            ),
        ];
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Text(
                  events.isEmpty ? 'Events' : 'Events (${events.length})',
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                if (canManage)
                  TextButton.icon(
                    onPressed: () => _attach(context, ref),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add events'),
                  ),
              ],
            ),
          ),
          if (events.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.playlist_add_outlined),
                title: Text('No events yet'),
                subtitle: Text(
                  'A tournament holds many draws — U-13 singles, senior '
                  'doubles, and the rest. Create them as events for this '
                  'club, then attach them here so they share courts and one '
                  'timetable.',
                ),
              ),
            )
          else
            for (final e in events)
              _EventTile(
                orgId: orgId,
                summary: e,
                canManage: canManage,
              ),
        ],
      ),
    );
  }

  Future<void> _attach(BuildContext context, WidgetRef ref) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _AttachEventsSheet(
          orgId: orgId,
          tournamentId: tournamentId,
        ),
      );
}

/// Adds events to a tournament: either the club's existing unattached ones, or
/// a sport created here and now.
///
/// Only events not already attached elsewhere are offered — an event belongs
/// to one tournament, because its matches are scheduled against one shared
/// pool of courts and being in two timetables at once is not a state that
/// means anything.
///
/// ## Why adding a sport outright belongs here
///
/// A season is created with its sports chosen up front, and a plan changes:
/// the volleyball net turns up, the kho-kho ground is double-booked, another
/// school asks whether there is a throwball event. Until now the only route
/// was "create one from the club first" and then come back and attach it —
/// two screens and a name to type for something the season form does in a
/// checkbox. A club with no spare unattached events could not add a sport to
/// its own season at all.
class _AttachEventsSheet extends ConsumerStatefulWidget {
  const _AttachEventsSheet({
    required this.orgId,
    required this.tournamentId,
  });

  final String orgId;
  final String tournamentId;

  @override
  ConsumerState<_AttachEventsSheet> createState() => _AttachEventsSheetState();
}

class _AttachEventsSheetState extends ConsumerState<_AttachEventsSheet> {
  final _picked = <String>{};

  /// Sports to create into this tournament, by catalog id, mapped to the
  /// draw format chosen for each — the same per-sport choice
  /// `CreateSeasonScreen` offers, so a sport added after the season already
  /// exists is not silently stuck on Round Robin.
  final _newSports = <String, CompetitionFormat>{};
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = ref.watch(competitionsProvider(widget.orgId)).valueOrNull ??
        const <Competition>[];
    final free = [
      for (final c in all)
        if (c.tournamentId == null) c,
    ];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Add events', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Events already in another tournament are not listed — one '
              'event belongs to one timetable.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            if (free.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'This club has no unattached events. Add a sport below '
                  'instead — it is created straight into this tournament.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            for (final c in free)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _picked.contains(c.id),
                title: Text(c.name),
                subtitle: Text(
                  '${c.sportName} · ${c.category.label} · ${c.format.label}',
                ),
                onChanged: (on) => setState(() {
                  if (on == true) {
                    _picked.add(c.id);
                  } else {
                    _picked.remove(c.id);
                  }
                }),
              ),
            const SizedBox(height: 20),
            Text('Or add a sport', style: theme.textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(
              'Each becomes its own event under this tournament, sharing its '
              'courts, its dates and its rest gap.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final sport in SportCatalog.all)
                  FilterChip(
                    label: Text('${sport.icon}  ${sport.name}'),
                    selected: _newSports.containsKey(sport.id),
                    onSelected: (on) => setState(() {
                      if (on) {
                        _newSports[sport.id] = sport.defaultCompetitionFormat;
                      } else {
                        _newSports.remove(sport.id);
                      }
                    }),
                  ),
              ],
            ),
            if (_newSports.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final sportId in _newSports.keys)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${SportCatalog.byId(sportId).icon}  '
                          '${SportCatalog.byId(sportId).name} format',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      SizedBox(
                        width: 180,
                        child: DropdownButtonFormField<CompetitionFormat>(
                          value: _newSports[sportId],
                          isDense: true,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final f in SportCatalog.byId(sportId)
                                .competitionFormats)
                              DropdownMenuItem(value: f, child: Text(f.label)),
                          ],
                          onChanged: (f) {
                            if (f != null) {
                              setState(() => _newSports[sportId] = f);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _total == 0 || _busy ? null : _save,
                  child: Text(_total == 0 ? 'Add' : 'Add $_total'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  int get _total => _picked.length + _newSports.length;

  Future<void> _save() async {
    setState(() => _busy = true);
    final repo = ref.read(tournamentRepositoryProvider);
    try {
      for (final compId in _picked) {
        await repo.addEvent(
          orgId: widget.orgId,
          tournamentId: widget.tournamentId,
          compId: compId,
        );
      }

      if (_newSports.isNotEmpty) {
        final tournament = ref
            .read(tournamentProvider((
              orgId: widget.orgId,
              tournamentId: widget.tournamentId,
            )))
            .valueOrNull;
        final competitions = ref.read(competitionRepositoryProvider);
        final uid = ref.read(currentUidProvider);

        for (final entry in _newSports.entries) {
          final sport = SportCatalog.byId(entry.key);
          await competitions.createCompetition(
            Competition(
              id: '',
              orgId: widget.orgId,
              tournamentId: widget.tournamentId,
              // Named for the sport within the tournament, matching what the
              // season form writes — a list of five events all called
              // "Sports Week 2026" tells an organizer nothing.
              name: '${tournament?.name ?? 'Tournament'} — ${sport.name}',
              sportId: sport.id,
              sportName: sport.name,
              archetype: sport.archetype,
              entrantType: sport.defaultEntrantType,
              format: entry.value,
              status: CompetitionStatus.registrationOpen,
              category: CompetitionCategory.presets(
                cutOff: tournament?.startDate,
              ).first,
              scoringPluginKey: sport.pluginKey,
              startDate: tournament?.startDate,
              waitlistEnabled: true,
              createdBy: uid,
            ),
          );
        }

        // Created already attached, so the attach path's own increment never
        // runs — see `noteEventsCreated` for why the count is load-bearing.
        repo.noteEventsCreated(
          orgId: widget.orgId,
          tournamentId: widget.tournamentId,
          count: _newSports.length,
        );
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// One event in the season, on one line.
///
/// ## Why it is one line
///
/// This was an `ExpansionTile` whose closed state was already two lines, and
/// whose open state was a points table plus a row of two more buttons — one of
/// which duplicated the pencil in its own trailing slot. A fifteen-event
/// season was therefore thirty lines of chrome before any of it said anything,
/// and reaching an event took two taps: open the drawer, find the button.
///
/// So the actions come out of the drawer and sit where the pencil already was.
/// The row is the event; the icons beside it are the three things anyone does
/// to one — look at its table, open its draws, edit it — and the table is the
/// only one that stays a disclosure, because it is the only one that is
/// content rather than a destination.
class _EventTile extends ConsumerStatefulWidget {
  const _EventTile({
    required this.orgId,
    required this.summary,
    required this.canManage,
  });

  final String orgId;
  final EventSummary summary;
  final bool canManage;

  @override
  ConsumerState<_EventTile> createState() => _EventTileState();
}

class _EventTileState extends ConsumerState<_EventTile> {
  bool _tableOpen = false;

  Future<void> _openEditDialog(Competition c) async {
    final updated = await showDialog<Competition>(
      context: context,
      builder: (_) => _EditEventDialog(competition: c),
    );
    if (updated == null) return;
    try {
      await ref.read(competitionRepositoryProvider).updateCompetition(updated);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Event updated successfully!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = widget.summary;
    final c = summary.competition;
    // A knockout split into groups has tables too — its groups are round
    // robins — so the format list alone was not the question to ask.
    final showsTable = _tableFormats.contains(c.format) || c.hasGroupStage;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            // The whole row opens the event, so the icon beside it is the
            // affordance rather than the only way in.
            onTap: () => context.push(Routes.competition(widget.orgId, c.id)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Row(
                children: [
                  summary.isComplete
                      ? Icon(Icons.emoji_events,
                          size: 20, color: theme.colorScheme.primary)
                      : summary.live > 0
                          ? Icon(Icons.circle,
                              size: 12, color: theme.colorScheme.error)
                          : const Icon(Icons.schedule_outlined, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge,
                        ),
                        Text(
                          [
                            c.format.label,
                            c.category.label,
                            '${summary.played}/${summary.total} played',
                            if (c.isSuspended) 'on hold',
                            if (summary.champion != null) summary.champion!,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (showsTable)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        _tableOpen
                            ? Icons.expand_less
                            : Icons.table_rows_outlined,
                        size: 20,
                      ),
                      tooltip: _tableOpen ? 'Hide the table' : 'Points table',
                      onPressed: () => setState(() => _tableOpen = !_tableOpen),
                    ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.open_in_new, size: 20),
                    tooltip: 'Open event & draws',
                    onPressed: () =>
                        context.push(Routes.competition(widget.orgId, c.id)),
                  ),
                  if (widget.canManage)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      tooltip: 'Edit event details',
                      onPressed: () => _openEditDialog(c),
                    ),
                ],
              ),
            ),
          ),
          if (_tableOpen && showsTable)
            _EventTable(orgId: widget.orgId, competition: c),
        ],
      ),
    );
  }

  static const _tableFormats = {
    CompetitionFormat.roundRobin,
    CompetitionFormat.leagueTable,
    CompetitionFormat.swiss,
    CompetitionFormat.groupThenKnockout,
  };
}

class _EditEventDialog extends StatefulWidget {
  const _EditEventDialog({required this.competition});
  final Competition competition;

  @override
  State<_EditEventDialog> createState() => _EditEventDialogState();
}

class _EditEventDialogState extends State<_EditEventDialog> {
  late final TextEditingController _name;
  late final TextEditingController _venue;
  late final TextEditingController _maxEntrants;
  late CompetitionFormat _format;
  late CompetitionStatus _status;
  late CompetitionCategory _category;

  /// The group stage's shape, editable here because a season's events are
  /// drawn by `setUpWholeSeason` and never open the draw setup sheet where
  /// these were previously the only settable settings. Without this, an event
  /// created before the season screens asked the question had no screen at
  /// all on which to gain a group stage.
  late DrawConfig _draw;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.competition.name);
    _venue = TextEditingController(text: widget.competition.venue ?? '');
    _maxEntrants = TextEditingController(
      text: widget.competition.maxEntrants?.toString() ?? '',
    );
    _format = widget.competition.format;
    _status = widget.competition.status;
    _category = widget.competition.category;
    _draw = widget.competition.drawConfig;
  }

  @override
  void dispose() {
    _name.dispose();
    _venue.dispose();
    _maxEntrants.dispose();
    super.dispose();
  }

  /// Entrants to plan the group split against — whoever has actually entered
  /// once the field is known, and the cap while it is still filling.
  int get _plannedEntrants {
    final entered = widget.competition.entrantCount;
    if (entered >= 2) return entered;
    final cap = int.tryParse(_maxEntrants.text.trim());
    return (cap == null || cap < 2) ? 16 : cap;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sport = SportCatalog.byId(widget.competition.sportId);
    final presets =
        CompetitionCategory.presets(cutOff: widget.competition.startDate);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.edit_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Edit Category / Event',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Event Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<CompetitionFormat>(
                  value: _format,
                  decoration: const InputDecoration(
                    labelText: 'Format',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final f in sport.competitionFormats)
                      DropdownMenuItem(value: f, child: Text(f.label)),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _format = v);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _category.label,
                  decoration: const InputDecoration(
                    labelText: 'Category (Age / Gender)',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final cat in presets)
                      DropdownMenuItem(
                          value: cat.label, child: Text(cat.label)),
                  ],
                  onChanged: (label) {
                    if (label != null) {
                      setState(() {
                        _category = presets.firstWhere((c) => c.label == label);
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<CompetitionStatus>(
                  value: _status,
                  decoration: const InputDecoration(
                    labelText: 'Registration Status',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final s in CompetitionStatus.values)
                      DropdownMenuItem(value: s, child: Text(s.label)),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _status = v);
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _venue,
                        decoration: const InputDecoration(
                          labelText: 'Venue (optional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _maxEntrants,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Max Entries',
                          hintText: 'Any',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                GroupStageFields(
                  format: _format,
                  entrantCount: _plannedEntrants,
                  config: _draw,
                  onChanged: (v) => setState(() => _draw = v),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        final trimmedName = _name.text.trim();
                        if (trimmedName.isEmpty) return;
                        final cap = int.tryParse(_maxEntrants.text.trim());
                        final updated = widget.competition.copyWith(
                          name: trimmedName,
                          format: _format,
                          drawConfig: GroupStageFields.normalize(
                            format: _format,
                            entrantCount: _plannedEntrants,
                            config: _draw,
                          ),
                          status: _status,
                          category: _category,
                          venue: _venue.text.trim().isEmpty
                              ? null
                              : _venue.text.trim(),
                          maxEntrants: cap,
                        );
                        Navigator.of(context).pop(updated);
                      },
                      child: const Text('Save Changes'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The points table for one event, inline.
///
/// A groups draw gets one table per group with the qualifying line drawn; a
/// league gets a single table. Both come from the same calculator the event
/// screen uses, so the tournament view can never disagree with the event view.
class _EventTable extends ConsumerWidget {
  const _EventTable({required this.orgId, required this.competition});

  final String orgId;
  final Competition competition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = CompRef(orgId, competition.id);

    if (competition.hasGroupStage) {
      final groups = ref.watch(groupStandingsProvider(key)).valueOrNull ??
          const <String, List<Standing>>{};
      if (groups.isEmpty) return const SizedBox.shrink();
      final ids = groups.keys.toList()..sort();
      return Column(
        children: [
          for (final id in ids)
            _Table(
              orgId: orgId,
              compId: competition.id,
              tournamentId: competition.tournamentId,
              caption: 'Group $id',
              rows: groups[id]!,
              // Pools promote nobody, so no qualifying line is drawn on them.
              qualifiers: competition.groupsFeedKnockout
                  ? competition.drawConfig.qualifiersPerGroup
                  : 0,
            ),
        ],
      );
    }

    final table =
        ref.watch(standingsProvider(key)).valueOrNull ?? const <Standing>[];
    if (table.isEmpty) return const SizedBox.shrink();
    return _Table(
      orgId: orgId,
      compId: competition.id,
      tournamentId: competition.tournamentId,
      caption: null,
      rows: table,
      qualifiers: 0,
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({
    required this.orgId,
    required this.compId,
    required this.tournamentId,
    required this.caption,
    required this.rows,
    required this.qualifiers,
  });

  final String orgId;
  final String compId;

  /// The season this table's event belongs to, when it belongs to one.
  ///
  /// It decides where a tapped name leads. Inside a season the useful page is
  /// the season one — every event that team entered, every match, one record —
  /// and the per-event page is a third of it. A standalone event has no season
  /// to show, so it keeps the per-event page it always had.
  final String? tournamentId;

  final String? caption;
  final List<Standing> rows;
  final int qualifiers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (caption != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(caption!, style: theme.textTheme.labelLarge),
            ),
          Row(
            children: [
              const SizedBox(width: 22),
              Expanded(child: Text('Team', style: theme.textTheme.labelSmall)),
              SizedBox(
                width: 26,
                child: Text('P',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.labelSmall),
              ),
              SizedBox(
                width: 26,
                child: Text('W',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.labelSmall),
              ),
              SizedBox(
                width: 26,
                child: Text('L',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.labelSmall),
              ),
              SizedBox(
                width: 32,
                child: Text('Pts',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.labelSmall),
              ),
            ],
          ),
          const Divider(height: 12),
          for (var i = 0; i < rows.length; i++) ...[
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => context.push(
                tournamentId == null
                    ? Routes.entrant(orgId, compId, rows[i].entrantId)
                    : Routes.seasonEntrant(
                        orgId,
                        tournamentId!,
                        rows[i].entrantId,
                      ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      child: Text(
                        '${i + 1}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: qualifiers > 0 && i < qualifiers
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                          fontWeight: qualifiers > 0 && i < qualifiers
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              rows[i].displayName,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.primary,
                                decoration: TextDecoration.underline,
                                decorationStyle: TextDecorationStyle.dotted,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right,
                            size: 14,
                            color: theme.hintColor,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 26,
                      child: Text('${rows[i].played}',
                          textAlign: TextAlign.end,
                          style: theme.textTheme.bodySmall),
                    ),
                    SizedBox(
                      width: 26,
                      child: Text('${rows[i].won}',
                          textAlign: TextAlign.end,
                          style: theme.textTheme.bodySmall),
                    ),
                    SizedBox(
                      width: 26,
                      child: Text('${rows[i].lost}',
                          textAlign: TextAlign.end,
                          style: theme.textTheme.bodySmall),
                    ),
                    SizedBox(
                      width: 32,
                      child: Text(
                        '${rows[i].points}',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (qualifiers > 0 && i == qualifiers - 1 && i < rows.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Divider(color: theme.colorScheme.primary)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'qualify',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.colorScheme.primary),
                      ),
                    ),
                    Expanded(child: Divider(color: theme.colorScheme.primary)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Who has won what — the board that replaces a Telegram message.
class _Honours extends StatelessWidget {
  const _Honours({required this.overview});

  final TournamentOverview? overview;

  @override
  Widget build(BuildContext context) {
    final champions = overview?.champions ?? const <EventSummary>[];
    if (champions.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.emoji_events, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Champions', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            for (final e in champions)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.competition.name,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(
                      e.champion!,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
