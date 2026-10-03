import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/competition.dart';
import '../../core/models/enums.dart';
import '../../core/models/fixture.dart';
import '../../core/models/organization.dart';
import '../../core/models/tournament.dart';
import '../../core/models/tournament_invite.dart';
import '../../core/models/tournament_official.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../domain/schedule/match_phase.dart';
import '../../domain/tournament/season_access.dart';
import '../../domain/tournament/season_blueprint.dart';
import '../../domain/tournament/season_entry_status.dart';
import '../../domain/tournament/season_sports.dart';
import '../../domain/tournament/tournament_leaderboard.dart';
import '../../domain/tournament/tournament_overview.dart';
import '../competitions/widgets/invited_club_block.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/identity.dart';
import '../../shared/ui_kit.dart';
import '../../core/models/draw_config.dart';
import '../competitions/widgets/bulk_category_selector_sheet.dart';
import '../competitions/widgets/group_stage_fields.dart';
import '../competitions/widgets/suspend_sheet.dart';
import '../../data/image_composer.dart';
import '../../shared/image_upload.dart';
import '../../shared/live_dot.dart';
import '../../shared/ps_banner.dart';
import 'tournaments_screen.dart' show TournamentEditor;
import '../competitions/widgets/schedule_board.dart' show MatchRow;
import '../competitions/widgets/schedule_export.dart';
import '../scoring/open_match.dart';
import 'widgets/leaderboard_cards.dart';
import 'widgets/running_late_card.dart';
import 'widgets/season_sport_panel.dart';
import 'widgets/share_season_sheet.dart';
import 'widgets/venue_selector_dialog.dart';
import 'tournament_schedule_screen.dart';
import 'widgets/graphical_schedule_view.dart';
import 'widgets/season_organizer_gate.dart';
import 'widgets/pending_entries_card.dart';
import 'season_entry.dart';

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
    // The one question every card below asks — see [SeasonAccess]. Nothing
    // on this screen reads a capability directly any more.
    final access = ref.watch(seasonAccessProvider(key));
    final canManage = access.canManage;
    // What the main page is drawn as. Organizers see the page everybody else
    // sees — their tools, staffing and draft work are on the desk — while an
    // official keeps the umpire lists they work from.
    const spectator = SeasonAccess(SeasonRole.spectator);
    final view = access.isOrganizer ? spectator : access;

    return AppScaffold(
      orgId: orgId,
      // "Tournament" for a one-sport tournament — the same page, see
      // `SeasonKind`.
      title: tAsync.valueOrNull?.kind.label ?? 'Season',
      body: AsyncView(
        value: tAsync,
        builder: (tournament) {
          if (tournament == null) {
            return const EmptyState(
              icon: Icons.search_off,
              title: 'This season no longer exists',
            );
          }

          final overview = ref.watch(tournamentOverviewProvider(key));
          final events =
              ref.watch(tournamentEventsProvider(key)).valueOrNull ?? const [];
          final fixtures =
              ref.watch(tournamentFixturesProvider(key)).valueOrNull ??
                  const <Fixture>[];
          final leaderboard =
              ref.watch(tournamentLeaderboardProvider(key)).valueOrNull;
          final sports = SeasonSport.split(
            tournament: tournament,
            events: events,
            fixtures: fixtures,
            leaderboard: leaderboard,
            roster: ref.watch(tournamentOfficialsProvider(key)).valueOrNull ??
                const [],
          );
          final hasChampions =
              (overview.valueOrNull?.completedEvents ?? 0) > 0;

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
                        what: tournament.kind.noun,
                        reason: tournament.suspendReason,
                        resumeLabel: 'Resume ${tournament.kind.noun}',
                        onResume: !canManage
                            ? null
                            : () => resumeSeason(
                                  context: context,
                                  ref: ref,
                                  orgId: orgId,
                                  tournamentId: tournamentId,
                                ),
                      ),
                    // One panel's worth of data, not the season: the matches
                    // feed can be down while the events and dates are fine.
                    AsyncErrorStrip(value: overview, what: 'the matches'),
                    // For a member of a club this season's host invited.
                    // Invisible to everybody else. See [InvitedClubBlock].
                    InvitedClubBlock(
                      hostOrgId: orgId,
                      tournamentId: tournamentId,
                    ),
                    // Everybody who is not running it: where they stand with
                    // this season. A button while there is something left to
                    // enter, and a plain "Already registered" line once there
                    // is not — see [SeasonEntryStatus]. Drawing the button
                    // regardless of whether they had entered was the bug: a
                    // club confirmed by the host was still being asked to
                    // register, and the natural next move is to press it
                    // again.
                    // Their house, for anybody who has one — an organizer
                    // who also plays included (TC-CLUB-001).
                    _MyHouseBanner(orgId: orgId, tournamentId: tournamentId),
                    if (!canManage)
                      _RegistrationStanding(
                        orgId: orgId,
                        tournamentId: tournamentId,
                        kind: tournament.kind,
                      ),

                    // Filling the season with other clubs, from the season
                    // itself. It used to be reachable only from the desk's
                    // tool row and from the separate Invitations screen,
                    // which is the wrong place to look for it: an organizer
                    // decides who to invite while reading the season — the
                    // sports, the dates, how many draws are still thin — not
                    // from a list of seasons elsewhere.
                    if (canManage)
                      _InviteFromSeason(
                        orgId: orgId,
                        tournament: tournament,
                      ),

                    // ---- The way into the organizer's desk -------------
                    // One door, not the desk itself. The main page is the
                    // season as everybody sees it — stats and leaderboards —
                    // and what needs doing lives inside: see
                    // [SeasonDeskScreen]. (User, 2026-09-13: "on season main
                    // page we don't have to show needs your attention or
                    // running late — it will go inside".)
                    if (canManage)
                      _DeskEntry(
                        orgId: orgId,
                        tournament: tournament,
                        events: events,
                        fixtures: fixtures,
                        sports: sports,
                      ),

                    // ---- An official's own duties ----------------------
                    if (access.isOfficial && !canManage)
                      _YourDuties(fixtures: fixtures, canManage: canManage),

                    // ---- The season, for everybody ---------------------
                    _SeasonPulse(
                      orgId: orgId,
                      tournamentId: tournamentId,
                      sports: sports,
                      overview: overview.valueOrNull,
                      access: view,
                    ),
                    const SizedBox(height: 12),
                    // Who is behind this season — the names a visiting club
                    // wants before they commit a side to it.
                    _WhoRunsThis(
                      orgId: orgId,
                      tournamentId: tournamentId,
                      events: events,
                    ),
                    const SizedBox(height: 12),
                    _SeasonTools(
                      orgId: orgId,
                      tournamentId: tournamentId,
                      canManage: false,
                      hasChampions: hasChampions,
                    ),
                    const SizedBox(height: 16),
                    // On match day the first thing anyone looks for, and the
                    // one list that must not be behind a tap.
                    _OnCourtNow(sports: sports, canManage: false),
                    // The season as what it is — several tournaments under
                    // one roof — one panel per sport. See [SeasonSport].
                    if (events.isEmpty)
                      _Events(
                        orgId: orgId,
                        tournamentId: tournamentId,
                        canManage: false,
                        overview: overview.valueOrNull,
                      )
                    else
                      _Sports(
                        orgId: orgId,
                        tournamentId: tournamentId,
                        sports: sports,
                        access: view,
                      ),
                    _Honours(overview: overview.valueOrNull),
                    // The long boards — every entrant, every statistic —
                    // folded, because each sport's panel already says who is
                    // winning it and a page read at a glance must stay short.
                    _SeasonRecords(
                      orgId: orgId,
                      tournamentId: tournamentId,
                      leaderboard: leaderboard,
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

/// "Your house: Charminar Strikers" — the first thing a student looks for on
/// a school season's page, and previously visible only inside each event.
class _MyHouseBanner extends ConsumerWidget {
  const _MyHouseBanner({required this.orgId, required this.tournamentId});

  final String orgId;
  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final houses = ref.watch(mySeasonHousesProvider(
      (orgId: orgId, tournamentId: tournamentId),
    ));
    if (houses.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PsCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.shield_outlined, color: Ps.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                houses.length == 1
                    ? 'Your house: ${houses.single}'
                    : 'Your houses: ${houses.join(', ')}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Where the person reading this season stands with it: a way in while there
/// is something left to enter, and a plain statement once there is not.
///
/// ## Why "Already registered" is a thing the page has to say
///
/// The button used to be drawn from one fact — some draw in this season is
/// taking entries — and never from whether this person had used it. A club
/// would enter, the host would confirm them, and the season would still open
/// with "Register for this tournament". There is no reading of that sentence
/// under which the entry went through, so the honest response is to press it
/// again, and the organizer's entry list fills with duplicates from people
/// the app told to make them.
///
/// See [SeasonEntryStatus] for what counts as an entry — it is not only the
/// ones you filed under your own name.
class _RegistrationStanding extends ConsumerWidget {
  const _RegistrationStanding({
    required this.orgId,
    required this.tournamentId,
    required this.kind,
  });

  final String orgId;
  final String tournamentId;
  final SeasonKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(seasonEntryStatusProvider(
      (orgId: orgId, tournamentId: tournamentId),
    ));

    // Nothing entered and nothing to enter: say nothing. The season page is
    // not the place to explain an absence nobody asked about.
    if (!status.hasEntry && !status.canStillEnter) {
      return const SizedBox.shrink();
    }

    // Their club is the one that enters. [InvitedClubBlock], directly above,
    // already says so and carries the one button they do have.
    if (status.clubEntersForMe && !status.hasEntry) {
      return const SizedBox.shrink();
    }

    final label = status.label(seasonNoun: kind.noun);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: status.canStillEnter
          // Still something open. The button stays primary, and carries the
          // count so somebody already half in knows what pressing it is for.
          ? FilledButton.icon(
              onPressed: () =>
                  context.push(Routes.seasonRegister(orgId, tournamentId)),
              icon: Icon(
                status.hasEntry
                    ? Icons.playlist_add_check_outlined
                    : Icons.how_to_reg_outlined,
              ),
              label: Text(label),
            )
          // In everything that is open. Not a button: there is nothing left
          // to press, and a tappable control here is an invitation to enter
          // twice. Still a door to the entries, because "registered for
          // what, exactly" is the next question.
          : PsCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              onTap: () =>
                  context.push(Routes.seasonRegister(orgId, tournamentId)),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Ps.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                            color: Ps.ink,
                          ),
                        ),
                        Text(
                          status.entered.length == 1
                              ? status.entered.first.name
                              : status.entered.map((e) => e.name).join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Ps.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Ps.faint),
                ],
              ),
            ),
    );
  }
}

