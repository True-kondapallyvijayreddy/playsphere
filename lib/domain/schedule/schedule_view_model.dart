import 'package:intl/intl.dart';

import '../../core/models/competition.dart';
import '../../core/models/fixture.dart';
import 'schedule_pdf.dart';

/// Which entrants in a draw are "ours".
///
/// The question every reader of a schedule actually asks is "when do we
/// play", and a 96-match round robin answers it only if the app answers it
/// first. Four independent things can make an entrant yours, and all four
/// matter in the field:
///
/// * it IS you — an individual event, your own account;
/// * you are in its squad — a team entrant listing your uid;
/// * it is one of your teams — a club coach who is not himself in the squad;
/// * it represents a club you belong to — the case a school actually cares
///   about, where "our matches" means the whole school's, not one team's.
///
/// Returned as entrant ids because that is what [Fixture.entrantAId] holds;
/// matching on display name would highlight "Team B" in two different draws.
class MyEntrants {
  const MyEntrants._();

  static Set<String> resolve({
    required Iterable<Entrant> entrants,
    String? uid,
    Set<String> myOrgIds = const {},
    Set<String> myTeamIds = const {},
  }) {
    final mine = <String>{};
    for (final e in entrants) {
      final isMe = uid != null &&
          (e.uid == uid || e.memberUids.contains(uid));
      final isMyTeam = e.teamId != null && myTeamIds.contains(e.teamId);
      final isMyClub = e.clubId != null && myOrgIds.contains(e.clubId);
      if (isMe || isMyTeam || isMyClub) mine.add(e.id);
    }
    return mine;
  }
}

/// Formatting a [Fixture] for a schedule, in the one place both the on-screen
/// board and the printed PDF read from.
///
/// They diverged once already — the list showed "00:00" for an unscheduled
/// match because `scheduledAt` was null and the formatter defaulted, which is
/// the single most misleading thing a schedule can say. "TBC" is the truth,
/// and it has to be the truth in both places.
class ScheduleFormat {
  const ScheduleFormat._();

  /// Whether the fixture has a real kick-off time.
  ///
  /// A draft bracket writes `scheduledAt` as the epoch rather than null in
  /// some older documents, and midnight on 1 Jan 1970 renders as a perfectly
  /// confident "00:00". Anything before PlaySphere existed is not a time.
  static bool hasTime(Fixture f) {
    final at = f.scheduledAt;
    return at != null && at.year > 2000;
  }

  /// "Sat 12 Oct · 09:00", or "TBC".
  static String when(Fixture f, {bool withDate = true}) {
    if (!hasTime(f)) return 'TBC';
    final at = f.scheduledAt!;
    final time = DateFormat('h:mm a').format(at);
    return withDate ? '${DateFormat('EEE d MMM').format(at)} · $time' : time;
  }

  /// "R3" for a group round, or the draw's own label ("Quarter-final") when
  /// it has one, which is what a knockout carries.
  static String round(Fixture f) {
    final label = f.roundLabel;
    if (label != null && label.trim().isNotEmpty) return label.trim();
    return 'R${f.round}';
  }

  /// Where it is played, preferring the court because that is what somebody
  /// standing in the venue needs.
  static String court(Fixture f) {
    final parts = <String>[
      if (f.courtId != null && f.courtId!.isNotEmpty) f.courtId!,
      if (f.venue != null && f.venue!.isNotEmpty) f.venue!,
    ];
    return parts.join(' · ');
  }

  /// The section a fixture belongs under: its group, or the knockout stage
  /// that follows the groups.
  static String section(Fixture f) =>
      f.groupId != null ? 'Group ${f.groupId}' : 'Knockout';

  /// Rounds sorted the way a programme is read.
  static int byRound(Fixture a, Fixture b) => a.round != b.round
      ? a.round.compareTo(b.round)
      : a.matchIndex.compareTo(b.matchIndex);

  /// Sorted by kick-off, with unscheduled matches last rather than first —
  /// a null time sorting to the top puts every unplaced match above the
  /// programme it is missing from.
  static int byTime(Fixture a, Fixture b) {
    final at = hasTime(a) ? a.scheduledAt! : null;
    final bt = hasTime(b) ? b.scheduledAt! : null;
    if (at == null && bt == null) return byRound(a, b);
    if (at == null) return 1;
    if (bt == null) return -1;
    final c = at.compareTo(bt);
    return c != 0 ? c : byRound(a, b);
  }

  /// Builds the printable sections for [fixtures].
  ///
  /// [mineEntrantIds] comes from [MyEntrants.resolve]; every row it touches
  /// is washed green on the page.
  static List<ScheduleSection> toSections(
    List<Fixture> fixtures, {
    Set<String> mineEntrantIds = const {},
    bool byDay = false,
    String Function(Fixture)? sectionOf,
  }) {
    final buckets = <String, List<Fixture>>{};
    for (final f in fixtures) {
      final key = byDay
          ? (hasTime(f)
              ? DateFormat('EEEE d MMMM y').format(f.scheduledAt!)
              : 'Not yet scheduled')
          : (sectionOf ?? section)(f);
      buckets.putIfAbsent(key, () => []).add(f);
    }

    // Groups read A, B, C; days read earliest first; "Knockout" and "Not yet
    // scheduled" are both tails and are pushed there explicitly rather than
    // landing wherever the alphabet put them.
    final keys = buckets.keys.toList()
      ..sort((a, b) {
        const tails = {'Knockout', 'Not yet scheduled'};
        if (tails.contains(a) != tails.contains(b)) {
          return tails.contains(a) ? 1 : -1;
        }
        if (byDay) {
          final fa = buckets[a]!.first.scheduledAt;
          final fb = buckets[b]!.first.scheduledAt;
          if (fa != null && fb != null) return fa.compareTo(fb);
        }
        return a.compareTo(b);
      });

    return [
      for (final key in keys)
        ScheduleSection(
          title: key,
          rows: [
            for (final f in [...buckets[key]!]..sort(byDay ? byTime : byRound))
              ScheduleRow(
                round: round(f),
                when: when(f),
                teamA: f.displayNameA(),
                teamB: f.displayNameB(),
                court: court(f),
                result: f.summary,
                mine: mineEntrantIds.contains(f.entrantAId) ||
                    mineEntrantIds.contains(f.entrantBId),
              ),
          ],
        ),
    ];
  }
}
