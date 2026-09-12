import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/fixture.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/career/club_honours.dart';
import '../../domain/career/club_record.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/section_header.dart' show friendlyDate;
import '../../shared/ui_kit.dart';
import '../../core/l10n/result_labels.dart';
import 'widgets/club_record_widgets.dart';

/// One sport within a club's record — its won/lost, its leading players, its
/// full stat tally and its match list. The club-scoped counterpart to
/// [PlayerSportScreen].
///
/// The won/lost card is new, and [ClubSportRecord] documents at length what it
/// does and does not count: a club's own two sides playing each other is a
/// match played with no club-level result in it, and the note under the card
/// says so rather than quietly folding those into a losing record.
class ClubSportStatsScreen extends ConsumerWidget {
  const ClubSportStatsScreen({
    super.key,
    required this.orgId,
    required this.sportId,
  });

  final String orgId;
  final String sportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final org = ref.watch(organizationProvider(orgId));
    final fixturesAsync =
        ref.watch(orgSportFixturesProvider((orgId: orgId, sportId: sportId)));
    final sport = SportCatalog.byId(sportId);
    // Titles are a property of an event, not of a match, so this page needs
    // the club's events as well. Non-blocking: the record renders while they
    // load, and the honours line simply appears when they arrive.
    final competitions =
        ref.watch(competitionsProvider(orgId)).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: Text('${sport.name} · ${org.valueOrNull?.name ?? 'Club'}'),
      ),
      body: AsyncView(
        value: fixturesAsync,
        onRetry: () => ref.invalidate(orgFixturesProvider(orgId)),
        builder: (fixtures) {
          final record =
              ClubRecord.forFixtures(fixtures: fixtures, orgId: orgId);
          final stats = record.forSport(sportId);
          final titles = ClubHonours.forClub(
            competitions: competitions,
            fixtures: fixtures,
            orgId: orgId,
          ).forSport(sportId);

          if (stats == null || stats.isEmpty) {
            return EmptyState(
              icon: Icons.query_stats_outlined,
              title: 'No ${sport.name} matches yet',
              message: 'A finished match credits this club automatically.',
            );
          }

          final finished = fixtures.where((f) => f.countsTowardsRecords).toList()
            ..sort((a, b) {
              final at = a.completedAt ?? a.startedAt ?? a.scheduledAt;
              final bt = b.completedAt ?? b.startedAt ?? b.scheduledAt;
              if (at == null && bt == null) return 0;
              if (at == null) return 1;
              if (bt == null) return -1;
              return bt.compareTo(at);
            });

          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              ContentBounds(
                maxWidth: 900,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    PsCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ClubRecordStats.ofSport(stats),
                          if (stats.decided > 0) ...[
                            const SizedBox(height: 14),
                            ClubFormBar(
                              won: stats.won,
                              lost: stats.lost,
                              drawn: stats.drawn,
                            ),
                          ],
                          ClubRecordNote.ofSport(stats),
                        ],
                      ),
                    ),
                    if (titles.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _TitlesCard(titles: titles, sportName: sport.name),
                    ],
                    const SizedBox(height: 12),
                    ClubTopPlayers(
                      record: stats,
                      limit: 10,
                      title: 'Top ${sport.name} players',
                    ),
                    const SizedBox(height: 12),
                    ClubMvpBoard(record: stats),
                    const SizedBox(height: 12),
                    _TallyCard(tally: stats.tally),
                    const SizedBox(height: 20),
                    Text(
                      'Matches',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    for (final f in finished)
                      _ClubMatchTile(fixture: f, orgId: orgId),
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

/// What this club has won in this sport.
///
/// A list, not a count. "Under-14 Cricket Championship 2026" is the sentence
/// a club says out loud; "3 titles" is the sentence a database says.
class _TitlesCard extends StatelessWidget {
  const _TitlesCard({required this.titles, required this.sportName});

  final List<ClubTitle> titles;
  final String sportName;

  @override
  Widget build(BuildContext context) {
    return PsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events, size: 17, color: Color(0xFFD97706)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '$sportName titles',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Ps.ink,
                  ),
                ),
              ),
              Text(
                psGrouped(titles.length),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Ps.ink,
                ),
              ),
            ],
          ),
          for (final title in titles)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => context.push(
                  Routes.competition(title.competition.orgId,
                      title.competition.id),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title.competition.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: Ps.ink),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      title.wonByTheClub
                          ? 'The club'
                          : title.championName,
                      style: const TextStyle(fontSize: 11.5, color: Ps.muted),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TallyCard extends StatelessWidget {
  const _TallyCard({required this.tally});

  final Map<String, num> tally;

  @override
  Widget build(BuildContext context) {
    final entries = tally.entries.where((e) => e.value != 0).toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    if (entries.isEmpty) return const SizedBox.shrink();

    return PsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Figures',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Ps.ink),
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
                    psFormatStat(entry.value),
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
}

/// One match on a club's list.
///
/// Told from the club's side where there is one — an accepted challenge names
/// the two clubs as the two entrants, so "Won" and "Lost" are facts about this
/// page's club and worth saying. Told neutrally otherwise, because plenty of
/// these are the club's own teams playing each other and there is no side to
/// take.
class _ClubMatchTile extends StatelessWidget {
  const _ClubMatchTile({required this.fixture, required this.orgId});

  final Fixture fixture;
  final String orgId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sport = SportCatalog.byId(fixture.sport.split(':').first);
    final when = fixture.completedAt ?? fixture.startedAt ?? fixture.scheduledAt;
    final result = _resultFor(fixture, orgId);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Text(sport.icon, style: const TextStyle(fontSize: 24)),
        title: Text(
          '${fixture.displayNameA()} v ${fixture.displayNameB()}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          [
            fixture.resolvedSource.label,
            if (when != null) friendlyDate(when),
            if (fixture.summary.isNotEmpty)
              localizedSummary(context, fixture.summary),
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        trailing: result == null
            ? Icon(Icons.chevron_right, color: theme.hintColor)
            : _ResultPip(result: result),
        onTap: () => context.push(
          Routes.watch(fixture.orgId, fixture.compId, fixture.id),
        ),
      ),
    );
  }

  /// 'W', 'L' or 'D' from this club's point of view, or null when the club is
  /// not one of the two named sides.
  static String? _resultFor(Fixture fixture, String orgId) {
    final side = fixture.entrantAId == orgId
        ? 'a'
        : fixture.entrantBId == orgId
            ? 'b'
            : null;
    if (side == null) return null;
    if (fixture.isDraw) return 'D';
    final winner = fixture.winnerEntrantId;
    if (winner == null) return null;
    final theirs = side == 'a' ? fixture.entrantAId : fixture.entrantBId;
    return winner == theirs ? 'W' : 'L';
  }
}

class _ResultPip extends StatelessWidget {
  const _ResultPip({required this.result});

  final String result;

  @override
  Widget build(BuildContext context) {
    final color = switch (result) {
      'W' => Ps.primary,
      'L' => Ps.live,
      _ => Ps.faint,
    };
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        result,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
