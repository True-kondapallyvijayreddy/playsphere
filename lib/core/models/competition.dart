import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_user.dart';
import 'enums.dart';
import 'firestore_codec.dart';

/// Eligibility rule attached to a competition.
///
/// A competition is never just "Table Tennis" — in a school, college or
/// government meet it is always "Table Tennis, Boys, Under-17". Modelling the
/// category as a first-class value instead of leaving it inside the free-text
/// name is what allows the app to actually check whether an entrant may play,
/// to produce a correct medal tally, and to stop a 19-year-old being entered
/// into a U-17 draw.
class CompetitionCategory {
  const CompetitionCategory({
    required this.label,
    this.dimensions = const {CategoryDimension.openCategory},
    this.minAge,
    this.maxAge,
    this.ageCutOffDate,
    this.allowedGenders = const {},
    this.minWeightKg,
    this.maxWeightKg,
    this.grade,
  });

  /// Display name such as "U-17 Boys" or "Senior Women 57kg".
  final String label;

  final Set<CategoryDimension> dimensions;

  /// Inclusive age bounds evaluated on [ageCutOffDate].
  final int? minAge;
  final int? maxAge;

  /// The date age is measured on. Every federation fixes one for the season
  /// so that a birthday mid-tournament cannot change a player's category.
  /// When null, the competition start date is used.
  final DateTime? ageCutOffDate;

  /// Empty means open to all genders.
  final Set<Gender> allowedGenders;

  final double? minWeightKg;
  final double? maxWeightKg;

  /// Class/year for school and college meets, e.g. "Class 9" or "2nd Year".
  final String? grade;

  bool get isOpen =>
      dimensions.length == 1 &&
      dimensions.contains(CategoryDimension.openCategory);

  /// Decides whether [user] may enter, returning a human-readable reason when
  /// they may not. Returning the reason rather than a bare bool matters: an
  /// organizer rejecting an entry has to be able to tell the player why.
  CategoryEligibility check(AppUser user, {DateTime? competitionStart}) {
    if (dimensions.contains(CategoryDimension.age) &&
        (minAge != null || maxAge != null)) {
      final cutOff = ageCutOffDate ?? competitionStart ?? DateTime.now();
      final age = user.ageAt(cutOff);
      if (minAge != null && age < minAge!) {
        return CategoryEligibility.ineligible(
          'Must be at least $minAge on ${_fmt(cutOff)} — this player is $age.',
        );
      }
      if (maxAge != null && age > maxAge!) {
        return CategoryEligibility.ineligible(
          'Must be $maxAge or under on ${_fmt(cutOff)} — this player is $age.',
        );
      }
    }

    if (allowedGenders.isNotEmpty && !allowedGenders.contains(user.gender)) {
      final allowed = allowedGenders.map((g) => g.label).join(' / ');
      return CategoryEligibility.ineligible('Open to $allowed only.');
    }

    return const CategoryEligibility.eligible();
  }

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  factory CompetitionCategory.fromMap(Map<String, dynamic> d) {
    return CompetitionCategory(
      label: Fs.str(d['label'], 'Open'),
      dimensions: Fs.strList(d['dimensions'])
          .map(CategoryDimension.fromWire)
          .toSet(),
      minAge: d['minAge'] == null ? null : Fs.integer(d['minAge']),
      maxAge: d['maxAge'] == null ? null : Fs.integer(d['maxAge']),
      ageCutOffDate: Fs.dateOrNull(d['ageCutOffDate']),
      allowedGenders: Fs.strList(d['allowedGenders']).map(Gender.fromWire).toSet(),
      minWeightKg:
          d['minWeightKg'] == null ? null : Fs.decimal(d['minWeightKg']),
      maxWeightKg:
          d['maxWeightKg'] == null ? null : Fs.decimal(d['maxWeightKg']),
      grade: Fs.strOrNull(d['grade']),
    );
  }

  Map<String, Object?> toMap() => {
        'label': label,
        'dimensions': dimensions.map((d) => d.wire).toList(),
        'minAge': minAge,
        'maxAge': maxAge,
        'ageCutOffDate': Fs.ts(ageCutOffDate),
        'allowedGenders': allowedGenders.map((g) => g.wire).toList(),
        'minWeightKg': minWeightKg,
        'maxWeightKg': maxWeightKg,
        'grade': grade,
      };

