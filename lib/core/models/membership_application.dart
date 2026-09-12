import 'package:cloud_firestore/cloud_firestore.dart';

import 'enums.dart';
import 'firestore_codec.dart';

/// One sport an applicant has actually played, as a club approving them needs
/// to read it: which sport, and how much of it.
class ApplicantSport {
  const ApplicantSport({required this.sportId, required this.matchesPlayed});

  final String sportId;
  final int matchesPlayed;

  factory ApplicantSport.fromMap(Map<String, dynamic> m) => ApplicantSport(
        sportId: Fs.str(m['sportId']),
        matchesPlayed: Fs.integer(m['matchesPlayed']),
      );

  Map<String, Object?> toMap() => {
        'sportId': sportId,
        'matchesPlayed': matchesPlayed,
      };
}

/// What somebody tells a club about themselves when they ask to join it.
///
/// ## Why this exists rather than "just read their profile"
///
/// Before this, a club admin reviewing the approval queue saw a name, a photo
/// and two buttons. They were being asked to decide whether to admit a
/// stranger with nothing to decide on — so in practice they either admitted
/// everybody or left the queue untouched, which is the failure the members
/// screen's own doc comment already worried about.
///
/// The obvious fix — open the applicant's profile — does not work on its own,
/// and the reason is a real one rather than an implementation gap.
/// `firestore.rules` will not serve `users/{uid}` to a stranger whose
/// visibility is `community` (the default for every new account) because the
/// two do not yet share a club; and it will not serve a MINOR's document to
/// anybody without a guardian-consent record, which a club admin will never
/// have. A school admitting thirteen-year-olds is exactly the case that
/// matters most and exactly the case a profile read can never cover.
///
/// So the applicant carries their own introduction. This is a snapshot the
/// APPLICANT writes, at the moment they apply, onto the membership document
/// they are already allowed to create — the same principle `playerCodes`
/// established, where a stranger lookup reads a small denormalized document
/// instead of the profile it points at. Nothing here is disclosed by anyone
/// except the person it describes, and it is disclosed to exactly one club.
///
/// It deliberately does NOT carry a date of birth, an email address or a
/// phone number. A club decides on "what do they play, roughly how old are
/// they, where are they" — none of which needs an identifier that could be
/// used to contact a minor off-platform.
class MembershipApplication {
  const MembershipApplication({
    this.note,
    this.ageYears,
    this.gender,
    this.locationLabel,
    this.playerCode,
    this.sports = const [],
    this.submittedAt,
  });

  /// Nothing was said. The shape every membership written before applications
  /// existed reads back as, so an old pending row still renders.
  static const empty = MembershipApplication();

  /// The applicant's own words — "I played district-level U-19, I've just
  /// moved to Warangal". Optional, and most people leave it blank.
  final String? note;

  /// Longest note accepted. Long enough for the two or three sentences that
  /// actually help a decision, short enough that the membership document
  /// stays small and nobody pastes a CV into a roster row.
  static const maxNoteLength = 400;

  /// Age in whole years AT [submittedAt], not now.
  ///
  /// Stored rather than derived because the reviewer cannot read the
  /// applicant's date of birth — that is the whole point of this class. It is
  /// rendered alongside the submission date so a stale queue reads honestly
  /// rather than confidently wrong.
  final int? ageYears;

  final Gender? gender;

  /// "Warangal, Telangana" — as coarse as the applicant's profile actually
  /// is, never more precise. Built by [describeGeo] so every applicant's line
  /// is composed the same way.
  final String? locationLabel;

  /// So an admin can look the applicant up the way they look anybody else up.
  final String? playerCode;

  /// Sports played, most-played first. Empty for a genuinely new player,
  /// which is a fact worth showing rather than hiding.
  final List<ApplicantSport> sports;

  final DateTime? submittedAt;

  bool get isEmpty =>
      note == null &&
      ageYears == null &&
      gender == null &&
      locationLabel == null &&
      sports.isEmpty;

  bool get isNotEmpty => !isEmpty;

  int get totalMatches =>
      sports.fold(0, (total, s) => total + s.matchesPlayed);

  factory MembershipApplication.fromMap(Map<String, dynamic> m) {
    if (m.isEmpty) return empty;
    final rawSports = m['sports'];
    return MembershipApplication(
      note: Fs.strOrNull(m['note']),
      ageYears: Fs.intOrNull(m['ageYears']),
      gender: m['gender'] == null ? null : Gender.fromWire(Fs.str(m['gender'])),
      locationLabel: Fs.strOrNull(m['locationLabel']),
      playerCode: Fs.strOrNull(m['playerCode']),
      sports: rawSports is List
          ? [
              for (final s in rawSports)
                if (s is Map) ApplicantSport.fromMap(Map<String, dynamic>.from(s)),
            ]
          : const [],
      submittedAt: Fs.dateOrNull(m['submittedAt']),
    );
  }

  /// Payload for the nested `application` map on a membership document.
  ///
  /// Pruned of nulls, and empty when nothing was supplied — an applicant who
  /// filled in nothing should not add a map of six nulls to their row.
  ///
  /// `submittedAt` is a client clock rather than `FieldValue.serverTimestamp()`
  /// because this is a nested map, and a sentinel inside a map is rejected by
  /// Firestore. It is only ever rendered next to [ageYears] as "as of when",
  /// never compared against another document's timestamp.
  Map<String, Object?> toMap() {
    if (isEmpty) return const {};
    return Fs.prune({
      'note': note,
      'ageYears': ageYears,
      'gender': gender?.wire,
      'locationLabel': locationLabel,
      'playerCode': playerCode,
      'sports': sports.isEmpty ? null : [for (final s in sports) s.toMap()],
      'submittedAt': Timestamp.fromDate(submittedAt ?? DateTime.now()),
    });
  }
}
