import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/career/scoped_stats.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui_kit.dart';

/// One player's record, sliced by where the matches came from.
///
/// `docs/Heart_of_the_playsphere.md` §18: a career total, a season total and
/// a tournament total are "different views of the same underlying match
/// data". This screen is that sentence made literal — every figure on it is
/// computed from the same list of fixtures, filtered, never from a separate
/// stored aggregate that could drift out of step.
///
/// ## Why this is computed on the client
///
/// `career_stats` holds lifetime totals only, one document per sport, and
/// deliberately so — it is written by increment on match finalize, which is
/// what makes it cheap and correct. Per-scope totals cannot be maintained the
/// same way without one stored document per (player x sport x scope), each of
/// which is another number that can disagree with the others. A career is a
/// few hundred fixtures, already streamed for the match list, so filtering it
/// costs nothing extra and cannot be inconsistent by construction.
class PlayerStatsScreen extends ConsumerStatefulWidget {
  const PlayerStatsScreen({
    super.key,
    required this.uid,
    required this.sportId,
  });

  final String uid;
  final String sportId;

  @override
  ConsumerState<PlayerStatsScreen> createState() => _PlayerStatsScreenState();
}

class _PlayerStatsScreenState extends ConsumerState<PlayerStatsScreen> {
  StatScope _scope = StatScope.all;

  @override
  Widget build(BuildContext context) {
    final fixturesAsync = ref.watch(playerFixturesProvider(widget.uid));
    final sportName = SportCatalog.byId(widget.sportId).name;

    return Scaffold(
      backgroundColor: Ps.canvas,
      appBar: AppBar(
        backgroundColor: Ps.surface,
        foregroundColor: Ps.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: Ps.ink),
        title: Text(
          '$sportName stats',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Ps.ink,
          ),
        ),
      ),
      body: AsyncView(
        value: fixturesAsync,
        onRetry: () => ref.invalidate(playerFixturesProvider(widget.uid)),
        builder: (fixtures) {
          final byScope = ScopedStats.forPlayer(
            fixtures: fixtures,
            uid: widget.uid,
            sportId: widget.sportId,
          );
          final stats = byScope[_scope]!;

          return Column(
            children: [
              const SizedBox(height: 8),
              _ScopeTabs(
                selected: _scope,
                // The count beside each label, so a scope that leads nowhere
                // says so before it is tapped.
                counts: {
                  for (final entry in byScope.entries)
                    entry.key: entry.value.matches,
                },
                onSelected: (scope) => setState(() => _scope = scope),
              ),
              Expanded(
                child: stats.isEmpty
                    ? _EmptyScope(scope: _scope, sportName: sportName)
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                        children: [
                          _RecordCard(stats: stats),
                          const SizedBox(height: 12),
                          _TallyCard(stats: stats),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ScopeTabs extends StatelessWidget {
  const _ScopeTabs({
    required this.selected,
    required this.counts,
    required this.onSelected,
  });

  final StatScope selected;
  final Map<StatScope, int> counts;
  final ValueChanged<StatScope> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: Ps.gutter,
        itemCount: StatScope.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final scope = StatScope.values[i];
          final isSelected = scope == selected;
          return InkWell(
            onTap: () => onSelected(scope),
            borderRadius: BorderRadius.circular(Ps.radiusSm),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isSelected ? Ps.primary : Ps.surface,
                borderRadius: BorderRadius.circular(Ps.radiusSm),
                border: Border.all(color: isSelected ? Ps.primary : Ps.border),
              ),
              child: Text(
                '${scope.label} (${counts[scope] ?? 0})',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : Ps.muted,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Matches, won, lost and win rate for the chosen scope.
class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.stats});

  final ScopedStats stats;

  @override
  Widget build(BuildContext context) {
    final rate = stats.winRate;
    return PsCard(
      child: PsStatRow(
        stats: [
          PsStat(value: psGrouped(stats.matches), label: 'Matches'),
          PsStat(value: psGrouped(stats.won), label: 'Won'),
          PsStat(value: psGrouped(stats.lost), label: 'Lost'),
          PsStat(
            // A dash, not 0%, when nothing has been decided — "has not
            // played" and "never wins" are different claims.
            value: rate == null ? '—' : '${(rate * 100).round()}%',
            label: 'Win rate',
          ),
        ],
      ),
    );
  }
}

/// Every counter this sport's engine recorded, summed over the scope.
class _TallyCard extends StatelessWidget {
  const _TallyCard({required this.stats});

  final ScopedStats stats;

  @override
  Widget build(BuildContext context) {
    final entries = stats.tally.entries.where((e) => e.value != 0).toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));

    if (entries.isEmpty) {
      return const PsCard(
        child: Text(
          'No per-player figures were recorded for these matches. A match '
          'scored without line-ups produces a result but no individual '
          'statistics.',
          style: TextStyle(fontSize: 13, color: Ps.muted, height: 1.4),
        ),
      );
    }

    return PsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Figures',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Ps.ink,
            ),
          ),
          const SizedBox(height: 10),
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      psHumanizeCounter(entry.key),
                      style: const TextStyle(fontSize: 13, color: Ps.muted),
                    ),
                  ),
                  Text(
                    _format(entry.value),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Ps.ink,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Whole numbers stay whole; rates and averages keep two places.
  static String _format(num v) =>
      v is int || v == v.roundToDouble() ? psGrouped(v.round()) : v.toStringAsFixed(2);

}

class _EmptyScope extends StatelessWidget {
  const _EmptyScope({required this.scope, required this.sportName});

  final StatScope scope;
  final String sportName;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.query_stats, size: 40, color: Ps.faint),
            const SizedBox(height: 12),
            Text(
              scope == StatScope.all
                  ? 'No finished $sportName matches yet'
                  : 'No $sportName matches in a ${scope.label.toLowerCase()}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Ps.ink,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Statistics appear once a match is finished and its result is '
              'settled.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Ps.muted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