/// Who runs this season, who officiates it, and how big the field is.
///
/// ## Why a season has to name people
///
/// A season page could say everything about the matches and nothing about the
/// people, and for the host club's own members that is survivable — they know
/// who the owner is. For everybody else it is the missing half. A club deciding
/// whether to send a side across the city is asking who is running this, is
/// there an umpire panel or are we scoring our own matches, and how many teams
/// have actually entered. None of those had an answer on this page, and an
/// event that cannot answer them is one clubs decline by default.
///
/// Roles come from the two places that already decide them, not from a third
/// list somebody has to keep up to date: the host club's member rows, which is
/// what `firestore.rules` checks, and this season's umpire panel.
///
/// Degrades quietly. A private host club's roster is unreadable to a visitor,
/// and that is the correct answer to give them — the panel then shows what it
/// can (the umpires, the size of the field) rather than an error about a list
/// they were never entitled to.
class _WhoRunsThis extends ConsumerWidget {
  const _WhoRunsThis({
    required this.orgId,
    required this.tournamentId,
    required this.events,
  });

  final String orgId;
  final String tournamentId;
  final List<Competition> events;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members =
        ref.watch(orgMembersProvider(orgId)).valueOrNull ?? const <Membership>[];
    final officials = ref
            .watch(tournamentOfficialsProvider(
              (orgId: orgId, tournamentId: tournamentId),
            ))
            .valueOrNull ??
        const <TournamentOfficial>[];

    List<Membership> withRole(MembershipRole role) => [
          for (final m in members)
            if (m.isActive && m.role == role) m,
        ];

    final owners = withRole(MembershipRole.owner);
    // Admins and event managers both run competitions here — that is what
    // `canManageCompetitions` admits — so they are shown together rather than
    // implying a distinction the rules do not make.
    final admins = [
      ...withRole(MembershipRole.admin),
      ...withRole(MembershipRole.eventManager),
    ];

    // The field, counted the way the entry lists count it. Confirmed only:
    // a pending application is not a participant yet, and counting it makes
    // the number shrink when an organizer rejects somebody.
    final entered = events.fold<int>(0, (n, e) => n + e.confirmedCount);
    final teamEvents = events.any((e) => e.entersAsTeams);

    if (owners.isEmpty &&
        admins.isEmpty &&
        officials.isEmpty &&
        entered == 0) {
      return const SizedBox.shrink();
    }

