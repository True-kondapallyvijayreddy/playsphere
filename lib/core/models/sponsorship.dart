import 'package:cloud_firestore/cloud_firestore.dart';

import 'enums.dart';
import 'firestore_codec.dart';
import 'geo.dart';

/// Sponsor an Athlete / Sponsor a Team — a direct, named, ongoing backing
/// relationship, at `sponsorshipListings/{listingId}`.
///
/// ## Why this is not another `GiveNeed`
///
/// `lib/core/models/give_need.dart` already models "a verified shortfall a
/// donor can act on" — and looks, at a glance, like the same idea. It is not:
/// Give is anonymous and one-off (a shoe donation matched against a
/// shortfall, no relationship afterwards); Sponsor is attributed and ongoing
/// (a named sponsor backs a named athlete or team, gets credited on their
/// public profile, and the relationship is visible to both sides for as long
/// as it lasts). Collapsing the two into one model would either strip Give of
/// its anonymity-by-default posture or strip Sponsor of the recognition that
/// is the entire point of the feature — see §17 of the product vision, which
/// draws this line explicitly: "Donate: I want to help sports generally" vs.
/// "Sponsor: I specifically want to support this athlete/team."
///
/// ## Privacy — what this document deliberately does not carry
///
/// A listing is discoverable (world-readable, like `GiveNeed`) so a sponsor
/// can find it before any relationship exists. It therefore never carries a
/// phone number, an exact address, or a birth date — a sponsor's interest
/// reaches the subject through [SponsorPledge], mediated by the app
/// (`firestore.rules`), never through contact details printed on this
/// document. For a minor subject, `firestore.rules` additionally requires
/// [createdByUid] to be the linked guardian, not the minor — see the rule
/// comment on `sponsorshipListings` for the reasoning; this class only
/// carries the fields, it does not (and structurally cannot) enforce that.
class SponsorshipListing {
  const SponsorshipListing({
    required this.id,
    required this.targetType,
    this.subjectUid,
    this.subjectDisplayName,
    this.orgId,
    this.orgName,
    required this.sport,
    this.geo = GeoLocation.empty,
    required this.headline,
    this.story = '',
    this.achievementSummary = const [],
    this.ratingPercentile,
    this.verificationTier,
    this.asks = const [],
    this.status = GiveNeedStatus.open,
    this.sponsorsCount = 0,
    this.createdByUid,
    this.createdAt,
  });

  final String id;
  final SponsorshipTargetType targetType;

  /// Set when [targetType] is [SponsorshipTargetType.athlete]. Just a uid +
  /// a display name the athlete/guardian chose to show publicly — never the
  /// full `AppUser` document. Same reduced-view discipline as
  /// `TalentProfile` in `lib/domain/scout/talent_profile.dart`.
  final String? subjectUid;
  final String? subjectDisplayName;

  /// Set when [targetType] is [SponsorshipTargetType.team].
  final String? orgId;
  final String? orgName;

  final String sport;

  /// District/mandal/city only — deliberately never carries `lat`/`lng` or a
  /// street address for this feature. A sponsor needs to know "a village near
  /// Nalgonda", never a pin on a map.
  final GeoLocation geo;

  /// A one-line hook — "State U-16 100m champion", "27 wins in 32 matches" —
  /// the thing that makes a sponsor stop scrolling.
  final String headline;

  final String story;

  /// Free-text highlights, newest first. Kept as plain strings rather than
  /// joining live match/tournament data so a listing still reads correctly
  /// after a season ends and standings move on.
  final List<String> achievementSummary;

  /// Optional snapshot of `TalentProfile.ratingPercentile` at the moment the
  /// listing was published/refreshed. Purely informative here — unlike
  /// `TalentSearch`, nothing about *finding* this listing depends on it, so a
  /// listing with no rating yet (a player too new to have one) is still a
  /// complete, valid listing.
  final double? ratingPercentile;
  final String? verificationTier;

  final List<SponsorshipAsk> asks;
  final GiveNeedStatus status;

