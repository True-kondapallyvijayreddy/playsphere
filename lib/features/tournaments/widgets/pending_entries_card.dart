import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/club_registration_request.dart';
import '../../../core/models/competition.dart';
import '../../../core/models/enums.dart';
import '../../../core/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/app_scaffold.dart';
import '../../../shared/identity.dart';
import '../../../shared/ui_kit.dart';

/// Entries waiting on the organizer, for the whole season, in one place.
///
/// ## Why this had to exist
///
/// Approving an entry was only ever possible on the event's own page, which is
/// two taps past the season and one page per draw. A season with six draws
/// therefore had six places to look, none of them the page the organizer
/// actually keeps open, and nothing anywhere told them a side was waiting. The
/// complaint that reached us was "I am the owner and organizer and I cannot
/// approve the team entry" — the permission was there all along; the button
/// was on a page they had no reason to open.
///
/// So the desk asks the question the organizer has: is anybody waiting on me.
/// It lists every pending entry across every draw, says which draw each is in,
/// and decides them in place.
///
/// ## Team entries are the point, not an afterthought
///
/// A team entry's document id is the TEAM's id and its `uid` field holds that
/// same team id — see `Registration.teamId` — which is exactly what
/// `decideRegistration` needs and exactly what is easy to get wrong by passing
/// the captain's uid instead. It is decided here through the same repository
/// call as an individual entry, and the row shows the squad size, because the
/// question an organizer is actually answering about a side is "are there
/// eleven of them".
class PendingEntriesCard extends ConsumerWidget {
  const PendingEntriesCard({
    super.key,
    required this.events,
  });

  final List<Competition> events;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // One stream per draw. A season has a handful of draws, and the
    // alternative — a collection-group query — cannot be authorised: the
    // cross-club registrations rule only returns rows about the reader, which
    // is the opposite of what an organizer needs here.
    final waiting = <(Competition, Registration)>[];
    for (final e in events) {
      if (e.format.isSingleMatch) continue;
      final regs = ref
              .watch(registrationsProvider(CompRef(e.orgId, e.id)))
              .valueOrNull ??
          const <Registration>[];
      for (final r in regs) {
        if (r.status == RegistrationStatus.pending) waiting.add((e, r));
      }
    }

    if (waiting.isEmpty) return const SizedBox.shrink();

    // Oldest first: an application that has been sitting for three days is
    // the one that matters, and a list that reshuffles as entries arrive is
    // one an organizer loses their place in.
    waiting.sort((a, b) {
      final x = a.$2.createdAt;
      final y = b.$2.createdAt;
      if (x == null || y == null) return 0;
      return x.compareTo(y);
    });

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PsCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.how_to_reg_outlined, color: Ps.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    waiting.length == 1
                        ? '1 entry waiting on you'
                        : '${waiting.length} entries waiting on you',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                      color: Ps.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Approve a side and it is in the draw. Everything here is an '
              'application until you decide it.',
              style: TextStyle(fontSize: 12.5, color: Ps.muted),
            ),
            const SizedBox(height: 6),
            for (final (event, reg) in waiting)
              _PendingRow(event: event, reg: reg),
          ],
        ),
      ),
    );
  }
}

class _PendingRow extends ConsumerStatefulWidget {
  const _PendingRow({required this.event, required this.reg});

  final Competition event;
  final Registration reg;

  @override
  ConsumerState<_PendingRow> createState() => _PendingRowState();
}

class _PendingRowState extends ConsumerState<_PendingRow> {
  bool _busy = false;