    return PsCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'WHO RUNS THIS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: Ps.faint,
            ),
          ),
          const SizedBox(height: 10),
          if (owners.isNotEmpty)
            _RoleLine(
              label: owners.length == 1 ? 'Owner' : 'Owners',
              names: [for (final m in owners) m.displayName],
              photos: {for (final m in owners) m.displayName: m.photoUrl},
            ),
          if (admins.isNotEmpty)
            _RoleLine(
              label: 'Organizers',
              names: [for (final m in admins) m.displayName],
              photos: {for (final m in admins) m.displayName: m.photoUrl},
            ),
          if (officials.isNotEmpty)
            _RoleLine(
              label: officials.length == 1 ? 'Umpire' : 'Umpires',
              names: [for (final o in officials) o.name],
              photos: const {},
              // The panel is a season-long thing an organizer builds and a
              // player checks the morning of a match, so it gets a door.
              onTap: () =>
                  context.push(Routes.tournamentOfficials(orgId, tournamentId)),
            )
          else
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Umpires · not appointed yet',
                style: TextStyle(fontSize: 12.5, color: Ps.muted),
              ),
            ),
          const Divider(height: 18),
          Row(
            children: [
              const Icon(Icons.groups_outlined, size: 18, color: Ps.muted),
              const SizedBox(width: 8),
              Text(
                entered == 0
                    ? 'No entries yet'
                    : teamEvents
                        ? '$entered ${entered == 1 ? 'entry' : 'entries'} '
                            'across ${events.length} '
                            '${events.length == 1 ? 'event' : 'events'}'
                        : '$entered ${entered == 1 ? 'participant' : 'participants'} '
                            'across ${events.length} '
                            '${events.length == 1 ? 'event' : 'events'}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Ps.ink,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One role and the people holding it, as chips.
class _RoleLine extends StatelessWidget {
  const _RoleLine({
    required this.label,
    required this.names,
    required this.photos,
    this.onTap,
  });

  final String label;
  final List<String> names;
  final Map<String, String?> photos;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Long panels are trimmed rather than turned into a wall of faces — a
    // twelve-umpire panel is a page of its own, and the tap goes there.
    const cap = 6;
    final shown = names.take(cap).toList();
    final extra = names.length - shown.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: Ps.muted,
                ),
              ),
              if (onTap != null) ...[
                const Spacer(),
                InkWell(
                  onTap: onTap,
                  child: const Text(
                    'See panel',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Ps.primary,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final n in shown)
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: PsAvatar(
                    name: n,
                    photoUrl: photos[n],
                    seed: n,
                    size: 20,
                  ),
                  label: Text(n, style: const TextStyle(fontSize: 12)),
                ),
              if (extra > 0)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    '+$extra more',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Invite clubs", on the season itself.
///
/// The action already existed, on the desk's tool row and on the separate
/// Invitations screen. Neither is where an organizer is standing when they
/// decide to use it: that decision is made while reading the season — which
/// sports are in it, how many sides each draw has, how many days are left —
/// and having to leave the season to act on it is how a draw of four ends up
/// staying a draw of four.
class _InviteFromSeason extends ConsumerWidget {
  const _InviteFromSeason({required this.orgId, required this.tournament});

  final String orgId;
  final Tournament tournament;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invites = ref
            .watch(tournamentInvitesProvider(
              (orgId: orgId, tournamentId: tournament.id),
            ))
            .valueOrNull ??
        const <TournamentInvite>[];
    final accepted = invites.where((i) => i.isAccepted).length;
    final pending = invites.where((i) => i.isPending).length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PsCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: () => context.push(Routes.inviteClubs(orgId, tournament.id)),
        child: Row(
          children: [
            const Icon(Icons.send_outlined, color: Ps.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    invites.isEmpty
                        ? 'Invite clubs to this ${tournament.kind.noun}'
                        : 'Invited clubs',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                      color: Ps.ink,
                    ),
                  ),
                  Text(
                    invites.isEmpty
                        ? 'Send the letter from here — pick the clubs, they '
                            'answer, their sides enter.'
                        : [
                            '$accepted playing',
                            if (pending > 0) '$pending waiting to answer',
                            'Invite more',
                          ].join(' · '),
                    style: const TextStyle(fontSize: 12.5, color: Ps.muted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Ps.faint),
          ],
        ),
      ),
    );
  }
}

/// The organizer's one way in to the desk, on the season's main page.
///
/// A single line with a count, instead of the desk itself. The count is the
/// same three questions the desk opens on — entries not open, things needing
/// attention, matches running late — so "3 need you" is never a number the
/// desk cannot account for.
class _DeskEntry extends ConsumerWidget {
  const _DeskEntry({
    required this.orgId,
    required this.tournament,
    required this.events,
    required this.fixtures,
    required this.sports,
  });

  final String orgId;
  final Tournament tournament;
  final List<Competition> events;
  final List<Fixture> fixtures;
  final List<SeasonSport> sports;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waiting = SeasonDeskScreen.waitingEntries(ref, events);
    final count = SeasonDeskScreen.pendingCount(
      tournament: tournament,
      events: events,
      fixtures: fixtures,
      sports: sports,
      waitingEntries: waiting,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PsCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: () =>
            context.push(Routes.seasonDesk(orgId, tournament.id)),
        child: Row(
          children: [
            const Icon(Icons.dashboard_customize_outlined, color: Ps.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Organizer desk',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                      color: Ps.ink,
                    ),
                  ),
                  Text(
                    // The waiting entries get named rather than folded into
                    // "3 things need you". Everything else on that list is
                    // the organizer's own work, which can wait; an entry is
                    // a club sitting on an unanswered application, and it is
                    // the one item where the delay is somebody else's.
                    waiting > 0
                        ? '$waiting ${waiting == 1 ? 'entry is' : 'entries are'} '
                            'waiting for your approval'
                        : count == 0
                            ? 'Entries, timetable, umpires, venues, invitations'
                            : '$count ${count == 1 ? 'thing needs' : 'things need'} '
                                'you',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: count == 0 ? Ps.muted : MatchRow.lateColor,
                      fontWeight:
                          count == 0 ? FontWeight.w400 : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Ps.faint),
          ],
        ),
      ),
    );
  }
}

/// Where a season is run from — everything an organizer does to it, and
/// nothing a member or a visitor needs.
///
/// ## Why it is a page of its own
///
/// The season page used to open, for an organizer, on "Nobody can enter this
/// season yet", "NEEDS YOUR ATTENTION", "Running late" and a timetable
/// builder, above the standings. That made the organizer's view of their own
/// season a to-do list, and it made the page two different pages depending on
/// who opened it. So the main page is the season — stats and leaderboards —
/// for everybody, and this desk holds the work: opening entries, what needs
/// attention, the running-late shift, the tools, the sport-by-sport staffing
/// and the timetable builder.
///
/// Organizers only, by [SeasonOrganizerGate]: it is reachable by URL.
class SeasonDeskScreen extends ConsumerWidget {
  const SeasonDeskScreen({
    super.key,
    required this.orgId,
    required this.tournamentId,
  });

  final String orgId;
  final String tournamentId;

