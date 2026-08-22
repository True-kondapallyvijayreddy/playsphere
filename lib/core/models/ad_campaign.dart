import 'package:cloud_firestore/cloud_firestore.dart';

import '../ads/promo.dart';
import 'enums.dart';
import 'firestore_codec.dart';

/// One advertiser's campaign, at `adCampaigns/{campaignId}`.
///
/// `lib/core/ads/promo.dart`'s file doc calls this out by name: "When there
/// is a real advertiser console, it fills the same `Promo` shape and nothing
/// above it changes." This is that shape, made persistent and reviewable —
/// see [toPromo]. Nothing about how a promo is rendered, targeted, disclosed
/// or gated from a minor/Premium viewer (`mayShowPromo`) changes; only where
/// the [Promo] came from does.
class AdCampaign {
  const AdCampaign({
    required this.id,
    required this.advertiserUid,
    required this.advertiserName,
    required this.headline,
    required this.body,
    required this.emoji,
    required this.ctaLabel,
    this.imageUrl,
    this.sportIds = const [],
    this.destination,
    this.slots = const [PromoSlot.home],
    this.status = AdCampaignStatus.pending,
    this.budgetPaise = 0,
    this.impressions = 0,
    this.clicks = 0,
    this.createdAt,
  });

  final String id;
  final String advertiserUid;
  final String advertiserName;

  final String headline;
  final String body;
  final String emoji;

  /// The advertiser's own artwork. Null is a complete campaign — see
  /// [Promo.imageUrl] for why the emoji is still the thing that lays out.
  final String? imageUrl;
  final String ctaLabel;
  final List<String> sportIds;

  /// In-app route only — see `PromoBanner._open`'s comment on why an
  /// external URL is never navigated straight from a banner tap. Rules
  /// enforce this too: see `firestore.rules` on `adCampaigns`.
  final String? destination;

  /// Which slot(s) this campaign is eligible to fill. An advertiser choosing
  /// [PromoSlot.grounds] for a coaching-camp ad and [PromoSlot.home] for a
  /// general brand push is two campaigns' worth of reach from one submission.
  final List<PromoSlot> slots;

  final AdCampaignStatus status;

  /// What the advertiser was quoted, real rupees — shown to them, never
  /// charged while `Pricing.introOfferActive`. See `AdRepository.submit`.
  final int budgetPaise;

  /// Function-incremented-by-exactly-one counters — see `firestore.rules`
  /// on `adCampaigns` for the narrow diff check that is all a client is
  /// allowed to do to either field.
  final int impressions;
  final int clicks;

  final DateTime? createdAt;

  bool get isLive => status == AdCampaignStatus.approved;

  /// The one thing this whole model exists to produce: the exact [Promo]
  /// shape every other ad slot in the app already knows how to render,
  /// disclose and gate. See the class doc.
  Promo toPromo() => Promo(
        id: 'campaign-$id',
        advertiser: advertiserName,
        headline: headline,
        body: body,
        emoji: emoji,
        imageUrl: imageUrl,
        ctaLabel: ctaLabel,
        sportIds: sportIds,
        destination: destination,
      );

  factory AdCampaign.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return AdCampaign(
      id: doc.id,
      advertiserUid: Fs.str(d['advertiserUid']),
      advertiserName: Fs.str(d['advertiserName'], 'An advertiser'),
      headline: Fs.str(d['headline']),
      body: Fs.str(d['body']),
      emoji: Fs.str(d['emoji'], '📣'),
      imageUrl: Fs.strOrNull(d['imageUrl']),
      ctaLabel: Fs.str(d['ctaLabel'], 'Learn more'),
      sportIds: (d['sportIds'] as List?)?.map((e) => e.toString()).toList(growable: false) ??
          const [],
      destination: Fs.strOrNull(d['destination']),
      slots: (d['slots'] as List?)
              ?.map((w) => PromoSlot.fromWire(w as String?))
              .toList(growable: false) ??
          const [PromoSlot.home],
      status: AdCampaignStatus.fromWire(d['status'] as String?),
      budgetPaise: Fs.intOrNull(d['budgetPaise']) ?? 0,
      impressions: Fs.intOrNull(d['impressions']) ?? 0,
      clicks: Fs.intOrNull(d['clicks']) ?? 0,
      createdAt: Fs.dateOrNull(d['createdAt']),
    );
  }

  /// The only shape a client may create — always [AdCampaignStatus.pending],
  /// zero counters. See `firestore.rules` on `adCampaigns`: only the `admin`
  /// claim (the same one `isGiveStaff()` checks) may approve, reject or
  /// pause a campaign after this.
  Map<String, Object?> toCreate({required String advertiserUid}) => Fs.prune({
        'advertiserUid': advertiserUid,
        'advertiserName': advertiserName,
        'headline': headline,
        'body': body,
        'emoji': emoji,
        'imageUrl': imageUrl,
        'ctaLabel': ctaLabel,
        'sportIds': sportIds,
        'destination': destination,
        'slots': slots.map((s) => s.wire).toList(growable: false),
        'status': AdCampaignStatus.pending.wire,
        'budgetPaise': budgetPaise,
        'impressions': 0,
        'clicks': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
}
