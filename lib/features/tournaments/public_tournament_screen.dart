import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/fixture.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/schedule/schedule_view_model.dart';
import '../../domain/tournament/tournament_overview.dart';
import '../competitions/widgets/schedule_board.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/offline_fee_notice.dart';
import '../../shared/ps_banner.dart';
import '../competitions/widgets/suspend_sheet.dart';
import 'widgets/leaderboard_cards.dart';
import '../../core/l10n/result_labels.dart';

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
                    // The spectator half of the suspension. Somebody who
                    // blocked out Saturday and followed the public link is
                    // exactly who the reason was written for; without this
                    // they read a schedule that is not going to happen.
                    if (tournament.isSuspended)
                      OnHoldBanner(
                        what: 'season',
                        reason: tournament.suspendReason,
                      ),
                    // This page is the one thing a club sends to people who
                    // do not have PlaySphere — the page that replaces the
                    // Telegram channel — and it opened with an app bar
                    // reading "Tournament" and nothing else. The banner is
                    // the season's own identity on the only surface where a
                    // stranger forms an impression of the product.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                      child: PsBanner(
                        imageUrl: tournament.bannerUrl,
                        // The badge belongs on this page above all others:
                        // it is the one surface a stranger judges the season
                        // on, and a school's crest says whose season it is
                        // faster than the name does.
                        logoUrl: tournament.logoUrl,
                        logoName: tournament.name,
                        seed: tournament.id,
                        fallbackIcon: Icons.emoji_events_outlined,
                        fallbackColor: const Color(0xFF0F766E),
                        height: 168,
                        child: Text(
                          tournament.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.15,
                          ),
                        ),
                      ),
                    ),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
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
                                if (tournament.seasonFeeCoversEverything)
                                  Chip(
                                    label: Text(
                                      '₹${tournament.entryFeeRupees} entry '
                                      '— covers every event',
                                    ),
                                  )
                                else if (tournament.chargesPerEvent)
                                  const Chip(
                                    label: Text('Entry fee varies by sport'),
                                  ),
                              ],
                            ),
                            // The entrant-facing side of the number the
                            // organizer declared at creation. Shown here
                            // rather than only on each event because this is
                            // the page somebody lands on from a poster.
                            //
                            // Under per-sport pricing the season has no one
                            // number to quote, so the chip says where to look
                            // instead of inventing a total.
                            if (tournament.seasonFeeCoversEverything ||
                                tournament.chargesPerEvent) ...[
                              const SizedBox(height: 12),
                              const OfflineFeeNotice.entry(),
                            ],
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

                    // The whole programme, not just what is on court in the
                    // next hour.
                    //
                    // This page is what a club sends to the other clubs, to
                    // parents and to a school noticeboard, and until now the
                    // only thing it said about the timetable was "on court
                    // now" and "up next" — three matches out of ninety. A
                    // visiting coach opening the link the morning after the
                    // schedule was published could not find out when their
                    // own team played, which is the single question the link
                    // is opened to answer. It is bucketed by DAY rather than
                    // by group, because a season is several draws at once and
                    // the reader is planning a Saturday, not reading one
                    // group's table.
                    _PublicSchedule(
                      orgId: orgId,
                      tournamentId: tournamentId,
                      tournamentName: tournament.name,
                    ),

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
                ? Text(
                    localizedSummary(context, f.summary),
                    style: theme.textTheme.labelSmall,
                  )
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


/// The season's full timetable on the public link.
///
/// Signed-out by design, like the rest of this page — but a signed-in reader
/// gets their own club's matches washed green and filterable, which is the
/// difference between a document and a schedule.
class _PublicSchedule extends ConsumerWidget {
  const _PublicSchedule({
    required this.orgId,
    required this.tournamentId,
    required this.tournamentName,
  });

  final String orgId;
  final String tournamentId;
  final String tournamentName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (orgId: orgId, tournamentId: tournamentId);
    final fixtures =
        ref.watch(tournamentFixturesProvider(key)).valueOrNull ?? const [];

    // Placeholder draws are already hidden from everyone but an organizer by
    // `firestore.rules`; filtering again costs nothing and means an organizer
    // reading their own public link sees what the public sees.
    final published = fixtures.where((f) => !f.isDraft).toList();
    if (published.isEmpty) return const SizedBox.shrink();

    final events =
        ref.watch(tournamentEventsProvider(key)).valueOrNull ?? const [];
    final eventNames = {for (final e in events) e.id: e.name};

    final mine = MyEntrants.resolve(
      entrants: ref.watch(tournamentEntrantsProvider(key)),
      uid: ref.watch(currentUidProvider),
      myOrgIds: {
        for (final m in ref.watch(myMembershipsProvider).valueOrNull ?? const [])
          m.orgId,
      },
      myTeamIds: {
        for (final t in ref.watch(myTeamsProvider).valueOrNull ?? const []) t.id,
      },
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ScheduleBoard(
        fixtures: published,
        mineEntrantIds: mine,
        title: 'Full schedule',
        byDay: true,
        pdfTitle: tournamentName,
        pdfSubtitle: events.isEmpty
            ? 'Full schedule'
            : '${events.length} events · full schedule',
        // The event's name, because one season's "Group A" belongs to four
        // different sports.
        sectionOf: (f) => eventNames[f.compId] ?? 'Matches',
        onTapFixture: (f) =>
            context.push(Routes.watch(f.orgId, f.compId, f.id)),
      ),
    );
  }
}
