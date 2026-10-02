import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/competition.dart';
import '../../core/models/enums.dart';
import '../../core/models/organization.dart';
import '../../core/models/season_interest.dart';
import '../../core/providers.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/identity.dart';
import '../../shared/ui_kit.dart';

/// Turning "who is available" into sides that are actually entered.
///
/// ## The gap this fills
///
/// An invited club already had both ends of the flow and nothing in between.
/// Members could put a hand up — see [SeasonInterest] — and an organizer could
/// enter a team that already existed. What there was no way to do was the
/// thing every club actually does between those two: read the hands, decide
/// there are enough for two sides, split them, name them, and send both in.
/// The organizer had to leave, create each team by hand on another screen,
/// remember who they had put where, come back, and enter them one at a time.
/// For a club fielding three sides that is a dozen screens and an easy mistake.
///
/// So this is one screen and one button. Tick the members who are playing,
/// deal them into as many sides as the club is fielding, press Enter — and the
/// teams are created in the club and registered in the draw in one go.
///
/// ## Team sports and individual sports are the same screen
///
/// Deliberately. To a club secretary the job is identical — "ask who is free,
/// pick from the answers, send them in" — and the difference is only what the
/// entry unit is at the far end. A team draw takes the squads assembled here.
/// An individual draw cannot: `firestore.rules` admits an invited club's entry
/// only as a TEAM belonging to that club, because an entry into a singles draw
/// is a commitment by the player, not by their secretary. So for those, this
/// screen nominates: the people picked are told they have been selected and
/// given the link, and they enter themselves. Selection is the club's;
/// consent stays the player's.
class BuildEntryScreen extends ConsumerStatefulWidget {
  const BuildEntryScreen({
    super.key,
    required this.orgId,
    required this.hostOrgId,
    required this.tournamentId,
  });

  /// The INVITED club — the one whose members are being picked and whose
  /// teams are being raised. Not the host.
  final String orgId;

  final String hostOrgId;
  final String tournamentId;

  @override
  ConsumerState<BuildEntryScreen> createState() => _BuildEntryScreenState();
}

class _BuildEntryScreenState extends ConsumerState<BuildEntryScreen> {
  /// The draw being entered. Null until the organizer picks one — a season is
  /// several draws and a squad is assembled for one of them.
  Competition? _event;

  /// Which side each picked member is in, by uid. A member not in the map is
  /// not picked. Side 0 is the first team.
  final Map<String, int> _assignment = {};

  /// How many sides the club is fielding. One is the common case and the
  /// default; the whole point of the screen is that it does not have to be.
  int _sides = 1;

  final Map<int, TextEditingController> _names = {};

  bool _busy = false;

  /// Show every member, not only the ones who put a hand up. The interest
  /// list is a convenience, not a gate — a secretary phoning round on Friday
  /// knows who is coming before the app does.
  bool _showAll = false;

