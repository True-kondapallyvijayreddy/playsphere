import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../text/ordinal.dart';
import 'billing.dart';
import 'enums.dart';
import 'firestore_codec.dart';
import 'geo.dart';

/// A tenant: a residential community, school, college, academy, club,
/// district association or state council. Stored at `orgs/{orgId}`.
///
/// Orgs form a tree via [parentOrgId] so a district association can sit above
/// the schools inside it, which is what lets a result earned at school level
/// be promoted into a district competition later.
class Organization {
  const Organization({
    required this.id,
    required this.name,
    required this.orgType,
    required this.visibility,
    required this.ownerUid,
    this.ownerUids = const [],
    required this.inviteCode,
    this.parentOrgId,
    this.description,
    this.district,
    this.city,
    this.geo = GeoLocation.empty,
    this.logoUrl,
    this.memberCount = 0,
    this.homeGroundId,
    this.homeGroundName,
    this.requiresApprovalToJoin = true,
    this.plan = OrgPlan.free,
    this.planState = PlanState.none,
    this.createdBy,
    this.createdAt,
    this.deletedAt,
  });

  final String id;
  final String name;
  final OrgType orgType;
  final OrgVisibility visibility;

  /// Exactly one primary owner uid lives here.
  final String ownerUid;

  /// Feature #3: Multi-owner list for organizations.
  final List<String> ownerUids;

  /// Returns whether [uid] is a primary or co-owner of this club.
  bool isOwner(String uid) => uid == ownerUid || ownerUids.contains(uid);

  /// Short human-shareable code. A coach reads it out in a WhatsApp group and
  /// players join without needing to be found by search.
  final String inviteCode;

  final String? parentOrgId;
  final String? description;

  /// Legacy flat location fields, kept and still written verbatim so any
  /// screen still reading `org.district`/`org.city` directly keeps working.
  /// [geo] is the field to prefer for anything gov-aggregate related — see
  /// its doc comment for how the two are reconciled on read.
  final String? district;
  final String? city;

  /// State → district → mandal → village, feeding `lib/domain/gov/`. Parsed
  /// with a fallback to [district]/[city] on [fromDoc] so a pre-existing org
  /// document (which has never had a `geo` map) still reports a location
  /// instead of silently dropping off the map the moment this shipped.
  final GeoLocation geo;

  final String? logoUrl;
  final int memberCount;

  /// The club's own ground — where its matches are actually played,
  /// distinct from a [Ground] booked one-off through the marketplace.
  ///
  /// Settable and changeable at any time by whoever can manage the
  /// organization, not just at creation, because a club's ground changes far
  /// less often than its roster but does change: a lease ends, a school gets
  /// a new court. Two fields rather than one, deliberately:
  /// [homeGroundId] links to a real `Ground` document when the club's ground
  /// is registered in the marketplace (so the profile can show its rate,
  /// hours and booking calendar); [homeGroundName] is a free-text fallback
  /// for the common case — a school hall, a village maidan — that will never
  /// be a bookable marketplace listing but is still worth naming on the
  /// club's own profile.
  final String? homeGroundId;
  final String? homeGroundName;

  bool get hasHomeGround =>
      (homeGroundId != null && homeGroundId!.isNotEmpty) ||
      (homeGroundName != null && homeGroundName!.trim().isNotEmpty);

  /// When false, anyone with the invite code becomes active immediately.
  /// Schools generally want this true; a casual apartment community usually
  /// does not, and forcing approval there just means nobody ever gets let in.
  final bool requiresApprovalToJoin;

  /// What this club has bought. Defaults to [OrgPlan.free], which is also
  /// what every club created before plans existed reads back as.
  final OrgPlan plan;

  /// When that plan was activated and when it lapses. See [PlanState] for why
  /// this lives on the org document rather than in a collection of its own.
  final PlanState planState;

  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;
  bool get isPublic => visibility == OrgVisibility.public;

