import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../domain/career/club_honours.dart';
import '../../../shared/ui_kit.dart';

/// The club's trophy cabinet.
///
/// ## Why a title is worth its own block rather than a number in a stat row
///
/// Everything else on a club page is a rate: matches played, win percentage,
/// runs scored. A title is not a rate — it is an event with a name and a
/// date, and "Under-14 Cricket Championship 2026" is the thing a club puts on
/// a banner and a joining player actually reacts to. Flattening it to
/// "Titles: 3" throws away the only part anybody repeats out loud.
///
/// Open titles lead. A trophy won against other clubs and a house
/// championship decided inside the club are both real, but only the first is
/// evidence about the club as a whole — see [ClubTitle.isOpenTitle] — and a
/// board that mixes them is one a rival reads as inflated.
class ClubHonoursCard extends StatelessWidget {
  const ClubHonoursCard({
    super.key,
    required this.orgId,
    required this.honours,
    this.limit = 3,
  });

  final String orgId;
  final ClubHonours honours;

  /// How many titles get a row before the rest go behind the count.
  final int limit;

  @override
  Widget build(BuildContext context) {
    if (honours.isEmpty) return const SizedBox.shrink();

    // Open titles first, then internal ones, each already newest-first.
    final ordered = [...honours.openTitles, ...honours.internalTitles];
    final shown = ordered.take(limit).toList();
    final more = ordered.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PsSectionHeader(
          title: 'Honours',
          actionLabel: 'All stats',
          onAction: () => context.push(Routes.clubStats(orgId)),
        ),
        const SizedBox(height: 8),
        PsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.emoji_events,
                    size: 20,
                    color: Color(0xFFD97706),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _headline(honours),
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: Ps.ink,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              for (final title in shown) _TitleRow(orgId: orgId, title: title),
              if (more > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'and ${psGrouped(more)} more.',
                    style: const TextStyle(fontSize: 12, color: Ps.muted),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  /// The one-line summary above the rows.
  ///
  /// Says which sports as well as how many, because "4 titles across 3
  /// sports" describes a different club from "4 titles in cricket" and the
  /// bare count cannot tell them apart.
  static String _headline(ClubHonours honours) {
    final count = honours.titles.length;
    final sports = honours.sportsWon.length;
    final titles = '${psGrouped(count)} ${count == 1 ? 'title' : 'titles'}';
    if (sports <= 1) return titles;
    return '$titles across ${psGrouped(sports)} sports';
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.orgId, required this.title});

  final String orgId;
  final ClubTitle title;

  @override
  Widget build(BuildContext context) {
    final c = title.competition;
    final year = title.when?.year;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => context.push(Routes.competition(orgId, c.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SportBadge(sportId: c.sportId, size: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Ps.ink,
                    ),
                  ),
                  Text(
                    [
                      // The club's own name is not repeated at it on its own
                      // page; "Won by the club" says the same thing shorter.
                      // Anything else names who lifted it, which on an
                      // internal event is the whole point of the row.
                      if (title.wonByTheClub)
                        'Won by the club'
                      else
                        'Won by ${title.championName}',
                      if (year != null) '$year',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: Ps.muted),
                  ),
                ],
              ),
            ),
            if (title.isOpenTitle)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Ps.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Open',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Ps.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
