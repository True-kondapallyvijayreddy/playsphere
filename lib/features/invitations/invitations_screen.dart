import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/async_combine.dart';
import '../../core/layout/responsive.dart';
import '../../core/models/tournament.dart';
import '../../core/models/tournament_invite.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/tournament/invitation_letter.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/identity.dart';
import '../../shared/ui_kit.dart';
import '../home/home_providers.dart';
import 'widgets/invitation_card.dart';

/// Club-to-club invitations, in one place.
///
/// ## Why a space of its own
///
/// An invitation used to arrive as a notification, and to be sent from a
/// sheet three menus deep on the season page. Both undersold it. For a club
/// running a season, inviting other clubs is how the season fills; for a club
/// being invited, it is the best thing in their inbox that week. Neither
/// belongs in a list of score updates.
///
/// Two tabs, because they are two jobs usually done by the same person:
///
///  * **Received** — every invitation to any club of yours, as a letter with
///    a Register button. Visible to every member, answerable by the people
///    who run the club — see [InvitationCard].
///  * **Send** — every season and tournament of every club you run, each
///    with how its invitations stand and a button into the composer.
///
/// ## One club at a time
///
/// Both tabs are about the club selected in the app bar and nothing else, and
/// the screen says which club that is at the top. A person running three
/// clubs used to see all three clubs' invitations mixed together and could
/// not tell which club was being asked, or which was answering — see
/// `scopedOrgIdsProvider`. Switching club in the app bar switches this page.
///
/// Opened for a named club ([clubId]) — from an invitation's notification —
/// the selection switches to that club on arrival, the way opening a club
/// page does. Otherwise an admin of two clubs with the other one selected
/// would tap "X invited you" and land on a list without it.
class InvitationsScreen extends ConsumerStatefulWidget {
  const InvitationsScreen({super.key, this.initialTab = 0, this.clubId});

  /// 0 = received, 1 = send.
  final int initialTab;

  /// The club to show, when the link names one. Ignored unless the person
  /// is an active member of it — `switchTo` refuses anything else.
  final String? clubId;

  @override
  ConsumerState<InvitationsScreen> createState() => _InvitationsScreenState();
}