  /// Whether the club's paid entitlement is live at [asOf].
  ///
  /// A lapsed plan is deliberately not a lockout — see [OrgPlan.free]. This
  /// answers "should we show the renewal prompt and the paid-only extras",
  /// never "may this club keep running its matches".
  bool hasPaidPlanAt(DateTime asOf) =>
      plan.rank >= OrgPlan.club.rank && planState.isActiveAt(asOf);

  factory Organization.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Organization(
      id: doc.id,
      name: Fs.str(d['name'], 'Unnamed organization'),
      orgType: OrgType.fromWire(Fs.str(d['orgType'])),
      visibility: OrgVisibility.fromWire(Fs.str(d['visibility'])),
      ownerUid: Fs.str(d['ownerUid']),
      ownerUids: Fs.strList(d['ownerUids']),
      inviteCode: Fs.str(d['inviteCode']),
      parentOrgId: Fs.strOrNull(d['parentOrgId']),
      description: Fs.strOrNull(d['description']),
      district: Fs.strOrNull(d['district']),
      city: Fs.strOrNull(d['city']),
      geo: GeoLocation.fromDocData(
        d,
        legacyDistrictKey: 'district',
        legacyVillageKey: 'city',
      ),
      logoUrl: Fs.strOrNull(d['logoUrl']),
      memberCount: Fs.integer(d['memberCount']),
      homeGroundId: Fs.strOrNull(d['homeGroundId']),
      homeGroundName: Fs.strOrNull(d['homeGroundName']),
      requiresApprovalToJoin: Fs.boolean(d['requiresApprovalToJoin'], true),
      plan: OrgPlan.fromWire(Fs.str(d['plan'])),
      planState: PlanState.fromDocData(
        d,
        activatedKey: 'planActivatedAt',
        validUntilKey: 'planValidUntil',
        lastPaymentKey: 'planPaymentId',
      ),
      createdBy: Fs.strOrNull(d['createdBy']),
      createdAt: Fs.dateOrNull(d['createdAt']),
      deletedAt: Fs.dateOrNull(d['deletedAt']),
    );
  }

  Map<String, Object?> toCreate() => {
        'name': name,
        'nameLower': name.toLowerCase(),
        'orgType': orgType.wire,
        'visibility': visibility.wire,
        'ownerUid': ownerUid,
        'inviteCode': inviteCode,
        'parentOrgId': parentOrgId,
        'description': description,
        'district': district,
        'city': city,
        'geo': geo.toMap(),
        'logoUrl': logoUrl,
        'memberCount': 1,
        'requiresApprovalToJoin': requiresApprovalToJoin,
        'plan': plan.wire,
        'planActivatedAt': Fs.ts(planState.activatedAt),
        'planValidUntil': Fs.ts(planState.validUntil),
        'planPaymentId': planState.lastPaymentId,
        'createdBy': ownerUid,
        'createdAt': FieldValue.serverTimestamp(),
        'deletedAt': null,
      };

  /// Deliberately carries no plan fields.
  ///
  /// This is what the club-settings form writes, and a club editing its own
  /// name must not be able to hand itself a paid plan in the same call. The
  /// entitlement is only ever written by `BillingRepository`, alongside the
  /// ledger row that justifies it, and `firestore.rules` enforces the same
  /// separation independently.
  Map<String, Object?> toUpdate() => Fs.prune({
        'name': name,
        'nameLower': name.toLowerCase(),
        'description': description,
        'district': district,
        'city': city,
        'geo': geo.toMap(),
        'logoUrl': logoUrl,
        'requiresApprovalToJoin': requiresApprovalToJoin,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// Six characters from an alphabet with no `0/O`, `1/I/L` — codes get read
  /// aloud and copied off whiteboards, and those pairs are where it goes
  /// wrong.
  /// The club's public identifier — what a member reads out, puts on a
  /// poster, or pastes into a WhatsApp group to say which club they mean.
  ///
  /// ## Why this is not the document id
  ///
  /// `orgs/{orgId}` holds a twenty-character Firestore auto-id. It is stable
  /// and unique and completely unusable as something a person says out loud,
  /// and putting it on screen would make an implementation detail into the
  /// name of the club. This is a short, ambiguity-free rendering of it —
  /// stable for exactly as long as the club exists, because it is a pure
  /// function of an id that never changes.
  ///
  /// ## Why it is not the invite code either
  ///
  /// [inviteCode] is a key: typing it into "join a club" starts a membership,
  /// and in a club with `requiresApprovalToJoin: false` it completes one. It
  /// is therefore an admin's to hand out, and the app has always treated it
  /// that way. This grants nothing at all. That difference is what lets it be
  /// shown to every member of every club — which is the point, because the
  /// person most likely to promote a club is an ordinary member of it, and
  /// until now they had no way to say which club they meant.
  ///
  /// ## Why it is derived rather than stored
  ///
  /// A stored random code would need writing to every club that already
  /// exists before a single member could see one, and members cannot write to
  /// their club's document. Deriving it means every club — including every
  /// club created before this existed — has its id the moment this ships, and
  /// the same id on every device, with no migration and nothing to keep in
  /// step.
  ///
  /// The trade is that it cannot be *chosen*: a club cannot ask for
  /// `HYDCC-01`. A vanity code is a stored field and a uniqueness check, and
  /// is a strictly later change than this one.
  String get clubCode => codeForId(id);

  /// Grouped for reading aloud — `4K7X-Q2M9` rather than `4K7XQ2M9`. The same
  /// reason card numbers are grouped: nobody reads eight characters back
  /// correctly in one run.
  String get clubCodeLabel =>
      '${clubCode.substring(0, 4)}-${clubCode.substring(4)}';

  /// Hashes a document id into an eight-character public code.
  ///
  /// ## Why two small hashes rather than one big one
  ///
  /// This has to produce the SAME code on a phone and in a browser, or a
  /// member reading their club's id off the web app and a member reading it
  /// off Android are quoting different clubs. Dart's `int` is 64-bit on the
  /// VM and a 53-bit double under dart2js, so the obvious 64-bit FNV-1a —
  /// multiply, mask to 64 bits, repeat — silently loses precision on the web
  /// and diverges. Masking does not save it: the precision is gone before the
  /// mask runs.
  ///
  /// So every intermediate here stays under 2^53, which is exact on both.
  /// Each pass keeps 31 bits, and two passes with different multipliers give
  /// about 62 bits between them — enough that a collision across any
  /// plausible number of clubs is negligible, where one 31-bit pass would put
  /// a duplicate somewhere in the list at a few thousand.
  ///
  /// Eight characters rather than the invite code's six for the same reason.
  /// Two clubs sharing a code is only cosmetic today — sharing a club sends a
  /// link, not a code — but it would be a real bug the day anything looks a
  /// club up by one.
  static String codeForId(String docId) {
    if (docId.isEmpty) return '--------';
    // The invite code's alphabet: no O/0, no I/1/L, nothing that gets read
    // back wrong over a phone.
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

    // 31 and 131 rather than one multiplier used twice: the same multiplier
    // would make the second pass a function of the first and buy no entropy.
    // Masked to 31 bits so `hash * multiplier` never approaches 2^53.
    int pass(int multiplier) {
      var hash = multiplier;
      for (final unit in docId.codeUnits) {
        hash = (hash * multiplier + unit) & 0x7FFFFFFF;
      }
      return hash;
    }

    final out = StringBuffer();
    for (var hash in [pass(31), pass(131)]) {
      for (var i = 0; i < 4; i++) {
        out.write(alphabet[hash % alphabet.length]);
        hash = hash ~/ alphabet.length;
      }
    }
    return out.toString();
  }

  static String generateInviteCode([Random? random]) {
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final rng = random ?? Random.secure();
    return List.generate(6, (_) => alphabet[rng.nextInt(alphabet.length)])
        .join();
  }

  Organization copyWith({
    String? name,
    String? description,
    String? district,
    String? city,
    GeoLocation? geo,
    String? logoUrl,
    bool? requiresApprovalToJoin,
    OrgVisibility? visibility,
  }) {
    return Organization(
      id: id,
      name: name ?? this.name,
      orgType: orgType,
      visibility: visibility ?? this.visibility,
      ownerUid: ownerUid,
      inviteCode: inviteCode,
      parentOrgId: parentOrgId,
      description: description ?? this.description,
      district: district ?? this.district,
      city: city ?? this.city,
      geo: geo ?? this.geo,
      logoUrl: logoUrl ?? this.logoUrl,
      memberCount: memberCount,
      // Not settable through copyWith — see [OrgRepository.setHomeGround],
      // the dedicated write path. Carried through verbatim so a profile-form
      // save (which goes through copyWith) can never silently erase it.
      homeGroundId: homeGroundId,
      homeGroundName: homeGroundName,
      requiresApprovalToJoin:
          requiresApprovalToJoin ?? this.requiresApprovalToJoin,
      plan: plan,
      planState: planState,
      createdBy: createdBy,
      createdAt: createdAt,
      deletedAt: deletedAt,
    );
  }
}

/// What an invite code resolves to, at `inviteCodes/{CODE}`.
///
/// Deliberately a separate, tiny, publicly-gettable document rather than a
/// query over `orgs`. An unlisted club is unreadable to someone who is not yet
/// a member, so a query could never resolve a code for exactly the people the
/// code was given to. This carries only what the join card needs to show.
class InviteTarget {
  const InviteTarget({
    required this.code,
    required this.orgId,
    required this.orgName,
    required this.orgType,
    required this.requiresApprovalToJoin,
    this.city,
  });

  final String code;
  final String orgId;
  final String orgName;
  final OrgType orgType;

  /// Drives what the join button says and whether membership is immediate.
  final bool requiresApprovalToJoin;

  final String? city;

  factory InviteTarget.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return InviteTarget(
      code: doc.id,
      orgId: Fs.str(d['orgId']),
      orgName: Fs.str(d['orgName'], 'Unnamed organization'),
      orgType: OrgType.fromWire(Fs.str(d['orgType'])),
      requiresApprovalToJoin: Fs.boolean(d['requiresApprovalToJoin'], true),
      city: Fs.strOrNull(d['city']),
    );
  }

  static Map<String, Object?> payload({
    required String code,
    required String orgId,
    required Organization org,
  }) =>
      {
        'code': code,
        'orgId': orgId,
        'orgName': org.name,
        'orgType': org.orgType.wire,
        'requiresApprovalToJoin': org.requiresApprovalToJoin,
        'city': org.city,
        'createdAt': FieldValue.serverTimestamp(),
      };
}

