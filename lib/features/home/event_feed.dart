import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/competition.dart';
import '../../core/models/tournament.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/section_header.dart';

/// One row in an events feed — either a standalone [Competition] or every
/// sport of one season, gathered behind [EventFeedSeason].
///
/// A `Competition` never says "I am part of a season" loudly enough to act
/// on — only its `tournamentId` does — so nothing upstream of [groupEventFeed]
/// needs to know seasons exist. Everything downstream just renders one of
/// these two cases.
sealed class EventFeedItem {
  const EventFeedItem();
}

class EventFeedSingle extends EventFeedItem {
  const EventFeedSingle(this.competition);
  final Competition competition;
}

class EventFeedSeason extends EventFeedItem {
  const EventFeedSeason({
    required this.orgId,
    required this.tournamentId,
    required this.competitions,
  });

  final String orgId;
  final String tournamentId;
  final List<Competition> competitions;
}

/// Folds a flat competition list into a feed where every season's sports sit
/// behind one [EventFeedSeason] instead of one card each.
///
/// ## Why this has to exist
///
/// Creating a season (Feature #8) fans it out into one [Competition] per
/// sport, each carrying the season's `tournamentId`. Before this, every list
/// that showed "events" — the home dashboard, "Events & tournaments" — showed
/// those exactly as they are stored: five separate cards for a five-sport
/// season, each opening its own bracket with no way back to the season, the
/// shared schedule, or the season-wide leaderboard around it. A club running
/// a sports week saw its one event balloon into five unrelated-looking rows.
///
/// Grouping happens here, once, rather than in every screen that lists
/// events — the alternative is each screen quietly disagreeing about what a
/// "season" card looks like.
///
/// A season keeps the list position of its first (most recent, since callers
/// pass an already-sorted list) sport, so a season some of whose sports are
/// old and some new does not jump to the bottom of a "what's new" feed.
List<EventFeedItem> groupEventFeed(List<Competition> events) {
  final items = <EventFeedItem>[];
  final seasonAt = <String, int>{};

  for (final c in events) {
    final tournamentId = c.tournamentId;
    if (tournamentId == null) {
      items.add(EventFeedSingle(c));
      continue;
    }
    final key = '${c.orgId}/$tournamentId';
    final at = seasonAt[key];
    if (at == null) {
      seasonAt[key] = items.length;
      items.add(EventFeedSeason(
        orgId: c.orgId,
        tournamentId: tournamentId,
        competitions: [c],
      ));
    } else {
      final existing = items[at] as EventFeedSeason;
      items[at] = EventFeedSeason(
        orgId: existing.orgId,
        tournamentId: existing.tournamentId,
        competitions: [...existing.competitions, c],
      );
    }
  }
  return items;
}

/// A season's card in an events feed: every sport it holds, one entry count,
/// one tap into the season view that already carries its schedule, its
/// leaderboard, its live matches and every sport's bracket together.
///
/// Public for the same reason [EventCard] is — [groupEventFeed] and this card
/// are meant to be reused verbatim by every screen that lists events, so the
/// home dashboard and the full cross-club list never disagree about what a
/// season looks like.
class SeasonCard extends ConsumerWidget {
  const SeasonCard({
    super.key,
    required this.orgId,
    required this.tournamentId,
    required this.competitions,
    this.showOrg = true,
  });

  final String orgId;
  final String tournamentId;
  final List<Competition> competitions;

  /// Whether the club's own name belongs in the subtitle. On a cross-club
  /// list it is the thing that tells two "Sports Week 2026" cards apart; on
  /// a club's own page every card is already that club's, so repeating its
  /// name on each row would say nothing a member does not already know.
  final bool showOrg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tournament = ref
        .watch(tournamentProvider((orgId: orgId, tournamentId: tournamentId)))
        .valueOrNull;
    final org = !showOrg ? null : ref.watch(organizationProvider(orgId)).valueOrNull;

    final icons = <String>{};
    var entered = 0;
    DateTime? earliest;
    for (final c in competitions) {
      icons.add(SportCatalog.byId(c.sportId).icon);
      entered += c.entrantCount;
      final start = c.startDate;
      if (start != null && (earliest == null || start.isBefore(earliest))) {
        earliest = start;
      }
    }
    final startDate = tournament?.startDate ?? earliest;
    final title = tournament?.name ??
        // Falls back to the sport-qualified name's season half — "Sports
        // Week 2026 — Cricket" becomes "Sports Week 2026" — for the one
        // instant between a season being created and its own document
        // reaching this listener.
        competitions.first.name.split(' — ').first;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.secondaryContainer,
          child: Icon(
            Icons.calendar_month_outlined,
            color: theme.colorScheme.onSecondaryContainer,
          ),
        ),
        title: Text(title),
        subtitle: Text(
          [
            if (org != null) org.name,
            '${competitions.length} '
                '${competitions.length == 1 ? 'sport' : 'sports'}'
                '${icons.isEmpty ? '' : ' ${icons.join(' ')}'}',
            '$entered entered',
            if (startDate != null) friendlyDate(startDate),
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        trailing:
            tournament == null ? null : _SeasonStatusChip(status: tournament.status),
        onTap: () => context.push(Routes.tournament(orgId, tournamentId)),
      ),
    );
  }
}

class _SeasonStatusChip extends StatelessWidget {
  const _SeasonStatusChip({required this.status});

  final TournamentStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (status) {
      TournamentStatus.entriesOpen => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer
        ),
      TournamentStatus.inProgress => (
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer
        ),
      _ => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}
