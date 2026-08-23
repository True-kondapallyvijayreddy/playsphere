import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/competition.dart';
import '../../../core/models/enums.dart';
import '../../../core/models/team.dart';
import '../../../core/permissions/capability.dart';
import '../../../core/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../domain/scoring/scoring_registry.dart';
import '../../../shared/app_scaffold.dart';
import '../../../shared/identity.dart';

/// Entering a side into a team event: pick the team, not the player.
///
/// ## Why this replaces "Register" on a group sport
///
/// A cricket tournament's field is a list of clubs, and the eleven people in
/// one of them are teammates rather than rivals. Offering each of them a
/// personal "Register" button — which is what every event did, because
/// registration only ever had one shape — invites 350 people to enter a
/// 32-team competition individually, and whichever of them presses it first
/// has entered nothing that can play.
///
/// So for an event whose entrants are teams, the entry unit on this screen is
/// a team, and the person pressing the button is doing it on the team's
/// behalf. Who may: whoever runs the team — its creator, captain or manager —
/// and the organizers of the club that owns it, which is the same authority
/// that lets them edit its roster and the same one `firestore.rules` enforces
/// on the write.
///
/// ## Why an existing team and not a squad typed in here
///
/// Because a squad typed in here is gone the moment the event ends. Rule 4 of
/// the product is that a team is a thing in its own right: it has a page, a
/// record across seasons, and a roster its members can see themselves on. A
/// club that plays four tournaments a year should assemble its side once. The
/// "Create a team" door at the bottom leads to the screen that does that, and
/// comes back here.
class RegisterTeamSheet extends ConsumerStatefulWidget {
  const RegisterTeamSheet({super.key, required this.competition});

  final Competition competition;

  static Future<void> show(
    BuildContext context, {
    required Competition competition,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => RegisterTeamSheet(competition: competition),
      );

  @override
  ConsumerState<RegisterTeamSheet> createState() => _RegisterTeamSheetState();
}

class _RegisterTeamSheetState extends ConsumerState<RegisterTeamSheet> {
  String? _busyTeamId;

  Future<void> _enter(Team team) async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;
    setState(() => _busyTeamId = team.id);
    try {
      final outcome =
          await ref.read(competitionRepositoryProvider).registerTeam(
                competition: widget.competition,
                team: team,
                byUid: uid,
              );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            switch (outcome) {
              RegistrationStatus.confirmed =>
                '${team.name} is in — ${team.memberUids.length} in the squad.',
              RegistrationStatus.waitlisted =>
                '${team.name} is on the waitlist. You will be told if a place '
                    'opens.',
              _ => '${team.name} has applied. The organizer decides next.',
            },
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _busyTeamId = null);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = widget.competition;
    final uid = ref.watch(currentUidProvider);
    final sport = SportCatalog.byId(c.sportId);

    // Two sources, because a team does not have to belong to the host club.
    // A visiting side entering an open tournament is the case the whole
    // tournament-invite flow exists for, and it would be strange to invite a
    // club and then have no way for it to enter.
    final mine = ref.watch(myTeamsProvider).valueOrNull ?? const <Team>[];
    final hostTeams =
        ref.watch(clubTeamsProvider(c.orgId)).valueOrNull ?? const <Team>[];
    // `manageOrganization` and not `manageCompetitions`, because that is the
    // capability `teamRuns()` checks in `firestore.rules`. Offering the wider
    // one here would list squads whose entry the server then refuses — the
    // exact dead end the `_mayEnter` filter exists to prevent.
    final runsTheClub = ref
        .watch(myCapabilitiesProvider(c.orgId))
        .contains(Capability.manageOrganization);

    final byId = <String, Team>{
      for (final t in mine) t.id: t,
      // The host club's teams, but only for somebody who can act for the
      // host club. A member who happens to be looking at the event must not
      // be able to enter a squad they are not on.
      if (runsTheClub)
        for (final t in hostTeams) t.id: t,
    };

    final eligible = [
      for (final t in byId.values)
        if (t.sportId == c.sportId && t.isSelectable && _mayEnter(t, uid)) t,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // Already in, so the row says so rather than offering a button that
    // throws. Withdrawn teams are not "in" and may enter again.
    final entered = <String>{
      for (final r
          in ref.watch(registrationsProvider(CompRef(c.orgId, c.id))).valueOrNull ??
              const <Registration>[])
        if (r.isTeamEntry && r.status.occupiesSlot) r.teamId!,
    };

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text('Enter a team', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${sport.icon} ${c.name} takes teams, not individual players — '
              'one entry per side.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            if (eligible.isEmpty)
              _NoTeams(sportName: sport.name)
            else
              for (final t in eligible)
                _TeamRow(
                  team: t,
                  alreadyIn: entered.contains(t.id),
                  busy: _busyTeamId == t.id,
                  // One at a time. Two entries committed from one sheet is
                  // two transactions racing for the same last slot.
                  enabled: _busyTeamId == null,
                  minSquad: c.teamSize,
                  onEnter: () => _enter(t),
                ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                context.push(Routes.createTeam(c.orgId));
              },
              icon: const Icon(Icons.group_add_outlined, size: 18),
              label: const Text('Create a team'),
            ),
          ],
        ),
      ),
    );
  }

  /// Whether this person can enter [team] — the client's half of the rule
  /// `teamRuns()` enforces in `firestore.rules`. Shown as a filter rather
  /// than as a failed write, because a list of teams you are not allowed to
  /// enter is a list of dead ends.
  bool _mayEnter(Team team, String? uid) {
    if (uid == null) return false;
    if (team.createdByUid == uid) return true;
    if (team.captainUid == uid || team.managerUid == uid) return true;
    final clubId = team.clubId;
    if (clubId == null) return false;
    return ref
        .watch(myCapabilitiesProvider(clubId))
        .contains(Capability.manageOrganization);
  }
}

class _TeamRow extends StatelessWidget {
  const _TeamRow({
    required this.team,
    required this.alreadyIn,
    required this.busy,
    required this.enabled,
    required this.minSquad,
    required this.onEnter,
  });

  final Team team;
  final bool alreadyIn;
  final bool busy;
  final bool enabled;

  /// Players the sport needs on the field, when the organizer has said. A
  /// squad below it is offered anyway — an organizer may be happy to let a
  /// side enter and fill up before the first match — but it is labelled, so
  /// nobody enters nine players for an eleven-a-side event by accident.
  final int? minSquad;

  final VoidCallback onEnter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = team.memberUids.length;
    final short = minSquad != null && size < minSquad!;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: PsCrest(
          name: team.name,
          logoUrl: team.photoUrl,
          seed: team.id,
          size: 40,
        ),
        title: Text(team.name, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          short
              ? '$size in the squad · needs $minSquad'
              : '$size in the squad',
          style: short
              ? theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)
              : null,
        ),
        trailing: alreadyIn
            ? const Chip(label: Text('Entered'))
            : busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : FilledButton.tonal(
                    onPressed: enabled ? onEnter : null,
                    child: const Text('Enter'),
                  ),
      ),
    );
  }
}

class _NoTeams extends StatelessWidget {
  const _NoTeams({required this.sportName});

  final String sportName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No $sportName team you can enter',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          Text(
            'A side has to exist before it can be entered. Raise one from '
            'your club’s members — ask who is available first if you '
            'like, then pick the squad from whoever said yes.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
