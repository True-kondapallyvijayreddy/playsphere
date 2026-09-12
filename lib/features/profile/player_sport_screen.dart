import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/fixture.dart';
import '../../core/models/ranking_entry.dart';
import '../../core/providers.dart';
import '../../data/career_repository.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui_kit.dart';
import 'my_matches_screen.dart';

/// One sport within one player's career.
///
/// Feature #14: tapping a sport should show that sport's matches, their
/// scorecards, the leaderboard and the related statistics. Before this, a
/// sport was a card on the profile that did not respond to a tap, so all four
/// of those existed in the data and none of them had a screen.
///
/// Composed entirely from providers that already existed — the per-sport
/// career tally, the ranking list for the sport, and the player's own
/// fixtures filtered to it. Nothing here computes a new statistic; it is the
/// first place they are shown together.
class PlayerSportScreen extends ConsumerWidget {
  const PlayerSportScreen({
    super.key,
    required this.uid,
    required this.sportId,
  });

  final String uid;

  /// May carry a qualifier — `chess:blitz` is a distinct record from
  /// `chess:classical`, per §7.11.
  final String sportId;

  String get _baseSportId => sportId.split(':').first;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final career = ref.watch(careerProvider(uid));
    final fixtures =
        ref.watch(playerSportFixturesProvider((uid: uid, sportId: sportId)));
    final ranking = ref.watch(rankingProvider(_baseSportId));
    final isMe = ref.watch(currentUidProvider) == uid;

    final sport = SportCatalog.byId(_baseSportId);
    final qualifier =
        sportId.contains(':') ? sportId.split(':').last : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          qualifier == null ? sport.name : '${sport.name} · $qualifier',
        ),
      ),
      body: AsyncView(
        value: career,
        onRetry: () => ref.invalidate(careerProvider(uid)),
        builder: (lines) {
          final line = lines.where((l) => l.sportId == sportId).firstOrNull;

          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              ContentBounds(
                maxWidth: 900,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    _Headline(sport: sport, line: line),

                    const SizedBox(height: 24),
                    _SectionTitle(
                      'Statistics',
                      subtitle: 'Lifetime totals in ${sport.name}.',
                    ),
                    _Stats(line: line),

                    const SizedBox(height: 24),
                    const _SectionTitle(
                      'Matches',
                      subtitle: 'Tap any match for its full scorecard.',
                    ),
                    AsyncErrorStrip(value: fixtures, what: 'matches'),
                    _Matches(uid: uid, fixtures: fixtures),

                    const SizedBox(height: 24),
                    const _SectionTitle(
                      'Leaderboard',
                      subtitle: 'Ranking points over the rolling window.',
                    ),
                    AsyncErrorStrip(value: ranking, what: 'the leaderboard'),
                    _Leaderboard(uid: uid, ranking: ranking, isMe: isMe),
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

class _Headline extends StatelessWidget {
  const _Headline({required this.sport, required this.line});

  final SportSpec sport;
  final CareerLine? line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rating = line?.rating;

    return Row(
      children: [
        Text(sport.icon, style: const TextStyle(fontSize: 40)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${line?.matchesPlayed ?? 0} '
                '${(line?.matchesPlayed ?? 0) == 1 ? 'match' : 'matches'}',
                style: theme.textTheme.headlineSmall,
              ),
              if (rating != null)
                Text(
                  rating.isProvisional
                      ? '${rating.tier} · ${rating.displayScore}/100 (still settling)'
                      : '${rating.tier} · ${rating.displayScore}/100',
                  style: theme.textTheme.bodyMedium,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.line});

  final CareerLine? line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tally = line?.stats?.tally ?? const <String, num>{};
    final entries = tally.entries.where((e) => e.value != 0).toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));

    if (entries.isEmpty) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.query_stats_outlined),
          title: Text('No statistics yet'),
          subtitle: Text(
            'Totals appear once a match in this sport has been finished.',
          ),
        ),
      );
    }

    // The full tally, not the profile card's top six: this is the page a
    // person opens when they want the detail.
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in entries)
              Chip(
                visualDensity: VisualDensity.compact,
                side: BorderSide.none,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                label: Text(
                  '${psHumanizeCounter(e.key)} ${_format(e.value)}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _format(num v) =>
      v is int || v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(2);

}

class _Matches extends StatelessWidget {
  const _Matches({required this.uid, required this.fixtures});

  final String uid;
  final AsyncValue<List<Fixture>> fixtures;

  @override
  Widget build(BuildContext context) {
    if (fixtures.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final list = fixtures.valueOrNull ?? const <Fixture>[];
    if (list.isEmpty) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.sports_score_outlined),
          title: Text('No matches recorded'),
          subtitle: Text('Matches in this sport will collect here.'),
        ),
      );
    }

    return Column(
      children: [
        for (final f in list) PlayerMatchTile(fixture: f, uid: uid),
      ],
    );
  }
}

class _Leaderboard extends StatelessWidget {
  const _Leaderboard({
    required this.uid,
    required this.ranking,
    required this.isMe,
  });

  final String uid;
  final AsyncValue<List<RankingRow>> ranking;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (ranking.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final rows = ranking.valueOrNull ?? const <RankingRow>[];
    if (rows.isEmpty) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.leaderboard_outlined),
          title: Text('No ranking yet'),
          subtitle: Text(
            'Ranking points come from tournament results. Once results are '
            'in, the table builds itself.',
          ),
        ),
      );
    }

    // Top ten, plus this player's own row wherever it sits. A leaderboard
    // that cuts off at ten is useless to the player ranked fortieth, who is
    // the person most likely to be reading it.
    final top = rows.take(10).toList();
    final mine = rows.where((r) => r.uid == uid).firstOrNull;
    final showMine = mine != null && !top.contains(mine);

    return Card(
      child: Column(
        children: [
          for (final r in top) _RankRow(row: r, highlight: r.uid == uid),
          if (showMine) ...[
            Divider(height: 1, color: theme.dividerColor),
            _RankRow(row: mine, highlight: true),
          ],
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({required this.row, required this.highlight});

  final RankingRow row;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      leading: SizedBox(
        width: 32,
        child: Text(
          '${row.rank}',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleSmall,
        ),
      ),
      title: Text(
        row.displayName,
        style: highlight
            ? theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)
            : null,
      ),
      subtitle: Text(
        '${row.eventsCounted} '
        '${row.eventsCounted == 1 ? 'result' : 'results'} counted',
      ),
      trailing: Text('${row.points}', style: theme.textTheme.titleMedium),
      tileColor:
          highlight ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35) : null,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