  @override
  void dispose() {
    for (final c in _names.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _nameFor(int side, String clubName) =>
      _names.putIfAbsent(
        side,
        () => TextEditingController(
          // A club fielding one side calls it by the club's name; two sides
          // become A and B. Both are what a fixture list would print.
          text: _sides == 1 ? clubName : '$clubName ${_letter(side)}',
        ),
      );

  static String _letter(int i) => String.fromCharCode(65 + i);

  List<String> _squad(int side) => [
        for (final e in _assignment.entries)
          if (e.value == side) e.key,
      ];

  /// Deals the picked members round the sides in order, so an organizer who
  /// has ticked thirty names and asked for three sides gets ten, ten and ten
  /// without dragging anybody. They can still move people afterwards.
  void _deal() {
    final picked = _assignment.keys.toList();
    setState(() {
      for (var i = 0; i < picked.length; i++) {
        _assignment[picked[i]] = i % _sides;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final club = ref.watch(organizationProvider(widget.orgId)).valueOrNull;
    final clubName = club?.name ?? 'Our club';

    final events = ref
            .watch(tournamentEventsProvider(
              (orgId: widget.hostOrgId, tournamentId: widget.tournamentId),
            ))
            .valueOrNull ??
        const <Competition>[];
    final open = [
      for (final e in events)
        if (e.registrationIsOpen && !e.format.isSingleMatch) e,
    ];

    final interest = ref
            .watch(seasonInterestProvider((
              orgId: widget.orgId,
              hostOrgId: widget.hostOrgId,
              tournamentId: widget.tournamentId,
            )))
            .valueOrNull ??
        const <SeasonInterest>[];
    final members =
        ref.watch(orgMembersProvider(widget.orgId)).valueOrNull ??
            const <Membership>[];

    final available = {for (final i in interest) i.uid};
    // Whoever put a hand up first, then the rest of the club behind a switch.
    final pool = <_Candidate>[
      for (final i in interest)
        _Candidate(uid: i.uid, name: i.displayName, photoUrl: i.photoUrl,
            note: i.note, saidYes: true),
      if (_showAll)
        for (final m in members)
          if (m.isActive && !available.contains(m.uid))
            _Candidate(
              uid: m.uid,
              name: m.displayName,
              photoUrl: m.photoUrl,
              saidYes: false,
            ),
    ];

    final event = _event ?? (open.length == 1 ? open.first : null);
    final entersAsTeams = event?.entersAsTeams ?? false;
    final picked = _assignment.length;

    return AppScaffold(
      title: 'Build our entry',
      subtitle: clubName,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          ContentBounds(
            maxWidth: 760,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _EventPicker(
                  events: open,
                  selected: event,
                  onPick: (e) => setState(() => _event = e),
                ),
                if (event == null) ...[
                  const SizedBox(height: 16),
                  const EmptyState(
                    icon: Icons.inbox_outlined,
                    title: 'Nothing is taking entries yet',
                    message: 'When the host opens a draw it appears here, and '
                        'you can pick the side that plays in it.',
                  ),
                ] else ...[
                  const SizedBox(height: 16),
                  _AvailabilityHeader(
                    saidYes: interest.length,
                    showAll: _showAll,
                    onToggle: (v) => setState(() => _showAll = v),
                  ),
                  const SizedBox(height: 8),
                  if (pool.isEmpty)
                    const _NobodyYet()
                  else
                    for (final c in pool)
                      _CandidateRow(
                        candidate: c,
                        side: _assignment[c.uid],
                        sides: entersAsTeams ? _sides : 1,
                        showSide: entersAsTeams && _sides > 1,
                        onToggle: () => setState(() {
                          if (_assignment.containsKey(c.uid)) {
                            _assignment.remove(c.uid);
                          } else {
                            _assignment[c.uid] = 0;
                          }
                        }),
                        onSide: (s) => setState(() => _assignment[c.uid] = s),
                      ),
                  const SizedBox(height: 16),
                  if (entersAsTeams)
                    _SidesEditor(
                      sides: _sides,
                      picked: picked,
                      clubName: clubName,
                      teamSize: event.teamSize,
                      squadOf: _squad,
                      nameFor: (s) => _nameFor(s, clubName),
                      onSides: (n) => setState(() {
                        _sides = n;
                        for (final k in _assignment.keys.toList()) {
                          if (_assignment[k]! >= n) _assignment[k] = n - 1;
                        }
                      }),
                      onDeal: _deal,
                    ),
                  const SizedBox(height: 16),
                  _Commit(
                    busy: _busy,
                    picked: picked,
                    entersAsTeams: entersAsTeams,
                    sides: _sides,
                    onPressed: picked == 0 || _busy
                        ? null
                        : () => entersAsTeams
                            ? _enterTeams(event, clubName)
                            : _nominate(event),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Raises each side in the club and enters it, one after another.
  ///
  /// Sequential on purpose. Each entry is a transaction against the same
  /// draw's slot count, and firing three at once is three transactions racing
  /// for the last two places. A failure part-way leaves the sides that got in
  /// in — which is the right outcome, and is said plainly rather than rolled
  /// back behind the organizer's back.
  Future<void> _enterTeams(Competition event, String clubName) async {
    final me = ref.read(currentUidProvider);
    if (me == null) return;
    setState(() => _busy = true);

    final teams = ref.read(teamRepositoryProvider);
    final comps = ref.read(competitionRepositoryProvider);
    final done = <String>[];
    final failed = <String, String>{};

    for (var side = 0; side < _sides; side++) {
      final squad = _squad(side);
      if (squad.isEmpty) continue;
      final name = _nameFor(side, clubName).text.trim().isEmpty
          ? '$clubName ${_letter(side)}'
          : _nameFor(side, clubName).text.trim();
      try {
        final teamId = await teams.createTeam(
          name: name,
          sportId: event.sportId,
          createdByUid: me,
          // Raised for this draw, from this club. `event` rather than
          // `permanent`: this is a side for one tournament, and calling it
          // permanent would put it on the club's team list forever.
          type: TeamType.event,
          clubId: widget.orgId,
          memberUids: squad,
          competitionId: event.id,
          // The organizer is picking the side, not playing in it. See
          // `TeamRepository.createTeam`.
          rosterIsExact: true,
        );
        final team = await teams.getTeam(teamId);
        if (team == null) {
          failed[name] = 'The side was created but could not be read back.';
          continue;
        }
        await comps.registerTeam(
          competition: event,
          team: team,
          byUid: me,
          invitedClubId: widget.orgId,
        );
        done.add(name);
      } catch (e) {
        failed[name] = '$e';
      }
    }

    if (!mounted) return;
    setState(() => _busy = false);
    await _report(done: done, failed: failed, event: event);
  }

  /// The individual-draw path: tell the people picked that they are picked.
  ///
  /// Not a registration, and it must not pretend to be one. Entering a singles
  /// draw is the player's own act — the rules say so, and they are right to:
  /// a club cannot commit a member to turning up on a Sunday. What the club
  /// can do is select, and say so, which is what this sends.
  Future<void> _nominate(Competition event) async {
    final me = ref.read(currentUidProvider);
    if (me == null) return;
    setState(() => _busy = true);
    final club = ref.read(organizationProvider(widget.orgId)).valueOrNull;
    try {
      await ref.read(tournamentRepositoryProvider).nominateForSeason(
            orgId: widget.orgId,
            hostOrgId: widget.hostOrgId,
            tournamentId: widget.tournamentId,
            competition: event,
            uids: _assignment.keys.toList(),
            byUid: me,
            clubName: club?.name ?? 'Your club',
          );
      if (!mounted) return;
      setState(() => _busy = false);
      final n = _assignment.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$n ${n == 1 ? 'player has' : 'players have'} been told they are '
            'selected, with the link to enter.',
          ),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showError(context, e);
    }
  }

  Future<void> _report({
    required List<String> done,
    required Map<String, String> failed,
    required Competition event,
  }) async {
    if (failed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            done.length == 1
                ? '${done.first} is entered in ${event.name}.'
                : '${done.length} sides are entered in ${event.name}.',
          ),
        ),
      );
      Navigator.of(context).pop();
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(done.isEmpty ? 'Nothing was entered' : 'Partly entered'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (done.isNotEmpty) ...[
                Text('In: ${done.join(', ')}'),
                const SizedBox(height: 10),
              ],
              for (final e in failed.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('${e.key}: ${e.value}'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _Candidate {
  const _Candidate({
    required this.uid,
    required this.name,
    required this.saidYes,
    this.photoUrl,
    this.note,
  });

  final String uid;
  final String name;
  final String? photoUrl;
  final String? note;

  /// Whether they put their own hand up, as against being added by the
  /// organizer from the full roster. Worth showing: a side made entirely of
  /// people who volunteered is a different thing from one made of people who
  /// have not been asked yet.
  final bool saidYes;
}

class _EventPicker extends StatelessWidget {
  const _EventPicker({
    required this.events,
    required this.selected,
    required this.onPick,
  });

  final List<Competition> events;
  final Competition? selected;
  final ValueChanged<Competition> onPick;

  @override
  Widget build(BuildContext context) {
    if (events.length <= 1) return const SizedBox.shrink();
    return PsCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'WHICH DRAW',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: Ps.faint,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in events)
                ChoiceChip(
                  selected: selected?.id == e.id,
                  onSelected: (_) => onPick(e),
                  label: Text(
                    '${SportCatalog.byId(e.sportId).icon} ${e.name}',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AvailabilityHeader extends StatelessWidget {
  const _AvailabilityHeader({
    required this.saidYes,
    required this.showAll,
    required this.onToggle,
  });

  final int saidYes;
  final bool showAll;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            saidYes == 0
                ? 'Nobody has said they are available yet'
                : '$saidYes said they are available',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Ps.ink,
            ),
          ),
        ),
        Switch(value: showAll, onChanged: onToggle),
        const Text(
          'All members',
          style: TextStyle(fontSize: 12.5, color: Ps.muted),
        ),
      ],
    );
  }
}

class _NobodyYet extends StatelessWidget {
  const _NobodyYet();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Ps.surface,
        borderRadius: BorderRadius.circular(Ps.radiusSm),
        border: Border.all(color: Ps.border),
      ),
      child: const Text(
        'Your members see "I\'m interested" on this season and their names '
        'land here. You do not have to wait for them — switch on All members '
        'and pick the side yourself.',
        style: TextStyle(fontSize: 12.5, color: Ps.muted),
      ),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.candidate,
    required this.side,
    required this.sides,
    required this.showSide,
    required this.onToggle,
    required this.onSide,
  });

  final _Candidate candidate;
  final int? side;
  final int sides;
  final bool showSide;
  final VoidCallback onToggle;
  final ValueChanged<int> onSide;

  @override
  Widget build(BuildContext context) {
    final picked = side != null;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      onTap: onToggle,
      leading: PsAvatar(
        name: candidate.name,
        photoUrl: candidate.photoUrl,
        seed: candidate.uid,
        size: 34,
      ),
      title: Text(candidate.name, overflow: TextOverflow.ellipsis),
      subtitle: candidate.note != null && candidate.note!.trim().isNotEmpty
          ? Text('"${candidate.note!.trim()}"')
          : Text(
              candidate.saidYes ? 'Put their hand up' : 'Not asked',
              style: TextStyle(
                color: candidate.saidYes ? Ps.primary : Ps.faint,
              ),
            ),
      trailing: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          if (picked && showSide)
            DropdownButton<int>(
              value: side,
              underline: const SizedBox.shrink(),
              items: [
                for (var i = 0; i < sides; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text(String.fromCharCode(65 + i)),
                  ),
              ],
              onChanged: (v) => v == null ? null : onSide(v),
            ),
          Checkbox(value: picked, onChanged: (_) => onToggle()),
        ],
      ),
    );
  }
}

class _SidesEditor extends StatelessWidget {
  const _SidesEditor({
    required this.sides,
    required this.picked,
    required this.clubName,
    required this.teamSize,
    required this.squadOf,
    required this.nameFor,
    required this.onSides,
    required this.onDeal,
  });

  final int sides;
  final int picked;
  final String clubName;
  final int? teamSize;
  final List<String> Function(int) squadOf;
  final TextEditingController Function(int) nameFor;
  final ValueChanged<int> onSides;
  final VoidCallback onDeal;

  @override
  Widget build(BuildContext context) {
    return PsCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'How many sides are we entering?',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Ps.ink,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'One side fewer',
                onPressed: sides <= 1 ? null : () => onSides(sides - 1),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text(
                '$sides',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Ps.ink,
                ),
              ),
              IconButton(
                tooltip: 'One more side',
                // Eight is not a rule, it is a stop: a club entering more
                // than eight sides into one draw has almost certainly
                // mistyped, and the draw has a cap of its own anyway.
                onPressed: sides >= 8 ? null : () => onSides(sides + 1),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          if (sides > 1) ...[
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: picked == 0 ? null : onDeal,
              icon: const Icon(Icons.shuffle, size: 18),
              label: Text('Split the $picked picked across $sides sides'),
            ),
          ],
          const SizedBox(height: 12),
          for (var i = 0; i < sides; i++) ...[
            TextField(
              controller: nameFor(i),
              decoration: InputDecoration(
                labelText: sides == 1 ? 'Team name' : 'Side ${_letter(i)} name',
                helperText: _squadLine(squadOf(i).length, teamSize),
                helperStyle: TextStyle(
                  color: teamSize != null && squadOf(i).length < teamSize!
                      ? Theme.of(context).colorScheme.error
                      : Ps.muted,
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  static String _letter(int i) => String.fromCharCode(65 + i);

  static String _squadLine(int n, int? needed) {
    if (n == 0) return 'Nobody in this side yet';
    if (needed == null) return '$n in the squad';
    return n < needed ? '$n in the squad · needs $needed' : '$n in the squad';
  }
}

class _Commit extends StatelessWidget {
  const _Commit({
    required this.busy,
    required this.picked,
    required this.entersAsTeams,
    required this.sides,
    required this.onPressed,
  });

  final bool busy;
  final int picked;
  final bool entersAsTeams;
  final int sides;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: onPressed,
          icon: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_outlined),
          label: Text(
            entersAsTeams
                ? sides == 1
                    ? 'Create the side and enter it'
                    : 'Create $sides sides and enter them'
                : picked == 1
                    ? 'Select 1 player and send the link'
                    : 'Select $picked players and send the link',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          entersAsTeams
              // Said before the button, because it creates documents that
              // outlive this screen and an organizer should not discover that
              // afterwards.
              ? 'Each side becomes a team in your club, with this squad, and '
                  'is entered straight away.'
              : 'A singles draw is entered by the player, so this tells them '
                  'they are selected and sends the link. Their entry is '
                  'theirs to make.',
          style: const TextStyle(fontSize: 12, color: Ps.muted),
        ),
      ],
    );
  }
}
