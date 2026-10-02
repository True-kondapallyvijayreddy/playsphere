import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/competition.dart';
import '../../core/models/enums.dart';
import '../../core/models/organization.dart';
import '../../core/models/tournament.dart';
import '../../core/providers.dart';
import '../home/home_providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../domain/tournament/invitation_letter.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/identity.dart';
import '../../shared/ui_kit.dart';
import '../competitions/widgets/invited_club_block.dart';
import '../tournaments/season_entry.dart';

/// Registering for a season or tournament — where an invitation's link lands.
///
/// ## Why a page of its own
///
/// The season page is a season's whole life: standings, timetable, results,
/// memories. A club that has just been invited wants one thing from it —
/// "what can we enter, and where is the button" — and on the season page
/// that answer is a scroll and a tap into each sport away. This page is only
/// that answer: every draw in the season, grouped by sport, whether it is
/// taking entries, and a Register button beside each that opens it.
///
/// The actual entry still happens on the event, deliberately. Who may enter
/// what — a member, a guest through an open door, an invited club entering a
/// team — is already decided there and in the rules, and a second copy of
/// those decisions here would be a second copy that drifts.
///
/// ## The invitation, if there is one
///
/// An invited club's organizers must accept before the rules let them enter
/// a side, so an unanswered invitation is answered here, at the top. Members
/// of the invited club see [InvitedClubBlock] instead, which is how they say
/// they are available.
class SeasonRegisterScreen extends ConsumerWidget {
  const SeasonRegisterScreen({
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
    final kind = tAsync.valueOrNull?.kind ?? SeasonKind.season;

    return AppScaffold(
      title: 'Register',
      subtitle: tAsync.valueOrNull?.name,
      body: AsyncView<Tournament?>(
        value: tAsync,
        builder: (t) {
          if (t == null) {
            // The season can be unreadable to an invited club — a private host
            // club's seasons are for its members — while the invitation itself
            // is not. So the answer stays on the page: a club can still say
            // yes or no to the letter it was sent.
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                ContentBounds(
                  maxWidth: 720,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _InvitationAnswer(
                        orgId: orgId,
                        tournamentId: tournamentId,
                      ),
                      EmptyState(
                        icon: Icons.search_off,
                        title: 'This ${kind.noun} is not available',
                        message: 'It may have been removed, or its club is '
                            'private. A private club\'s season can only be '
                            'opened by its members — ask the host club to '
                            'make the club public so you can register.',
                      ),
                    ],
                  ),
                ),
              ],
            );
          }
          final host = ref.watch(organizationProvider(orgId)).valueOrNull;
          final eventsAsync = ref.watch(tournamentEventsProvider(key));
          final events = [
            for (final c in eventsAsync.valueOrNull ?? const <Competition>[])
              if (c.status != CompetitionStatus.cancelled &&
                  !c.format.isSingleMatch)
                c,
          ];
          final bySport = <String, List<Competition>>{};
          for (final e in events) {
            (bySport[e.sportId] ??= <Competition>[]).add(e);
          }
          // Counted against what this profile has already entered, so the
          // headline agrees with the rows under it. "4 events taking entries"
          // above four rows that all say "Already registered" is the same
          // contradiction as the Register button that would not go away.
          final status = ref.watch(seasonEntryStatusProvider(key));
          final open = status.openAndNotEntered.length;
          final mine = status.entered.length;
          // Nothing is known yet, which is NOT the same as nothing being open.
          // `SeasonEntryStatus.none` is what the provider returns while the
          // events are still loading, so the headline below read "Entries are
          // not open yet" for the twenty seconds this page takes to load on a
          // slow connection — to somebody who had just accepted an invitation
          // in order to enter. The truthful answer while loading is that we do
          // not know yet.
          final stillLoading = eventsAsync.isLoading && events.isEmpty;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              ContentBounds(
                maxWidth: 720,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Masthead(tournament: t, host: host, events: events),
                    const SizedBox(height: 14),
                    _InvitationAnswer(orgId: orgId, tournamentId: tournamentId),
                    InvitedClubBlock(
                      hostOrgId: orgId,
                      tournamentId: tournamentId,
                    ),
                    const SizedBox(height: 6),
                    AsyncErrorStrip(value: eventsAsync, what: 'the events'),
                    Text(
                      stillLoading
                          ? 'Checking what’s open…'
                          : open == 0 && mine > 0
                              ? mine == 1
                                  ? "You're registered for 1 event"
                                  : "You're registered for $mine events"
                              : open == 0
                                  ? 'Entries are not open yet'
                                  : open == 1
                                      ? '1 event taking entries'
                                      : '$open events taking entries',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Ps.ink,
                      ),
                    ),
                    if (!stillLoading &&
                        open == 0 &&
                        mine == 0 &&
                        events.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${host?.name ?? 'The organizers'} will open entries '
                          'soon. Come back to this page — the Register '
                          'buttons light up here.',
                          style:
                              const TextStyle(fontSize: 12.5, color: Ps.muted),
                        ),
                      ),
                    const SizedBox(height: 10),
                    if (stillLoading)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    for (final entry in bySport.entries)
                      _SportBlock(
                        sportId: entry.key,
                        events: entry.value,
                        feeMode: t.feeMode,
                        seasonFee: t.entryFeeRupees,
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () =>
                          context.push(Routes.tournament(orgId, tournamentId)),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: Text('See the full ${t.kind.noun}'),
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

class _Masthead extends StatelessWidget {
  const _Masthead({
    required this.tournament,
    required this.host,
    required this.events,
  });

  final Tournament tournament;
  final Organization? host;
  final List<Competition> events;

  @override
  Widget build(BuildContext context) {
    final t = tournament;
    final when = InvitationLetter.dateSpan(t.startDate, t.endDate)
        .replaceFirst(RegExp(r'^(from|on) '), '');
    final sports = InvitationLetter.sportList(events.map((e) => e.sportName));
    final place = events
        .map((e) => e.venue?.trim() ?? '')
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');

    return PsCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PsCrest(
            name: host?.name ?? t.name,
            logoUrl: t.logoUrl ?? host?.logoUrl,
            seed: t.orgId,
            size: 48,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.kind.label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: Ps.primary,
                  ),
                ),
                Text(
                  t.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Ps.ink,
                  ),
                ),
                if (host != null)
                  Text(
                    'Hosted by ${host!.name}',
                    style: const TextStyle(fontSize: 12.5, color: Ps.muted),
                  ),
                const SizedBox(height: 6),
                PsMetaRow(
                  items: [
                    if (sports.isNotEmpty) sports,
                    if (when.isNotEmpty) when,
                    if (place.isNotEmpty) place,
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Accept the invitation" for the invited club's organizers, while it is
/// still unanswered. Nothing for anybody else.
class _InvitationAnswer extends ConsumerStatefulWidget {
  const _InvitationAnswer({required this.orgId, required this.tournamentId});

  final String orgId;
  final String tournamentId;

  @override
  ConsumerState<_InvitationAnswer> createState() => _InvitationAnswerState();
}

class _InvitationAnswerState extends ConsumerState<_InvitationAnswer> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final ctx = ref.watch(invitedSeasonContextProvider(
      (hostOrgId: widget.orgId, tournamentId: widget.tournamentId),
    ));
    if (ctx == null || !ctx.canEnterForClub || !ctx.invite.isPending) {
      return const SizedBox.shrink();
    }
    final invite = ctx.invite;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${invite.fromOrgName} invited ${invite.toOrgName}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                'Accept the invitation to enter your club\'s teams. '
                'Accepting does not enter anyone by itself.',
                style: TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          try {
                            await ref
                                .read(tournamentRepositoryProvider)
                                .respondToInvite(
                                  inviteId: invite.id,
                                  status: 'accepted',
                                );
                          } catch (e) {
                            if (context.mounted) showError(context, e);
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Accept invitation'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SportBlock extends StatelessWidget {
  const _SportBlock({
    required this.sportId,
    required this.events,
    required this.feeMode,
    required this.seasonFee,
  });

  final String sportId;
  final List<Competition> events;
  final SeasonFeeMode feeMode;
  final int seasonFee;

  @override
  Widget build(BuildContext context) {
    final sport = SportCatalog.byId(sportId);
    final name = events.first.sportName.isEmpty
        ? sport.name
        : events.first.sportName;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PsCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              child: Text(
                '${sport.icon}  $name',
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: Ps.ink,
                ),
              ),
            ),
            for (final e in events)
              _EventRow(event: e, feeMode: feeMode, seasonFee: seasonFee),
          ],
        ),
      ),
    );
  }
}

