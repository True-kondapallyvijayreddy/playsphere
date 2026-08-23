import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/competition.dart';
import '../../../core/models/enums.dart';
import '../../../core/models/fixture.dart';
import '../../../core/models/squad_entry.dart';
import '../../../core/permissions/capability.dart';
import '../../../core/providers.dart';
import '../../../shared/app_scaffold.dart';
import '../../../shared/identity.dart';
import 'squad_rsvp_actions.dart';

/// One club's side of a challenge, and how it is being filled.
///
/// This is the half of the flow's step 6 that had nothing behind it: "XYZ Club
/// selects players **or opens registration**". Before this, the challenged
/// club's admin had to name every player by hand — the same
/// chasing-people-over-WhatsApp problem that participation models solved at
/// the event level, one level down where a challenge actually lives.
///
/// Shown to both clubs, but each sees their own side's controls. A member sees
/// a place to put their hand up; an admin sees the call itself.
class SquadCallCard extends ConsumerWidget {
  const SquadCallCard({
    super.key,
    required this.competition,
    required this.fixture,
  });

  final Competition competition;
  final Fixture fixture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only inter-club matches have two independently-owned sides. An internal
    // competition's entrants are players or house teams, and its field is
    // decided by the competition's own participation model.
    if (fixture.participantOrgIds == null) return const SizedBox.shrink();

    final me = ref.watch(currentUidProvider);
    if (me == null) return const SizedBox.shrink();

    // Which side is *mine*. A member of neither club gets no controls — they
    // can still read the lists, which is normal for a match about to be
    // played.
    final myOrgId = _myClub(ref);
    final mySide = myOrgId == null ? null : fixture.sideForOrg(myOrgId);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Squads',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              _readiness(fixture),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: fixture.bothSquadsLocked
                        ? Theme.of(context).colorScheme.primary
                        : null,
                    fontWeight:
                        fixture.bothSquadsLocked ? FontWeight.w600 : null,
                  ),
            ),
            const SizedBox(height: 16),
            _SideBlock(
              competition: competition,
              fixture: fixture,
              side: 'a',
              isMine: mySide == 'a',
              myUid: me,
            ),
            const Divider(height: 32),
            _SideBlock(
              competition: competition,
              fixture: fixture,
              side: 'b',
              isMine: mySide == 'b',
              myUid: me,
            ),
          ],
        ),
      ),
    );
  }

  /// Where this match has got to, in one line.
  ///
  /// The two clubs pick independently and at whatever moment suits them, so
  /// the interesting question on this card is not "how many have said yes"
  /// but "are we waiting on the other club". Saying so plainly is what stops
  /// an organizer arriving on the morning to find the visitors never picked
  /// anybody.
  ///
  /// A locked squad is what "ready" means — it is the existing statement that
  /// a club has finished picking, and inventing a second flag beside it would
  /// give a side two ways to be done and no way to reconcile them.
  String _readiness(Fixture fixture) {
    if (fixture.bothSquadsLocked) {
      return 'Both squads are locked. This match is ready to start.';
    }
    if (!fixture.squadLockedA && !fixture.squadLockedB) {
      return 'Each club picks its own side.';
    }
    final waitingOn =
        fixture.squadLockedA ? fixture.entrantBName : fixture.entrantAName;
    return 'Waiting on $waitingOn to lock their squad.';
  }

  /// The contesting club this user actually belongs to, if either.
  String? _myClub(WidgetRef ref) {
    for (final orgId in [fixture.entrantAId, fixture.entrantBId]) {
      final membership = ref.watch(myMembershipProvider(orgId)).valueOrNull;
      if (membership != null && membership.isActive) return orgId;
    }
    return null;
  }
}

class _SideBlock extends ConsumerWidget {
  const _SideBlock({
    required this.competition,
    required this.fixture,
    required this.side,
    required this.isMine,
    required this.myUid,
  });

  final Competition competition;
  final Fixture fixture;
  final String side;
  final bool isMine;
  final String myUid;

  String get _orgId => side == 'a' ? fixture.entrantAId : fixture.entrantBId;
  String get _name =>
      side == 'a' ? fixture.entrantAName : fixture.entrantBName;
  bool get _locked =>
      side == 'a' ? fixture.squadLockedA : fixture.squadLockedB;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final call = fixture.squadCallFor(side);
    final canManage = ref
        .watch(myCapabilitiesProvider(_orgId))
        .contains(Capability.manageCompetitions);