/// What a club knows about where one of its members sits INSIDE it — their
/// house, department, year, class, section.
///
/// ## Why this is on the membership and not on the person
///
/// "ECE — 3rd Year" is not a fact about a human being. It is a fact about that
/// human being's relationship to one college, and it stops being true when
/// they graduate, and it was never true at the cricket club they also play
/// for. Putting `department` on [AppUser] would make one institution's filing
/// system into a permanent property of a person's portable record, and would
/// make it visible to — and editable by — every other club they join.
///
/// So it lives at `orgs/{orgId}/members/{uid}`, which makes club-scoping
/// structural rather than a rule anyone has to remember: a member of two clubs
/// has two independent groupings, and an outside entrant on an open event has
/// none at all, so nothing here can ever place them into somebody else's
/// house.
///
/// ## Why five fields and not one free-text tag
///
/// The whole point is to be able to GENERATE the house a student belongs in
/// and match it against the list the organizer authored — see `HouseAssigner`.
/// A single tag can only ever be compared for equality against exactly the
/// naming convention it was typed in. Structured fields can be rendered into
/// whichever convention this particular event chose, so one roster serves an
/// inter-department meet, an inter-year meet and an inter-house meet without
/// being re-entered three times.
///
/// Every field is optional. A club that never fills any of it in is exactly
/// the club that was fine before this existed.
class MemberGrouping {
  const MemberGrouping({
    this.house,
    this.department,
    this.year,
    this.grade,
    this.section,
  });

