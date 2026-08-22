import 'package:cloud_firestore/cloud_firestore.dart';

import 'billing.dart';
import 'coach.dart';
import 'firestore_codec.dart';

/// What kind of practitioner somebody is, at `sportsMedics/{uid}`.
///
/// Five values rather than one free-text "specialty" field, because this is
/// the filter the whole directory turns on: a captain with a swollen ankle on
/// Sunday morning wants a physiotherapist, and a parent holding an MRI report
/// wants an orthopaedic surgeon, and neither should have to guess which of
/// forty free-text job titles means the other one.
///
/// [wire] is stored, never `Enum.name` — see `enums.dart` for why.
enum SportsMedicRole {
  sportsDoctor('sports_doctor', 'Sports Physician'),
  physiotherapist('physiotherapist', 'Physiotherapist'),
  orthopedicSurgeon('orthopedic_surgeon', 'Orthopaedic Surgeon'),
  rehabSpecialist('rehab_specialist', 'Rehab & S&C Specialist'),
  sportsNutritionist('sports_nutritionist', 'Sports Nutritionist');

  const SportsMedicRole(this.wire, this.label);

  final String wire;
  final String label;

  static SportsMedicRole fromWire(String? w) =>
      SportsMedicRole.values.firstWhere(
        (e) => e.wire == w,
        // A physiotherapist is the overwhelming majority of this directory,
        // so an unreadable document degrades to the least surprising row
        // rather than disappearing.
        orElse: () => SportsMedicRole.physiotherapist,
      );
}

/// How a practitioner will actually see somebody.
///
/// [onField] is the one that does not exist on a general medical directory
/// and is the reason this one exists: a tournament needs a physio who will
/// stand at the boundary on match day, which is a different question from
/// "do you have a clinic in Kukatpally".
enum ConsultationMode {
  clinic('clinic', 'At the clinic'),
  online('online', 'Online consult'),
  onField('on_field', 'On-field / match day'),
  homeVisit('home_visit', 'Home visit');

  const ConsultationMode(this.wire, this.label);

  final String wire;
  final String label;

  static ConsultationMode fromWire(String? w) =>
      ConsultationMode.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => ConsultationMode.clinic,
      );

  static List<ConsultationMode> listFromWire(Object? v) => [
        for (final w in Fs.strList(v))
          if (ConsultationMode.values.any((e) => e.wire == w))
            ConsultationMode.fromWire(w),
      ];
}

/// A sports doctor, physiotherapist or surgeon who has listed themselves, at
/// `sportsMedics/{uid}`.
///
/// ## Why this is a second directory and not a [CoachProfile] role
///
/// The obvious economy is a `role` field on the coach listing — both are "a
/// professional publishing a phone number", and both are found by sport and
/// city. It is the wrong economy. A coach listing answers "who will teach my
/// son to bowl"; this one answers "my knee gave way on Saturday, who do I
/// see". The filters differ ([consultationModes], [bodyPartsTreated] against
/// age groups and session formats), the ranking differs, and the duty of care
/// differs — a directory that mixes an unverified cricket coach into the
/// results for "orthopaedic surgeon" is a directory that has misled somebody
/// about a medical decision. Kept separate, each list can say plainly what it
/// is and what PlaySphere has checked.
///
/// ## Why the document id is the uid
///
/// Identical to `CoachProfile`, for identical reasons: one person is one
/// practitioner, "am I listed?" stays a single `get`, the security rule stays
/// `uid() == medicUid`, and nobody can end up in the directory three times by
/// tapping Save three times. A doctor with two clinics lists both in
/// [clinicName] and [address]; they are still one doctor with one
/// registration number and one reputation.
///
/// ## What PlaySphere does and does not assert
///
/// Nothing here is checked except [isVerified], which the client cannot
/// write — `firestore.rules` enforces it. [registrationNumber] is published
/// precisely so it can be checked by somebody else: the NMC and state
/// physiotherapy council registers are public, and a number printed on the
/// page is a claim a patient can verify in a minute. That is worth far more
/// than a badge PlaySphere would have to award by hand.
class SportsMedicProfile {
  const SportsMedicProfile({
    required this.uid,
    required this.displayName,
    required this.role,
    this.photoUrl,
    this.headline,
    this.bio,
    this.qualifications = const [],
    this.registrationNumber,
    this.councilName,
    this.experienceYears = 0,
    this.sportIds = const [],
    this.bodyPartsTreated = const [],
    this.clinicName = '',
    this.city = '',
    this.district,
    this.address,
    this.languages = const [],
    this.consultationModes = const [ConsultationMode.clinic],
    this.consultationFeePaise = 0,
    this.contactPhone,
    this.whatsappPhone,
    this.email,
    this.acceptingNewPatients = true,
    this.isActive = true,
    this.isVerified = false,
    this.createdAt,
  });

  /// Also the document id.
  final String uid;

  /// Copied from the account on every save, never typed — see
  /// `CoachProfile.displayName` for why the copy is deliberate.
  final String displayName;
  final String? photoUrl;

  final SportsMedicRole role;

