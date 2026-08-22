import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_codec.dart';

/// One entry on a tournament's officiating panel, at
/// `orgs/{orgId}/tournaments/{tournamentId}/officials/{uid}`.
///
/// ## Why this is a third thing, not the same as [UmpireProfile] or
/// [MatchOfficial]
///
/// `umpires/{uid}` is a person's standing, cross-club claim — "I am
/// certified to officiate badminton." `Fixture.officials` is who actually
/// stood at one specific match. Neither can answer "who has this season
/// owner already lined up for this tournament, before a single fixture
/// exists?" — and that question, asked and answered ahead of time, is the
/// whole point of doing this ICC-style rather than finding an umpire at the
/// gate. This roster is the season owner's curated shortlist: built from the
/// open registry, or from someone who has never opened the app, and it is
/// what the bulk assignment algorithm and the per-match picker both draw
/// from.
class TournamentOfficial {
  const TournamentOfficial({
    required this.uid,
    required this.name,
    this.role = 'main_umpire',
    this.sports = const [],
    this.clubId,
    this.scoringRightsGranted = true,
    this.availableDates = const [],
    this.maxMatchesPerDay = 8,
    this.addedBy,
    this.addedAt,
  });

  final String uid;
  final String name;

  /// 'main_umpire', 'square_leg_umpire', 'referee', 'third_umpire',
  /// 'linesman' — mirrors [MatchOfficial.role], since a roster entry becomes
  /// exactly that once it lands on a fixture.
  final String role;

  /// Sports this person is being trusted to officiate in this tournament.
  /// Drives which slots the bulk assigner will offer them for.
  final List<String> sports;

  /// The club they belong to, if any — carried onto every assignment made
  /// from this roster entry so [OfficialsAssigner]'s neutrality check has
  /// something to check against. Null is the common and unproblematic case:
  /// an unaffiliated official is never blocked from any match.
  final String? clubId;

  /// Whether this person may score matches they're assigned to, decided once
  /// here rather than re-asked at every fixture. Still revocable per match
  /// after assignment — see [MatchOfficial.grantedScoringAccess].
  final bool scoringRightsGranted;

  /// The days this person can actually turn up, as `yyyy-MM-dd` calendar keys.
  ///
  /// Empty means every day of the tournament, which is both the default and
  /// the right one: most volunteers at a one-day club meet are there for the
  /// day, and demanding a date list before anyone can be added would put a
  /// form between an organizer and the panel they are trying to build.
  ///
  /// ## Why strings and not `DateTime`
  ///
  /// "Ravi is free on Saturday" is a fact about a calendar day, not about an
  /// instant. Stored as a timestamp it acquires a time and a zone, and the
  /// comparison that decides whether he can take the 9am match becomes a
  /// question about midnight — which is how an official free on the 14th
  /// reads as unavailable for a match at 00:30 on the 14th. A day key has no
  /// midnight to be on the wrong side of.
  ///
  /// This is what turns the bulk assigner from "spread the work" into
  /// something an organizer can trust: it will not put a name on a Sunday
  /// match for somebody who said they could only do Saturday.
  final List<String> availableDates;

  /// How many matches this person will take in one day.
  ///
  /// Per DAY, not per tournament, which is the distinction a three-day season
  /// makes load-bearing: a cap of eight across three days is not a limit on
  /// anything, and one of eight per day is the promise that nobody stands for
  /// fourteen matches on the Saturday.
  final int maxMatchesPerDay;

  /// Whether this person can officiate [sportId] here.
  ///
  /// An empty [sports] means "anything this tournament runs" rather than
  /// "nothing" — the same default-open reading as [availableDates], and for
  /// the same reason: a panel added in a hurry must still be usable.
  bool coversSport(String? sportId) =>
      sports.isEmpty || sportId == null || sports.contains(sportId);

  /// Whether this person is free on the calendar day [dayKey] (`yyyy-MM-dd`).
  bool isFreeOn(String dayKey) =>
      availableDates.isEmpty || availableDates.contains(dayKey);

  final String? addedBy;
  final DateTime? addedAt;

  factory TournamentOfficial.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const {};
    return TournamentOfficial(
      uid: doc.id,
      name: Fs.str(d['name'], 'Official'),
      role: Fs.str(d['role'], 'main_umpire'),
      sports: Fs.strList(d['sports']),
      clubId: Fs.strOrNull(d['clubId']),
      scoringRightsGranted: Fs.boolean(d['scoringRightsGranted'], true),
      availableDates: Fs.strList(d['availableDates']),
      maxMatchesPerDay: Fs.integer(d['maxMatchesPerDay'], 8),
      addedBy: Fs.strOrNull(d['addedBy']),
      addedAt: Fs.dateOrNull(d['addedAt']),
    );
  }

  Map<String, Object?> toCreate({required String addedBy}) => {
        'name': name,
        'role': role,
        'sports': sports,
        'clubId': clubId,
        'scoringRightsGranted': scoringRightsGranted,
        'availableDates': availableDates,
        'maxMatchesPerDay': maxMatchesPerDay,
        'addedBy': addedBy,
        'addedAt': FieldValue.serverTimestamp(),
      };

  /// The editable half of a roster entry.
  ///
  /// `addedBy` and `addedAt` are absent because `firestore.rules` refuses an
  /// update that changes either — a panel entry records who put this person
  /// on it, and editing their availability is not a re-add.
  Map<String, Object?> toUpdate() => {
        'name': name,
        'role': role,
        'sports': sports,
        'clubId': clubId,
        'scoringRightsGranted': scoringRightsGranted,
        'availableDates': availableDates,
        'maxMatchesPerDay': maxMatchesPerDay,
      };

  TournamentOfficial copyWith({
    String? name,
    String? role,
    List<String>? sports,
    String? clubId,
    bool? scoringRightsGranted,
    List<String>? availableDates,
    int? maxMatchesPerDay,
  }) =>
      TournamentOfficial(
        uid: uid,
        name: name ?? this.name,
        role: role ?? this.role,
        sports: sports ?? this.sports,
        clubId: clubId ?? this.clubId,
        scoringRightsGranted:
            scoringRightsGranted ?? this.scoringRightsGranted,
        availableDates: availableDates ?? this.availableDates,
        maxMatchesPerDay: maxMatchesPerDay ?? this.maxMatchesPerDay,
        addedBy: addedBy,
        addedAt: addedAt,
      );
}