  /// Presets covering the overwhelming majority of Indian school, college and
  /// district meets. Offering these means an organizer picks a category in
  /// one tap instead of hand-entering bounds and getting them wrong.
  static List<CompetitionCategory> presets({DateTime? cutOff}) {
    List<CompetitionCategory> ageBand(int max, String noun, Set<Gender> g, String gl) => [
          CompetitionCategory(
            label: 'U-$max $gl',
            dimensions: const {CategoryDimension.age, CategoryDimension.gender},
            maxAge: max,
            ageCutOffDate: cutOff,
            allowedGenders: g,
          ),
        ];

    return [
      const CompetitionCategory(label: 'Open'),
      for (final band in [11, 14, 17, 19])
        ...ageBand(band, 'Under', {Gender.male}, 'Boys'),
      for (final band in [11, 14, 17, 19])
        ...ageBand(band, 'Under', {Gender.female}, 'Girls'),
      CompetitionCategory(
        label: 'Senior Men',
        dimensions: const {CategoryDimension.age, CategoryDimension.gender},
        minAge: 19,
        ageCutOffDate: cutOff,
        allowedGenders: const {Gender.male},
      ),
      CompetitionCategory(
        label: 'Senior Women',
        dimensions: const {CategoryDimension.age, CategoryDimension.gender},
        minAge: 19,
        ageCutOffDate: cutOff,
        allowedGenders: const {Gender.female},
      ),
      const CompetitionCategory(
        label: 'Mixed',
        dimensions: {CategoryDimension.openCategory},
      ),
    ];
  }
}

class CategoryEligibility {
  const CategoryEligibility.eligible()
      : isEligible = true,
        reason = null;
  const CategoryEligibility.ineligible(this.reason) : isEligible = false;

  final bool isEligible;
  final String? reason;
}

/// A single contest inside an organization, at
/// `orgs/{orgId}/competitions/{compId}`.
class Competition {
  const Competition({
    required this.id,
    required this.orgId,
    required this.name,
    required this.sportId,
    required this.sportName,
    required this.archetype,
    required this.entrantType,
    required this.format,
    required this.status,
    required this.category,
    required this.scoringPluginKey,
    this.description,
    this.venue,
    this.startDate,
    this.endDate,
    this.registrationClosesAt,
    this.maxEntrants,
    this.entrantCount = 0,
    this.fixtureCount = 0,
    this.verificationTier = VerificationTier.casual,
    this.rulesetVersion = 1,
    this.pointsForWin = 3,
    this.pointsForDraw = 1,
    this.pointsForLoss = 0,
    this.tiebreakChain,
    this.participantOrgIds,
    this.createdBy,
    this.createdAt,
  });

  final String id;
  final String orgId;
  final String name;
  final String sportId;
  final String sportName;
  final CompetitionArchetype archetype;
  final EntrantType entrantType;
  final CompetitionFormat format;
  final CompetitionStatus status;
  final CompetitionCategory category;

  /// Which scoring rules apply. Resolved from the sport at creation time and
  /// then frozen, so enabling a better cricket plugin next season cannot
  /// retroactively change how last season's matches were scored.
  final String scoringPluginKey;

  final String? description;
  final String? venue;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime? registrationClosesAt;
  final int? maxEntrants;
  final int entrantCount;
  final int fixtureCount;
  final VerificationTier verificationTier;

  /// Bumped whenever the organizer changes scoring configuration. Fixtures
  /// record the version they were played under so a mid-season rule change
  /// never rewrites a finished result.
  final int rulesetVersion;

  final int pointsForWin;
  final int pointsForDraw;
  final int pointsForLoss;

  /// How this league separates teams level on points, as a list of
  /// [Tiebreak] wire names. Null means "use the sport's default chain" —
  /// cricket goes to net run rate, football to goal difference, a Swiss
  /// chess field to Buchholz.
  final List<String>? tiebreakChain;

  /// The organizations taking part, when this competition spans more than the
  /// one that owns it — a school-vs-school or village-vs-village challenge.
  ///
  /// ## Why the document is not enough on its own
  ///
  /// Competitions live at `orgs/{orgId}/competitions/{compId}`, which encodes
  /// exactly one owner. An inter-club match has two, and the club that did not
  /// happen to host it still has to read the fixture, watch it live and see its
  /// own result. This field is what the security rules consult to grant that
  /// second club access, so it is the authorization record for the match, not a
  /// convenience copy.
  ///
  /// Null for ordinary internal competitions. When present it always contains
  /// exactly two org ids, one of which is [orgId] — `firestore.rules` enforces
  /// both, because the read rule checks the entries by index and a longer list
  /// would silently grant nobody the access they were promised.
  final List<String>? participantOrgIds;

