import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../core/ads/promo.dart';
import '../core/firebase/firestore_refs.dart';
import '../core/models/ad_campaign.dart';
import 'media_uploader.dart';
import 'org_repository.dart' show guard, guardStream;

/// The advertiser side of `lib/core/ads/promo.dart`. Submission is
/// self-serve; approval is staff-only (the `admin` claim, same as Give's
/// `isGiveStaff()`) with no in-app review screen — see `firestore.rules` on
/// `adCampaigns` and the same precedent `giveNeeds.verified` already set:
/// this product reviews trust-sensitive claims from the console, not from a
/// screen inside the app that does not exist for Give either.
class AdRepository {
  const AdRepository({FirebaseStorage? storage}) : _storage = storage;

  /// Injectable so a test can drive the creative upload against a fake bucket.
  final FirebaseStorage? _storage;

  MediaUploader get _media => MediaUploader(storage: _storage);

  /// Uploads an advertiser's artwork and returns the URL to put on a campaign.
  ///
  /// Keyed on the advertiser's uid rather than a campaign id, because the
  /// artwork is picked *while the campaign is being written* and has no id to
  /// hang off yet. That is also the only shape `storage.rules` can gate here
  /// — see the `adCreatives` block.
  ///
  /// Returns the URL rather than writing it anywhere: the editor sheet holds
  /// it in state and it lands with the rest of the campaign on submit, so an
  /// advertiser who changes their mind and closes the sheet has changed
  /// nothing.
  Future<String> uploadCreative({
    required String advertiserUid,
    required Uint8List bytes,
    required String contentType,
  }) =>
      guard(
        () => _media.putImage(
          folder: 'adCreatives',
          uid: advertiserUid,
          bytes: bytes,
          contentType: contentType,
        ),
      );

  /// Every campaign this advertiser has submitted, any status.
  Stream<List<AdCampaign>> watchMyCampaigns(String advertiserUid) =>
      guardStream(
        () => Refs.adCampaigns
            .where('advertiserUid', isEqualTo: advertiserUid)
            .orderBy('createdAt', descending: true)
            .snapshots()
            .map((s) => s.docs.map(AdCampaign.fromDoc).toList(growable: false)),
      );

  /// Approved campaigns eligible for [slot], for `PromoBanner` to pick among
  /// via `PromoCatalog.forSlotWithCampaigns`. Small and cached client-side by
  /// Firestore's own listener — this is a handful of rows, not a feed.
  Stream<List<AdCampaign>> watchApprovedForSlot(PromoSlot slot) => guardStream(
        () => Refs.adCampaigns
            .where('status', isEqualTo: 'approved')
            .where('slots', arrayContains: slot.wire)
            .snapshots()
            .map((s) => s.docs.map(AdCampaign.fromDoc).toList(growable: false)),
      );

  /// Submits a campaign. Lands exactly as [AdCampaign.toCreate] shapes it —
  /// pending, zero counters, whatever the advertiser was quoted in
  /// [budgetPaise] recorded but never charged while
  /// `Pricing.introOfferActive` (see that flag's doc).
  Future<String> submit(
    AdCampaign campaign, {
    required String advertiserUid,
  }) =>
      guard(() async {
        final ref = Refs.adCampaigns.doc();
        await ref.set(campaign.toCreate(advertiserUid: advertiserUid));
        return ref.id;
      });

  /// Fire-and-forget impression/click counters. Rules permit exactly a
  /// same-request +1 to one of these two fields and nothing else — see the
  /// `adCampaigns` update rule. Errors are swallowed: a missed impression
  /// count is not worth surfacing to the viewer it was measuring.
  Future<void> recordImpression(String campaignId) => Refs.adCampaign(campaignId)
      .update({'impressions': FieldValue.increment(1)}).catchError((_) {});

  Future<void> recordClick(String campaignId) => Refs.adCampaign(campaignId)
      .update({'clicks': FieldValue.increment(1)}).catchError((_) {});
}
