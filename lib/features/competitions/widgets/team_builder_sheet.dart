import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/competition.dart';
import '../../../core/models/enums.dart';
import '../../../core/providers.dart';
import '../../../data/competition_repository.dart';
import '../../../domain/tournament/house_roster.dart';
import '../../../domain/tournament/team_partitioner.dart';
import '../../../shared/app_scaffold.dart';

/// Interactive Smart Team Builder & Draft modal for organizers.
/// Allows splitting player pool into N balanced teams, house squads, or custom drafts.
class TeamBuilderSheet extends ConsumerStatefulWidget {
  const TeamBuilderSheet({
    super.key,
    required this.competition,
    required this.registrations,
  });

  final Competition competition;
  final List<Registration> registrations;

  static Future<void> show(
    BuildContext context, {
    required Competition competition,
    required List<Registration> registrations,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        builder: (_) => TeamBuilderSheet(
          competition: competition,
          registrations: registrations,
        ),
      );

  @override
  ConsumerState<TeamBuilderSheet> createState() => _TeamBuilderSheetState();
}

class _DraftTeam {
  _DraftTeam({required this.name, List<Registration>? members})
      : members = members ?? [];

  String name;
  List<Registration> members;
}

class _TeamBuilderSheetState extends ConsumerState<TeamBuilderSheet> {
  final List<_DraftTeam> _teams = [];
  final List<Registration> _unassigned = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _initDraft();
  }

  void _initDraft() {
    _unassigned.clear();
    _teams.clear();

    final c = widget.competition;
    final confirmed = widget.registrations
        .where((r) => r.status == RegistrationStatus.confirmed)
        .toList();

    if (c.teamEntryMode == TeamEntryMode.houseBatch &&
        c.presetHouses.isNotEmpty) {
      // Group by preset houses
      final houseMap = <String, List<Registration>>{
        for (final h in c.presetHouses) h: [],
      };
      for (final r in confirmed) {
        final h = r.houseName;
        if (h != null && houseMap.containsKey(h)) {
          houseMap[h]!.add(r);
        } else if (c.presetHouses.isNotEmpty) {
          // Put in unassigned
          _unassigned.add(r);
        }
      }
      for (final entry in houseMap.entries) {
        _teams.add(_DraftTeam(name: entry.key, members: entry.value));
      }
    } else {
      // Default: Put all into unassigned and prepare 2 default teams
      _unassigned.addAll(confirmed);
      _autoBalance(2);
    }
  }

  void _autoBalance(int teamCount, [RemainderStrategy strategy = RemainderStrategy.distributeEvenly]) {
    if (teamCount < 2) return;
    setState(() {
      final allPlayers = [
        ..._unassigned,
        for (final t in _teams) ...t.members,
      ];
      _unassigned.clear();
      _teams.clear();

      const partitioner = TeamPartitioner();
      final result = partitioner.partition(
        players: allPlayers,
        teamCount: teamCount,
        targetSquadSize: widget.competition.teamSize,
        remainderStrategy: strategy,
      );

      for (final squad in result.squads) {
        _teams.add(_DraftTeam(name: squad.name, members: squad.members));
      }
      _unassigned.addAll(result.unassigned);
      _unassigned.addAll(result.waitlistOverflow);
    });
  }

  void _splitByHouses() {
    final c = widget.competition;
    final houses = c.presetHouses.isNotEmpty
        ? c.presetHouses
        : HouseTemplates.schoolColours;

    setState(() {
      final allPlayers = [
        ..._unassigned,
        for (final t in _teams) ...t.members,
      ];
      _unassigned.clear();
      _teams.clear();

      const partitioner = TeamPartitioner();
      final result = partitioner.partitionByBuckets(
        players: allPlayers,
        bucketIds: houses,
        bucketNames: {for (final h in houses) h: h},
      );

      for (final squad in result.squads) {
        _teams.add(_DraftTeam(name: squad.name, members: squad.members));
      }
      _unassigned.addAll(result.unassigned);
    });
  }

  void _addCustomTeam() {
    setState(() {
      _teams.add(_DraftTeam(name: 'Team ${_teams.length + 1}'));
    });
  }

  void _movePlayer(Registration player, _DraftTeam fromTeam, _DraftTeam? toTeam) {
    setState(() {
      fromTeam.members.removeWhere((r) => r.uid == player.uid);
      if (toTeam != null) {
        toTeam.members.add(player);
      } else {
        _unassigned.add(player);
      }
    });
  }