  /// How many things are waiting on the organizer: draws not yet taking
  /// entries, the attention items, and matches running late. Shared with the
  /// door on the main page so the two cannot disagree.
  static int pendingCount({
    required Tournament tournament,
    required List<Competition> events,
    required List<Fixture> fixtures,
    required List<SeasonSport> sports,
    int waitingEntries = 0,
  }) {
    final drafts =
        events.any((e) => e.status == CompetitionStatus.draft) ? 1 : 0;
    final noUmpire = sports.fold<int>(0, (n, s) => n + s.aheadWithoutUmpire);
    final late = sports.fold<int>(0, (n, s) => n + s.tally.overdue);
    return drafts +
        // Somebody waiting on a decision is the one item on this list that is
        // another person's time rather than the organizer's own work.
        (waitingEntries > 0 ? 1 : 0) +
        (_unpublishedSports(tournament, sports).isNotEmpty ? 1 : 0) +
        (noUmpire > 0 ? 1 : 0) +
        (late > 0 ? 1 : 0);
  }

  /// How many entries across a season's draws are still applications.
  ///
  /// Watched rather than passed in, because it is the one number on the desk
  /// door that changes while nobody is looking at the season — a club enters
  /// on Friday night and the organizer's page has to say so on Saturday
  /// morning without being reopened.
  static int waitingEntries(WidgetRef ref, List<Competition> events) {
    var n = 0;
    for (final e in events) {
      if (e.format.isSingleMatch) continue;
      final regs = ref
              .watch(registrationsProvider(CompRef(e.orgId, e.id)))
              .valueOrNull ??
          const <Registration>[];
      n += regs.where((r) => r.status == RegistrationStatus.pending).length;
    }
    return n;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (orgId: orgId, tournamentId: tournamentId);
    final tAsync = ref.watch(tournamentProvider(key));
    final access = ref.watch(seasonAccessProvider(key));

    return AppScaffold(
      orgId: orgId,
      title: 'Organizer desk',
      subtitle: tAsync.valueOrNull?.name,
      body: SeasonOrganizerGate(
        orgId: orgId,
        tournamentId: tournamentId,
        what: 'the organizer desk',
        child: AsyncView(
          value: tAsync,
          builder: (tournament) {
            if (tournament == null) {
              return const EmptyState(
                icon: Icons.search_off,
                title: 'This season no longer exists',
              );
            }
            final overview = ref.watch(tournamentOverviewProvider(key));
            final events =
                ref.watch(tournamentEventsProvider(key)).valueOrNull ??
                    const <Competition>[];
            final fixtures =
                ref.watch(tournamentFixturesProvider(key)).valueOrNull ??
                    const <Fixture>[];
            final sports = SeasonSport.split(
              tournament: tournament,
              events: events,
              fixtures: fixtures,
              leaderboard:
                  ref.watch(tournamentLeaderboardProvider(key)).valueOrNull,
              roster:
                  ref.watch(tournamentOfficialsProvider(key)).valueOrNull ??
                      const [],
            );

            return ListView(
              padding: const EdgeInsets.fromLTRB(0, 16, 0, 32),
              children: [
                ContentBounds(
                  maxWidth: 960,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Before anything else on the desk: somebody has asked
                      // to play and is waiting on an answer. See
                      // [PendingEntriesCard] for why approving an entry used
                      // to mean finding the right event page first.
                      PendingEntriesCard(events: events),
                      ClubRegistrationRequestsCard(
                        orgId: orgId,
                        tournamentId: tournamentId,
                      ),
                      _OpenEntriesCard(
                        orgId: orgId,
                        tournamentId: tournamentId,
                        events: events,
                      ),
                      _NeedsAttention(
                        orgId: orgId,
                        tournament: tournament,
                        sports: sports,
                      ),
                      RunningLateCard(
                        // Draft placeholders are never "running late" — see
                        // `Fixture.isDraft`.
                        fixtures: [
                          for (final f in fixtures)
                            if (!f.isDraft) f,
                        ],
                        onShift: ({by, newStart}) => ref
                            .read(tournamentRepositoryProvider)
                            .shiftSchedule(
                              orgId: orgId,
                              tournamentId: tournamentId,
                              by: by,
                              newStart: newStart,
                            ),
                      ),
                      // TC-ADM-077: the top-scorer/wicket-taker board, on the
                      // desk itself rather than only on the public season
                      // page — an organizer signing off results should not
                      // have to leave their own management screen to see who
                      // is leading. Same provider, same card, as the season
                      // home's "Season records" section; self-hides while
                      // there is nothing to show yet.
                      PlayerBoardsCard(
                        bySport: ref
                            .watch(tournamentPlayerBoardsBySportProvider(key))
                            .valueOrNull,
                      ),
                      _SeasonTools(
                        orgId: orgId,
                        tournamentId: tournamentId,
                        canManage: true,
                        hasChampions: false,
                      ),
                      const SizedBox(height: 16),
                      _OnCourtNow(sports: sports, canManage: true),
                      if (events.isEmpty)
                        _Events(
                          orgId: orgId,
                          tournamentId: tournamentId,
                          canManage: true,
                          overview: overview.valueOrNull,
                        )
                      else
                        _Sports(
                          orgId: orgId,
                          tournamentId: tournamentId,
                          sports: sports,
                          access: access,
                        ),
                      const SizedBox(height: 8),
                      // Read-only on the desk. Schedules are built and
                      // published per sport, on each sport's own schedule
                      // page; the season-wide buttons that used to sit here
                      // redrew and published every sport from one press.
                      GraphicalScheduleView(
                        tournament: tournament,
                        events: events,
                        fixtures: fixtures,
                        canManage: true,
                        onOpenFullPage: () => context.push(
                            Routes.tournamentSchedule(orgId, tournamentId)),
                        onOpenSport: (sportId) => context.push(
                          Routes.tournamentSchedule(
                            orgId,
                            tournamentId,
                            sportId: sportId,
                          ),
                        ),
                        onOpenMatch: (fixture) => openMatch(
                          context,
                          fixture: fixture,
                          myUid: ref.read(currentUidProvider),
                          canManage: true,
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
                  Expanded(
                    child: Text(
                      t.kind.label.toUpperCase(),
                      style: const TextStyle(
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
                    fixtures: [
                      for (final f in ref
                              .watch(tournamentFixturesProvider(
                                  (orgId: orgId, tournamentId: t.id)))
                              .valueOrNull ??
                          const <Fixture>[])
                        // A printed sheet of "Team A v Team B" placeholders
                        // is the organizer's draft, not anybody's timetable.
                        if (canManage || !f.isDraft) f,
                    ],
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
              if (t.organizerName != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Organised by ${t.organizerName}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
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
    final uid = ref.read(authUidProvider);
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
    final uid = ref.read(authUidProvider);
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

/// The season in one card: how far through, what is on, what is left, and
/// how many sports, umpires and people in charge it takes.
///
/// Counted from the sports ([SeasonSport]) rather than from the raw fixture
/// list, so the figures here are exactly the sum of the panels below and the
/// two can never be caught disagreeing.
class _SeasonPulse extends ConsumerWidget {
  const _SeasonPulse({
    required this.orgId,
    required this.tournamentId,
    required this.sports,
    required this.overview,
    required this.access,
  });

  final String orgId;
  final String tournamentId;
  final List<SeasonSport> sports;
  final TournamentOverview? overview;
  final SeasonAccess access;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (sports.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    var total = 0, played = 0, onNow = 0, ahead = 0, late = 0, halted = 0;
    final umpires = <String>{};
    for (final s in sports) {
      total += s.tally.total;
      played += s.tally.played;
      onNow += s.tally.inProgress;
      ahead += s.tally.ahead;
      late += s.tally.overdue;
      halted += s.tally.halted;
      umpires.addAll(s.umpires.map((u) => u.uid));
    }
    // The club's organizers, for the people who can read the member list —
    // which is exactly the people who would act on the number.
    final admins = access.seesStaffing
        ? (ref.watch(orgMembersProvider(orgId)).valueOrNull ?? const [])
            .where((m) => m.isActive && SportLead.eligible.contains(m.role))
            .length
        : null;
    final running = sports
        .where((s) =>
            s.stage == SportStage.running || s.stage == SportStage.needsRuling)
        .length;
    final done = sports.where((s) => s.stage == SportStage.complete).length;
    final through = overview?.scheduledThrough;

    return PsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Season at a glance',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (total > 0)
                Text(
                  '${(played * 100 / total).round()}% played',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Ps.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            [
              if (running > 0)
                '$running ${running == 1 ? 'sport' : 'sports'} in progress',
              if (done > 0) '$done complete',
              if (through != null) 'last match starts ${_stamp(through)}',
              if (running == 0 && done == 0) 'nothing played yet',
            ].join(' · '),
            style: const TextStyle(fontSize: 12.5, color: Ps.muted),
          ),
          if (total > 0) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: played / total,
                minHeight: 8,
                color: Ps.primary,
                backgroundColor: Ps.border,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PulseTile(
                icon: Icons.check_circle_outline,
                value: '$played/$total',
                label: 'Played',
              ),
              _PulseTile(
                icon: Icons.sensors,
                value: '$onNow',
                label: 'On now',
                color: onNow > 0 ? Ps.live : null,
              ),
              _PulseTile(
                icon: Icons.schedule,
                value: '$ahead',
                label: late > 0 ? 'To play · $late late' : 'To play',
                color: late > 0 ? MatchRow.lateColor : null,
              ),
              if (halted > 0)
                _PulseTile(
                  icon: Icons.pause_circle_outline,
                  value: '$halted',
                  label: 'Stopped',
                  color: MatchRow.lateColor,
                ),
              _PulseTile(
                icon: Icons.emoji_events_outlined,
                value: '${sports.length}',
                label: sports.length == 1 ? 'Sport' : 'Sports',
              ),
              // Who runs and officiates the season is the organizers' and
              // officials' business; a spectator's glance is the matches.
              if (access.seesUmpires)
                _PulseTile(
                  icon: Icons.sports_outlined,
                  value: '${umpires.length}',
                  label: 'Umpires',
                  onTap: access.canManage
                      ? () => context.push(
                            Routes.tournamentOfficials(orgId, tournamentId),
                          )
                      : null,
                ),
              if (admins != null)
                _PulseTile(
                  icon: Icons.shield_outlined,
                  value: '$admins',
                  label: 'Organizers',
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _stamp(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _PulseTile extends StatelessWidget {
  const _PulseTile({
    required this.icon,
    required this.value,
    required this.label,
    this.color,
    this.onTap,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Ps.ink;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Ps.radiusSm),
      child: Container(
        constraints: const BoxConstraints(minWidth: 96),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Ps.canvas,
          borderRadius: BorderRadius.circular(Ps.radiusSm),
          border: Border.all(
            color: color == null ? Ps.border : tint.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color ?? Ps.muted),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: tint,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: Ps.muted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Every place an organizer goes from a season, named, in one row.
///
/// These were scattered: two link tiles half-way down, two more at the very
/// bottom that only appeared once an event had finished, and the timetable
/// behind an overflow menu. An organizer should not have to remember which
/// scroll position a door is at.
class _SeasonTools extends StatelessWidget {
  const _SeasonTools({
    required this.orgId,
    required this.tournamentId,
    required this.canManage,
    required this.hasChampions,
  });

  final String orgId;
  final String tournamentId;
  final bool canManage;
  final bool hasChampions;

  @override
  Widget build(BuildContext context) {
    Widget tool(IconData icon, String label, VoidCallback onTap) =>
        OutlinedButton.icon(
          icon: Icon(icon, size: 18),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            foregroundColor: Ps.ink,
            side: const BorderSide(color: Ps.border),
          ),
          onPressed: onTap,
        );

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        tool(
          Icons.calendar_month_outlined,
          'Timetable',
          () => context.push(Routes.tournamentSchedule(orgId, tournamentId)),
        ),
        if (canManage) ...[
          // The way a season fills with other clubs — see
          // `InviteClubsScreen`. On the surface, not in the menu.
          tool(
            Icons.send_outlined,
            'Invite clubs',
            () => context.push(Routes.inviteClubs(orgId, tournamentId)),
          ),
          tool(
            Icons.add_circle_outline,
            'Add a sport or event',
            () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => _AttachEventsSheet(
                orgId: orgId,
                tournamentId: tournamentId,
              ),
            ),
          ),
          tool(
            Icons.sports_outlined,
            'Umpire panel',
            () => context.push(Routes.tournamentOfficials(orgId, tournamentId)),
          ),
          // The grounds come before the panel in the work: a panel is
          // assigned to a timetable, and the timetable cannot be right until
          // the grounds have said when they are open.
          tool(
            Icons.event_available_outlined,
            'Venue planner',
            () => context.push(Routes.venuePlanner(orgId, tournamentId)),
          ),
        ],
        if (hasChampions)
          tool(
            Icons.workspace_premium_outlined,
            'Certificates',
            () => context.push(Routes.certificates(orgId, tournamentId)),
          ),
        tool(
          Icons.photo_library_outlined,
          'Memories',
          () => context.push(Routes.seasonMemories(orgId, tournamentId)),
        ),
      ],
    );
  }
}

/// Every match being played across the season, under its sport.
class _OnCourtNow extends ConsumerWidget {
  const _OnCourtNow({required this.sports, required this.canManage});

  final List<SeasonSport> sports;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = [
      for (final s in sports)
        if (s.onNow.isNotEmpty) s,
    ];
    if (busy.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final many = sports.length > 1;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const LiveDot(size: 10),
                const SizedBox(width: 8),
                Text('On court now', style: theme.textTheme.titleMedium),
              ],
            ),
          ),
          for (final s in busy) ...[
            if (many)
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 4, 0, 6),
                child: Row(
                  children: [
                    Icon(SportVisual.of(s.sportId).icon,
                        size: 14, color: SportVisual.of(s.sportId).color),
                    const SizedBox(width: 6),
                    Text(
                      s.sportName.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: Ps.muted,
                      ),
                    ),
                  ],
                ),
              ),
            for (final f in s.onNow)
              MatchRow(
                fixture: f,
                // The match itself, never the event page: tapping a score is
                // asking for that score.
                onTap: () => openMatch(
                  context,
                  fixture: f,
                  myUid: ref.read(currentUidProvider),
                  canManage: canManage,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Sports with matches on the board whose timetable is not published yet.
List<SeasonSport> _unpublishedSports(
  Tournament tournament,
  List<SeasonSport> sports,
) =>
    [
      for (final s in sports)
        if (s.tally.total > 0 && !tournament.isSportScheduleLocked(s.sportId))
          s,
    ];

/// What the organizer should do next, in one card — or nothing at all when
/// the season is in order.
///
/// These were warnings scattered through the page, some of them on panels a
/// member could see. They are the running of the season, and they belong on
/// the organizer's desk, above it.
class _NeedsAttention extends StatelessWidget {
  const _NeedsAttention({
    required this.orgId,
    required this.tournament,
    required this.sports,
  });

  final String orgId;
  final Tournament tournament;
  final List<SeasonSport> sports;

  @override
  Widget build(BuildContext context) {
    final t = tournament;
    final unpublished = _unpublishedSports(t, sports);
    final noUmpire = sports.fold<int>(0, (n, s) => n + s.aheadWithoutUmpire);
    final leaderless = [
      for (final s in sports)
        if (s.leads.isEmpty) s.sportName,
    ];

    final items = <Widget>[
      if (unpublished.isNotEmpty)
        _AttentionRow(
          icon: Icons.lock_open_outlined,
          text: 'The ${_list([for (final s in unpublished) s.sportName])} '
              '${unpublished.length == 1 ? 'timetable is' : 'timetables are'} '
              'still a draft — players and parents cannot rely on '
              '${unpublished.length == 1 ? 'it' : 'them'} until published.',
          action: 'Timetable',
          onTap: () => context.push(Routes.tournamentSchedule(
            orgId,
            t.id,
            sportId: unpublished.first.sportId,
          )),
        ),
      if (noUmpire > 0)
        _AttentionRow(
          icon: Icons.sports_outlined,
          text: '$noUmpire ${noUmpire == 1 ? 'match' : 'matches'} still to '
              'play ${noUmpire == 1 ? 'has' : 'have'} no umpire.',
          action: 'Umpire panel',
          onTap: () => context.push(Routes.tournamentOfficials(orgId, t.id)),
        ),
      if (leaderless.isNotEmpty && sports.length > 1)
        _AttentionRow(
          icon: Icons.shield_outlined,
          text: 'Nobody is in charge of ${_list(leaderless)} — assign '
              'someone from the sport below.',
        ),
    ];
    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: MatchRow.lateColor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(Ps.radius),
          border: Border.all(color: MatchRow.lateColor.withValues(alpha: 0.35)),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'NEEDS YOUR ATTENTION',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: MatchRow.lateColor,
              ),
            ),
            const SizedBox(height: 4),
            ...items,
          ],
        ),
      ),
    );
  }

  static String _list(List<String> names) => names.length <= 2
      ? names.join(' and ')
      : '${names.take(2).join(', ')} and ${names.length - 2} more';
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({
    required this.icon,
    required this.text,
    this.action,
    this.onTap,
  });

  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: MatchRow.lateColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontSize: 13, color: Ps.ink),
              ),
            ),
            if (action != null && onTap != null)
              TextButton(onPressed: onTap, child: Text(action!)),
          ],
        ),
      );
}

/// The matches the signed-in official is on, soonest first — what an umpire
/// opens the season page for.
class _YourDuties extends ConsumerWidget {
  const _YourDuties({required this.fixtures, required this.canManage});

  final List<Fixture> fixtures;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUidProvider);
    if (uid == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final mine = [
      for (final f in fixtures)
        if (!f.isDraft &&
            !MatchPhase.of(f, now).isDone &&
            (f.scorerUids.contains(uid) || f.officials.any((o) => o.uid == uid)))
          f,
    ]..sort((a, b) {
        final at = a.scheduledAt, bt = b.scheduledAt;
        if (at == null || bt == null) return at == null ? 1 : -1;
        return at.compareTo(bt);
      });

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.sports_outlined, size: 20, color: Ps.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    mine.isEmpty
                        ? 'Your umpiring'
                        : 'Your matches to umpire (${mine.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (mine.isEmpty)
              const Text(
                'No matches are assigned to you yet. They appear here as soon '
                'as the organizers put you on one.',
                style: TextStyle(fontSize: 12.5, color: Ps.muted),
              )
            else
              for (final f in mine.take(5))
                MatchRow(
                  fixture: f,
                  onTap: () => openMatch(
                    context,
                    fixture: f,
                    myUid: uid,
                    canManage: canManage,
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// The season-wide boards, folded.
class _SeasonRecords extends ConsumerWidget {
  const _SeasonRecords({
    required this.orgId,
    required this.tournamentId,
    required this.leaderboard,
  });

  final String orgId;
  final String tournamentId;
  final TournamentLeaderboard? leaderboard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boards = ref
        .watch(tournamentPlayerBoardsBySportProvider(
          (orgId: orgId, tournamentId: tournamentId),
        ))
        .valueOrNull;
    final hasPlayers = leaderboard?.players.isNotEmpty ?? false;
    final hasBoards = boards?.values.any((b) => !b.isEmpty) ?? false;
    if (!hasPlayers && !hasBoards) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: Ps.surface,
          borderRadius: BorderRadius.circular(Ps.radius),
          border: Border.all(color: Ps.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          // Open on arrival the moment there is a genuine top performer to
          // show — TC-ADM-077. Before that, a season's first morning has
          // nothing under here worth spending a screen's worth of space on
          // by default, which is why this stays collapsed for [hasBoards]
          // false rather than always-open.
          initiallyExpanded: hasBoards,
          leading: const Icon(Icons.bar_chart_rounded),
          title: const Text('Season records & top performers'),
          subtitle: const Text(
            'Every entrant\'s record and the season\'s top individual figures',
          ),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          children: [
            LeaderboardCard(
              leaderboard: leaderboard,
              onTapEntrant: (record) => context.push(
                Routes.seasonEntrant(orgId, tournamentId, record.entrantId),
              ),
            ),
            // That board says who had the best season; this one says what
            // they actually did — "Rahul won five" against "Rahul scored 642".
            PlayerBoardsCard(bySport: boards),
          ],
        ),
      ),
    );
  }
}

/// The sports, one panel each, with a chip row to focus one.
class _Sports extends StatefulWidget {
  const _Sports({
    required this.orgId,
    required this.tournamentId,
    required this.sports,
    required this.access,
  });

  final String orgId;
  final String tournamentId;
  final List<SeasonSport> sports;
  final SeasonAccess access;

  @override
  State<_Sports> createState() => _SportsState();
}

class _SportsState extends State<_Sports> {
  /// Null is "All sports".
  String? _focus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sports = widget.sports;
    final many = sports.length > 1;
    // A sport detached since it was chosen leaves a focus on nothing.
    final focus = sports.any((s) => s.sportId == _focus) ? _focus : null;
    final shown = focus == null
        ? sports
        : sports.where((s) => s.sportId == focus).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              many ? 'Sports (${sports.length})' : 'The sport',
              style: theme.textTheme.titleMedium,
            ),
          ),
          if (many) ...[
            _SportPicker(
              sports: sports,
              selected: focus,
              onChanged: (id) => setState(() => _focus = id),
            ),
            const SizedBox(height: 10),
          ],
          for (final s in shown)
            SeasonSportPanel(
              // Keyed on the choice too, so going back to "All sports" folds
              // the panel that was open rather than leaving it where it was.
              key: ValueKey('${s.sportId}|$focus'),
              orgId: widget.orgId,
              tournamentId: widget.tournamentId,
              sport: s,
              access: widget.access,
              // One sport, or the one picked, opens. "All sports" is the list
              // of folded sport headers — each its own drop-down — which is
              // the overview of a season with several.
              initiallyExpanded: !many || focus != null,
              eventTile: (e) => _EventTile(
                orgId: widget.orgId,
                summary: e,
                canManage: widget.access.canManage,
              ),
            ),
        ],
      ),
    );
  }
}

