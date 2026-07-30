import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/fixture.dart';
import '../../core/models/match_player.dart';
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

  void _toggleMember(String uid, String name) {
    setState(() {
      final list = _current;
      final existing = list.indexWhere((p) => p.id == uid);
      if (existing >= 0) {
        list.removeAt(existing);
      } else {
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
    final membersAsync = ref.watch(orgMembersProvider(f.orgId));
    final members = membersAsync.valueOrNull ?? const [];
    final active = members.where((m) => m.isActive).toList();
    final selectedIds = _current.map((p) => p.id).toSet();

    return AlertDialog(
      title: const Text('Who is playing?'),
      content: SizedBox(
        width: 460,
        height: 460,
        child: Column(
          children: [
            SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 0, label: Text('${f.entrantAName} (${_a.length})')),
                ButtonSegment(value: 1, label: Text('${f.entrantBName} (${_b.length})')),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
            const SizedBox(height: 8),
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
                      onChanged: (_) => _toggleMember(m.uid, m.displayName),
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
                        onPressed: () =>
                            setState(() => _current.removeWhere((p) => p.id == g.id)),
                      ),
                    ),
                  TextButton.icon(
                    onPressed: _addGuest,
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
        FilledButton(
          onPressed: _busy || _a.isEmpty || _b.isEmpty
              ? null
              : () async {
                  setState(() => _busy = true);
                  try {
                    await ref.read(competitionRepositoryProvider).setLineups(
                          orgId: f.orgId,
                          compId: f.compId,
                          fixtureId: f.id,
                          lineupA: _a,
                          lineupB: _b,
                        );
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    if (context.mounted) {
                      setState(() => _busy = false);
                      showError(context, e);
                    }
                  }
                },
          child: Text(_busy ? 'Saving…' : 'Save line-ups'),
        ),
      ],
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
  String _decision = 'bat';
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final f = widget.fixture;

    return AlertDialog(
      title: const Text('Toss'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Who won it?'),
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
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'bat', label: Text('Bat')),
              ButtonSegment(value: 'field', label: Text('Field')),
            ],
            selected: {_decision},
            onSelectionChanged: (s) => setState(() => _decision = s.first),
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
                  // The side that bats first is the toss winner if they chose
                  // to bat, otherwise the other side.
                  final winnerIsA = _winnerId == f.entrantAId;
                  final battingFirst = _decision == 'bat'
                      ? (winnerIsA ? 'a' : 'b')
                      : (winnerIsA ? 'b' : 'a');
                  try {
                    await ref.read(competitionRepositoryProvider).recordToss(
                          orgId: f.orgId,
                          compId: f.compId,
                          fixtureId: f.id,
                          wonByEntrantId: _winnerId!,
                          decision: _decision,
                          battingFirstSide: battingFirst,
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
  });

  final String title;

  /// payload key -> label, in the order they should be chosen.
  final Map<String, String> roles;

  /// Which players may fill a given role.
  final List<MatchPlayer> Function(String roleKey) candidatesFor;

  @override
  State<PlayerPicker> createState() => _PlayerPickerState();
}

class _PlayerPickerState extends State<PlayerPicker> {
  final Map<String, String> _chosen = {};

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
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: DropdownButtonFormField<String>(
                  value: _chosen[entry.key],
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: entry.value,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final p in widget.candidatesFor(entry.key))
                      DropdownMenuItem(value: p.id, child: Text(p.name)),
                  ],
                  onChanged: (v) => setState(() => _chosen[entry.key] = v ?? ''),
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
          // Every role must be filled: a half-named delivery is exactly the
          // state the engine refuses.
          onPressed: _chosen.length == widget.roles.length &&
                  _chosen.values.every((v) => v.isNotEmpty)
              ? () => Navigator.pop(context, Map<String, dynamic>.from(_chosen))
              : null,
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