  final String? createdBy;
  final DateTime? createdAt;

  /// True when this competition exists because a challenge was accepted, and
  /// therefore answers to two clubs rather than one.
  bool get isInterClub =>
      participantOrgIds != null && participantOrgIds!.length == 2;

  /// The other club in an inter-club match, from [orgId]'s point of view.
  String? opponentOf(String someOrgId) {
    final ids = participantOrgIds;
    if (ids == null) return null;
    for (final id in ids) {
      if (id != someOrgId) return id;
    }
    return null;
  }

  bool get isFull => maxEntrants != null && entrantCount >= maxEntrants!;

  bool get registrationIsOpen {
    if (!status.acceptsRegistrations) return false;
    if (isFull) return false;
    final closes = registrationClosesAt;
    if (closes != null && DateTime.now().isAfter(closes)) return false;
    return true;
  }

  factory Competition.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Competition(
      id: doc.id,
      orgId: Fs.str(d['orgId']),
      name: Fs.str(d['name'], 'Untitled competition'),
      sportId: Fs.str(d['sportId']),
      sportName: Fs.str(d['sportName']),
      archetype: CompetitionArchetype.fromWire(Fs.str(d['archetype'])),
      entrantType: EntrantType.fromWire(Fs.str(d['entrantType'])),
      format: CompetitionFormat.fromWire(Fs.str(d['format'])),
      status: CompetitionStatus.fromWire(Fs.str(d['status'])),
      category: CompetitionCategory.fromMap(Fs.map(d['category'])),
      scoringPluginKey: Fs.str(d['scoringPluginKey'], 'simple_points'),
      description: Fs.strOrNull(d['description']),
      venue: Fs.strOrNull(d['venue']),
      startDate: Fs.dateOrNull(d['startDate']),
      endDate: Fs.dateOrNull(d['endDate']),
      registrationClosesAt: Fs.dateOrNull(d['registrationClosesAt']),
      maxEntrants: d['maxEntrants'] == null ? null : Fs.integer(d['maxEntrants']),
      entrantCount: Fs.integer(d['entrantCount']),
      fixtureCount: Fs.integer(d['fixtureCount']),
      verificationTier: VerificationTier.fromWire(Fs.str(d['verificationTier'])),
      rulesetVersion: Fs.integer(d['rulesetVersion'], 1),
      pointsForWin: Fs.integer(d['pointsForWin'], 3),
      pointsForDraw: Fs.integer(d['pointsForDraw'], 1),
      pointsForLoss: Fs.integer(d['pointsForLoss']),
      tiebreakChain:
          d['tiebreakChain'] is List ? Fs.strList(d['tiebreakChain']) : null,
      participantOrgIds: d['participantOrgIds'] is List
          ? Fs.strList(d['participantOrgIds'])
          : null,
      createdBy: Fs.strOrNull(d['createdBy']),
      createdAt: Fs.dateOrNull(d['createdAt']),
    );
  }

  Map<String, Object?> toCreate() => {
        'orgId': orgId,
        'name': name,
        'nameLower': name.toLowerCase(),
        'sportId': sportId,
        'sportName': sportName,
        'archetype': archetype.wire,
        'entrantType': entrantType.wire,
        'format': format.wire,
        // An ordinary competition always starts as a draft, so the organizer
        // configures it before anyone can enter. A challenge match has nothing
        // left to configure — both clubs already agreed the sport, the slot and
        // the venue when the challenge was accepted — so it is created ready to
        // play. `firestore.rules` permits exactly these two starting states.
        'status': isInterClub
            ? CompetitionStatus.scheduled.wire
            : CompetitionStatus.draft.wire,
        'category': category.toMap(),
        'scoringPluginKey': scoringPluginKey,
        'description': description,
        'venue': venue,
        'startDate': Fs.ts(startDate),
        'endDate': Fs.ts(endDate),
        'registrationClosesAt': Fs.ts(registrationClosesAt),
        'maxEntrants': maxEntrants,
        'entrantCount': 0,
        'fixtureCount': 0,
        'verificationTier': verificationTier.wire,
        'rulesetVersion': rulesetVersion,
        'pointsForWin': pointsForWin,
        'pointsForDraw': pointsForDraw,
        'pointsForLoss': pointsForLoss,
        'tiebreakChain': tiebreakChain,
        'participantOrgIds': participantOrgIds,
        'createdBy': createdBy,
        'createdAt': FieldValue.serverTimestamp(),
      };

  Map<String, Object?> toUpdate() => Fs.prune({
        'name': name,
        'nameLower': name.toLowerCase(),
        'description': description,
        'venue': venue,
        'startDate': Fs.ts(startDate),
        'endDate': Fs.ts(endDate),
        'registrationClosesAt': Fs.ts(registrationClosesAt),
        'maxEntrants': maxEntrants,
        'category': category.toMap(),
        'pointsForWin': pointsForWin,
        'pointsForDraw': pointsForDraw,
        'pointsForLoss': pointsForLoss,
        'tiebreakChain': tiebreakChain,
        'updatedAt': FieldValue.serverTimestamp(),
      });
}

