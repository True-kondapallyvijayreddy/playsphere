import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/fixture.dart';
import '../../core/models/match_player.dart';
import '../../core/permissions/capability.dart';
import '../../domain/scoring/scoring_plugin.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../core/providers.dart';
import '../../shared/app_scaffold.dart';

/// Everything that has to happen between "the teams have arrived" and the
/// first ball: who is playing, and who won the toss.
///
/// Both are prerequisites rather than nice-to-haves. The scoring engines
/// refuse a delivery that names nobody, and cricket cannot know which innings
/// belongs to whom until the toss is recorded.

/// Picks the players for one side.
///
/// Members of the organization are offered first, because most of a squad is
/// already in the club. A guest can be added by name alone: a team turns up
/// one short and borrows someone who has never installed the app, and refusing
/// to start the match over that is how a scorer gives up and reaches for
/// paper.
class LineupEditor extends ConsumerStatefulWidget {
  const LineupEditor({super.key, required this.fixture});

  final Fixture fixture;

  @override
  ConsumerState<LineupEditor> createState() => _LineupEditorState();
}

class _LineupEditorState extends ConsumerState<LineupEditor> {
  late final List<MatchPlayer> _a = [...widget.fixture.lineupA];
  late final List<MatchPlayer> _b = [...widget.fixture.lineupB];
  bool _busy = false;
  int _tab = 0;

  List<MatchPlayer> get _current => _tab == 0 ? _a : _b;

  /// Which sides this user is allowed to pick.
  ///
  /// In an ordinary competition the hosting club's organizers run both teams,
  /// which is right — one person is setting up a house match. An inter-club
  /// challenge is the opposite situation: two clubs that do not answer to
  /// each other, and the visiting club must be able to name its own players
  /// without handing the host the power to pick them. `firestore.rules`
  /// enforces the same split, so this is the honest shape of the screen
  /// rather than a courtesy.
  Set<int> _editableSides(WidgetRef ref) {
    final f = widget.fixture;
    final sides = <int>{};

    // Authority in the club that owns the fixture runs the whole match.
    if (ref
        .watch(myCapabilitiesProvider(f.orgId))
        .contains(Capability.manageCompetitions)) {
      sides.addAll({0, 1});
    }

    // Authority in either contesting club runs that club's own side.
    if (f.participantOrgIds != null) {
      if (ref
          .watch(myCapabilitiesProvider(f.entrantAId))
          .contains(Capability.manageCompetitions)) {
        sides.add(0);
      }
      if (ref
          .watch(myCapabilitiesProvider(f.entrantBId))
          .contains(Capability.manageCompetitions)) {
        sides.add(1);
      }
    }

    return sides;
  }

  /// Whose member list to offer for a side.
  ///
  /// For a challenge match the two squads come from two different clubs, and
  /// offering the host's members for both is how the visiting club ends up
  /// with a team sheet full of strangers. For everything else both sides are
  /// drawn from the club running the competition, as before.
  String _memberOrgFor(int side) {
    final f = widget.fixture;
    if (f.participantOrgIds == null) return f.orgId;
    return side == 0 ? f.entrantAId : f.entrantBId;
  }

  bool _lockedFor(int side) =>
      side == 0 ? widget.fixture.squadLockedA : widget.fixture.squadLockedB;

  void _toggleMember(String uid, String name) {
    setState(() {
      final list = _current;
      final existing = list.indexWhere((p) => p.id == uid);
      if (existing >= 0) {
        list.removeAt(existing);
      } else {
        // Bug #7: A player cannot play for both sides. If present in the
        // opposite team list, remove them first.
        final otherList = _tab == 0 ? _b : _a;
        otherList.removeWhere((p) => p.id == uid);
        list.add(MatchPlayer(id: uid, name: name, uid: uid));
      }
    });
  }

