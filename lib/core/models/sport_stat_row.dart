import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_codec.dart';

/// One sport's directory totals, as written nightly by
/// `functions/sports.js`'s `computeSportStats`.
///
/// See that file for what each count actually measures — in particular why
/// `tournamentCount` counts competitions rather than the product's own
/// `tournaments` collection.
class SportStatRow {
  const SportStatRow({
    required this.sportId,
    required this.tournamentCount,
    required this.teamCount,
    required this.playerCount,
    this.computedAt,
  });

  final String sportId;
  final int tournamentCount;
  final int teamCount;
  final int playerCount;

  /// When the rollup last ran. The directory needs this to avoid presenting
  /// a nightly number as a live one.
  final DateTime? computedAt;

  /// The count a directory row leads with beside its tournaments.
  ///
  /// A sport is described by whichever unit it is actually played in rather
  /// than by its catalogue default: a club running badminton as an inter-house
  /// team league should see teams, and cricket played as singles-ladder
  /// friendlies should see players. Ties go to teams, which is the reading
  /// that matches the catalogue for every sport where both are plausible.
  bool get isTeamShaped => teamCount >= playerCount;

  int get headlineEntrantCount => isTeamShaped ? teamCount : playerCount;

  String get headlineEntrantLabel => isTeamShaped ? 'Teams' : 'Players';

  /// What a sport with no rollup row yet reads as — a sport nobody has run an
  /// event in is genuinely all zeroes, and that is a truthful thing for the
  /// directory to show. Distinguishing "no data" from "zero" here would mean
  /// a blank row for every sport on a fresh install.
  factory SportStatRow.empty(String sportId) => SportStatRow(
        sportId: sportId,
        tournamentCount: 0,
        teamCount: 0,
        playerCount: 0,
      );

  factory SportStatRow.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return SportStatRow(
      sportId: Fs.str(d['sportId'], doc.id),
      tournamentCount: Fs.integer(d['tournamentCount']),
      teamCount: Fs.integer(d['teamCount']),
      playerCount: Fs.integer(d['playerCount']),
      computedAt: Fs.dateOrNull(d['computedAt']),
    );
  }
}