/// An application to take part, at
/// `orgs/{orgId}/competitions/{compId}/registrations/{uid}`.
///
/// The document id is the applicant's uid, so a player physically cannot hold
/// two registrations for the same competition.
class Registration {
  const Registration({
    required this.uid,
    required this.displayName,
    required this.status,
    this.photoUrl,
    this.teamName,
    this.eligibilityNote,
    this.decidedBy,
    this.createdAt,
  });

  final String uid;
  final String displayName;
  final RegistrationStatus status;
  final String? photoUrl;
  final String? teamName;

  /// Recorded when an organizer overrode a failed eligibility check, so the
  /// decision is visible later if the result is protested.
  final String? eligibilityNote;

  final String? decidedBy;
  final DateTime? createdAt;

  factory Registration.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Registration(
      uid: doc.id,
      displayName: Fs.str(d['displayName'], 'Player'),
      status: RegistrationStatus.fromWire(Fs.str(d['status'])),
      photoUrl: Fs.strOrNull(d['photoUrl']),
      teamName: Fs.strOrNull(d['teamName']),
      eligibilityNote: Fs.strOrNull(d['eligibilityNote']),
      decidedBy: Fs.strOrNull(d['decidedBy']),
      createdAt: Fs.dateOrNull(d['createdAt']),
    );
  }

  Map<String, Object?> toCreate() => {
        'uid': uid,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'teamName': teamName,
        'status': RegistrationStatus.pending.wire,
        'eligibilityNote': eligibilityNote,
        'createdAt': FieldValue.serverTimestamp(),
      };
}

/// A confirmed competitor in the draw, at
/// `orgs/{orgId}/competitions/{compId}/entrants/{entrantId}`.
///
/// Separate from [Registration] because a registration is an *application*
/// and an entrant is a *starter*. Keeping them apart is what allows an
/// organizer to close entries, seed the field, and generate a draw without
/// late applications silently appearing inside a bracket already in play.
class Entrant {
  const Entrant({
    required this.id,
    required this.displayName,
    required this.entrantType,
    this.uid,
    this.photoUrl,
    this.seed,
    this.memberUids = const [],
    this.withdrawn = false,
  });

  final String id;
  final String displayName;
  final EntrantType entrantType;

  /// Set for individual entrants; null for teams.
  final String? uid;
  final String? photoUrl;

  /// Lower is stronger. Drives knockout bracket placement so the top two
  /// seeds cannot meet before the final.
  final int? seed;

  /// Populated for team entrants.
  final List<String> memberUids;

  final bool withdrawn;

  factory Entrant.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Entrant(
      id: doc.id,
      displayName: Fs.str(d['displayName'], 'Entrant'),
      entrantType: EntrantType.fromWire(Fs.str(d['entrantType'])),
      uid: Fs.strOrNull(d['uid']),
      photoUrl: Fs.strOrNull(d['photoUrl']),
      seed: d['seed'] == null ? null : Fs.integer(d['seed']),
      memberUids: Fs.strList(d['memberUids']),
      withdrawn: Fs.boolean(d['withdrawn']),
    );
  }

  Map<String, Object?> toMap() => {
        'displayName': displayName,
        'entrantType': entrantType.wire,
        'uid': uid,
        'photoUrl': photoUrl,
        'seed': seed,
        'memberUids': memberUids,
        'withdrawn': withdrawn,
      };
}
