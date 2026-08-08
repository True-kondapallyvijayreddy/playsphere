import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/enums.dart';
import '../../core/models/fixture.dart';
import '../../core/models/match_official.dart';
import '../../core/models/organization.dart';
import '../../core/models/tournament_official.dart';
import '../../core/models/umpire_profile.dart';
import '../../core/providers.dart';
import '../../domain/draw/officials_roster.dart';
import '../../shared/app_scaffold.dart';

/// The season owner's officiating panel — added ahead of the tournament,
/// ICC-style, so nobody is chasing an umpire at the gate.
///
/// Three things happen here, in the order an organizer actually needs them:
/// build the panel (from the open registry, or by hand), run the neutral
/// bulk assignment once the bracket is scheduled, and fix by hand whatever
/// it could not place. The bulk step never overwrites a hand fix — see
/// [TournamentRepository.assignOfficialsAcrossTournament].
class OfficialsScreen extends ConsumerWidget {
  const OfficialsScreen({
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

    return AppScaffold(
      orgId: orgId,
      title: 'Officials',
      actions: [
        IconButton(
          icon: const Icon(Icons.person_add_alt_outlined),
          tooltip: 'Add an official',
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) =>
                _AddOfficialSheet(orgId: orgId, tournamentId: tournamentId),
          ),
        ),
      ],
      body: AsyncView(
        value: tAsync,
        builder: (tournament) {
          if (tournament == null) {
            return const EmptyState(
              icon: Icons.search_off,
              title: 'This tournament no longer exists',
            );
          }

          final rosterAsync = ref.watch(tournamentOfficialsProvider(key));
          final roster = rosterAsync.valueOrNull ?? const <TournamentOfficial>[];
          final fixturesAsync = ref.watch(tournamentFixturesProvider(key));
          final fixtures = fixturesAsync.valueOrNull ?? const <Fixture>[];
          final unofficiated = [
            for (final f in fixtures)
              if (f.officials.isEmpty && f.status == FixtureStatus.scheduled)
                f,
          ];

          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              ContentBounds(
                maxWidth: 820,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    AsyncErrorStrip(value: rosterAsync, what: 'the panel'),
                    AsyncErrorStrip(
                      value: fixturesAsync,
                      what: 'the matches',
                    ),
                    if (roster.isEmpty)
                      const EmptyState(
                        icon: Icons.sports_outlined,
                        title: 'No officials added yet',
                        message: 'Add umpires and referees to this '
                            "tournament's panel before the draw goes live — "
                            'pick from the open registry, or add someone by '
                            'hand.',
                      )
                    else ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                        child: Text(
                          'Panel (${roster.length})',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      for (final o in roster)
                        _OfficialTile(
                          orgId: orgId,
                          tournamentId: tournamentId,
                          official: o,
                        ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        icon: const Icon(Icons.rule_outlined),
                        label: const Text(
                          'Assign officials across the bracket',
                        ),
                        onPressed: () => _runBulkAssign(context, ref),
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          'Neutral by construction — nobody is placed on a '
                          "match their own club is playing. What can't be "
                          'placed is reported below, not silently skipped.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color:
                                    Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    ],
                    if (unofficiated.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                        child: Text(
                          'Still need an official (${unofficiated.length})',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      for (final f in unofficiated)
                        _UnstaffedFixtureTile(
                          orgId: orgId,
                          fixture: f,
                          roster: roster,
                        ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _runBulkAssign(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    late final OfficialsRoster result;
    try {
      result = await ref.read(tournamentRepositoryProvider).assignOfficialsAcrossTournament(
            orgId: orgId,
            tournamentId: tournamentId,
          );
    } catch (e) {
      if (context.mounted) showError(context, e);
      return;
    }
    if (!context.mounted) return;

    if (result.isComplete) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '${result.assignments.length} match'
              '${result.assignments.length == 1 ? '' : 'es'} staffed. '
              'Every match has a neutral official.',
            ),
          ),
        );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Some matches still need an official'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${result.assignments.length} placed, '
                '${result.unstaffed.length} could not be.',
              ),
              const SizedBox(height: 12),
              for (final u in result.unstaffed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${u.slot.label.isEmpty ? u.slot.fixtureId : u.slot.label}\n'
                    '${u.reason}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _OfficialTile extends ConsumerWidget {
  const _OfficialTile({
    required this.orgId,
    required this.tournamentId,
    required this.official,
  });

  final String orgId;
  final String tournamentId;
  final TournamentOfficial official;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = official;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.sports_outlined),
        title: Text(o.name),
        subtitle: Text(
          [
            _roleLabel(o.role),
            if (o.sports.isNotEmpty) o.sports.join(', '),
            if (!o.scoringRightsGranted) 'scoring rights not granted',
          ].join(' · '),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Remove from panel',
          onPressed: () async {
            try {
              await ref.read(tournamentRepositoryProvider).removeOfficialFromRoster(
                    orgId: orgId,
                    tournamentId: tournamentId,
                    uid: o.uid,
                  );
            } catch (e) {
              if (context.mounted) showError(context, e);
            }
          },
        ),
      ),
    );
  }

  static String _roleLabel(String role) => switch (role) {
        'square_leg_umpire' => 'Square leg umpire',
        'referee' => 'Referee',
        'third_umpire' => 'Third umpire',
        'linesman' => 'Linesman',
        _ => 'Umpire',
      };
}

/// A scheduled match with no official yet — the manual fallback for whatever
/// the bulk run above could not place, or hasn't been run yet.
class _UnstaffedFixtureTile extends ConsumerWidget {
  const _UnstaffedFixtureTile({
    required this.orgId,
    required this.fixture,
    required this.roster,
  });

  final String orgId;
  final Fixture fixture;
  final List<TournamentOfficial> roster;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = fixture;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text('${f.entrantAName} vs ${f.entrantBName}'),
        subtitle: Text([
          if (f.roundLabel != null) f.roundLabel!,
          if (f.scheduledAt != null) _fmt(f.scheduledAt!),
          if (f.venue != null) f.venue!,
        ].join(' · ')),
        trailing: TextButton(
          onPressed: roster.isEmpty
              ? null
              : () => showModalBottomSheet<void>(
                    context: context,
                    showDragHandle: true,
                    builder: (_) => _AssignToFixtureSheet(
                      orgId: orgId,
                      fixture: f,
                      roster: roster,
                    ),
                  ),
          child: const Text('Assign'),
        ),
      ),
    );
  }

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _AssignToFixtureSheet extends ConsumerStatefulWidget {
  const _AssignToFixtureSheet({
    required this.orgId,
    required this.fixture,
    required this.roster,
  });

  final String orgId;
  final Fixture fixture;
  final List<TournamentOfficial> roster;

  @override
  ConsumerState<_AssignToFixtureSheet> createState() =>
      _AssignToFixtureSheetState();
}

