import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/enums.dart';
import '../../core/models/fixture.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui_kit.dart';
import 'widgets/share_match_button.dart';

/// What a match becomes the moment it ends.
///
/// The reference flow draws three screens here — End Match & Result, Match
/// Summary, and Finalized & Stats Updated — which are one screen at three
/// points in time. Splitting them into three routes would mean two of them
/// were unreachable a second after they appeared, and a person who opened
/// the match an hour later would have no way back to the summary they were
/// shown. So this is one screen that reports where the result has actually
/// got to.
///
/// ## The checklist tells the truth
///
/// The reference shows five green ticks. Five green ticks that are painted on
/// unconditionally are worse than no checklist: statistics settle
/// asynchronously in `functions/index.js`, and a screen that claims they are
/// done the instant the scorer presses end would be lying about the one thing
/// this screen exists to confirm. Every row below is derived from something
/// real — see each row's comment for what.
class MatchResultScreen extends ConsumerWidget {
  const MatchResultScreen({
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
    final canManage = ref
        .watch(myCapabilitiesProvider(orgId))
        .contains(Capability.manageCompetitions);

    return AppScaffold(
      orgId: orgId,
      title: 'Result',
      body: AsyncView(
        value: fixtureAsync,
        builder: (fixture) {
          if (fixture == null) {
            return const EmptyState(
              icon: Icons.search_off,
              title: 'This match is not available',
              message: 'It may have been removed, or belong to a private club.',
            );
          }
          if (!fixture.status.isResulted) {
            // Reachable by a stale link or a back-press after a result was
            // reopened for correction. Saying so beats an empty trophy.
            return EmptyState(
              icon: Icons.hourglass_empty,
              title: 'This match has no result yet',
              message: 'It is ${fixture.status.label.toLowerCase()}. The '
                  'result appears here once the match is finished.',
              action: FilledButton(
                onPressed: () =>
                    context.push(Routes.matchCenter(orgId, compId, fixtureId)),
                child: const Text('Open Match Center'),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _ResultHero(fixture: fixture),
              const SizedBox(height: 12),
              _ScoreComparison(fixture: fixture),
              if (fixture.mvp != null) ...[
                const SizedBox(height: 12),
                _PlayerOfTheMatch(fixture: fixture),
              ],
              const SizedBox(height: 12),
              _ProjectionChecklist(fixture: fixture),
              const SizedBox(height: 20),
              _ResultActions(fixture: fixture, canManage: canManage),
            ],
          );
        },
      ),
    );
  }
}

/// The trophy and who won.
class _ResultHero extends StatelessWidget {
  const _ResultHero({required this.fixture});

  final Fixture fixture;

  @override
  Widget build(BuildContext context) {
    final plugin = ScoringRegistry.resolve(fixture.scoringPluginKey);
    final summary = plugin.summary(
      fixture.scoreState,
      fixture.scoringContext(),
    );

    final winnerName = switch (fixture.winnerEntrantId) {
      final id? when id == fixture.entrantAId => fixture.entrantAName,
      final id? when id == fixture.entrantBId => fixture.entrantBName,
      _ => null,
    };

    return PsCard(
      child: Column(
        children: [
          const SizedBox(height: 4),
          Icon(
            fixture.isDraw ? Icons.handshake_outlined : Icons.emoji_events,
            size: 44,
            // Amber for a trophy, not the brand green: a winner's medal is
            // one of the few places a product's own colour is the wrong one.
            color: fixture.isDraw
                ? Ps.muted
                : const Color(0xFFF59E0B),
          ),
          const SizedBox(height: 12),
          Text(
            fixture.isDraw ? 'Match drawn' : (winnerName ?? 'Match finished'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Ps.ink,
            ),
          ),
          if (summary.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              summary,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13.5, color: Ps.muted),
            ),
          ],
          // How it ended, when that is not the ordinary way. A walkover or an
          // abandoned match reads as a normal result otherwise, which is the
          // sort of thing people dispute weeks later.
          if (fixture.resultType != MatchResultType.normal) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Ps.canvas,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Ps.border),
              ),
              child: Text(
                fixture.resultType.label,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Ps.muted,
                ),
              ),
            ),
          ],
          if (fixture.resultNote case final note? when note.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                note,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, color: Ps.muted),
              ),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

/// Both sides' final figures, side by side.
class _ScoreComparison extends StatelessWidget {
  const _ScoreComparison({required this.fixture});

  final Fixture fixture;

  @override
  Widget build(BuildContext context) {
    final won = fixture.winnerEntrantId;
    return PsCard(
      child: Row(
        children: [
          Expanded(
            child: _SideColumn(
              name: fixture.entrantAName,
              isWinner: won == fixture.entrantAId,
            ),
          ),
          const SizedBox(
            height: 40,
            child: VerticalDivider(width: 1, color: Ps.border, thickness: 1),
          ),
          Expanded(
            child: _SideColumn(
              name: fixture.entrantBName,
              isWinner: won == fixture.entrantBId,
            ),
          ),
        ],
      ),
    );
  }
}

class _SideColumn extends StatelessWidget {
  const _SideColumn({required this.name, required this.isWinner});

