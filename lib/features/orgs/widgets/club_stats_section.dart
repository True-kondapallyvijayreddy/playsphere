import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/competition.dart';
import '../../../core/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../domain/career/club_honours.dart';
import '../../../domain/career/club_record.dart';
import '../../../shared/app_scaffold.dart';
import '../../../shared/ui_kit.dart';
import 'club_honours_card.dart';
import 'club_record_widgets.dart';
import 'club_sport_breakdown.dart';

/// The club's record, on its own page, between who it is and what it is
/// running.
///
/// ## Why this belongs above the events list
///
/// A club page had a crest, four counters and a list of events — which
/// answers "what is on next" and nothing else. The question a player deciding
/// whether to join actually asks is "are these people any good, would I get a
/// game, and who would I be playing alongside", and the answer was three taps
/// away behind a "Sports" counter nobody reads as a link to analytics.
///
/// So the club's page now answers it in the shape a player already knows how
/// to read: the same sport tab strip their own profile uses, the same counter
/// tiles under it, and the same drill-down out of each one — plus the two
/// things a club has that a person does not, a trophy cabinet and a
/// top-players board.
///
/// It shows for everybody, not only members. That is the point — it is the
/// half of the page that has to work on a stranger.
class ClubStatsSection extends ConsumerWidget {
  const ClubStatsSection({
    super.key,
    required this.orgId,
    required this.competitions,
  });

  final String orgId;

  /// The club's events, already streamed by the page above. Passed in rather
  /// than watched again so the honours board is built from exactly the list
  /// the events section below is showing.
  final List<Competition> competitions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fixturesAsync = ref.watch(orgFixturesProvider(orgId));
    final fixtures = fixturesAsync.valueOrNull;

    // Nothing at all while the first read is in flight. A skeleton block
    // between the club header and its events would push the events down and
    // then let them jump back, on the one screen a member opens most.
    if (fixtures == null) {
      return AsyncErrorStrip(value: fixturesAsync, what: 'club statistics');
    }

    final record = ClubRecord.forFixtures(fixtures: fixtures, orgId: orgId);
    if (record.isEmpty) return const _NoMatchesYet();

    final honours = ClubHonours.forClub(
      competitions: competitions,
      fixtures: fixtures,
      orgId: orgId,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        ClubHonoursCard(orgId: orgId, honours: honours),
        PsSectionHeader(
          title: 'Club record',
          actionLabel: 'Full stats',
          onAction: () => context.push(Routes.clubStats(orgId)),
        ),
        const SizedBox(height: 8),
        PsCard(
          onTap: () => context.push(Routes.clubStats(orgId)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClubRecordStats.of(record),
              if (record.decided > 0) ...[
                const SizedBox(height: 14),
                ClubFormBar(
                  won: record.won,
                  lost: record.lost,
                  drawn: record.drawn,
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.groups_outlined, size: 15, color: Ps.faint),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${psGrouped(record.playerCount)} '
                      '${record.playerCount == 1 ? 'player has' : 'players have'} '
                      'played for this club across '
                      '${psGrouped(record.sports.length)} '
                      '${record.sports.length == 1 ? 'sport' : 'sports'}.',
                      style: const TextStyle(fontSize: 12, color: Ps.muted),
                    ),
                  ),
                ],
              ),
              ClubRecordNote.of(record),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Sport by sport, behind the strip a player's own profile uses.
        ClubSportBreakdown(
          orgId: orgId,
          record: record,
          honours: honours,
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// What the section says before the club has played anything.
///
/// Kept rather than rendering nothing, because a club with no record is
/// exactly the club whose page needs to say that a record is a thing it will
/// have — and because a page that silently changes shape after the first
/// match reads as a bug to the person who scored it.
class _NoMatchesYet extends StatelessWidget {
  const _NoMatchesYet();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: PsCard(
        child: Row(
          children: [
            Icon(Icons.query_stats_outlined, size: 20, color: Ps.faint),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'No record yet. The first finished match starts this club\'s '
                'statistics — played, won, lost, and who scored them.',
                style: TextStyle(fontSize: 12.5, color: Ps.muted, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