  static const MemberGrouping empty = MemberGrouping();

  /// The named house a school splits into — "Red House", "Gandhi House".
  final String? house;

  /// Department or stream — "ECE", "CSE", "Commerce".
  final String? department;

  /// Year of study, as a number so it can be rendered "3rd Year" in whatever
  /// form the event's house list uses.
  final int? year;

  /// Class or grade for a school — "Class 8".
  final String? grade;

  /// Section within that class — "A".
  final String? section;

  bool get isEmpty =>
      house == null &&
      department == null &&
      year == null &&
      grade == null &&
      section == null;

  bool get isNotEmpty => !isEmpty;

  /// A short human line for the roster — "ECE · 3rd Year · Red House".
  String get summary => [
        if (department != null) department!,
        if (grade != null) grade!,
        if (section != null && grade == null) 'Section $section',
        if (year != null) '${ordinal(year!)} Year',
        if (house != null) house!,
      ].join(' · ');

  MemberGrouping copyWith({
    String? house,
    String? department,
    int? year,
    String? grade,
    String? section,
    bool clearHouse = false,
    bool clearDepartment = false,
    bool clearYear = false,
    bool clearGrade = false,
    bool clearSection = false,
  }) =>
      MemberGrouping(
        house: clearHouse ? null : (house ?? this.house),
        department: clearDepartment ? null : (department ?? this.department),
        year: clearYear ? null : (year ?? this.year),
        grade: clearGrade ? null : (grade ?? this.grade),
        section: clearSection ? null : (section ?? this.section),
      );