  Future<void> _decide(RegistrationStatus status) async {
    final me = ref.read(currentUidProvider);
    if (me == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(competitionRepositoryProvider).decideRegistration(
            orgId: widget.event.orgId,
            compId: widget.event.id,
            // The registration's own id, which on a TEAM entry is the team's
            // id rather than any person's. Passing the captain's uid here is
            // the mistake that produces "that registration is gone" on a
            // perfectly valid side.
            uid: widget.reg.uid,
            status: status,
            decidedByUid: me,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == RegistrationStatus.confirmed
                ? '${widget.reg.displayName} is in.'
                : '${widget.reg.displayName} was not accepted.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reg;
    final e = widget.event;
    final short = r.isTeamEntry &&
        e.teamSize != null &&
        r.memberUids.length < e.teamSize!;

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      onTap: () => context.push(Routes.competition(e.orgId, e.id)),
      leading: r.isTeamEntry
          ? PsCrest(name: r.displayName, logoUrl: r.photoUrl, seed: r.uid, size: 34)
          : PsAvatar(
              name: r.displayName,
              photoUrl: r.photoUrl,
              seed: r.uid,
              size: 34,
            ),
      title: Text(r.displayName, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          e.name,
          // The one number an organizer checks a side against before letting
          // it into a draw, flagged here rather than found at the toss.
          if (r.isTeamEntry)
            short
                ? '${r.memberUids.length} of ${e.teamSize} needed'
                : '${r.memberUids.length} in the squad',
          if (r.houseName != null) r.houseName!,
        ].join(' · '),
        style: short
            ? TextStyle(color: Theme.of(context).colorScheme.error)
            : null,
      ),
      trailing: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Wrap(
              children: [
                IconButton(
                  tooltip: 'Approve',
                  icon: const Icon(Icons.check, color: Ps.primary),
                  onPressed: () => _decide(RegistrationStatus.confirmed),
                ),
                IconButton(
                  tooltip: 'Reject',
                  icon: const Icon(Icons.close),
                  onPressed: () => _decide(RegistrationStatus.rejected),
                ),
              ],
            ),
    );
  }
}

/// Uninvited clubs asking to bring a side into this season, on the desk
/// itself — TC-CLUB-034/035/036. The other half of [PendingEntriesCard]:
/// that one is people this club already let in asking to play; this one is a
/// club nobody has vouched for yet.
class ClubRegistrationRequestsCard extends ConsumerWidget {
  const ClubRegistrationRequestsCard({
    super.key,
    required this.orgId,
    required this.tournamentId,
  });

  final String orgId;
  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (orgId: orgId, tournamentId: tournamentId);
    final requests = (ref.watch(clubRegistrationRequestsProvider(key)).valueOrNull ??
            const <ClubRegistrationRequest>[])
        .where((r) => r.isPending)
        .toList()
      ..sort((a, b) {
        final x = a.createdAt;
        final y = b.createdAt;
        if (x == null || y == null) return 0;
        return x.compareTo(y);
      });

    if (requests.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PsCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.groups_outlined, color: Ps.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    requests.length == 1
                        ? '1 club asking to enter'
                        : '${requests.length} clubs asking to enter',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                      color: Ps.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Nobody invited these clubs. Approving sends them an invitation '
              'to your season, which they then accept the same way any '
              'invited club does.',
              style: TextStyle(fontSize: 12.5, color: Ps.muted),
            ),
            const SizedBox(height: 6),
            for (final r in requests) _ClubRequestRow(request: r),
          ],
        ),
      ),
    );
  }
}

class _ClubRequestRow extends ConsumerStatefulWidget {
  const _ClubRequestRow({required this.request});

  final ClubRegistrationRequest request;

  @override
  ConsumerState<_ClubRequestRow> createState() => _ClubRequestRowState();
}

class _ClubRequestRowState extends ConsumerState<_ClubRequestRow> {
  bool _busy = false;

  Future<void> _decide(bool approve) async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;

    String? declineReason;
    if (!approve) {
      declineReason = await showDialog<String>(
        context: context,
        builder: (context) {
          final controller = TextEditingController();
          return AlertDialog(
            title: const Text('Decline this club?'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'Capacity is full for this sport.',
              ),
              onSubmitted: (v) => Navigator.pop(context, v),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Back'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, controller.text),
                child: const Text('Decline'),
              ),
            ],
          );
        },
      );
      if (declineReason == null) return;
    }

    setState(() => _busy = true);
    try {
      final r = widget.request;
      final tournament = await ref
          .read(tournamentProvider((orgId: r.hostOrgId, tournamentId: r.tournamentId))
              .future);
      if (tournament == null) return;
      final hostOrg = await ref.read(organizationProvider(r.hostOrgId).future);
      await ref.read(tournamentRepositoryProvider).decideClubRegistrationRequest(
            tournament: tournament,
            hostOrgName: hostOrg?.name ?? r.hostOrgName,
            request: r,
            approve: approve,
            invitedByUid: uid,
            declineReason: declineReason,
          );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(r.requestingOrgName),
      subtitle: r.note != null && r.note!.isNotEmpty ? Text(r.note!) : null,
      trailing: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Approve — sends an invitation',
                  icon: const Icon(Icons.check, color: Ps.primary),
                  onPressed: () => _decide(true),
                ),
                IconButton(
                  tooltip: 'Decline',
                  icon: const Icon(Icons.close),
                  onPressed: () => _decide(false),
                ),
              ],
            ),
    );
  }
}
