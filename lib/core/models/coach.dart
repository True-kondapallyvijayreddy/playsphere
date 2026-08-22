import 'package:cloud_firestore/cloud_firestore.dart';

import 'billing.dart';
import 'firestore_codec.dart';

/// Somebody who teaches a sport, at `coaches/{uid}`.
///
/// ## Why the document id is the coach's uid
///
/// A person is one coach. Keying by uid makes "am I listed?" a single `get`
/// rather than a query, makes the security rule the shortest one in the file
/// (`uid() == coachUid`), and makes it impossible to end up with the same
/// person listed three times under three ids — which is what a generated id
/// would have allowed the first time somebody tapped Save twice.
///
/// The cost is that a coach cannot hold two separate listings, one for
/// cricket and one for athletics. That is the right trade: they are the same
/// person with the same phone number and the same reputation, and [sportIds]
/// already says they teach both.
///
/// ## Why this is not a club role
///
/// The obvious modelling is `MembershipRole.coach` on a club membership. It
/// is wrong for the country this is built for. Most coaches in India are
/// independent — a man who takes twelve boys for cricket at 6am on a
/// municipal ground belongs to no club, and under a role-based model he does
/// not exist. `MembershipRole` is also an authority ladder (`rank`), and
/// coaching is not a permission level: a coach does not need to approve
/// members or manage competitions, and giving them a rung on that ladder to
/// make them findable would grant powers to describe a job.
///
/// A coach who DOES work for a club is a member of it as well; the two facts
/// are independent and both true.
///
/// ## Why it is self-declared
///
/// Nothing here is verified except [isVerified], which PlaySphere sets and
/// the client cannot write. A directory that only listed credential-checked
/// coaches would have launched empty and stayed that way. What the product
/// owes a parent instead is honesty about which is which — see the badge on
/// `CoachCard` — plus [yearsExperience] and [certifications] as claims
/// attributed to the coach, never as facts asserted by PlaySphere.
class CoachProfile {
  const CoachProfile({
    required this.uid,
    required this.displayName,
    required this.sportIds,
    this.photoUrl,
    this.headline,
    this.bio,
    this.city = '',
    this.district,
    this.yearsExperience = 0,
    this.certifications = const [],
    this.ageGroups = const [],
    this.formats = const [],
    this.sessionRatePaise = 0,
    this.acceptingStudents = true,
    this.contactPhone,
    this.isActive = true,
    this.isVerified = false,
    this.createdAt,
  });

  /// Also the document id.
  final String uid;

  /// Copied from the user's profile on every save.
  ///
  /// Denormalized on purpose. A directory of forty coaches would otherwise
  /// cost forty `users/{uid}` reads to render forty names, and half of those
  /// reads would be refused for a coach whose own profile is private — which
  /// would blank out the name on a listing the coach deliberately published.
  /// The copy goes stale if somebody renames themselves and never edits their
  /// listing; a stale display name is a far smaller problem than a directory
  /// that cannot show names at all.
  final String displayName;
  final String? photoUrl;

  /// What they teach. At least one, enforced in the rules — a coach listing
  /// with no sport cannot be found by anybody looking for a coach.
  ///
  /// Unlike `Ground.sportIds`, an empty list is not "all sports". A maidan
  /// really does host anything; a person who claims to coach every sport in
  /// the catalog is not making a claim worth indexing.
  final List<String> sportIds;

  /// One line, the way a coach would introduce themselves — "Ex-Ranji seamer,
  /// twelve years with junior sides". Shown in the directory row, so it is
  /// the field that decides whether anybody taps.
  final String? headline;

  final String? bio;

  /// Where they actually take sessions. City is the level people search at,
  /// exactly as it is for a ground.
  final String city;
  final String? district;

  /// Claimed, not verified. Zero means unstated rather than "brand new" —
  /// the UI omits the line rather than printing "0 years".
  final int yearsExperience;

  /// "NIS Patiala", "BCCI Level 1", "World Rugby Level 2". Free text for the
  /// same reason `Ground.facilities` is: the meaningful credential differs by
  /// sport and by decade, and a fixed enum would need a release to add one.
  final List<String> certifications;

  /// "U12", "U16", "Seniors", "Beginners". Who they take, in their words.
  final List<String> ageGroups;

  /// "One-to-one", "Group", "Online", "Residential camp".
  final List<String> formats;

  /// Per session, in paise. Zero means unstated — a great many coaches settle
  /// a monthly fee in conversation and will not publish a number, and forcing
  /// one would either be a lie or keep them off the directory.
  final int sessionRatePaise;

  /// Whether they are taking anybody new right now.
  ///
  /// Separate from [isActive] because they mean different things to a parent
  /// reading the page. A full coach is still worth finding, still worth
  /// contacting for next season, and still the answer to "who coaches high
  /// jump in Warangal". A coach who has left the district is not.
  final bool acceptingStudents;

  final String? contactPhone;

  /// The coach's own switch. Turning it off delists them without destroying
  /// the profile, so somebody taking a season out can come back to it.
  final bool isActive;

  /// PlaySphere's judgement, never the coach's, and `firestore.rules`
  /// enforces that a client cannot write it. A coach who could tick their own
  /// verified box makes the badge worth nothing, which matters more here than
  /// anywhere else in the product: this is the one directory where a parent
  /// hands over a child on the strength of a listing.
  final bool isVerified;

