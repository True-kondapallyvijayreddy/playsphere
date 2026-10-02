import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_exception.dart';
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
  const RegisterTeamSheet({
    super.key,
    required this.competition,
    this.invitedClubId,
  });

  final Competition competition;

  /// The club an accepted invitation lets its organizers enter a side for, when
  /// this sheet is entering one. Only that club's own teams are offered — the
  /// rules admit an invited entry for a team whose `clubId` is the invited
  /// club, entered by one of its organizers — and the entry names the club so
  /// the invitation can be checked.
  final String? invitedClubId;

  static Future<void> show(
    BuildContext context, {
    required Competition competition,
    String? invitedClubId,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => RegisterTeamSheet(
          competition: competition,
          invitedClubId: invitedClubId,
        ),
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
                invitedClubId: widget.invitedClubId,
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
        // A squad refused on age or gender names one line per player, which a
        // snackbar cuts off at exactly the point the captain needs to read —
        // who to drop. Anything shorter stays a snackbar.
        if (e is ValidationException && e.message.contains('\n')) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('This squad cannot enter'),
              content: SingleChildScrollView(child: Text(e.message)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        } else {
          showError(context, e);
        }
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

    final invitedClubId = widget.invitedClubId;
    final invitedTeams = invitedClubId == null
        ? const <Team>[]
        : ref.watch(clubTeamsProvider(invitedClubId)).valueOrNull ??
            const <Team>[];
    final runsInvitedClub = invitedClubId != null &&
        ref
            .watch(myCapabilitiesProvider(invitedClubId))
            .contains(Capability.manageCompetitions);

    final byId = invitedClubId != null
        ? <String, Team>{
            // An invited club enters its own sides, and only those.
            if (runsInvitedClub)
              for (final t in invitedTeams)
                if (t.clubId == invitedClubId) t.id: t,
          }
        : <String, Team>{
            // My own sides — but not ones that belong to somebody ELSE's club.
            // `myTeamsProvider` is every team I am on anywhere, and offering
            // all of them put a team of another club in the picker for this
            // club's event ("Team Vijay" on a PS Test Academy event). A club's
            // side enters another club's season through the invitation, which
            // is the branch above; there is no other honest route, and the
            // server refuses this one anyway.
            for (final t in mine)
              if (_couldEnterHere(t, c)) t.id: t,
            // The host club's teams, but only for somebody who can act for the
            // host club. A member who happens to be looking at the event must
            // not be able to enter a squad they are not on.
            if (runsTheClub)
              for (final t in hostTeams) t.id: t,
          };

    final eligible = [
      for (final t in byId.values)
        if (t.sportId == c.sportId &&
            t.isSelectable &&
            (invitedClubId != null || _mayEnter(t, uid)))
          t,
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
                context.push(Routes.createTeam(invitedClubId ?? c.orgId));
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

  /// Whether [team] is a side that could belong in [c] at all.
  ///
  /// Two things disqualify it, both independent of who is holding the phone:
  ///
  ///  * it is another club's permanent side. That club enters by being invited
  ///    — see the `invitedClubId` branch — and a club's squad appearing in the
  ///    picker for an unrelated club's event is how one season offered
  ///    "Team Vijay" for a PS Test Academy event.
  ///  * it is an event team built for a different event. Those are scoped to
  ///    the competition they were created for and mean nothing outside it.
  ///
  /// A side with no club at all is kept: that is the player's own team, and
  /// entering one is the ordinary path into an open event.
  static bool _couldEnterHere(Team team, Competition c) {
    final clubId = team.clubId;
    if (clubId != null && clubId != c.orgId) return false;
    final scopedTo = team.competitionId;
    if (scopedTo != null && scopedTo != c.id) return false;
    return true;
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
