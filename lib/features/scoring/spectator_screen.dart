import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/fixture.dart';
import '../../domain/scoring/match_award.dart';
import '../../core/providers.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../profile/widgets/match_memories_section.dart';
import 'widgets/ask_to_score.dart';
import 'widgets/box_score_table.dart';
import 'widgets/share_match_button.dart';

/// The remote viewer's screen — a parent in an office, a class on a laptop.
///
/// Public by design: this route is reachable without signing in, because
/// requiring an account to watch a school match would defeat the entire
/// purpose. It holds one document listener for the score, and a second,
/// capped listener for commentary, so a thousand simultaneous viewers stay
/// affordable.
class SpectatorScreen extends ConsumerWidget {
  const SpectatorScreen({
    super.key,
    required this.orgId,
    required this.compId,
    required this.fixtureId,
  });

  final String orgId;
  final String compId;
  final String fixtureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = FixtureRef(orgId, compId, fixtureId);
    final fixtureAsync = ref.watch(fixtureProvider(key));
    final org = ref.watch(organizationProvider(orgId)).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Live match'),
            if (org != null)
              Text(org.name, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          // Watching is how most people arrive, and passing it on is how the
          // next person arrives.
          if (fixtureAsync.valueOrNull case final f?)
            ShareMatchButton(fixture: f, compact: true),
        ],
      ),
      body: AsyncView(
        value: fixtureAsync,
        builder: (fixture) {
          if (fixture == null) {
            return const EmptyState(
              icon: Icons.search_off,
              title: 'This match is not available',
              message: 'It may have been removed, or belong to a private '
                  'organization.',
            );
          }

          final plugin = ScoringRegistry.resolve(fixture.scoringPluginKey);
          final ctx = fixture.scoringContext();

          final board = _BigScoreboard(
            fixture: fixture,
            headline: plugin.headline(fixture.scoreState, ctx),
            status: plugin.statusLine(fixture.scoreState, ctx),
            summary: plugin.summary(fixture.scoreState, ctx),
          );

          final commentary = _Commentary(fixtureKey: key);
          // This screen is where a club member who taps an unscored match
          // ends up — the match list sends anyone without the pen to the
          // spectator view. So it is the one place the offer to score has to
          // exist, or the person nearest the pitch never sees it. Renders
          // nothing for scorers, spectators from other clubs, and finished
          // matches.
          final askToScore = AskToScoreButton(fixture: fixture);
          final memories = MatchMemoriesSection(fixture: fixture);
          // The scorecard, not just the score. A remote viewer following a
          // school match wants to know who is batting and what they have
          // made — the headline alone is what a scoreboard photo gives you.
          final scorecard = MatchScorecard(fixture: fixture);

          // On a laptop the score sits beside the commentary; on a phone the
          // commentary scrolls beneath it. Same data, same code.
          if (context.windowSize.supportsTwoPane) {
            return ContentBounds(
              maxWidth: 1200,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: ListView(
                      children: [
                        board,
                        const SizedBox(height: 16),
                        askToScore,
                        const SizedBox(height: 24),
                        scorecard,
                        const SizedBox(height: 24),
                        memories,
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(flex: 2, child: commentary),
                ],
              ),
            );
          }

          return ListView(
            children: [
              ContentBounds(
                maxWidth: 700,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    board,
                    const SizedBox(height: 16),
                    askToScore,
                    const SizedBox(height: 20),
                    scorecard,
                    const SizedBox(height: 20),
                    commentary,
                    const SizedBox(height: 28),
                    memories,
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

class _BigScoreboard extends StatelessWidget {
  const _BigScoreboard({
    required this.fixture,
    required this.headline,
    required this.status,
    required this.summary,
  });

  final Fixture fixture;
  final String headline;
  final String? status;
  final String summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final winner = fixture.winnerEntrantId;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        child: Column(
          children: [
            if (fixture.isLive)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'LIVE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              )
            else
              Text(
                fixture.status.label.toUpperCase(),
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.hintColor, letterSpacing: 1),
              ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    fixture.entrantAName,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: winner == fixture.entrantAId
                          ? FontWeight.w800
                          : FontWeight.w500,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    fixture.entrantBName,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: winner == fixture.entrantBId
                          ? FontWeight.w800
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Tabular figures stop the score jittering horizontally every
            // time a digit changes, which is very visible on a projector.
            Text(
              headline,
              style: theme.textTheme.displayLarge?.copyWith(
                fontWeight: FontWeight.w900,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (status != null) ...[
              const SizedBox(height: 10),
              Text(
                status!,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
            if (summary != headline) ...[
              const SizedBox(height: 8),
              Text(
                summary,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
            // The best performer, once there is a result to attach it to.
            // This is the part of a finished match people actually talk about
            // afterwards, and it was the one panel of the flow's completion
            // step with nothing behind it.
            if (fixture.mvp != null && fixture.hasResult) ...[
              const SizedBox(height: 20),
              _MvpBadge(award: fixture.mvp!),
            ],
            if (fixture.venue != null) ...[
              const SizedBox(height: 16),
              Text(
                fixture.venue!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.hintColor),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Commentary extends ConsumerWidget {
  const _Commentary({required this.fixtureKey});
  final FixtureRef fixtureKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(matchEventsProvider(fixtureKey));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Ball by ball',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            events.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (e, _) => Text(
                'Commentary unavailable.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              data: (list) {
                if (list.isEmpty) {
                  return Text(
                    'Nothing has happened yet.',
                    style: Theme.of(context).textTheme.bodySmall,
                  );
                }
                return Column(
                  children: [
                    for (final e in list.take(40))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 14,
                          child: Text(
                            '${e.seq}',
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                        title: Text(_describe(e)),
                        trailing: e.at == null
                            ? null
                            : Text(
                                DateFormat.Hms().format(e.at!),
                                style:
                                    Theme.of(context).textTheme.labelSmall,
                              ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  static String _describe(MatchEvent e) {
    final side = e.payload['side'];
    final sideText = side == 'a' ? 'A' : (side == 'b' ? 'B' : '');
    final runs = e.payload['runs'];
    return switch (e.type) {
      'runs' => '$runs run${runs == 1 ? '' : 's'}',
      'wicket' => 'Wicket!',
      'wide' => 'Wide',
      'no_ball' => 'No ball — free hit',
      'bye' => 'Bye',
      'leg_bye' => 'Leg bye',
      'point' => 'Point to $sideText',
      'score' => 'Score for $sideText',
      'correct' => 'Correction ($sideText)',
      'next_period' => 'Next period',
      'end_innings' => 'End of innings',
      'finish' => 'Match ended',
      'retire' => 'Retired',
      _ => e.type,
    };
  }
}

/// Names the best performer of a finished match.
///
/// Deliberately understated. A grassroots scoreboard is read on a phone in
/// sunlight and projected onto a wall in a college corridor; the award belongs
/// under the score, not competing with it.
class _MvpBadge extends StatelessWidget {
  const _MvpBadge({required this.award});

  final MatchAward award;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.star_rounded,
            size: 18,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Best performer: ${award.name}',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