  final String name;
  final bool isWinner;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isWinner ? FontWeight.w800 : FontWeight.w500,
            color: Ps.ink,
          ),
        ),
        if (isWinner) ...[
          const SizedBox(height: 4),
          const Text(
            'WON',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: Ps.primary,
            ),
          ),
        ],
      ],
    );
  }
}

class _PlayerOfTheMatch extends StatelessWidget {
  const _PlayerOfTheMatch({required this.fixture});

  final Fixture fixture;

  @override
  Widget build(BuildContext context) {
    final award = fixture.mvp!;
    return PsCard(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.star,
              size: 20,
              color: Color(0xFFF59E0B),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Player of the Match',
                  style: TextStyle(fontSize: 11.5, color: Ps.muted),
                ),
                const SizedBox(height: 2),
                Text(
                  award.name,
                  style: const TextStyle(
                    fontSize: 15,
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

/// What has actually happened to this result, and what has not yet.
class _ProjectionChecklist extends StatelessWidget {
  const _ProjectionChecklist({required this.fixture});

  final Fixture fixture;

  @override
  Widget build(BuildContext context) {
    final rows = <_CheckRow>[
      // The scorecard is the fixture document itself, and it is saved by
      // definition once the match is resulted — this row is always done, and
      // is here because its absence would be the alarming thing.
      const _CheckRow(
        label: 'Scorecard saved',
        state: _CheckState.done,
        detail: 'The full ball-by-ball record is stored and cannot be edited.',
      ),

      // The verification gate — §23. Three genuinely different outcomes, and
      // "no approval required" is not a failure.
      switch (fixture.resultState) {
        MatchResultState.awaitingApproval => const _CheckRow(
            label: 'Result verified',
            state: _CheckState.pending,
            detail: 'Waiting for an official to confirm the result.',
          ),
        MatchResultState.finalized => const _CheckRow(
            label: 'Result verified',
            state: _CheckState.done,
            detail: 'Confirmed by an official.',
          ),
        MatchResultState.none => const _CheckRow(
            label: 'Result verified',
            state: _CheckState.notRequired,
            detail: 'This competition does not require approval.',
          ),
      },

      // The only asynchronous one, and the reason this checklist is not five
      // static ticks. `ratingSettledAt` is stamped by the finalize trigger in
      // the same batch as the ratings themselves.
      if (fixture.ratingSettledAt != null)
        const _CheckRow(
          label: 'Player stats updated',
          state: _CheckState.done,
          detail: 'Career records and ratings have been updated.',
        )
      else
        const _CheckRow(
          label: 'Player stats updated',
          state: _CheckState.pending,
          detail: 'Usually within a few seconds of the match finishing.',
        ),

      // Standings are computed from fixtures whenever a table is opened
      // rather than stored, so there is no job to wait on — the result
      // counting IS the update.
      const _CheckRow(
        label: 'Standings include this match',
        state: _CheckState.done,
        detail: 'Points tables are calculated from results as they are read.',
      ),

      // Ranking points are awarded per TOURNAMENT, not per match — see
      // `onTournamentCompleted`. Claiming a leaderboard update here would be
      // the one outright false row on the screen.
      if (fixture.tournamentId != null)
        const _CheckRow(
          label: 'Ranking points',
          state: _CheckState.pending,
          detail: 'Awarded when the whole tournament is closed.',
        ),
    ];

    return PsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'What happens to this result',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Ps.ink,
            ),
          ),
          const SizedBox(height: 12),
          for (final row in rows) row,
        ],
      ),
    );
  }
}

enum _CheckState { done, pending, notRequired }

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.label,
    required this.state,
    required this.detail,
  });

  final String label;
  final _CheckState state;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (state) {
      _CheckState.done => (Icons.check_circle, Ps.primary),
      _CheckState.pending => (Icons.schedule, const Color(0xFFF59E0B)),
      _CheckState.notRequired => (Icons.remove_circle_outline, Ps.faint),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Ps.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Ps.muted,
                    height: 1.35,
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

class _ResultActions extends ConsumerWidget {
  const _ResultActions({required this.fixture, required this.canManage});

  final Fixture fixture;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The verification action itself, shown only to somebody who can
        // actually perform it and only while it is outstanding. This is where
        // the tournament wizard's "Results Approval" toggle finally reaches a
        // user.
        if (canManage &&
            fixture.resultState == MatchResultState.awaitingApproval) ...[
          PsPrimaryButton(
            label: 'Verify and finalize result',
            onPressed: () => _finalize(context, ref),
          ),
          const SizedBox(height: 10),
        ],
        PsSecondaryButton(
          label: 'View full scorecard',
          icon: Icons.receipt_long_outlined,
          onPressed: () => context.push(
            Routes.watch(fixture.orgId, fixture.compId, fixture.id),
          ),
        ),
        const SizedBox(height: 10),
        Center(child: ShareMatchButton(fixture: fixture)),
      ],
    );
  }

  Future<void> _finalize(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(umpireRepositoryProvider).finalizeResult(
            orgId: fixture.orgId,
            compId: fixture.compId,
            fixtureId: fixture.id,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Result finalized.')),
        );
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}
