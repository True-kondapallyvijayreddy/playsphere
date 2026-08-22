import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/enums.dart';
import '../../core/models/fixture.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/section_header.dart';
import '../../core/l10n/result_labels.dart';

/// Every match a player has appeared in, across every club and every sport.
///
/// Exists because the home screen's "Matches" counter had nowhere to go. It
/// and the "Sports" counter both pushed `/me`, so two tiles with different
/// numbers and different labels landed on the same profile page and neither
/// answered the question it had just asked (Bug #2).
///
/// Reads one collection-group query — the same one head-to-head has always
/// used — and groups it in memory. A career is capped at a few hundred
/// matches by [CareerRepository.watchPlayerFixtures], which is well inside
/// what a phone can sort and what a free tier can serve.
class MyMatchesScreen extends ConsumerStatefulWidget {
  const MyMatchesScreen({super.key, required this.uid});

  final String uid;

  @override
  ConsumerState<MyMatchesScreen> createState() => _MyMatchesScreenState();
}

/// Which slice of a career the list is showing.
enum _Filter {
  all('All'),
  live('Live'),
  completed('Results'),
  upcoming('Upcoming');

  const _Filter(this.label);
  final String label;

  bool matches(Fixture f, DateTime now) => switch (this) {
        _Filter.all => true,
        // Activity-aware, per Bug #1: a match nobody has scored in days is
        // not live however its status field reads.
        _Filter.live => f.isLiveAt(now),
        _Filter.completed => f.status.isResulted,
        _Filter.upcoming =>
          f.status == FixtureStatus.scheduled || f.isStaleLiveAt(now),
      };
}

class _MyMatchesScreenState extends ConsumerState<MyMatchesScreen> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final fixtures = ref.watch(playerFixturesProvider(widget.uid));
    final isMe = ref.watch(currentUidProvider) == widget.uid;

    return Scaffold(
      appBar: AppBar(title: Text(isMe ? 'My matches' : 'Matches')),
      body: AsyncView(
        value: fixtures,
        onRetry: () => ref.invalidate(playerFixturesProvider(widget.uid)),
        builder: (all) {
          if (all.isEmpty) {
            return EmptyState(
              icon: Icons.sports_score_outlined,
              title: isMe ? 'No matches yet' : 'No matches yet',
              message: isMe
                  ? 'Play a match and it lands here automatically — every '
                      'club, every sport, for good.'
                  : 'This player has not appeared in a match yet.',
            );
          }

          final now = DateTime.now();
          final shown = [
            for (final f in all)
              if (_filter.matches(f, now)) f,
          ];

          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              ContentBounds(
                maxWidth: 900,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    // Counts on the chips themselves: a filter that leads to
                    // an empty list is a dead end, and the number tells you
                    // before you tap.
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final f in _Filter.values)
                          FilterChip(
                            label: Text(
                              '${f.label} '
                              '(${all.where((x) => f.matches(x, now)).length})',
                            ),
                            selected: _filter == f,
                            onSelected: (_) => setState(() => _filter = f),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: EmptyState(
                          icon: Icons.filter_alt_off_outlined,
                          title: 'Nothing under ${_filter.label}',
                          message: 'Try another filter.',
                        ),
                      )
                    else
                      for (final f in shown)
                        PlayerMatchTile(fixture: f, uid: widget.uid),
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

/// One match on a player's list, told from that player's side.
///
/// Shared with the per-sport page so a match reads identically wherever it
/// appears. Tapping opens the scorecard — the whole point of the list is that
/// a result is a doorway to the full card, per Bug #15.
class PlayerMatchTile extends StatelessWidget {
  const PlayerMatchTile({
    super.key,
    required this.fixture,
    required this.uid,
  });

  final Fixture fixture;
  final String uid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final isLive = fixture.isLiveAt(now);
    final sport = SportCatalog.byId(fixture.sport.split(':').first);

    final when = fixture.completedAt ?? fixture.startedAt ?? fixture.scheduledAt;
    final outcome = fixture.outcomeForUid(uid);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Text(sport.icon, style: const TextStyle(fontSize: 24)),
        title: Text(
          '${fixture.displayNameA()} v ${fixture.displayNameB()}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Where the match came from — `docs/Heart_of_the_playsphere.md`
            // §20. Without it a career reads as an undifferentiated list, and
            // "51 not out in a tournament final" looks the same as one in a
            // friendly. `resolvedSource` rather than `sourceType` so matches
            // played before the field existed still say something true.
            Text(
              [
                fixture.resolvedSource.label,
                if (fixture.roundLabel != null) fixture.roundLabel!,
              ].join(' · '),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              [
                if (when != null) friendlyDate(when),
                if (fixture.summary.isNotEmpty)
                  localizedSummary(context, fixture.summary),
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        isThreeLine: true,
        trailing: isLive
            ? const _LiveChip()
            : (fixture.status.isResulted
                // Won/Lost/Drawn from THIS player's side, which is the only
                // reading that means anything on a personal match list — the
                // fixture knows which entrant won, not which one was theirs.
                // Falls back to a chevron when the person is not on either
                // team sheet, which happens for a quick match scored without
                // line-ups.
                ? (outcome == null
                    ? Icon(Icons.chevron_right, color: theme.hintColor)
                    : _OutcomeChip(outcome: outcome))
                // Bug #1 / #15: a stale-live match still carries
                // status == FixtureStatus.live, so its label would read
                // "Live". Say "Paused" instead — the scorer stopped.
                : Text(
                    fixture.isStaleLiveAt(now) ? 'Paused' : fixture.status.label,
                    style: theme.textTheme.labelSmall,
                  )),
        onTap: () => context.push(
          // A live match opens the spectator view; a finished one opens the
          // same route, which renders the completed scorecard.
          Routes.watch(fixture.orgId, fixture.compId, fixture.id),
        ),
      ),
    );
  }
}

/// Won / Lost / Drawn, from the viewing player's side.
class _OutcomeChip extends StatelessWidget {
  const _OutcomeChip({required this.outcome});

  final PlayerResult outcome;

  @override
  Widget build(BuildContext context) {
    // Green for a win and grey for everything else. A loss is deliberately
    // not red: this is somebody's own career list, they already know how it
    // went, and colouring half a season in alarm red is a way to make a
    // record people avoid looking at.
    final (fg, bg) = switch (outcome) {
      PlayerResult.won => (
          const Color(0xFF16A34A),
          const Color(0xFF16A34A).withValues(alpha: 0.12),
        ),
      _ => (const Color(0xFF64748B), const Color(0xFFF1F5F9)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        outcome.label.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: fg,
        ),
      ),
    );
  }
}

class _LiveChip extends StatelessWidget {
  const _LiveChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
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
    );
  }
}