  final DateTime? createdAt;

  String get cityKey => city.trim().toLowerCase();

  bool coaches(String sportId) => sportIds.contains(sportId);

  bool get isFree => sessionRatePaise == 0;

  /// "₹500/session", or "Rate on request" when none was published — never
  /// "₹0", which reads as a promise of free coaching nobody made.
  String get rateLabel => isFree
      ? 'Rate on request'
      : '${Pricing.formatPaise(sessionRatePaise)}/session';

  /// Every word this coach should be findable by.
  ///
  /// Same mechanism as `Ground.searchTokens`, and deliberately the same
  /// function — Firestore has no full-text search, so the words have to be on
  /// the document to be queryable at all, and a second hand-rolled tokenizer
  /// would drift from the first the day one of them learned to split
  /// `table_tennis`.
  List<String> get searchTokens => tokenize([
        displayName,
        city,
        district,
        headline,
        ...sportIds,
        ...certifications,
        ...ageGroups,
        ...formats,
      ]);

  /// Splits free text into searchable words. See `Ground.tokenize`, whose
  /// rules this follows exactly: words of one character are dropped because
  /// they match nearly every document, and the list is capped because it is
  /// written to every profile and read back by every search.
  static List<String> tokenize(Iterable<String?> parts, {int cap = 40}) {
    final out = <String>{};
    for (final part in parts) {
      if (part == null) continue;
      for (final raw in part.toLowerCase().split(RegExp(r'[^a-z0-9]+'))) {
        if (raw.length < 2) continue;
        out.add(raw);
        if (out.length >= cap) return out.toList();
      }
    }
    return out.toList();
  }

  factory CoachProfile.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return CoachProfile(
      uid: doc.id,
      displayName: Fs.str(d['displayName'], 'Coach'),
      photoUrl: Fs.strOrNull(d['photoUrl']),
      sportIds: Fs.strList(d['sportIds']),
      headline: Fs.strOrNull(d['headline']),
      bio: Fs.strOrNull(d['bio']),
      city: Fs.str(d['city']),
      district: Fs.strOrNull(d['district']),
      yearsExperience: Fs.integer(d['yearsExperience']),
      certifications: Fs.strList(d['certifications']),
      ageGroups: Fs.strList(d['ageGroups']),
      formats: Fs.strList(d['formats']),
      sessionRatePaise: Fs.integer(d['sessionRatePaise']),
      acceptingStudents: Fs.boolean(d['acceptingStudents'], true),
      contactPhone: Fs.strOrNull(d['contactPhone']),
      isActive: Fs.boolean(d['isActive'], true),
      isVerified: Fs.boolean(d['isVerified']),
      createdAt: Fs.dateOrNull(d['createdAt']),
    );
  }

  Map<String, Object?> toCreate() => {
        ...toUpdate(),
        // Listed explicitly rather than left out, so the intent survives
        // somebody later tidying up the create map: neither of these is the
        // client's to set.
        'isVerified': false,
        'createdAt': FieldValue.serverTimestamp(),
      };

  /// Everything the coach may edit. Excludes [isVerified] and [createdAt].
  Map<String, Object?> toUpdate() => {
        'displayName': displayName,
        'photoUrl': photoUrl,
        'sportIds': sportIds,
        'headline': headline,
        'bio': bio,
        'city': city.trim(),
        'cityKey': cityKey,
        // Recomputed on every write, never entered. A profile edited to add a
        // sport has to become findable by it in the same save.
        'searchTokens': searchTokens,
        'district': district,
        'yearsExperience': yearsExperience,
        'certifications': certifications,
        'ageGroups': ageGroups,
        'formats': formats,
        'sessionRatePaise': sessionRatePaise,
        'acceptingStudents': acceptingStudents,
        'contactPhone': contactPhone,
        'isActive': isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  CoachProfile copyWith({
    String? displayName,
    String? photoUrl,
    List<String>? sportIds,
    String? headline,
    String? bio,
    String? city,
    String? district,
    int? yearsExperience,
    List<String>? certifications,
    List<String>? ageGroups,
    List<String>? formats,
    int? sessionRatePaise,
    bool? acceptingStudents,
    String? contactPhone,
    bool? isActive,
  }) =>
      CoachProfile(
        uid: uid,
        displayName: displayName ?? this.displayName,
        photoUrl: photoUrl ?? this.photoUrl,
        sportIds: sportIds ?? this.sportIds,
        headline: headline ?? this.headline,
        bio: bio ?? this.bio,
        city: city ?? this.city,
        district: district ?? this.district,
        yearsExperience: yearsExperience ?? this.yearsExperience,
        certifications: certifications ?? this.certifications,
        ageGroups: ageGroups ?? this.ageGroups,
        formats: formats ?? this.formats,
        sessionRatePaise: sessionRatePaise ?? this.sessionRatePaise,
        acceptingStudents: acceptingStudents ?? this.acceptingStudents,
        contactPhone: contactPhone ?? this.contactPhone,
        isActive: isActive ?? this.isActive,
        isVerified: isVerified,
        createdAt: createdAt,
      );
}