/// "Sport: Cricket ▾" — one drop-down to jump between the season's sports.
///
/// A drop-down rather than a row of chips because a season of six sports did
/// not fit a phone as chips and scrolled sideways, hiding the sport you were
/// looking for; a menu lists every sport at once, each with where it is.
class _SportPicker extends StatelessWidget {
  const _SportPicker({
    required this.sports,
    required this.selected,
    required this.onChanged,
  });

  final List<SeasonSport> sports;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final live = sports.fold<int>(0, (n, s) => n + s.tally.inProgress);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Ps.surface,
        borderRadius: BorderRadius.circular(Ps.radiusSm),
        border: Border.all(color: Ps.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          key: const ValueKey('season-sport-picker'),
          value: selected,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          borderRadius: BorderRadius.circular(Ps.radiusSm),
          onChanged: onChanged,
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: _PickerRow(
                leading: const Icon(Icons.apps_rounded, size: 22, color: Ps.muted),
                title: 'All sports',
                status: live > 0 ? '$live on now' : '${sports.length} sports',
                statusColor: live > 0 ? Ps.live : Ps.muted,
              ),
            ),
            for (final s in sports)
              DropdownMenuItem<String?>(
                value: s.sportId,
                child: _PickerRow(
                  leading: SportBadge(sportId: s.sportId, size: 26),
                  title: s.sportName,
                  status: _statusOf(s),
                  statusColor: s.tally.inProgress > 0
                      ? Ps.live
                      : s.tally.overdue > 0
                          ? MatchRow.lateColor
                          : Ps.muted,
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _statusOf(SeasonSport s) {
    final t = s.tally;
    if (t.inProgress > 0) return '${t.inProgress} on now';
    if (t.overdue > 0) return '${t.overdue} late';
    return switch (s.stage) {
      SportStage.notDrawn => 'Not drawn yet',
      SportStage.notStarted => 'Not started',
      SportStage.complete => 'Complete',
      SportStage.needsRuling => '${t.halted} stopped · needs a ruling',
      SportStage.running => '${t.played}/${t.total} played',
    };
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.leading,
    required this.title,
    required this.status,
    required this.statusColor,
  });

  final Widget leading;
  final String title;
  final String status;
  final Color statusColor;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          leading,
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: Ps.ink,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            status,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: statusColor,
            ),
          ),
        ],
      );
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
            Card(
              child: ListTile(
                leading: const Icon(Icons.playlist_add_outlined),
                title: const Text('No events yet'),
                subtitle: Text(
                  canManage
                      ? 'A season holds many draws — U-13 singles, senior '
                          'doubles, and the rest. Add a sport, or attach '
                          "the club's events, so they share courts and one "
                          'timetable.'
                      : 'The organizers have not added the sports to this '
                          'season yet.',
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

  /// Events to create into this season, one per sport × arrangement ×
  /// category — picked with the same sheet the season forms use.
  ///
  /// This used to be a sport id mapped to a format, which could only ever
  /// add a sport's default arrangement in the Open category: a live season
  /// had no way to gain Badminton Doubles or an U-17 draw (test run TC-24).
  final _newEvents = <SeasonCategorySpec>[];
  bool _busy = false;

  /// Why the last Add did nothing, shown INSIDE the sheet.
  ///
  /// A `SnackBar` is drawn by the scaffold underneath this modal sheet, so
  /// the refusal `addSportsToSeason` throws for an already-present category
  /// ("Badminton Singles · Open is already in this season…") was posted to a
  /// surface the organizer could not see: the sheet simply stayed open with
  /// nothing added and nothing said (test run TC-ADM-006).
  String? _error;

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
                for (final sport in _offeredSports.take(8))
                  ActionChip(
                    avatar: Text(sport.icon),
                    label: Text(sport.name),
                    onPressed: () => _pickEvents(sportId: sport.id),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('Any sport or category'),
                  onPressed: () => _pickEvents(
                    sportId: _offeredSports.length == 1
                        ? _offeredSports.first.id
                        : null,
                  ),
                ),
              ],
            ),
            if (_newEvents.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final spec in _newEvents)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Text(
                    spec.sport.icon,
                    style: const TextStyle(fontSize: 20),
                  ),
                  title: Text(spec.label),
                  subtitle: Text(spec.format.label),
                  trailing: IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _newEvents.remove(spec)),
                  ),
                ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline,
                      size: 18, color: theme.colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                ],
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

  int get _total => _picked.length + _newEvents.length;

  /// Opens the season forms' category sheet and keeps what it returns.
  Future<void> _pickEvents({String? sportId}) async {
    final season = ref
        .read(tournamentProvider((
          orgId: widget.orgId,
          tournamentId: widget.tournamentId,
        )))
        .valueOrNull;
    final drafts = await showModalBottomSheet<List<CategoryDraftItem>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => BulkCategorySelectorSheet(
        initialSportId: sportId,
        cutOff: season?.startDate,
      ),
    );
    if (drafts == null || drafts.isEmpty || !mounted) return;
    setState(() {
      for (final d in drafts) {
        final spec = SeasonCategorySpec(
          sportId: d.sportId,
          sideFormat: d.sideFormat,
          category: d.category,
          format: d.format,
          equipment: d.equipmentType,
        );
        if (!_newEvents.any((e) => e.identity == spec.identity)) {
          _newEvents.add(spec);
        }
      }
    });
    // After the sheet has finished closing: its fields still hold these
    // controllers while it animates out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final d in drafts) {
        d.dispose();
      }
    });
  }

  /// Every sport for a season; only its own for a one-sport tournament — a
  /// badminton championship takes another badminton draw, not a cricket one.
  List<SportSpec> get _offeredSports {
    final key = (orgId: widget.orgId, tournamentId: widget.tournamentId);
    final season = ref.watch(tournamentProvider(key)).valueOrNull;
    if (season == null || !season.isSingleSportTournament) {
      return SportCatalog.all;
    }
    final own = {
      for (final e in ref.watch(tournamentEventsProvider(key)).valueOrNull ??
          const <Competition>[])
        e.sportId,
    };
    if (own.isEmpty) return SportCatalog.all;
    return [
      for (final sport in SportCatalog.all)
        if (own.contains(sport.id)) sport,
    ];
  }

  Future<void> _save() async {
    if (_busy) return;
    final uid = ref.read(authUidProvider);
    final season = ref
        .read(tournamentProvider((
          orgId: widget.orgId,
          tournamentId: widget.tournamentId,
        )))
        .valueOrNull;
    if (uid == null || season == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // One commit: new sports built like every other event of this season,
      // existing events attached, and the count kept true.
      await ref.read(tournamentRepositoryProvider).addSportsToSeason(
            season: season,
            sports: _newEvents,
            attachCompIds: _picked.toList(),
            createdBy: uid,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      // Inline rather than a snackbar: see [_error]. The sheet stays open on
      // purpose, with the picked list intact, so the organizer can drop the
      // duplicate and add the rest.
      if (mounted) setState(() => _error = errorMessage(e));
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
    final season = c.tournamentId == null
        ? null
        : ref
            .read(tournamentProvider(
                (orgId: widget.orgId, tournamentId: c.tournamentId!)))
            .valueOrNull;
    final result = await showDialog<_EventEdit>(
      context: context,
      builder: (_) => _EditEventDialog(competition: c, season: season),
    );
    if (result == null) return;
    final updated = result.competition;
    try {
      await ref.read(competitionRepositoryProvider).updateCompetition(updated);
      // `Competition.toUpdate()` deliberately omits `status` — the lifecycle
      // belongs to `setStatus`, which also lifts a season out of draft when a
      // draw under it opens. Without this the dialog's Registration Status
      // dropdown was a silent no-op: the toast said saved, the field reverted
      // on reopen (TC-ADM-009).
      if (updated.status != c.status) {
        await ref.read(competitionRepositoryProvider).setStatus(
              orgId: c.orgId,
              compId: c.id,
              status: updated.status,
              seasonId: c.tournamentId,
            );
      }
      if (result.start != c.startDate || result.end != c.endDate) {
        await ref.read(tournamentRepositoryProvider).setEventDates(
              orgId: c.orgId,
              compId: c.id,
              start: result.start,
              end: result.end,
            );
      }
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

/// What the edit dialog hands back. The dates travel beside the competition
/// because a null [end] ("runs to the season's last day") can't go through
/// `Competition.toUpdate`, which drops nulls.
typedef _EventEdit = ({Competition competition, DateTime? start, DateTime? end});

class _EditEventDialog extends StatefulWidget {
  const _EditEventDialog({required this.competition, this.season});
  final Competition competition;

  /// The season the event belongs to, for the date pickers' bounds.
  final Tournament? season;

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

  /// The event's own start, date and time of day. Null means it follows
  /// the season's first day.
  late DateTime? _start = widget.competition.startDate;

  /// The event's last day. Null means the season's last day.
  late DateTime? _end = widget.competition.endDate;

  /// Set by hand here after a season is moved, when the time the move kept
  /// is not the one the organizer wants. See `SeasonDateShift`.
  Future<void> _pickStart() async {
    final season = widget.season;
    final now = DateTime.now();
    final initial = _start ?? season?.startDate ?? now;
    final first = DateTime(now.year - 1);
    final last = DateTime(now.year + 3);
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(first) || initial.isAfter(last)
          ? now
          : initial,
      firstDate: first,
      lastDate: last,
      helpText: 'Event starts on',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'Event starts at',
    );
    if (!mounted) return;
    setState(() {
      final t = time ?? TimeOfDay.fromDateTime(initial);
      _start = DateTime(date.year, date.month, date.day, t.hour, t.minute);
      if (_end != null && _day(_end!).isBefore(_day(_start!))) _end = null;
    });
  }

  Future<void> _pickEnd() async {
    final now = DateTime.now();
    final from = _start ?? widget.season?.startDate ?? now;
    final first = DateTime(from.year, from.month, from.day);
    final initial = _end ?? widget.season?.endDate ?? from;
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(first) ? first : initial,
      firstDate: first,
      lastDate: DateTime(now.year + 3),
      helpText: 'Last day of this event',
    );
    if (date == null || !mounted) return;
    setState(() => _end = date);
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// A warning, not a refusal: an event outside its season is legal, but it
  /// won't be scheduled on those days.
  String? get _outsideSeason {
    final s = widget.season;
    final start = _start;
    if (s?.startDate == null || start == null) return null;
    final first = _day(s!.startDate!);
    final last = _day(s.endDate ?? s.startDate!);
    final day = _day(start);
    if (day.isBefore(first) || day.isAfter(last)) {
      return 'This is outside the season\'s dates, so no matches will be '
          'scheduled on it until the season covers it.';
    }
    return null;
  }

  String _formatStart(DateTime d) {
    final loc = MaterialLocalizations.of(context);
    return '${loc.formatMediumDate(d)} · '
        '${loc.formatTimeOfDay(TimeOfDay.fromDateTime(d))}';
  }

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
                      tooltip: 'Close',
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
                const SizedBox(height: 12),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Starts',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _start == null
                              ? 'With the season'
                              : _formatStart(_start!),
                        ),
                      ),
                      TextButton(
                        onPressed: _pickStart,
                        child: const Text('Change'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Last day',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _end == null
                              ? 'The season\'s last day'
                              : MaterialLocalizations.of(context)
                                  .formatMediumDate(_end!),
                        ),
                      ),
                      if (_end != null)
                        IconButton(
                          tooltip: 'Run to the season\'s last day',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() => _end = null),
                        ),
                      TextButton(
                        onPressed: _pickEnd,
                        child: const Text('Change'),
                      ),
                    ],
                  ),
                ),
                if (_outsideSeason != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _outsideSeason!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
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
                        Navigator.of(context).pop<_EventEdit>((
                          competition: updated,
                          start: _start,
                          end: _end,
                        ));
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
              // An open slot has no entrant page to open.
              onTap: Entrant.isPlaceholderId(rows[i].entrantId)
                  ? null
                  : () => context.push(
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
