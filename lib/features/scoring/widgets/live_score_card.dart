import 'package:flutter/material.dart';

import '../../../core/models/enums.dart';
import '../../../core/models/fixture.dart';
import '../../../domain/scoring/scoring_registry.dart';

/// Compact live scoreboard.
///
/// Reads only the fixture's denormalized projection, never the event log, so
/// a list of twenty live matches costs twenty document reads rather than a
/// query per match. That is what keeps the "everyone can watch" promise
/// affordable.
class LiveScoreCard extends StatelessWidget {
  const LiveScoreCard({
    super.key,
    required this.fixture,
    this.onTap,
    this.dense = false,
  });

  final Fixture fixture;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plugin = ScoringRegistry.resolve(fixture.scoringPluginKey);
    final ctx = fixture.scoringContext();

    final headline = plugin.headline(fixture.scoreState, ctx);
    final status = plugin.statusLine(fixture.scoreState, ctx);
    final winnerId = fixture.winnerEntrantId;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(dense ? 12 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (fixture.isLive) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'LIVE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      fixture.roundLabel ?? 'Match',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: theme.hintColor),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (fixture.venue != null)
                    Text(
                      fixture.venue!,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.hintColor),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: _Side(
                      name: fixture.entrantAName,
                      isWinner: winnerId == fixture.entrantAId,
                      align: TextAlign.start,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      headline,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  Expanded(
                    child: _Side(
                      name: fixture.entrantBName,
                      isWinner: winnerId == fixture.entrantBId,
                      align: TextAlign.end,
                    ),
                  ),
                ],
              ),
              if (status != null) ...[
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    status,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: fixture.isLive
                          ? theme.colorScheme.primary
                          : theme.hintColor,
                      fontWeight:
                          fixture.isLive ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ],
              if (fixture.status == FixtureStatus.walkover ||
                  fixture.status == FixtureStatus.abandoned) ...[
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    fixture.status.label,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({
    required this.name,
    required this.isWinner,
    required this.align,
  });

  final String name;
  final bool isWinner;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    return Text(
      name,
      textAlign: align,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: isWinner ? FontWeight.w800 : FontWeight.w500,
          ),
    );
  }
}