    final entriesAsync = ref.watch(
      squadEntriesProvider(
        FixtureRef(fixture.orgId, fixture.compId, fixture.id),
      ),
    );
    final entries = (entriesAsync.valueOrNull ?? const <SquadEntry>[])
        .where((e) => e.side == side && e.status.occupiesSlot)
        .toList();
    final mine = entries.where((e) => e.uid == myUid).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _name,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (_locked)
              const Chip(
                avatar: Icon(Icons.lock, size: 14),
                label: Text('Locked'),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(_statusLine(call, entries.length), style: theme.textTheme.bodySmall),
        const SizedBox(height: 10),

        if (entries.isEmpty)
          Text(
            'Nobody yet.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          )
        else
          for (final e in entries)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: PsAvatar(
                name: e.displayName,
                photoUrl: e.photoUrl,
                seed: e.uid,
                size: 28,
              ),
              title: Text(e.displayName),
              subtitle: Text(
                [
                  if (e.status == RegistrationStatus.waitlisted &&
                      e.waitlistPosition != null)
                    'Reserve #${e.waitlistPosition}'
                  else
                    e.status.label,
                  if (e.addedByAdmin) 'picked by the club',
                ].join(' · '),
              ),
            ),

        // Only your own club's controls. The other side is somebody else's
        // team sheet — visible, not editable.
        if (isMine && !_locked) ...[
          const SizedBox(height: 8),
          // The organizer's route: ask the club, then move the yeses onto the
          // sheet. Above the member's own button because filling the side is
          // what the club is here to do; putting your own hand up is the
          // thing you do to a call that already exists.
          if (canManage)
            SquadRsvpActions(
              fixture: fixture,
              orgId: _orgId,
              side: side,
              entries: entries,
            ),
          if (canManage) const SizedBox(height: 8),
          if (mine == null && call.acceptsEntries)
            FilledButton.tonal(
              onPressed: () => _join(context, ref),
              child: Text(
                call.outcomeOfJoiningNow == RegistrationStatus.waitlisted
                    ? 'Join the reserves'
                    : 'I am playing',
              ),
            )
          else if (mine != null)
            OutlinedButton(
              onPressed: () => _leave(context, ref),
              child: const Text('Pull out'),
            ),
          if (canManage) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => _configure(context, ref, call),
                  child: Text(
                    call.open ? 'Change the call' : 'Open to our members',
                  ),
                ),
                if (entries.any((e) => e.isPlaying))
                  TextButton(
                    onPressed: () => _lock(context, ref),
                    child: const Text('Lock this squad'),
                  ),
              ],
            ),
          ],
        ],
      ],
    );
  }

  String _statusLine(SquadCall call, int entered) {
    if (_locked) return 'Final squad — $entered players';
    if (!call.open) {
      return entered == 0
          ? 'The club has not opened this side to members yet'
          : '$entered picked by the club';
    }
    final left = call.slotsRemaining;
    if (left == null) return 'Open — $entered signed up, no limit';
    if (left > 0) return 'Open — $left of ${call.capacity} places left';
    return call.waitlistEnabled
        ? 'Full — reserves are being taken'
        : 'Full';
  }

  Future<void> _join(BuildContext context, WidgetRef ref) async {
    final me = ref.read(currentUserProvider).valueOrNull;
    if (me == null) return;
    try {
      final outcome = await ref.read(competitionRepositoryProvider).joinSquad(
            fixture: fixture,
            forOrgId: _orgId,
            user: me,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              outcome == RegistrationStatus.confirmed
                  ? 'You are in the squad.'
                  : 'Squad is full — you are a reserve. You move up '
                      'automatically if someone pulls out.',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(competitionRepositoryProvider).leaveSquad(
            fixture: fixture,
            uid: myUid,
          );
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _lock(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(competitionRepositoryProvider).lockSquadFromEntries(
            fixture: fixture,
            forOrgId: _orgId,
          );
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _configure(
    BuildContext context,
    WidgetRef ref,
    SquadCall call,
  ) async {
    final result = await showDialog<({bool open, int? capacity, bool waitlist})>(
      context: context,
      builder: (_) => _SquadCallDialog(call: call, clubName: _name),
    );
    if (result == null) return;
    try {
      await ref.read(competitionRepositoryProvider).setSquadCall(
            fixture: fixture,
            forOrgId: _orgId,
            open: result.open,
            capacity: result.capacity,
            waitlistEnabled: result.waitlist,
          );
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}

class _SquadCallDialog extends StatefulWidget {
  const _SquadCallDialog({required this.call, required this.clubName});

  final SquadCall call;
  final String clubName;

  @override
  State<_SquadCallDialog> createState() => _SquadCallDialogState();
}

class _SquadCallDialogState extends State<_SquadCallDialog> {
  late bool _open = widget.call.open;
  late bool _waitlist = widget.call.waitlistEnabled;
  late final _capacity = TextEditingController(
    text: widget.call.capacity?.toString() ?? '',
  );

  @override
  void dispose() {
    _capacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.clubName} squad'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            value: _open,
            onChanged: (v) => setState(() => _open = v),
            contentPadding: EdgeInsets.zero,
            title: const Text('Open to our members'),
            subtitle: const Text(
              'Members register themselves, first come first served',
            ),
          ),
          TextField(
            controller: _capacity,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Players we need',
              hintText: 'e.g. 11',
              helperText: 'Blank = no limit',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _waitlist,
            onChanged: (v) => setState(() => _waitlist = v),
            contentPadding: EdgeInsets.zero,
            title: const Text('Keep reserves'),
            subtitle: const Text(
              'The first reserve moves up if someone pulls out',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (
            open: _open,
            capacity: int.tryParse(_capacity.text.trim()),
            waitlist: _waitlist,
          )),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
