import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/competition.dart';
import '../../core/models/enums.dart';
import '../../core/models/fixture.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/tournament/season_entrant.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/live_dot.dart';
import '../../shared/ui_kit.dart';

/// One team or player, in one season.
///
/// ## What this page is for
///
/// Tapping a name on a season's leaderboard asks "how is this team doing in
/// this season", and until now there was nowhere for that tap to go that
/// answered it. A career page spans every club and year and buries the season
/// inside it; the per-event entrant page is scoped to one draw, so a team in
/// three events of a season was three unrelated pages.
///
/// So this is deliberately season-shaped, and what it keeps is what somebody
/// following one team actually asks between matches:
///
/// - **When do they play next**, and where. The single most-asked question at
///   a tournament, and the reason this page is opened from a car park.
/// - **How they have done here** — played, won, lost, and the titles, scoped
///   to this season and nothing else.
/// - **Each event they entered, and how far they got**: champion, runner-up,
///   their position in their own group, or how many they have left.
/// - **Every match, with the score.** Finished ones newest first, because the
///   one that just ended is the one being discussed.
///
/// What it deliberately leaves out is anything from another season. A team's
/// record last year is a different question, and mixing the two produces a
/// page that answers neither.
class SeasonEntrantScreen extends ConsumerWidget {
  const SeasonEntrantScreen({
    super.key,
    required this.orgId,
    required this.tournamentId,
    required this.entrantId,
  });

  final String orgId;
  final String tournamentId;
  final String entrantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (orgId: orgId, tournamentId: tournamentId);
    final eventsAsync = ref.watch(tournamentEventsProvider(key));
    final fixturesAsync = ref.watch(tournamentFixturesProvider(key));
    final tournament = ref.watch(tournamentProvider(key)).valueOrNull;

    final events = eventsAsync.valueOrNull ?? const <Competition>[];
    final fixtures = fixturesAsync.valueOrNull ?? const <Fixture>[];

    final record = SeasonEntrantRecord.from(
      entrantId: entrantId,
      events: events,
      fixtures: fixtures,
    );