  /// Denormalized count of accepted, non-withdrawn pledges — written only by
  /// `onSponsorPledgeStatusChanged` (Cloud Function), never the client. See
  /// `GiveImpactStats` for why this codebase always puts a derived tally
  /// behind a function rather than a client increment.
  final int sponsorsCount;

  final String? createdByUid;
  final DateTime? createdAt;

  bool get isAthlete => targetType == SponsorshipTargetType.athlete;
  bool get isOpen =>
      status == GiveNeedStatus.open ||
      status == GiveNeedStatus.partiallyFulfilled;

  factory SponsorshipListing.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const {};
    return SponsorshipListing(
      id: doc.id,
      targetType: SponsorshipTargetType.fromWire(d['targetType'] as String?),
      subjectUid: Fs.strOrNull(d['subjectUid']),
      subjectDisplayName: Fs.strOrNull(d['subjectDisplayName']),
      orgId: Fs.strOrNull(d['orgId']),
      orgName: Fs.strOrNull(d['orgName']),
      sport: Fs.str(d['sport']),
      geo: GeoLocation.fromDocData(d, legacyDistrictKey: null),
      headline: Fs.str(d['headline']),
      story: Fs.str(d['story']),
      achievementSummary: (d['achievementSummary'] as List?)
              ?.map((e) => e.toString())
              .toList(growable: false) ??
          const [],
      ratingPercentile: (d['ratingPercentile'] as num?)?.toDouble(),
      verificationTier: Fs.strOrNull(d['verificationTier']),
      asks: SponsorshipAsk.listFromRaw(d['asks']),
      status: GiveNeedStatus.fromWire(d['status'] as String?),
      sponsorsCount: Fs.intOrNull(d['sponsorsCount']) ?? 0,
      createdByUid: Fs.strOrNull(d['createdByUid']),
      createdAt: Fs.dateOrNull(d['createdAt']),
    );
  }

  /// The only shape a client may create — always [GiveNeedStatus.open] and
  /// `sponsorsCount: 0`. See the class doc on why [createdByUid] is checked
  /// against the linked guardian, not accepted at face value, when the
  /// subject is a minor.
  Map<String, Object?> toCreate({required String createdByUid}) => Fs.prune({
        'targetType': targetType.wire,
        'subjectUid': subjectUid,
        'subjectDisplayName': subjectDisplayName,
        'orgId': orgId,
        'orgName': orgName,
        'sport': sport,
        'geo': geo.toMap(),
        'headline': headline,
        'story': story,
        'achievementSummary': achievementSummary,
        'ratingPercentile': ratingPercentile,
        'verificationTier': verificationTier,
        'asks': SponsorshipAsk.listToRaw(asks),
        'status': GiveNeedStatus.open.wire,
        'sponsorsCount': 0,
        'createdByUid': createdByUid,
        'createdAt': FieldValue.serverTimestamp(),
      });
}

/// One thing a listing is asking a sponsor to provide.
class SponsorshipAsk {
  const SponsorshipAsk({
    required this.category,
    this.equipmentCategory,
    required this.description,
    this.estimatedAmountPaise,
    this.fulfilled = false,
  });

  final SponsorshipSupportCategory category;

  /// Set iff [category] is [SponsorshipSupportCategory.equipment] — the
  /// specific item, reusing `EquipmentCategory` so an ask for "cricket
  /// shoes" here and a Give donation of "cricket shoes" share one vocabulary.
  final EquipmentCategory? equipmentCategory;

  final String description;

  /// Null means "in kind / not costed" — a sponsor offering their own
  /// coaching time has no rupee figure attached, and forcing one would
  /// pressure a listing into inventing a number it cannot stand behind.
  final int? estimatedAmountPaise;

  final bool fulfilled;

  Map<String, Object?> toMap() => Fs.prune({
        'category': category.wire,
        'equipmentCategory': equipmentCategory?.wire,
        'description': description,
        'estimatedAmountPaise': estimatedAmountPaise,
        'fulfilled': fulfilled,
      });