  /// One line in their own words: "Team physio, Hyderabad Ranji squad".
  final String? headline;
  final String? bio;

  /// "MBBS", "MS Ortho", "MPT (Sports)", "CSCS". Free text rather than an
  /// enum: Indian qualifications differ by council, by state and by decade,
  /// and an enum would need an app release to admit a new one.
  final List<String> qualifications;

  /// NMC / state medical council or state physiotherapy council number.
  ///
  /// Published on purpose. See the class doc: a number a patient can look up
  /// on a public register is stronger than a badge, and the field being
  /// present and empty is itself information.
  final String? registrationNumber;

  /// Which register the number is on — "Telangana State Medical Council".
  final String? councilName;

  final int experienceYears;

  /// Sports they actually work with. Unlike `CoachProfile.sportIds`, an empty
  /// list is meaningful here and is not a defect: a general orthopaedic
  /// surgeon treats the knee regardless of which game tore it, and forcing
  /// them to tick twenty boxes to be findable would be a lie about
  /// specialisation. Empty is shown as "All sports".
  final List<String> sportIds;

  /// Wire values from `BodyPart` in `domain/medical/sports_medicine_library`.
  ///
  /// Held as strings rather than the enum so this model stays free of the
  /// content library — the library is a catalogue that changes with every
  /// release, and a stored document must not depend on the shape it had.
  final List<String> bodyPartsTreated;

  final String clinicName;

  /// Where somebody would actually go. City is the level people search at,
  /// exactly as for grounds and coaches.
  final String city;
  final String? district;
  final String? address;

  /// "Telugu", "Hindi", "English". A consultation in a language the patient
  /// does not speak is not a consultation.
  final List<String> languages;

  final List<ConsultationMode> consultationModes;

  /// Zero means unstated, never free — same rule as `CoachProfile`. Most
  /// clinics quote on the phone and printing "₹0" would promise something
  /// nobody offered.
  final int consultationFeePaise;

  final String? contactPhone;

  /// Separate from [contactPhone] because they are often different numbers —
  /// a clinic landline that is answered and a mobile that takes messages —
  /// and because a person with a suspected fracture at 9pm needs to know
  /// which one is worth trying.
  final String? whatsappPhone;

  final String? email;

  /// Whether they are taking anybody new. A full practice is still worth
  /// finding for next month; one that has left the city is not, and that is
  /// [isActive].
  final bool acceptingNewPatients;

  /// The practitioner's own switch. Delisting rather than deleting, so
  /// somebody on a posting elsewhere can switch back on when they return.
  final bool isActive;

  /// PlaySphere's judgement, never the practitioner's, and unwritable by any
  /// client. What it means is spelled out in words on the detail page: an
  /// identity and a registration number were checked against a public
  /// register. It is not a clinical endorsement and the page says so.
  final bool isVerified;

  final DateTime? createdAt;

  String get cityKey => city.trim().toLowerCase();

  bool treats(String sportId) =>
      sportIds.isEmpty || sportIds.contains(sportId);

  bool offers(ConsultationMode mode) => consultationModes.contains(mode);

  bool get isFree => consultationFeePaise == 0;

  /// "₹600 consult", or "Fee on request" when none was published.
  String get feeLabel => isFree
      ? 'Fee on request'
      : '${Pricing.formatPaise(consultationFeePaise)} consult';

  /// The line under the name in the directory: what they are, and where.
  String get subtitleLine => [
        role.label,
        if (clinicName.isNotEmpty) clinicName,
        if (city.isNotEmpty) city,
      ].join('  ·  ');

  /// Every word this practitioner should be findable by.
  ///
  /// Same mechanism as `CoachProfile` and `Ground`, and literally the same
  /// function as the first of them, for the reason given there: Firestore has
  /// no full-text index, so the words must be on the document to be queryable
  /// at all. `CoachProfile.tokenize` is called rather than copied because
  /// there are already two copies of it in this package and a third would be
  /// a third thing to fix the day one of them learns to split `table_tennis`.
  List<String> get searchTokens => CoachProfile.tokenize([
        displayName,
        clinicName,
        city,
        district,
        headline,
        role.label,
        councilName,
        ...qualifications,
        ...sportIds,
        ...bodyPartsTreated,
        ...languages,
      ]);

  /// Splits something typed into a search box into the same words the
  /// stored [searchTokens] were built from.
  ///
  /// Exposed here rather than having the repository reach for
  /// `CoachProfile.tokenize` directly, so that if this directory ever needs a
  /// tokenizer of its own — medical terms hyphenate differently — there is
  /// one place to change and the query and the stored array cannot disagree.
  static List<String> tokenizeQuery(String raw) =>
      CoachProfile.tokenize([raw]);

