import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/fixture.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/tournament/tournament_overview.dart';
import '../../shared/app_scaffold.dart';
import 'widgets/leaderboard_cards.dart';

/// The whole tournament on one public link.
///
/// Spectating is deliberately signed-out, for the same reason the single-match
/// watch page is: a parent at work and a class on a laptop have to be able to
/// follow it, and asking them to make an account defeats the point. This is
/// the page that replaces the Telegram channel — draws, live scores, the
/// order of play, group tables and champions, at one address anybody can open.
class PublicTournamentScreen extends ConsumerWidget {
  const PublicTournamentScreen({
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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tournament'),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Copy link',
            onPressed: () => _copyLink(context),
          ),
        ],
      ),
      body: AsyncView(
        value: tAsync,
        builder: (tournament) {
          if (tournament == null) {
            return const EmptyState(
              icon: Icons.search_off,
              title: 'This tournament is not available',
            );
          }

          final overview =
              ref.watch(tournamentOverviewProvider(key)).valueOrNull;
          final board =
              ref.watch(tournamentLeaderboardProvider(key)).valueOrNull;

          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              ContentBounds(
                maxWidth: 900,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tournament.name,
                              style: theme.textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                Chip(label: Text(tournament.grade.label)),
                                Chip(label: Text(tournament.status.label)),
                                if (overview != null &&
                                    overview.totalMatches > 0)
                                  Chip(
                                    label: Text(
                                      '${overview.playedMatches}/'
                                      '${overview.totalMatches} played',
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (overview != null && overview.onCourtNow.isNotEmpty) ...[
                      Row(
                        children: [
                          Icon(Icons.circle,
                              size: 10, color: theme.colorScheme.error),
                          const SizedBox(width: 8),
                          Text('On court now',
                              style: theme.textTheme.titleMedium),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (final f in overview.onCourtNow)
                        _PublicMatch(fixture: f),
                      const SizedBox(height: 16),
                    ],

                    if (overview != null && overview.upNext.isNotEmpty) ...[
                      Text('Up next', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      for (final f in overview.upNext)
                        _PublicMatch(fixture: f),
                      const SizedBox(height: 16),
                    ],

                    GroupsSummaryCard(leaderboard: board),
                    LeaderboardCard(leaderboard: board),
                    // The public page is the link that gets shared, so the
                    // charts belong here as much as on the organizer's copy —
                    // "who is top of the run chart" is the thing people open a
                    // tournament link to find out.
                    PlayerBoardsCard(
                      bySport: ref
                          .watch(tournamentPlayerBoardsBySportProvider(key))
                          .valueOrNull,
                    ),

                    if (overview != null && overview.champions.isNotEmpty)
                      _PublicChampions(overview: overview),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _copyLink(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final url = Routes.publicTournamentUrl(orgId, tournamentId);
    try {
      await SharePlus.instance.share(
        ShareParams(text: 'Follow the tournament live: $url'),
      );
    } catch (_) {
      // Sharing is unavailable on desktop web; the clipboard always works.
      await Clipboard.setData(ClipboardData(text: url));
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Tournament link copied.')),
        );
    }
  }
}

class _PublicMatch extends StatelessWidget {
  const _PublicMatch({required this.fixture});

  final Fixture fixture;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = fixture;
    final when = f.scheduledAt;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        title: Text(
          '${f.displayNameA()}  v  ${f.displayNameB()}',
          style: theme.textTheme.bodyMedium,
        ),
        subtitle: Text(
          [
            if (f.roundLabel != null) f.roundLabel!,
            if (f.courtId != null) f.courtId! else if (f.venue != null) f.venue!,
            if (when != null)
              '${when.hour.toString().padLeft(2, '0')}:'
                  '${when.minute.toString().padLeft(2, '0')}',
          ].join(' · '),
          style: theme.textTheme.bodySmall,
        ),
        trailing: f.isLiveAt(DateTime.now())
            ? Icon(Icons.circle, size: 10, color: theme.colorScheme.error)
            : (f.summary.isNotEmpty
                ? Text(f.summary, style: theme.textTheme.labelSmall)
                : null),
      ),
    );
  }
}

class _PublicChampions extends StatelessWidget {
  const _PublicChampions({required this.overview});

  final TournamentOverview overview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.emoji_events, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Champions', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            for (final e in overview.champions)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.competition.name,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(
                      e.champion!,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