class _AssignToFixtureSheetState extends ConsumerState<_AssignToFixtureSheet> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final f = widget.fixture;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${f.entrantAName} vs ${f.entrantBName}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            for (final o in widget.roster)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.sports_outlined),
                title: Text(o.name),
                enabled: !_busy,
                onTap: () => _assign(o),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _assign(TournamentOfficial o) async {
    setState(() => _busy = true);
    try {
      await ref.read(umpireRepositoryProvider).assignOfficialToFixture(
            orgId: widget.orgId,
            compId: widget.fixture.compId,
            fixtureId: widget.fixture.id,
            official: MatchOfficial(
              uid: o.uid,
              name: o.name,
              role: o.role,
              grantedScoringAccess: o.scoringRightsGranted,
            ),
            grantScoringAccess: o.scoringRightsGranted,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }
}

/// Adding someone to the panel — from the open, cross-club registry of
/// people certified to officiate, from this club's own members, or typed in
/// by hand for the common case: a volunteer who has never opened the app.
class _AddOfficialSheet extends ConsumerStatefulWidget {
  const _AddOfficialSheet({required this.orgId, required this.tournamentId});

  final String orgId;
  final String tournamentId;

  @override
  ConsumerState<_AddOfficialSheet> createState() => _AddOfficialSheetState();
}

class _AddOfficialSheetState extends ConsumerState<_AddOfficialSheet> {
  final _sport = TextEditingController();
  final _name = TextEditingController();
  bool _searching = false;
  bool _busy = false;
  List<UmpireProfile> _found = const [];

  @override
  void dispose() {
    _sport.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final membersAsync = ref.watch(orgMembersProvider(widget.orgId));
    final members = membersAsync.valueOrNull ?? const <Membership>[];
    final query = _name.text.trim().toLowerCase();
    final memberMatches = query.isEmpty
        ? const <Membership>[]
        : [
            for (final m in members)
              if (m.isActive && m.displayName.toLowerCase().contains(query)) m,
          ].take(8).toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add an official', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Pick someone certified in the open registry, a member of '
                'this club, or add a name by hand.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _sport,
                decoration: InputDecoration(
                  labelText: 'Search the open registry by sport',
                  hintText: 'e.g. cricket',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: const OutlineInputBorder(),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          icon: const Icon(Icons.arrow_forward),
                          onPressed: _search,
                        ),
                ),
                onSubmitted: (_) => _search(),
              ),
              if (_found.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final u in _found)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.verified_outlined),
                    title: Text(u.displayName),
                    subtitle: Text('${_badgeLabel(u.badgeLevel)} · '
                        '${u.sports.join(', ')}'),
                    trailing: FilledButton.tonal(
                      onPressed: _busy
                          ? null
                          : () => _add(
                                uid: u.uid,
                                name: u.displayName,
                                sports: u.sports,
                              ),
                      child: const Text('Add'),
                    ),
                  ),
              ],
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 8),
              Text('Or a club member', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Find by name',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              for (final m in memberMatches)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.person_outline),
                  title: Text(m.displayName),
                  trailing: FilledButton.tonal(
                    onPressed: _busy
                        ? null
                        : () => _add(
                              uid: m.uid,
                              name: m.displayName,
                              clubId: widget.orgId,
                            ),
                    child: const Text('Add'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _badgeLabel(String tier) => switch (tier) {
        'district_certified' => 'District certified',
        'state_certified' => 'State certified',
        'association_certified' => 'Association certified',
        _ => 'Community',
      };

  Future<void> _search() async {
    final sport = _sport.text.trim().toLowerCase();
    if (sport.isEmpty) return;
    setState(() => _searching = true);
    try {
      final found =
          await ref.read(umpireRepositoryProvider).fetchUmpiresForSport(sport);
      if (mounted) setState(() => _found = found);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _add({
    required String uid,
    required String name,
    List<String> sports = const [],
    String? clubId,
  }) async {
    final addedBy = ref.read(currentUidProvider);
    if (addedBy == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(tournamentRepositoryProvider).addOfficialToRoster(
            orgId: widget.orgId,
            tournamentId: widget.tournamentId,
            official: TournamentOfficial(
              uid: uid,
              name: name,
              sports: sports,
              clubId: clubId,
            ),
            addedByUid: addedBy,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('$name added to the panel.')));
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }
}