class _InvitationsScreenState extends ConsumerState<InvitationsScreen>
    with SingleTickerProviderStateMixin {
  late final _tabs =
      TabController(length: 2, vsync: this, initialIndex: widget.initialTab);

  /// Whether [InvitationsScreen.clubId] has been adopted. Once only, so
  /// the person can still switch club from the app bar while here.
  bool _adoptedLinkedClub = false;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _adoptLinkedClub() {
    final linked = widget.clubId;
    if (_adoptedLinkedClub || linked == null || linked.isEmpty) return;
    final mine = ref.watch(myActiveOrgIdsProvider);
    // Memberships still loading: try again when they arrive.
    if (!mine.contains(linked)) {
      if (ref.watch(myActiveMembershipsProvider).hasValue) {
        _adoptedLinkedClub = true;
      }
      return;
    }
    _adoptedLinkedClub = true;
    if (ref.read(currentClubIdProvider) == linked) return;
    // Deferred a frame: a provider write during build is a build that
    // depends on its own outcome.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(currentClubIdProvider.notifier).switchTo(linked);
    });
  }

  @override
  Widget build(BuildContext context) {
    _adoptLinkedClub();
    final received = ref.watch(_receivedInvitesProvider).valueOrNull ?? const [];
    final waiting = received.where((i) => i.isPending).length;
    final clubId = ref.watch(currentClubIdProvider);
    final club = clubId == null
        ? null
        : ref.watch(organizationProvider(clubId)).valueOrNull;

    return AppScaffold(
      title: 'Invitations',
      // Which club, said up front: everything below is this club's alone.
      subtitle: club == null ? 'Pick a club first' : 'For ${club.name}',
      body: Column(
        children: [
          TabBar(
            controller: _tabs,
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Received'),
                    if (waiting > 0) ...[
                      const SizedBox(width: 6),
                      _CountDot(count: waiting),
                    ],
                  ],
                ),
              ),
              const Tab(text: 'Send invitations'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: const [_Received(), _Send()],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Received
// ---------------------------------------------------------------------------

/// Every live invitation — unanswered or accepted — to the selected club,
/// soonest first.
final _receivedInvitesProvider =
    Provider.autoDispose<AsyncValue<List<TournamentInvite>>>((ref) {
  // The club selected in the app bar, never all of them — see
  // `scopedOrgIdsProvider`.
  final orgIds = ref.watch(scopedOrgIdsProvider);
  if (orgIds.isEmpty) return const AsyncValue.data([]);
  return combineAsyncAll([
    for (final id in orgIds) ref.watch(liveIncomingTournamentInvitesProvider(id)),
  ]).whenData((all) {
    final byId = {for (final i in all) i.id: i};
    return byId.values.toList()
      ..sort((a, b) {
        // Unanswered first: they are the ones waiting on somebody.
        if (a.isPending != b.isPending) return a.isPending ? -1 : 1;
        return (a.startDate ?? DateTime(9999))
            .compareTo(b.startDate ?? DateTime(9999));
      });
  });
});

class _Received extends ConsumerWidget {
  const _Received();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_receivedInvitesProvider);
    final today = DateUtils.dateOnly(DateTime.now());

    return AsyncView<List<TournamentInvite>>(
      value: async,
      builder: (invites) {
        final current = [
          for (final i in invites)
            if ((i.endDate ?? i.startDate) == null ||
                !(i.endDate ?? i.startDate)!.isBefore(today))
              i,
        ];
        final past = [
          for (final i in invites)
            if (!current.contains(i)) i,
        ];
        if (invites.isEmpty) {
          return const EmptyState(
            icon: Icons.mark_email_unread_outlined,
            title: 'No invitations for this club',
            message: 'When another club invites the club selected at the top '
                'to a season or a tournament, the invitation appears here '
                'with a button to register.',
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            ContentBounds(
              maxWidth: 720,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final i in current)
                    InvitationCard(key: ValueKey(i.id), invite: i),
                  if (past.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(4, 8, 4, 8),
                      child: Text(
                        'FINISHED',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                          color: Ps.faint,
                        ),
                      ),
                    ),
                    for (final i in past)
                      Opacity(
                        opacity: 0.7,
                        child: InvitationCard(key: ValueKey(i.id), invite: i),
                      ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Send
// ---------------------------------------------------------------------------

class _Send extends ConsumerWidget {
  const _Send();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Inviting is `manageCompetitions` at the host — owner, admin, event
    // manager — the same line the rules draw on `tournamentInvites` create.
    final orgIds = [
      for (final id in ref.watch(scopedOrgIdsProvider))
        if (ref
            .watch(myCapabilitiesProvider(id))
            .contains(Capability.manageCompetitions))
          id,
    ];

    if (orgIds.isEmpty) {
      return const EmptyState(
        icon: Icons.outgoing_mail,
        title: 'For this club\'s organizers',
        message: 'Owners, admins and event managers of the club selected at '
            'the top can invite other clubs to its seasons and tournaments. '
            'If you run a different club, switch to it there.',
      );
    }

    final rows = <({String orgId, Tournament season})>[];
    var loading = false;
    for (final id in orgIds) {
      final seasons = ref.watch(tournamentsProvider(id));
      loading = loading || seasons.isLoading;
      for (final t in seasons.valueOrNull ?? const <Tournament>[]) {
        if (t.status == TournamentStatus.cancelled ||
            t.status == TournamentStatus.completed) {
          continue;
        }
        rows.add((orgId: id, season: t));
      }
    }
    rows.sort((a, b) => (a.season.startDate ?? DateTime(9999))
        .compareTo(b.season.startDate ?? DateTime(9999)));

    if (rows.isEmpty) {
      if (loading) return const Center(child: CircularProgressIndicator());
      return EmptyState(
        icon: Icons.emoji_events_outlined,
        title: 'Nothing to invite clubs to yet',
        message: 'Create a season or a tournament, then come back here to '
            'invite other clubs to it.',
        action: FilledButton.icon(
          onPressed: () => context.push(Routes.createCompetition(orgIds.first)),
          icon: const Icon(Icons.add),
          label: const Text('Create one'),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        ContentBounds(
          maxWidth: 720,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Pick a season or tournament, choose clubs by name, area or '
                  'sport, and send them an invitation with a registration '
                  'link.',
                  style: TextStyle(fontSize: 13, color: Ps.muted),
                ),
              ),
              for (final r in rows)
                _SeasonToInvite(orgId: r.orgId, season: r.season),
            ],
          ),
        ),
      ],
    );
  }
}

class _SeasonToInvite extends ConsumerWidget {
  const _SeasonToInvite({required this.orgId, required this.season});

  final String orgId;
  final Tournament season;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = season;
    final invites = ref
            .watch(tournamentInvitesProvider((orgId: orgId, tournamentId: t.id)))
            .valueOrNull ??
        const <TournamentInvite>[];
    final host = ref.watch(organizationProvider(orgId)).valueOrNull;
    final coming = invites.where((i) => i.isAccepted).length;
    final waiting = invites.where((i) => i.isPending).length;
    final when = InvitationLetter.dateSpan(t.startDate, t.endDate)
        .replaceFirst(RegExp(r'^(from|on) '), '');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PsCard(
        padding: const EdgeInsets.all(14),
        onTap: () => context.push(Routes.inviteClubs(orgId, t.id)),
        child: Row(
          children: [
            PsCrest(
              name: t.name,
              logoUrl: t.logoUrl,
              seed: t.id,
              size: 42,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                      color: Ps.ink,
                    ),
                  ),
                  PsMetaRow(
                    items: [
                      t.kind.label,
                      if (host != null) host.name,
                      if (when.isNotEmpty) when,
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    invites.isEmpty
                        ? 'No clubs invited yet'
                        : '${invites.length} invited · $coming coming · '
                            '$waiting waiting',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: invites.isEmpty ? Ps.muted : Ps.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: () => context.push(Routes.inviteClubs(orgId, t.id)),
              icon: const Icon(Icons.send_outlined, size: 18),
              label: const Text('Invite'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountDot extends StatelessWidget {
  const _CountDot({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Ps.live,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}
