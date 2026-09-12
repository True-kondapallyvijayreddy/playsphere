import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/career/club_honours.dart';
import '../../domain/career/club_record.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/club_context_banner.dart';
import '../../shared/ui_kit.dart';
import 'widgets/club_honours_card.dart';
import 'widgets/club_record_widgets.dart';

/// A club's whole record: what it has played, how it has done, and one row
/// per sport into the detail — the club-scoped counterpart to
/// [MySportsScreen], reached from the "Full stats" link on the club's own
/// home screen and from the "Sports" counter on its header.
///
/// The summary at the top is the thing this screen gained. It used to open
/// straight onto a list of sports, which answers "what does this club play"
/// but leaves "and are they any good" to be worked out by opening each sport
/// in turn and adding up.
class ClubStatsScreen extends ConsumerWidget {
  const ClubStatsScreen({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final org = ref.watch(organizationProvider(orgId));
    final fixtures = ref.watch(orgFixturesProvider(orgId));
    // Honours need the events as well as the matches: a title is a
    // competition somebody won, and the fixtures alone cannot say which
    // competition finished. Read without blocking — a club's record still
    // renders while its events are in flight.
    final competitions =
        ref.watch(competitionsProvider(orgId)).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: Text(org.valueOrNull?.name ?? 'Club stats'),
      ),
      body: AsyncView(
        value: fixtures,
        onRetry: () => ref.invalidate(orgFixturesProvider(orgId)),
        builder: (allFixtures) {
          final record =
              ClubRecord.forFixtures(fixtures: allFixtures, orgId: orgId);
          final honours = ClubHonours.forClub(
            competitions: competitions,
            fixtures: allFixtures,
            orgId: orgId,
          );
          if (record.isEmpty) {
            return const EmptyState(
              icon: Icons.query_stats_outlined,
              title: 'No matches yet',
              message: 'A finished match credits this club automatically — '
                  'play one and its sport appears here.',
            );
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              ContentBounds(
                maxWidth: 900,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    // The app bar carries the club's name; this carries its
                    // id. A district with two "Sunrise" clubs is exactly
                    // where somebody screenshots the wrong one's numbers.
                    ClubContextBanner(orgId: orgId, label: 'Analytics for'),
                    _OverallCard(record: record, honours: honours),
                    const SizedBox(height: 18),
                    // Every title, not the three the club's home page
                    // previews — this is the page somebody came to in order
                    // to read the whole cabinet.
                    ClubHonoursCard(
                      orgId: orgId,
                      honours: honours,
                      limit: honours.titles.length,
                    ),
                    const Text(
                      'By sport',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Ps.ink,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final sport in record.sports)
                      ClubSportRecordRow(orgId: orgId, record: sport),
                    const SizedBox(height: 8),
                    _MembersLink(orgId: orgId, record: record),
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

/// Everything the club has done, across every sport, in one card.
class _OverallCard extends StatelessWidget {
  const _OverallCard({required this.record, required this.honours});

  final ClubRecord record;
  final ClubHonours honours;

  @override
  Widget build(BuildContext context) {
    return PsCard(
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
          const SizedBox(height: 14),
          PsStatRow(
            stats: [
              PsStat(
                value: psGrouped(record.sports.length),
                label: record.sports.length == 1 ? 'Sport' : 'Sports',
              ),
              PsStat(
                value: psGrouped(record.playerCount),
                label: record.playerCount == 1 ? 'Player' : 'Players',
              ),
              if (honours.titles.isNotEmpty)
                PsStat(
                  value: psGrouped(honours.titles.length),
                  label: honours.titles.length == 1 ? 'Title' : 'Titles',
                ),
              if (record.mvps > 0)
                PsStat(value: psGrouped(record.mvps), label: 'Awards'),
            ],
          ),
          ClubRecordNote.of(record),
        ],
      ),
    );
  }
}

/// The line under the sports list that turns a stat page into a recruiting
/// one.
///
/// A stranger who has read this far has decided they like the look of the
/// club; the next thing they want is its people, and the members screen is
/// where the club's teams and roster live. Without this the page dead-ends
/// on numbers.
class _MembersLink extends StatelessWidget {
  const _MembersLink({required this.orgId, required this.record});

  final String orgId;
  final ClubRecord record;

  @override
  Widget build(BuildContext context) {
    return PsCard(
      onTap: () => context.push(Routes.members(orgId)),
      child: Row(
        children: [
          const Icon(Icons.groups_outlined, size: 20, color: Ps.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${psGrouped(record.playerCount)} '
              '${record.playerCount == 1 ? 'person has' : 'people have'} '
              'played for this club. See the teams and the roster.',
              style: const TextStyle(fontSize: 13, color: Ps.ink, height: 1.4),
            ),
          ),
          const Icon(Icons.chevron_right, size: 20, color: Ps.faint),
        ],
      ),
    );
  }
}
