import '../../core/models/enums.dart';
import '../../core/models/fixture.dart';

/// Where a match is, in the words an organizer uses on match day.
///
/// [FixtureStatus] is the stored lifecycle, and it is the wrong thing to
/// paint a row from. A `live` status on a scoreboard nobody has touched since
/// Tuesday is not a match in progress, and a `scheduled` match whose start
/// time went by forty minutes ago is not simply "upcoming" — it is the one
/// row on the sheet somebody needs to go and chase. Every list that shows a
/// match asks this one question, so the season page, the event board and the
/// public link cannot disagree about what is going on.
enum MatchPhase {
  /// Being scored right now. See [Fixture.isLiveAt].
  live,

  /// Started, but the scoreboard has gone quiet. Still unfinished business.
  paused,

  /// Over, with a result that counts — played out or ruled.
  finished,

  /// Stopped without a result: abandoned, or frozen by a dispute.
  halted,

  /// Not started, and its start time has passed.
  overdue,

  /// Not started yet, and not late.
  upcoming;

  /// How long after its slot a match that has not begun counts as late.
  /// Long enough that a changeover running a few minutes over is not an
  /// alarm; short enough that a no-show is flagged inside one match length.
  static const Duration graceAfterStart = Duration(minutes: 15);

  static MatchPhase of(Fixture f, DateTime now) {
    if (f.isLiveAt(now)) return MatchPhase.live;
    if (f.status.isResulted) return MatchPhase.finished;
    if (f.status == FixtureStatus.abandoned ||
        f.status == FixtureStatus.disputed) {
      return MatchPhase.halted;
    }
    if (f.isStaleLiveAt(now)) return MatchPhase.paused;
    final at = f.scheduledAt;
    if (at != null && now.isAfter(at.add(graceAfterStart))) {
      return MatchPhase.overdue;
    }
    return MatchPhase.upcoming;
  }

  /// Started and not yet over — what "going on" means to an organizer.
  bool get inProgress => this == MatchPhase.live || this == MatchPhase.paused;

  /// Nothing more will happen on it without somebody deciding something.
  bool get isDone => this == MatchPhase.finished || this == MatchPhase.halted;

  /// Still to be played.
  bool get isAhead => this == MatchPhase.overdue || this == MatchPhase.upcoming;
}

/// The numbers an organizer reads a set of matches by: played, going on,
/// still to play — with the late ones inside "to play" and the stopped ones
/// beside it, because both of those need a person.
///
/// "Played" is [MatchPhase.finished] only, the same count as
/// `TournamentOverview.playedMatches`: an abandoned match may yet be replayed,
/// so it is shown as its own figure rather than quietly counted as done.
class MatchTally {
  const MatchTally({
    required this.total,
    required this.played,
    required this.inProgress,
    required this.ahead,
    required this.overdue,
    required this.halted,
  });

  factory MatchTally.of(Iterable<Fixture> fixtures, DateTime now) {
    var total = 0, played = 0, going = 0, ahead = 0, late = 0, halted = 0;
    for (final f in fixtures) {
      // A draft is an organizer's preview against placeholder sides — see
      // `Fixture.isDraft` — and is not a match anybody will play.
      if (f.isDraft) continue;
      total++;
      switch (MatchPhase.of(f, now)) {
        case MatchPhase.finished:
          played++;
        case MatchPhase.live || MatchPhase.paused:
          going++;
        case MatchPhase.overdue:
          ahead++;
          late++;
        case MatchPhase.upcoming:
          ahead++;
        case MatchPhase.halted:
          halted++;
      }
    }
    return MatchTally(
      total: total,
      played: played,
      inProgress: going,
      ahead: ahead,
      overdue: late,
      halted: halted,
    );
  }

  final int total;
  final int played;

  /// Live or paused.
  final int inProgress;

  /// Not started, late or not.
  final int ahead;

  /// The part of [ahead] whose start time has gone by.
  final int overdue;

  /// Abandoned or disputed.
  final int halted;

  double get progress => total == 0 ? 0 : played / total;
}