  factory SportsMedicProfile.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const {};
    return SportsMedicProfile(
      uid: doc.id,
      displayName: Fs.str(d['displayName'], 'Practitioner'),
      photoUrl: Fs.strOrNull(d['photoUrl']),
      role: SportsMedicRole.fromWire(Fs.strOrNull(d['role'])),
      headline: Fs.strOrNull(d['headline']),
      bio: Fs.strOrNull(d['bio']),
      qualifications: Fs.strList(d['qualifications']),
      registrationNumber: Fs.strOrNull(d['registrationNumber']),
      councilName: Fs.strOrNull(d['councilName']),
      experienceYears: Fs.integer(d['experienceYears']),
      sportIds: Fs.strList(d['sportIds']),
      bodyPartsTreated: Fs.strList(d['bodyPartsTreated']),
      clinicName: Fs.str(d['clinicName']),
      city: Fs.str(d['city']),
      district: Fs.strOrNull(d['district']),
      address: Fs.strOrNull(d['address']),
      languages: Fs.strList(d['languages']),
      consultationModes: () {
        final modes = ConsultationMode.listFromWire(d['consultationModes']);
        // Never an empty list: a practitioner who offers no way to be seen
        // is a row somebody taps and cannot act on. The clinic is the
        // assumption every one of these listings starts from.
        return modes.isEmpty ? const [ConsultationMode.clinic] : modes;
      }(),
      consultationFeePaise: Fs.integer(d['consultationFeePaise']),
      contactPhone: Fs.strOrNull(d['contactPhone']),
      whatsappPhone: Fs.strOrNull(d['whatsappPhone']),
      email: Fs.strOrNull(d['email']),
      acceptingNewPatients: Fs.boolean(d['acceptingNewPatients'], true),
      isActive: Fs.boolean(d['isActive'], true),
      isVerified: Fs.boolean(d['isVerified']),
      createdAt: Fs.dateOrNull(d['createdAt']),
    );
  }

  Map<String, Object?> toCreate() => {
        ...toUpdate(),
        // Spelled out rather than omitted, so the intent survives somebody
        // later tidying the map: neither is the client's to set, and the
        // rules refuse the write if either is wrong.
        'isVerified': false,
        'createdAt': FieldValue.serverTimestamp(),
      };

  /// Everything the practitioner may edit. Excludes [isVerified] and
  /// [createdAt].
  Map<String, Object?> toUpdate() => {
        'displayName': displayName,
        'photoUrl': photoUrl,
        'role': role.wire,
        'headline': headline,
        'bio': bio,
        'qualifications': qualifications,
        'registrationNumber': registrationNumber,
        'councilName': councilName,
        'experienceYears': experienceYears,
        'sportIds': sportIds,
        'bodyPartsTreated': bodyPartsTreated,
        'clinicName': clinicName.trim(),
        'city': city.trim(),
        'cityKey': cityKey,
        'district': district,
        'address': address,
        'languages': languages,
        'consultationModes': [
          for (final m in consultationModes) m.wire,
        ],
        'consultationFeePaise': consultationFeePaise,
        'contactPhone': contactPhone,
        'whatsappPhone': whatsappPhone,
        'email': email,
        'acceptingNewPatients': acceptingNewPatients,
        'isActive': isActive,
        // Recomputed on every write, never entered — a profile edited to add
        // a sport has to become findable by it in the same save.
        'searchTokens': searchTokens,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  SportsMedicProfile copyWith({
    String? displayName,
    String? photoUrl,
    SportsMedicRole? role,
    String? headline,
    String? bio,
    List<String>? qualifications,
    String? registrationNumber,
    String? councilName,
    int? experienceYears,
    List<String>? sportIds,
    List<String>? bodyPartsTreated,
    String? clinicName,
    String? city,
    String? district,
    String? address,
    List<String>? languages,
    List<ConsultationMode>? consultationModes,
    int? consultationFeePaise,
    String? contactPhone,
    String? whatsappPhone,
    String? email,
    bool? acceptingNewPatients,
    bool? isActive,
  }) =>
      SportsMedicProfile(
        uid: uid,
        displayName: displayName ?? this.displayName,
        photoUrl: photoUrl ?? this.photoUrl,
        role: role ?? this.role,
        headline: headline ?? this.headline,
        bio: bio ?? this.bio,
        qualifications: qualifications ?? this.qualifications,
        registrationNumber: registrationNumber ?? this.registrationNumber,
        councilName: councilName ?? this.councilName,
        experienceYears: experienceYears ?? this.experienceYears,
        sportIds: sportIds ?? this.sportIds,
        bodyPartsTreated: bodyPartsTreated ?? this.bodyPartsTreated,
        clinicName: clinicName ?? this.clinicName,
        city: city ?? this.city,
        district: district ?? this.district,
        address: address ?? this.address,
        languages: languages ?? this.languages,
        consultationModes: consultationModes ?? this.consultationModes,
        consultationFeePaise: consultationFeePaise ?? this.consultationFeePaise,
        contactPhone: contactPhone ?? this.contactPhone,
        whatsappPhone: whatsappPhone ?? this.whatsappPhone,
        email: email ?? this.email,
        acceptingNewPatients:
            acceptingNewPatients ?? this.acceptingNewPatients,
        isActive: isActive ?? this.isActive,
        isVerified: isVerified,
        createdAt: createdAt,
      );
}