    return AppScaffold(
      orgId: orgId,
      title: record.displayName,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ContentBounds(
            maxWidth: 820,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AsyncErrorStrip(value: eventsAsync, what: 'the events'),
                AsyncErrorStrip(value: fixturesAsync, what: 'the matches'),
                if (record.isEmpty)
                  EmptyState(
                    icon: fixturesAsync.isLoading
                        ? Icons.hourglass_empty
                        : Icons.person_search_outlined,
                    title: fixturesAsync.isLoading
                        ? 'Loading'
                        : 'Nothing for them in this season',
                    message: fixturesAsync.isLoading
                        ? null
                        : 'They have no matches in '
                            '${tournament?.name ?? 'this season'} — either '
                            'the draw has not been made, or this name belongs '
                            'to another season.',
                  )
                else ...[
                  const SizedBox(height: 12),
                  _Summary(record: record, seasonName: tournament?.name),
                  if (record.nextMatch != null)
                    _NextMatch(
                      orgId: orgId,
                      fixture: record.nextMatch!,
                      eventName:
                          record.eventNames[record.nextMatch!.compId] ?? '',
                    ),
                  _Runs(record: record),
                  _Matches(orgId: orgId, record: record),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.record, required this.seasonName});

  final SeasonEntrantRecord record;
  final String? seasonName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = record;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              r.displayName,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: Ps.ink,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 2),
            PsMetaRow(
              items: [
                if (seasonName != null) seasonName,
                '${r.runs.length} ${r.runs.length == 1 ? 'event' : 'events'}',
                if (r.titles > 0)
                  '${r.titles} ${r.titles == 1 ? 'title' : 'titles'}',
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _Figure(label: 'Played', value: '${r.matchesPlayed}'),
                _Figure(label: 'Won', value: '${r.won}'),
                _Figure(label: 'Lost', value: '${r.lost}'),
                if (r.drawn > 0) _Figure(label: 'Drawn', value: '${r.drawn}'),
                _Figure(
                  label: 'Win %',
                  // Blank rather than 100% off one match — the same bar the
                  // leaderboard sets, so the two pages never disagree.
                  value: r.winRate == null
                      ? '—'
                      : '${(r.winRate! * 100).round()}%',
                ),
              ],
            ),
            if (r.upcoming.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                '${r.upcoming.length} still to play in this season',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// The next match, given its own card.
///
/// It is the question this page is opened with often enough that burying it
/// eight rows down a match list would be the whole page's failure.
class _NextMatch extends StatelessWidget {
  const _NextMatch({
    required this.orgId,
    required this.fixture,
    required this.eventName,
  });

  final String orgId;
  final Fixture fixture;
  final String eventName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = fixture;
    final at = f.scheduledAt;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PsCard(
        onTap: () => context.push(Routes.matchCenter(orgId, f.compId, f.id)),
        color: theme.colorScheme.primaryContainer,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (f.status == FixtureStatus.live) ...[
                  const LiveDot(),
                  const SizedBox(width: 8),
                ],
                Text(
                  f.status == FixtureStatus.live ? 'On court now' : 'Next up',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${f.entrantAName} vs ${f.entrantBName}',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            Text(
              [
                if (eventName.isNotEmpty) eventName,
                if (f.roundLabel != null) f.roundLabel!,
                if (at != null) DateFormat('EEE d MMM, HH:mm').format(at)
                else 'Time to be confirmed',
                if (f.courtId != null) f.courtId! else if (f.venue != null) f.venue!,
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row per event entered, with how far they got in it.
class _Runs extends StatelessWidget {
  const _Runs({required this.record});

  final SeasonEntrantRecord record;

  @override
  Widget build(BuildContext context) {
    if (record.runs.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Events entered', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final run in record.runs)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        run.isChampion
                            ? Icons.emoji_events
                            : run.isLive
                                ? Icons.schedule_outlined
                                : Icons.check_circle_outline,
                        size: 18,
                        color: run.isChampion
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(run.eventName,
                                style: theme.textTheme.bodyMedium),
                            Text(
                              '${run.sportName} · ${run.outcome}'
                              '${run.groupPoints == null ? '' : ' · ${run.groupPoints} pts'}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${run.won}–${run.lost}',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Every match of theirs in this season, with the score.
class _Matches extends StatelessWidget {
  const _Matches({required this.orgId, required this.record});

  final String orgId;
  final SeasonEntrantRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = record;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Matches', style: theme.textTheme.titleMedium),
            // Fixtures beyond the next one still matter — a captain plans a
            // week from them — so they are listed rather than collapsed into
            // the card above.
            if (r.upcoming.length > 1) ...[
              const SizedBox(height: 8),
              Text('To play', style: theme.textTheme.labelMedium),
              for (final f in r.upcoming.skip(1))
                _MatchRow(
                  orgId: orgId,
                  fixture: f,
                  entrantId: r.entrantId,
                  eventName: r.eventNames[f.compId] ?? '',
                ),
            ],
            if (r.played.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Played', style: theme.textTheme.labelMedium),
              for (final f in r.played)
                _MatchRow(
                  orgId: orgId,
                  fixture: f,
                  entrantId: r.entrantId,
                  eventName: r.eventNames[f.compId] ?? '',
                ),
            ],
            if (r.played.isEmpty && r.upcoming.length <= 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Nothing played yet.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({
    required this.orgId,
    required this.fixture,
    required this.entrantId,
    required this.eventName,
  });

  final String orgId;
  final Fixture fixture;
  final String entrantId;
  final String eventName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = fixture;
    final isA = f.entrantAId == entrantId;
    final opponent = isA ? f.entrantBName : f.entrantAName;
    final at = f.scheduledAt;

    // Won / lost from THEIR side. A season page that reports the match's
    // winner rather than this team's result makes the reader do the swap on
    // every row.
    final (verdict, colour) = switch (f) {
      _ when !f.status.isResulted => ('', theme.colorScheme.onSurfaceVariant),
      _ when f.isDraw => ('Drew', theme.colorScheme.onSurfaceVariant),
      _ when f.winnerEntrantId == entrantId =>
        ('Won', theme.colorScheme.primary),
      _ when f.winnerEntrantId != null => ('Lost', theme.colorScheme.error),
      _ => ('', theme.colorScheme.onSurfaceVariant),
    };

    return InkWell(
      onTap: () => context.push(Routes.matchCenter(orgId, f.compId, f.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (f.status == FixtureStatus.live) ...[
                        const LiveDot(),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          'v $opponent',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    [
                      if (eventName.isNotEmpty) eventName,
                      if (f.roundLabel != null) f.roundLabel!,
                      if (at != null) DateFormat('d MMM').format(at),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (verdict.isNotEmpty)
                  Text(
                    verdict,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: colour, fontWeight: FontWeight.w700),
                  ),
                if (f.summary.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(
                      f.summary,
                      textAlign: TextAlign.end,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