  factory MemberGrouping.fromMap(Map<String, dynamic> d) => MemberGrouping(
        house: Fs.strOrNull(d['house']),
        department: Fs.strOrNull(d['department']),
        year: d['year'] == null ? null : Fs.integer(d['year']),
        grade: Fs.strOrNull(d['grade']),
        section: Fs.strOrNull(d['section']),
      );

  Map<String, Object?> toMap() => {
        'house': house,
        'department': department,
        'year': year,
        'grade': grade,
        'section': section,
      };
}

/// A person's role inside one organization, at `orgs/{orgId}/members/{uid}`.
///
/// The document id is the uid, which makes "one membership per person per
/// org" a structural guarantee rather than something a query has to police.
class Membership {
  const Membership({
    required this.uid,
    required this.orgId,
    required this.role,
    required this.status,
    required this.displayName,
    this.photoUrl,
    this.joinedAt,
    this.invitedBy,
    this.approvedBy,
    this.jerseyNumber,
    this.notes,
    this.grouping = MemberGrouping.empty,
  });

  final String uid;
  final String orgId;
  final MembershipRole role;
  final MembershipStatus status;

  /// Denormalized from the user profile so a roster list renders from a
  /// single query instead of N profile fetches. Refreshed on approval.
  final String displayName;
  final String? photoUrl;

  final DateTime? joinedAt;
  final String? invitedBy;
  final String? approvedBy;
  final String? jerseyNumber;
  final String? notes;

  /// Where this member sits inside this club — see [MemberGrouping]. Empty
  /// for every club that does not split its roster, which is most of them.
  final MemberGrouping grouping;

  bool get isActive => status == MembershipStatus.active;
  bool get isPending => status == MembershipStatus.pending;

  factory Membership.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Membership(
      uid: doc.id,
      orgId: Fs.str(d['orgId']),
      role: MembershipRole.fromWire(Fs.str(d['role'])),
      status: MembershipStatus.fromWire(Fs.str(d['status'])),
      displayName: Fs.str(d['displayName'], 'Member'),
      photoUrl: Fs.strOrNull(d['photoUrl']),
      joinedAt: Fs.dateOrNull(d['joinedAt']),
      invitedBy: Fs.strOrNull(d['invitedBy']),
      approvedBy: Fs.strOrNull(d['approvedBy']),
      jerseyNumber: Fs.strOrNull(d['jerseyNumber']),
      notes: Fs.strOrNull(d['notes']),
      grouping: MemberGrouping.fromMap(Fs.map(d['grouping'])),
    );
  }

  Map<String, Object?> toCreate() => {
        'uid': uid,
        'orgId': orgId,
        'role': role.wire,
        'status': status.wire,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'joinedAt': FieldValue.serverTimestamp(),
        'invitedBy': invitedBy,
        'approvedBy': approvedBy,
      };
}
