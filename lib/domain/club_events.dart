import 'package:flutter/material.dart';

import '../core/models/competition.dart';
import '../core/models/enums.dart';

/// What kind of thing one of a club's events actually is.
///
/// The same four shapes [EventType] offers when an organizer creates
/// something — deliberately, because a club that was asked "season,
/// tournament, single match or challenge?" on the way in should be able to
/// ask the same question on the way out. `EventType` cannot be reused
/// directly: it is a *creation* vocabulary and nothing writes it onto the
/// competition, so what an event is has to be read back off the document.
///
/// The order of the checks in [of] is the whole subtlety. A multi-sport
/// challenge is grouped under a tournament id exactly as a season is (see
/// `CommunityRepository.acceptChallenge`), so asking about the season first
/// would file every inter-club afternoon under "Seasons". Being contested by
/// two clubs is the more specific fact, so it is asked first.
enum ClubEventKind {
  season(
    label: 'Seasons',
    singular: 'Season',
    icon: Icons.calendar_month_outlined,
    empty: 'No seasons yet. A season gathers several sports under one '
        'calendar — a sports week, an inter-house term.',
  ),
  tournament(
    label: 'Tournaments',
    singular: 'Tournament',
    icon: Icons.emoji_events_outlined,
    empty: 'No tournaments yet. A tournament is one sport, open for '
        'registrations, with a draw behind it.',
  ),
  singleMatch(
    label: 'Matches',
    singular: 'Single match',
    icon: Icons.sports_score_outlined,
    empty: 'No single matches yet. These are the club\'s own games — both '
        'sides named on the spot, no draw to wait for.',
  ),
  challenge(
    label: 'Challenges',
    singular: 'Challenge',
    icon: Icons.sports_kabaddi_outlined,
    empty: 'No challenges yet. A challenge is a match agreed with another '
        'club — they accept, and the fixture appears here.',
  );

  const ClubEventKind({
    required this.label,
    required this.singular,
    required this.icon,
    required this.empty,
  });

  /// The tab label — plural, because it heads a list.
  final String label;

  final String singular;
  final IconData icon;

  /// What to say when a club has none of these yet.
  final String empty;

  /// Which kind [c] is.
  static ClubEventKind of(Competition c) {
    if (c.isInterClub) return ClubEventKind.challenge;
    if (c.tournamentId != null) return ClubEventKind.season;
    if (c.format == CompetitionFormat.singleMatch) {
      return ClubEventKind.singleMatch;
    }
    return ClubEventKind.tournament;
  }

  /// Whether the events of this kind gather behind one card per season — see
  /// `groupEventFeed`. Only a season does: a challenge's legs are shown one
  /// per match, because "who did we play and what happened" is the question
  /// being asked of them.
  bool get groupsBySeason => this == ClubEventKind.season;
}

/// A stage of an event's life, as somebody browsing a club's events would
/// name it.
///
/// A thin re-labelling of [CompetitionStatus] rather than a second source of
/// truth: [matches] compares against `Competition.displayStatus()`, so an
/// event whose registration deadline has passed files itself under "Entries
/// closed" without an organizer having to touch it — the same behaviour the
/// status chip on every event card already shows.
///
/// [scheduled] and [inProgress] are folded into one "Playing" filter. Nobody
/// standing at a ground distinguishes a match that is about to start from one
/// that has, and offering two filters that differ by a single write is two
/// taps to find out which one an event is under.
enum ClubEventStage {
  all('All', null),
  draft('Draft', {CompetitionStatus.draft}),
  entriesOpen('Entries open', {CompetitionStatus.registrationOpen}),
  entriesClosed('Entries closed', {CompetitionStatus.registrationClosed}),
  playing('Playing', {
    CompetitionStatus.scheduled,
    CompetitionStatus.inProgress,
  }),
  played('Played', {CompetitionStatus.completed}),
  cancelled('Cancelled', {CompetitionStatus.cancelled});

  const ClubEventStage(this.label, this.statuses);

  final String label;

  /// Null for [all], which matches everything.
  final Set<CompetitionStatus>? statuses;

  bool matches(Competition c, [DateTime? now]) =>
      statuses == null || statuses!.contains(c.displayStatus(now));
}

/// One club's events, sliced the way its page offers them.
///
/// Built once from the club's full competition list rather than filtered at
/// each tab, so the counts on the tabs and the rows under them can never
/// disagree — the bug that makes a "3 Tournaments" tab open onto two rows.
class ClubEventIndex {
  ClubEventIndex._(this._byKind, this.now);

  final Map<ClubEventKind, List<Competition>> _byKind;

  /// Pinned at construction. `displayStatus` is time-dependent, and a list
  /// whose filter is evaluated against a clock that moves between the count
  /// and the rows can show four events under a tab labelled five.
  final DateTime now;

  factory ClubEventIndex.of(List<Competition> competitions, {DateTime? now}) {
    final byKind = <ClubEventKind, List<Competition>>{
      for (final kind in ClubEventKind.values) kind: <Competition>[],
    };
    for (final c in competitions) {
      byKind[ClubEventKind.of(c)]!.add(c);
    }
    return ClubEventIndex._(byKind, now ?? DateTime.now());
  }

  /// Every event of one kind, in the order they arrived (callers pass an
  /// already-sorted list), optionally narrowed to one stage.
  List<Competition> events(
    ClubEventKind kind, {
    ClubEventStage stage = ClubEventStage.all,
  }) {
    final all = _byKind[kind] ?? const <Competition>[];
    if (stage == ClubEventStage.all) return all;
    return [
      for (final c in all)
        if (stage.matches(c, now)) c,
    ];
  }

  /// What to put on the tab: seasons counted as seasons, everything else
  /// counted as events.
  ///
  /// A five-sport season is one thing a club ran, not five, and a tab that
  /// says "5" over a list showing one card is the same disagreement
  /// `groupEventFeed` exists to prevent further down the page.
  int count(ClubEventKind kind, {ClubEventStage stage = ClubEventStage.all}) {
    final rows = events(kind, stage: stage);
    if (!kind.groupsBySeason) return rows.length;
    return {
      for (final c in rows) '${c.orgId}/${c.tournamentId}',
    }.length;
  }

  /// Whether the club has run anything at all of this kind, ignoring stage.
  bool has(ClubEventKind kind) => (_byKind[kind] ?? const []).isNotEmpty;

  /// The stages that actually occur among one kind's events, in enum order
  /// and always led by [ClubEventStage.all].
  ///
  /// Offering all seven unconditionally means a club with four completed
  /// tournaments is given six filters that lead to an empty screen, which
  /// teaches people that the filters are broken.
  List<ClubEventStage> stagesPresent(ClubEventKind kind) {
    final rows = _byKind[kind] ?? const <Competition>[];
    return [
      ClubEventStage.all,
      for (final stage in ClubEventStage.values)
        if (stage != ClubEventStage.all &&
            rows.any((c) => stage.matches(c, now)))
          stage,
    ];
  }
}
