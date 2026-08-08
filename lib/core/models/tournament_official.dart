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
        'addedBy': addedBy,
        'addedAt': FieldValue.serverTimestamp(),
      };
}