  void _assignPlayerFromPool(Registration player, _DraftTeam targetTeam) {
    setState(() {
      _unassigned.removeWhere((r) => r.uid == player.uid);
      targetTeam.members.add(player);
    });
  }

  Future<void> _submitAndLock() async {
    final validTeams = _teams.where((t) => t.members.isNotEmpty).toList();
    if (validTeams.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please form at least 2 teams with players to create a draw.'),
        ),
      );
      return;
    }

    setState(() => _busy = true);
    final c = widget.competition;

    try {
      final specs = validTeams
          .map(
            (t) => TeamDraftSpec(
              name: t.name.trim().isEmpty ? 'Team' : t.name.trim(),
              memberUids: t.members.map((m) => m.uid).toList(),
              captainUid: t.members.first.uid,
            ),
          )
          .toList();

      await ref.read(competitionRepositoryProvider).formTeamsFromPool(
            orgId: c.orgId,
            compId: c.id,
            teams: specs,
          );

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${specs.length} teams locked into draw! Generating fixtures and timetable.',
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
    final theme = Theme.of(context);
    final confirmedCount = widget.registrations
        .where((r) => r.status == RegistrationStatus.confirmed)
        .length;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.groups_3_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Smart Team Builder & Draft',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '$confirmedCount players confirmed in pool',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Action Toolbar
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              PopupMenuButton<int>(
                tooltip: 'Auto-balance into equal teams',
                onSelected: _autoBalance,
                itemBuilder: (ctx) => [
                  for (final n in [2, 3, 4, 6, 8])
                    PopupMenuItem(
                      value: n,
                      child: Text('Auto-split into $n Teams'),
                    ),
                ],
                child: Chip(
                  avatar: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text('Auto-Balance Teams'),
                  backgroundColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                ),
              ),
              ActionChip(
                avatar: const Icon(Icons.school_outlined, size: 16),
                label: const Text('Split by Houses'),
                onPressed: _splitByHouses,
              ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 16),
                label: const Text('+ Custom Team'),
                onPressed: _addCustomTeam,
              ),
            ],
          ),
          const Divider(height: 20),

          // Unassigned Pool (if any)
          if (_unassigned.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Unassigned Pool (${_unassigned.length})',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final player in _unassigned)
                        PopupMenuButton<_DraftTeam>(
                          tooltip: 'Assign to a team',
                          onSelected: (team) => _assignPlayerFromPool(player, team),
                          itemBuilder: (ctx) => [
                            for (final team in _teams)
                              PopupMenuItem(
                                value: team,
                                child: Text('Move to ${team.name}'),
                              ),
                          ],
                          child: Chip(
                            avatar: const Icon(Icons.person, size: 14),
                            label: Text(player.displayName),
                            deleteIcon: const Icon(Icons.arrow_drop_down, size: 16),
                            onDeleted: () {},
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Squad Cards
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _teams.length,
              itemBuilder: (ctx, idx) {
                final team = _teams[idx];
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                initialValue: team.name,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: UnderlineInputBorder(),
                                  labelText: 'Team Name',
                                ),
                                onChanged: (v) => team.name = v,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Chip(
                              label: Text('${team.members.length} players'),
                              backgroundColor: theme.colorScheme.primaryContainer,
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              onPressed: () {
                                setState(() {
                                  _unassigned.addAll(team.members);
                                  _teams.removeAt(idx);
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (team.members.isEmpty)
                          Text(
                            'No players in squad. Assign from pool above or drag players.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.hintColor,
                              fontStyle: FontStyle.italic,
                            ),
                          )
                        else
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              for (final player in team.members)
                                PopupMenuButton<_DraftTeam?>(
                                  tooltip: 'Reassign player',
                                  onSelected: (target) => _movePlayer(player, team, target),
                                  itemBuilder: (ctx) => [
                                    for (final other in _teams)
                                      if (other != team)
                                        PopupMenuItem(
                                          value: other,
                                          child: Text('Move to ${other.name}'),
                                        ),
                                    const PopupMenuItem(
                                      value: null,
                                      child: Text('Move back to Pool'),
                                    ),
                                  ],
                                  child: Chip(
                                    label: Text(player.displayName),
                                    deleteIcon: const Icon(Icons.arrow_drop_down, size: 16),
                                    onDeleted: () {},
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _submitAndLock,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.lock_outline),
            label: Text(
              _busy
                  ? 'Saving Teams...'
                  : 'Lock ${_teams.where((t) => t.members.isNotEmpty).length} Squads & Create Draw Entrants',
            ),
          ),
        ],
      ),
    );
  }
}
