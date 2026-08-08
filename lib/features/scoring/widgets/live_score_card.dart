import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/enums.dart';
import '../../../core/models/fixture.dart';
import '../../../core/router/app_router.dart';
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

    // Not `fixture.isLive`. A fixture stays in the `live` status from its
    // first ball until the plugin declares a result, so every match a scorer
    // abandoned still claims to be live — days later, in one reported case.
    // The badge only means something if it tracks the scoreboard, not the
    // status field.
    final now = DateTime.now();
    final isLive = fixture.isLiveAt(now);
    final isStale = fixture.isStaleLiveAt(now);

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
                  if (isLive) ...[
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
                  ] else if (isStale) ...[
                    // Deliberately grey and deliberately not "LIVE". The
                    // scoreboard is real and worth showing; the claim that it
                    // is happening right now is not.
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'PAUSED',
                        style: TextStyle(
                          color: theme.hintColor,
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
                  if (_whereAndWhen(fixture) != null)
                    Text(
                      _whereAndWhen(fixture)!,
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
                      // Names the group a slot is waiting on rather than
                      // "To be decided" — a spectator reading a bracket wants
                      // to know it is the Group A winner who lands here.
                      name: fixture.displayNameA(),
                      isWinner: winnerId == fixture.entrantAId,
                      align: TextAlign.start,
                      // Every id here already lives on the fixture, so this
                      // needs nothing from whoever built this card — every
                      // list that already shows a `LiveScoreCard` gets a
                      // tappable name for free. A quick-match/challenge side
                      // has no real `Entrant` behind it; `EntrantDetailScreen`
                      // shows a plain "no profile" state for those rather
                      // than this card needing to know the difference.
                      onTap: () => context.push(
                        Routes.entrant(
                          fixture.orgId,
                          fixture.compId,
                          fixture.entrantAId,
                        ),
                      ),
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
                      name: fixture.displayNameB(),
                      isWinner: winnerId == fixture.entrantBId,
                      align: TextAlign.end,
                      onTap: () => context.push(
                        Routes.entrant(
                          fixture.orgId,
                          fixture.compId,
                          fixture.entrantBId,
                        ),
                      ),
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
                      color: isLive
                          ? theme.colorScheme.primary
                          : theme.hintColor,
                      fontWeight:
                          isLive ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ],
              // The result TYPE, not the status. A retirement and a
              // disqualification are both `completed` fixtures, so a card
              // keyed on status alone showed them as ordinary wins and lost
              // the one fact a reader needs.
              if (fixture.resultType != MatchResultType.normal) ...[
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    fixture.resultType.label,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (fixture.resultNote != null)
                  Center(
                    child: Text(
                      fixture.resultNote!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.hintColor),
                    ),
                  ),
              ] else if (fixture.status == FixtureStatus.abandoned) ...[
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

  /// "Court 3 · 14:30" — where and when, in the corner where the venue used
  /// to sit alone.
  ///
  /// The time matters more than anything else on a tournament day. Before the
  /// draw carried a per-match schedule there was nothing to show here but a
  /// venue name shared by every match in the competition, so a player had no
  /// way to learn when they were on except by waiting at the hall.
  static String? _whereAndWhen(Fixture fixture) {
    final parts = <String>[
      if (fixture.courtId != null) fixture.courtId!
      else if (fixture.venue != null) fixture.venue!,
      if (fixture.scheduledAt != null) _hhmm(fixture.scheduledAt!),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}

class _Side extends StatelessWidget {
  const _Side({
    required this.name,
    required this.isWinner,
    required this.align,
    this.onTap,
  });

  final String name;
  final bool isWinner;
  final TextAlign align;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      name,
      textAlign: align,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: isWinner ? FontWeight.w800 : FontWeight.w500,
          ),
    );
    if (onTap == null) return text;
    // A small InkWell nested inside the card's own — the whole card still
    // opens the match everywhere except the two words naming who is
    // playing, which is a more specific, more useful thing to tap.
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: text,
      ),
    );
  }
}