  factory SponsorshipAsk.fromMap(Map<String, dynamic> m) => SponsorshipAsk(
        category: SponsorshipSupportCategory.fromWire(m['category'] as String?),
        equipmentCategory: m['equipmentCategory'] == null
            ? null
            : EquipmentCategory.fromWire(m['equipmentCategory'] as String?),
        description: Fs.str(m['description']),
        estimatedAmountPaise: Fs.intOrNull(m['estimatedAmountPaise']),
        fulfilled: Fs.boolean(m['fulfilled']),
      );

  static List<SponsorshipAsk> listFromRaw(Object? raw) => raw is List
      ? raw
          .whereType<Map>()
          .map((m) => SponsorshipAsk.fromMap(Map<String, dynamic>.from(m)))
          .toList(growable: false)
      : const [];

  static List<Map<String, Object?>> listToRaw(List<SponsorshipAsk> asks) =>
      asks.map((a) => a.toMap()).toList(growable: false);
}

/// One sponsor's offer against a [SponsorshipListing], at
/// `sponsorPledges/{pledgeId}`.
///
/// Top-level rather than a subcollection of the listing, mirroring
/// `GiveDonation`/`Refs.giveDonations`: "every pledge I've ever made" and
/// "every pledge waiting on my listing" both need to be queries a single
/// person can run without reading every listing in the country.
class SponsorPledge {
  const SponsorPledge({
    required this.id,
    required this.listingId,
    required this.sponsorUid,
    required this.sponsorDisplayName,
    this.message = '',
    this.offeredCategories = const [],
    this.amountPaise,
    this.anonymous = false,
    this.status = SponsorPledgeStatus.pending,
    this.createdAt,
    this.respondedAt,
  });

  final String id;
  final String listingId;

  final String sponsorUid;

  /// Denormalized so the listing owner's inbox renders without a join per
  /// card. Ignored entirely on the public side when [anonymous] is true.
  final String sponsorDisplayName;

  final String message;
  final List<SponsorshipSupportCategory> offeredCategories;

  /// Intent, not a charge — see `lib/data/billing_repository.dart`'s
  /// `PaymentGateway` doc. PlaySphere's payment gateway is a launch-offer
  /// stub product-wide, so this field records what a sponsor says they will
  /// give, never money actually moved. Once a real gateway exists, accepting
  /// a pledge is the seam where a charge would be collected.
  final int? amountPaise;

  /// Whether this sponsor wants public credit on the listing. A sponsor who
  /// prefers not to be named still shows up in [SponsorshipListing.sponsorsCount],
  /// just not in any "sponsored by" byline.
  final bool anonymous;

  final SponsorPledgeStatus status;
  final DateTime? createdAt;
  final DateTime? respondedAt;

  factory SponsorPledge.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return SponsorPledge(
      id: doc.id,
      listingId: Fs.str(d['listingId']),
      sponsorUid: Fs.str(d['sponsorUid']),
      sponsorDisplayName: Fs.str(d['sponsorDisplayName'], 'A sponsor'),
      message: Fs.str(d['message']),
      offeredCategories: (d['offeredCategories'] as List?)
              ?.map((w) => SponsorshipSupportCategory.fromWire(w as String?))
              .toList(growable: false) ??
          const [],
      amountPaise: Fs.intOrNull(d['amountPaise']),
      anonymous: Fs.boolean(d['anonymous']),
      status: SponsorPledgeStatus.fromWire(d['status'] as String?),
      createdAt: Fs.dateOrNull(d['createdAt']),
      respondedAt: Fs.dateOrNull(d['respondedAt']),
    );
  }

  /// The only shape a client may create — always [SponsorPledgeStatus.pending].
  /// Responding (`accepted`/`declined`) is the listing owner's move, and
  /// withdrawing is the sponsor's; neither happens through this factory.
  Map<String, Object?> toCreate() => Fs.prune({
        'listingId': listingId,
        'sponsorUid': sponsorUid,
        'sponsorDisplayName': sponsorDisplayName,
        'message': message,
        'offeredCategories':
            offeredCategories.map((c) => c.wire).toList(growable: false),
        'amountPaise': amountPaise,
        'anonymous': anonymous,
        'status': SponsorPledgeStatus.pending.wire,
        'createdAt': FieldValue.serverTimestamp(),
        'respondedAt': null,
      });
}
