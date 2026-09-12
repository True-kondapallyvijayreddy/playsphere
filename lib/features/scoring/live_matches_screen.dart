import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/competition.dart';
import '../../core/models/fixture.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../shared/app_scaffold.dart';
import 'widgets/live_score_card.dart';

/// Everything happening right now in this organization, plus the matches the
/// signed-in user is personally assigned to score.
///
/// This is the screen a remote spectator lands on, and the one a volunteer
/// scorer opens when they arrive at the ground.
///
/// A flat list of every live fixture reads fine at ten matches and becomes
/// noise at a hundred — a big season runs several sports across several
/// courts at once, and a spectator looking for one match should not have to
/// scan past all the others to find it. So this groups by sport and then by
/// competition, with a sport filter row on top; nothing here bounds the
/// *query* (that is a separate fix — see `liveFixturesProvider`), it only
/// bounds what one screen asks a person to look at.
class LiveMatchesScreen extends ConsumerStatefulWidget {
  const LiveMatchesScreen({super.key, required this.orgId});

  final String orgId;

  @override
  ConsumerState<LiveMatchesScreen> createState() => _LiveMatchesScreenState();
}

class _LiveMatchesScreenState extends ConsumerState<LiveMatchesScreen> {
  /// Null means "all sports". Holds a sport *name* (not id) because that is
  /// what [Competition.sportName] gives us for grouping, and it is the same
  /// label the rest of the app already shows for a sport.
  String? _sportFilter;

  @override
  Widget build(BuildContext context) {
    final orgId = widget.orgId;
    final live = ref.watch(liveFixturesProvider(orgId));
    final competitions = ref.watch(competitionsProvider(orgId));
    final mineAsync = ref.watch(myScoringAssignmentsProvider);
    final mine = mineAsync.valueOrNull ?? const [];
    final canScore =
        ref.watch(myCapabilitiesProvider(orgId)).contains(Capability.scoreMatches);

    final myHere = mine.where((f) => f.orgId == orgId).toList();

    return AppScaffold(
      orgId: orgId,
      title: 'Live now',
      body: AsyncView(
        value: live,
        builder: (fixtures) {
          // Guarded by `!hasError`: if the assignments query was rejected,
          // `myHere` is empty for the wrong reason, and telling a scorer that
          // nothing is being played would send them home from a live ground.
          if (fixtures.isEmpty && myHere.isEmpty && !mineAsync.hasError) {
            return const EmptyState(
              icon: Icons.sensors_off_outlined,
              title: 'Nothing is being played right now',
              message: 'When a scorer starts a match it will appear here '
                  'instantly, for everyone.',
            );
          }

          // compId -> Competition, so a fixture can be labelled by its sport
          // and competition name without an extra read per card.
          final compById = <String, Competition>{
            for (final c in competitions.valueOrNull ?? const <Competition>[])
              c.id: c,
          };

          final grouped = _groupBySportThenCompetition(fixtures, compById);
          final sportOrder = grouped.keys.toList()..sort();
          final selected = _sportFilter != null && sportOrder.contains(_sportFilter)
              ? _sportFilter
              : null;
          final visibleSports = selected == null ? sportOrder : [selected];

          return ListView(
            children: [
              ContentBounds(
                maxWidth: 980,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AsyncErrorStrip(
                      value: mineAsync,
                      what: 'the matches you are scoring',
                    ),
                    if (canScore && myHere.isNotEmpty) ...[
                      Text(
                        'You are scoring',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tap to open the scoring pad.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 10),
                      for (final f in myHere)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: LiveScoreCard(
                            fixture: f,
                            onTap: () => context.push(
                              Routes.scoring(orgId, f.compId, f.id),
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),
                    ],
                    if (fixtures.isNotEmpty) ...[
                      Text(
                        'Live matches',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      // Only worth showing once there is something to split —
                      // one sport, one chip, is a filter nobody needs.
                      if (sportOrder.length > 1) ...[
                        _SportFilterRow(
                          sports: sportOrder,
                          counts: {
                            for (final s in sportOrder)
                              s: grouped[s]!.values
                                  .fold<int>(0, (n, list) => n + list.length),
                          },
                          selected: selected,
                          onSelected: (s) => setState(() => _sportFilter = s),
                        ),
                        const SizedBox(height: 14),
                      ],
                      for (final sport in visibleSports)
                        _SportSection(
                          sportName: sport,
                          byCompetition: grouped[sport]!,
                          compById: compById,
                          onTap: (f) => context.push(
                            Routes.watch(orgId, f.compId, f.id),
                          ),
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

  /// sportName -> compId -> fixtures, each fixture list in scheduled order.
  ///
  /// A fixture with no matching competition (deleted, or a read raced the
  /// competition doc) falls back to compId as both the sport and competition
  /// label rather than being silently dropped — a live match is worth
  /// showing even mislabelled.
  Map<String, Map<String, List<Fixture>>> _groupBySportThenCompetition(
    List<Fixture> fixtures,
    Map<String, Competition> compById,
  ) {
    final grouped = <String, Map<String, List<Fixture>>>{};
    for (final f in fixtures) {
      final comp = compById[f.compId];
      final sportName = comp?.sportName ?? 'Other';
      final bySport = grouped.putIfAbsent(sportName, () => {});
      bySport.putIfAbsent(f.compId, () => []).add(f);
    }
    return grouped;
  }
}

class _SportFilterRow extends StatelessWidget {
  const _SportFilterRow({
    required this.sports,
    required this.counts,
    required this.selected,
    required this.onSelected,
  });

  final List<String> sports;
  final Map<String, int> counts;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          ChoiceChip(
            label: Text('All ($total)'),
            selected: selected == null,
            onSelected: (_) => onSelected(null),
          ),
          const SizedBox(width: 8),
          for (final sport in sports) ...[
            ChoiceChip(
              label: Text('$sport (${counts[sport]})'),
              selected: selected == sport,
              onSelected: (_) => onSelected(sport),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _SportSection extends StatelessWidget {
  const _SportSection({
    required this.sportName,
    required this.byCompetition,
    required this.compById,
    required this.onTap,
  });

  final String sportName;
  final Map<String, List<Fixture>> byCompetition;
  final Map<String, Competition> compById;
  final void Function(Fixture) onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Competitions with more live matches lead — that is where the action
    // (and the search) actually is.
    final compIds = byCompetition.keys.toList()
      ..sort((a, b) => byCompetition[b]!.length.compareTo(byCompetition[a]!.length));

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(sportName, style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.primary,
          )),
          const SizedBox(height: 8),
          for (final compId in compIds) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                compById[compId]?.name ?? 'Unnamed competition',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            for (final f in byCompetition[compId]!)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: LiveScoreCard(fixture: f, onTap: () => onTap(f)),
              ),
          ],
        ],
      ),
    );
  }
}