  Future<void> _addGuest() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a guest player'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name',
            helperText: 'They will appear on the scorecard. Career stats '
                'start once they join PlaySphere.',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    setState(() {
      _current.add(MatchPlayer(
        // Distinct from any uid, and stable for the life of the match.
        id: 'guest_${DateTime.now().microsecondsSinceEpoch}',
        name: name.trim(),
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.fixture;
    final editable = _editableSides(ref);

    // Land on a side this user may actually pick, so a visiting club's admin
    // does not open the screen looking at the opposition's team sheet.
    if (editable.isNotEmpty && !editable.contains(_tab)) {
      _tab = editable.first;
    }

    final membersAsync = ref.watch(orgMembersProvider(_memberOrgFor(_tab)));
    final members = membersAsync.valueOrNull ?? const [];
    final active = members.where((m) => m.isActive).toList();
    final selectedIds = _current.map((p) => p.id).toSet();
    final locked = _lockedFor(_tab);
    final canEditThisSide = editable.contains(_tab) && !locked;

    return AlertDialog(
      title: const Text('Who is playing?'),
      content: SizedBox(
        width: 460,
        height: 460,
        child: Column(
          children: [
            SegmentedButton<int>(
              segments: [
                ButtonSegment(
                  value: 0,
                  label: Text('${f.entrantAName} (${_a.length})'),
                  icon: f.squadLockedA ? const Icon(Icons.lock, size: 14) : null,
                ),
                ButtonSegment(
                  value: 1,
                  label: Text('${f.entrantBName} (${_b.length})'),
                  icon: f.squadLockedB ? const Icon(Icons.lock, size: 14) : null,
                ),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
            const SizedBox(height: 8),
            if (!editable.contains(_tab))
              const _SquadNotice(
                icon: Icons.visibility_outlined,
                message: 'This is the other club\'s squad. They pick it, '
                    'you can see it.',
              )
            else if (locked)
              const _SquadNotice(
                icon: Icons.lock_outline,
                message: 'This squad is locked. Reopen it to make changes.',
              ),
            // Without this, a rejected member read leaves an empty checklist
            // and the scorer concludes the club has no players.
            AsyncErrorStrip(value: membersAsync, what: 'the member list'),
            Expanded(
              child: ListView(
                children: [
                  for (final m in active)
                    CheckboxListTile(
                      dense: true,
                      value: selectedIds.contains(m.uid),
                      onChanged: canEditThisSide
                          ? (_) => _toggleMember(m.uid, m.displayName)
                          : null,
                      title: Text(m.displayName),
                    ),
                  // Guests already added to this side.
                  for (final g in _current.where((p) => p.isGuest))
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.person_outline),
                      title: Text(g.name),
                      subtitle: const Text('Guest'),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: canEditThisSide
                            ? () => setState(
                                () => _current.removeWhere((p) => p.id == g.id))
                            : null,
                      ),
                    ),
                  TextButton.icon(
                    onPressed: canEditThisSide ? _addGuest : null,
                    icon: const Icon(Icons.person_add_alt),
                    label: const Text('Add a guest player'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        // Reopening a squad this club locked. Only offered to the club that
        // locked it — the segment is not editable otherwise.
        if (locked && editable.contains(_tab))
          TextButton(
            onPressed: _busy ? null : () => _save(unlockOnly: true),
            child: const Text('Reopen squad'),
          ),
        // "Lock final squad" from the flow: one club telling the other it has
        // finished picking. Only meaningful in an inter-club match, where
        // there is another club to tell.
        if (!locked && canEditThisSide && f.participantOrgIds != null)
          TextButton(
            onPressed: _busy || _current.isEmpty
                ? null
                : () => _save(lock: true),
            child: const Text('Save & lock'),
          ),
        FilledButton(
          onPressed: _busy || !canEditThisSide || !_hasEnoughPlayers()
              ? null
              : () => _save(),
          child: Text(_busy ? 'Saving…' : _saveLabel()),
        ),
      ],
    );
  }

  /// An internal match needs both sides before it can be scored; a club
  /// picking only its own side is done when its own side is picked.
  bool _hasEnoughPlayers() {
    if (_restrictedToOneSide) return _current.isNotEmpty;
    return _a.isNotEmpty && _b.isNotEmpty;
  }

  bool get _restrictedToOneSide =>
      widget.fixture.participantOrgIds != null &&
      _editableSides(ref).length == 1;

  String _saveLabel() => _restrictedToOneSide ? 'Save our squad' : 'Save line-ups';

  Future<void> _save({bool lock = false, bool unlockOnly = false}) async {
    final f = widget.fixture;
    setState(() => _busy = true);
    try {
      final repo = ref.read(competitionRepositoryProvider);

      if (_restrictedToOneSide || lock || unlockOnly) {
        // One club, one side. Which club this user is acting for is decided
        // by the side they are on, not by anything they can type.
        final orgId = _memberOrgFor(_tab);
        await repo.setSideLineup(
          fixture: f,
          forOrgId: orgId,
          lineup: unlockOnly
              ? (_tab == 0 ? f.lineupA : f.lineupB)
              : _current,
          lock: unlockOnly ? false : (lock ? true : null),
        );
      } else {
        await repo.setLineups(
          fixture: f,
          lineupA: _a,
          lineupB: _b,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }
}

/// A short explanation of why this squad is not editable right now.
class _SquadNotice extends StatelessWidget {
  const _SquadNotice({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// The toss.
///
/// Every match starts with one and the app previously just assumed side A went
/// first. Recording it decides which innings belongs to whom, and is written
/// into the fixture's frozen scoring config so the match reads the same way
/// forever.
class TossDialog extends ConsumerStatefulWidget {
  const TossDialog({super.key, required this.fixture});

  final Fixture fixture;

  @override
  ConsumerState<TossDialog> createState() => _TossDialogState();
}

class _TossDialogState extends ConsumerState<TossDialog> {
  String? _winnerId;
  late final List<TossChoice> _choices =
      TossOptions.forSport(widget.fixture.sport);
  late String _decision = _choices.first.id;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final f = widget.fixture;
    final sport = SportCatalog.byId(f.sport);

    return AlertDialog(
      // Chess has no toss; it has a drawing of lots for colour. Calling it
      // "Toss" there would be the same error in the title that the Bat/Field
      // buttons were in the body.
      title: Text(f.sport == 'chess' ? 'Colours' : 'Toss'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                f.sport == 'chess' ? 'Who drew White?' : 'Who won it?',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              OutlinedButton.icon(
                onPressed: () {
                  final randomWinner = (DateTime.now().millisecondsSinceEpoch % 2 == 0)
                      ? f.entrantAId
                      : f.entrantBId;
                  final winnerName = randomWinner == f.entrantAId
                      ? f.entrantAName
                      : f.entrantBName;
                  setState(() => _winnerId = randomWinner);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('🪙 Coin toss result: $winnerName won the toss!')),
                  );
                },
                icon: const Icon(Icons.casino_outlined, size: 16),
                label: const Text('Flip Coin 🪙'),
              ),
            ],
          ),
          RadioListTile<String>(
            value: f.entrantAId,
            groupValue: _winnerId,
            onChanged: (v) => setState(() => _winnerId = v),
            title: Text(f.entrantAName),
            dense: true,
          ),
          RadioListTile<String>(
            value: f.entrantBId,
            groupValue: _winnerId,
            onChanged: (v) => setState(() => _winnerId = v),
            title: Text(f.entrantBName),
            dense: true,
          ),
          const Divider(),
          const Text('And chose to'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final c in _choices)
                ChoiceChip(
                  label: Text(c.label),
                  selected: _decision == c.id,
                  onSelected: (_) => setState(() => _decision = c.id),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${sport.name} · ${_startsLabel(f)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy || _winnerId == null
              ? null
              : () async {
                  setState(() => _busy = true);
                  try {
                    await ref.read(competitionRepositoryProvider).recordToss(
                          fixture: f,
                          wonByEntrantId: _winnerId!,
                          decision: _decision,
                          startingSide: _startingSide(f),
                          // Only cricket's toss decides who bats, and only
                          // cricket's engine reads `battingFirst`. Writing it
                          // for a badminton match would put a meaningless key
                          // into a frozen ruleset.
                          decidesBatting: TossOptions.decidesBatting(f.sport),
                          scoringConfig: f.scoringConfig,
                        );
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    if (context.mounted) {
                      setState(() => _busy = false);
                      showError(context, e);
                    }
                  }
                },
          child: Text(_busy ? 'Saving…' : 'Record toss'),
        ),
      ],
    );
  }

  /// Which side actually starts, given who won and what they took.
  ///
  /// One rule for every sport: a choice that gives you the first turn means
  /// you start, and one that does not hands it to the other side. Choosing
  /// ends concedes the serve; fielding concedes the bat.
  String _startingSide(Fixture f) {
    final winnerIsA = _winnerId == f.entrantAId;
    final choice = TossOptions.resolve(f.sport, _decision);
    if (choice.givesFirstTurn) return winnerIsA ? 'a' : 'b';
    return winnerIsA ? 'b' : 'a';
  }

  /// Spells the consequence back before it is saved, in the sport's own
  /// words. "Bat" and "field" produce opposite starters and a scorer who
  /// tapped the wrong chip has no other way to notice.
  String _startsLabel(Fixture f) {
    final startsA = _startingSide(f) == 'a';
    final who = startsA ? f.entrantAName : f.entrantBName;
    final verb = switch (f.sport) {
      'cricket' => 'bats first',
      'chess' => 'plays White',
      'kabaddi' => 'raids first',
      'kho_kho' => 'chases first',
      'football' || 'hockey' => 'starts',
      _ => 'serves first',
    };
    return '$who $verb';
  }
}

/// Asks which player fills a role — the incoming batter, the next bowler, or
/// the opening trio.
///
/// Returned as a payload so the caller can merge it into the ScoreAction the
/// plugin asked for.
class PlayerPicker extends StatefulWidget {
  const PlayerPicker({
    super.key,
    required this.title,
    required this.roles,
    required this.candidatesFor,
    this.optionalRoles = const {},
    this.multiRoles = const {},
    this.exclusiveRoleGroups = const [],
    this.values = const [],
  });

  /// Numbers to collect alongside the people — a time, a distance, a wind
  /// reading. Rendered after the roles, because "who" comes before "how
  /// fast".
  final List<ValuePrompt> values;

  final String title;

  /// payload key -> label, in the order they should be chosen.
  final Map<String, String> roles;

  /// Which players may fill a given role.
  final List<MatchPlayer> Function(String roleKey) candidatesFor;

  /// Roles the scorer may leave blank.
  ///
  /// An assist is the case that matters: plenty of goals have none, and a
  /// picker that will not close without one teaches the scorer to name
  /// whoever is nearest, which is worse than recording nothing. Anything not
  /// listed here is required, because the engine will reject the event
  /// without it.
  final Set<String> optionalRoles;

  /// Roles that name SEVERAL people and are written as a list.
  ///
  /// A kabaddi tackle is the case: three defenders get hold of the raider and
  /// the engine splits the points between all of them, so a single dropdown
  /// would hand a super-tackle to one player and falsify the rest.
  final Set<String> multiRoles;

  /// Groups of roles that must each name a DIFFERENT person.
  ///
  /// The cricket case is the one that got reported: a scorer could pick the
  /// same player as striker and non-striker, and only found out after tapping
  /// through the whole dialog, when the engine rejected the delivery. The
  /// answer to "who is at the other end" can never be "the person already on
  /// strike", so offering them was never right — the fix is to stop offering,
  /// not to explain the refusal better.
  ///
  /// The caller derives these from the prompts drawing on the same pool, so
  /// this generalises past cricket without knowing any sport: a footballer
  /// cannot assist their own goal, and a kho-kho attacker cannot tag himself.
  /// A prompt drawn from the OPPOSING side is in a different group and stays
  /// unfiltered — the bowler is on the other team and has nothing to do with
  /// who is batting.
  final List<Set<String>> exclusiveRoleGroups;

  @override
  State<PlayerPicker> createState() => _PlayerPickerState();
}

class _PlayerPickerState extends State<PlayerPicker> {
  final Map<String, String> _chosen = {};
  final Map<String, Set<String>> _chosenMany = {};

  bool _filled(String key) => widget.multiRoles.contains(key)
      ? (_chosenMany[key]?.isNotEmpty ?? false)
      : (_chosen[key]?.isNotEmpty ?? false);

  /// The candidates for [key], minus anyone already named in a role that must
  /// be a different person.
  ///
  /// Recomputed on every build rather than cached, because it depends on what
  /// the scorer has picked so far: choosing a striker has to remove that
  /// player from the non-striker list on the same frame.
  List<MatchPlayer> _available(String key) {
    final taken = <String>{};
    for (final group in widget.exclusiveRoleGroups) {
      if (!group.contains(key)) continue;
      for (final other in group) {
        if (other == key) continue;
        final one = _chosen[other];
        if (one != null && one.isNotEmpty) taken.add(one);
        final many = _chosenMany[other];
        if (many != null) taken.addAll(many);
      }
    }
    final pool = widget.candidatesFor(key);
    if (taken.isEmpty) return pool;
    return [
      for (final p in pool)
        if (!taken.contains(p.id)) p,
    ];
  }

  /// Drops a selection that a LATER pick has just made illegal.
  ///
  /// Without this, picking A as striker and then A as non-striker is blocked,
  /// but picking A as non-striker first and then A as striker would leave A
  /// sitting in both — the second dropdown's filter only runs against what was
  /// chosen before it. Clearing the clash keeps the dialog in a state the
  /// engine would accept, whatever order the scorer answers in.
  void _clearClashes(String justSet) {
    final id = _chosen[justSet];
    if (id == null || id.isEmpty) return;
    for (final group in widget.exclusiveRoleGroups) {
      if (!group.contains(justSet)) continue;
      for (final other in group) {
        if (other == justSet) continue;
        if (_chosen[other] == id) _chosen.remove(other);
        _chosenMany[other]?.remove(id);
      }
    }
  }

  /// Raw text per value field, kept as typed rather than as a parsed number.
  ///
  /// A half-typed "10." is not a double and must not be discarded on the
  /// keystroke that produced it — parsing on submit rather than on change is
  /// what lets somebody type a time without the field fighting them.
  final Map<String, String> _typed = {};

  double? _valueOf(ValuePrompt v) {
    final text = _typed[v.key]?.trim() ?? '';
    if (text.isEmpty) return null;
    final parsed = double.tryParse(text);
    if (parsed == null) return null;
    if (v.min != null && parsed < v.min!) return null;
    if (v.max != null && parsed > v.max!) return null;
    return parsed;
  }

  bool get _complete =>
      widget.roles.keys.every(
        (key) => widget.optionalRoles.contains(key) || _filled(key),
      ) &&
      widget.values.every((v) => v.optional || _valueOf(v) != null);

  /// Fills a role that has exactly one candidate, so the scorer is not asked
  /// a question with one answer.
  ///
  /// Real on a ground: a five-a-side with one keeper, or a kho-kho batch down
  /// to its last defender. Tapping through a dropdown of one during play is
  /// the kind of friction that gets an app put down.
  @override
  void initState() {
    super.initState();
    for (final key in widget.roles.keys) {
      if (widget.multiRoles.contains(key)) continue;
      final only = _available(key);
      if (only.length == 1) _chosen[key] = only.first.id;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in widget.roles.entries)
              if (widget.multiRoles.contains(entry.key))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.value,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final p in _available(entry.key))
                            FilterChip(
                              label: Text(p.name),
                              selected:
                                  _chosenMany[entry.key]?.contains(p.id) ??
                                      false,
                              onSelected: (on) => setState(() {
                                final set = _chosenMany.putIfAbsent(
                                  entry.key,
                                  () => <String>{},
                                );
                                if (on) {
                                  set.add(p.id);
                                } else {
                                  set.remove(p.id);
                                }
                              }),
                            ),
                        ],
                      ),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: DropdownButtonFormField<String>(
                    value: _chosen[entry.key],
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: entry.value,
                      helperText: widget.optionalRoles.contains(entry.key)
                          ? 'Optional'
                          : null,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      if (widget.optionalRoles.contains(entry.key))
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Nobody'),
                        ),
                      for (final p in _available(entry.key))
                        DropdownMenuItem(value: p.id, child: Text(p.name)),
                    ],
                    onChanged: (v) => setState(() {
                      _chosen[entry.key] = v ?? '';
                      _clearClashes(entry.key);
                    }),
                  ),
                ),
            for (final v in widget.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: TextFormField(
                  autofocus: widget.roles.isEmpty,
                  keyboardType: TextInputType.numberWithOptions(
                    decimal: !v.isInteger,
                    // A wind reading can be negative; a time cannot. The
                    // keyboard offers a minus sign only where one is legal.
                    signed: (v.min ?? 0) < 0,
                  ),
                  decoration: InputDecoration(
                    labelText: v.label,
                    suffixText: v.unit,
                    helperText: v.optional ? 'Optional' : null,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (text) => setState(() => _typed[v.key] = text),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          // Every REQUIRED role must be filled: a half-named delivery is
          // exactly the state the engine refuses.
          onPressed: _complete
              ? () => Navigator.pop(context, <String, dynamic>{
                    // Blank optional roles are dropped rather than sent as
                    // empty strings — an engine checking `payload['assistId']
                    // != null` would otherwise credit an assist to nobody.
                    for (final e in _chosen.entries)
                      if (e.value.isNotEmpty) e.key: e.value,
                    for (final e in _chosenMany.entries)
                      if (e.value.isNotEmpty) e.key: e.value.toList(),
                    // Integers go over the wire as ints: a lane is lane 4,
                    // not lane 4.0, and the engine reads `is num` either way
                    // but the stored event should say what it means.
                    for (final v in widget.values)
                      if (_valueOf(v) case final n?)
                        v.key: v.isInteger ? n.round() : n,
                  })
              : null,
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