class _EventRow extends ConsumerWidget {
  const _EventRow({
    required this.event,
    required this.feeMode,
    required this.seasonFee,
  });

  final Competition event;
  final SeasonFeeMode feeMode;
  final int seasonFee;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = event;
    // Already in this draw — as yourself, in the squad that entered, or as
    // the person who filed it. The Register button on a draw you are already
    // in is the whole of the "it still says register" complaint, and this is
    // the row it is drawn on. See [SeasonEntryStatus].
    final entered = ref.watch(
      competitionEnteredProvider(CompRef(e.orgId, e.id)),
    );
    final isOpen = e.status == CompetitionStatus.registrationOpen;
    final fee = feeMode == SeasonFeeMode.perEvent ? e.entryFeeRupees : 0;
    final details = <String>[
      if (!e.category.isOpen) e.category.label,
      e.format.label,
      e.entrantType == EntrantType.team ? 'Teams' : 'Players',
      e.maxEntrants == null
          ? '${e.confirmedCount} entered'
          : '${e.confirmedCount}/${e.maxEntrants} entered',
      if (fee > 0) '₹$fee',
      if (feeMode == SeasonFeeMode.wholeSeason && seasonFee > 0)
        'Season fee ₹$seasonFee',
    ];

    return ListTile(
      title: Text(
        e.name,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
      ),
      subtitle: Text(details.join(' · ')),
      trailing: entered
          // A statement, not a button. Tapping the row still opens the event,
          // which is where an entry is withdrawn or a second side added — but
          // nothing here says "register" to somebody who has.
          ? const Chip(
              avatar: Icon(Icons.check, size: 16, color: Ps.primary),
              label: Text('Already registered'),
              visualDensity: VisualDensity.compact,
            )
          : isOpen
          ? FilledButton(
              onPressed: () =>
                  context.push(Routes.competition(e.orgId, e.id)),
              child: Text(
                e.entrantType == EntrantType.team ? 'Enter a team' : 'Register',
              ),
            )
          : Text(
              switch (e.status) {
                CompetitionStatus.draft => 'Opens soon',
                CompetitionStatus.registrationClosed => 'Entries closed',
                _ => e.status.label,
              },
              style: const TextStyle(fontSize: 12, color: Ps.muted),
            ),
      onTap: () => context.push(Routes.competition(e.orgId, e.id)),
    );
  }
}
