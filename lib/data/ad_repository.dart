import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../core/ads/promo.dart';
import '../core/firebase/firestore_refs.dart';
import '../core/models/ad_campaign.dart';
import '../core/models/enums.dart';
import 'media_uploader.dart';
import 'org_repository.dart' show guard, guardStream;

/// The advertiser side of `lib/core/ads/promo.dart`. Submission is
/// self-serve; approval is staff-only (the `admin` claim, same as Give's
/// `isGiveStaff()`) — see `firestore.rules` on `adCampaigns`.
///
/// Approval used to have no destination at all: a campaign landed as
/// `pending` and the only way to move it was the Firebase console, so from
/// inside the product a submitted campaign went nowhere and nobody was told
/// it had arrived. [watchForReview] and [review] are the queue side of that,
/// `AdReviewScreen` renders it, and `onAdCampaignSubmitted` in
/// `functions/index.js` pages whoever is on the `ads` desk of
/// `platformStaff` — see `StaffMember` for why that roster has to exist for
/// a custom claim to be reachable by a notification.
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

  // --- Staff review --------------------------------------------------

  /// Every campaign in one status, for the ops queue — newest first.
  ///
  /// Separate from [watchMyCampaigns] rather than a nullable-uid variant of
  /// it, because the two are different reads with different rules branches:
  /// an advertiser reads their own rows by `advertiserUid`, and staff read
  /// everybody's by `status`. Collapsing them into one method would hide
  /// which of the two `firestore.rules` is being asked to allow.
  Stream<List<AdCampaign>> watchForReview(AdCampaignStatus status) =>
      guardStream(
        () => Refs.adCampaigns
            .where('status', isEqualTo: status.wire)
            .orderBy('createdAt', descending: true)
            .limit(200)
            .snapshots()
            .map((s) => s.docs.map(AdCampaign.fromDoc).toList(growable: false)),
      );

  /// A reviewer approving, rejecting, pausing or un-pausing a campaign.
  ///
  /// [reviewNote] is written for the advertiser to read, and is what
  /// `onAdCampaignReviewed` puts in the notification body — a rejection with
  /// no reason attached is a support ticket waiting to happen. Cleared on
  /// approval so an old rejection note cannot survive on a live campaign.
  ///
  /// `firestore.rules` allows this write only to the `admin` claim; see the
  /// `adCampaigns` update rule, whose other branch is the narrow
  /// counter-increment [recordImpression] uses.
  Future<void> review(
    String campaignId, {
    required AdCampaignStatus status,
    String? reviewNote,
  }) =>
      guard(
        () => Refs.adCampaign(campaignId).update({
          'status': status.wire,
          'reviewNote': status == AdCampaignStatus.approved
              ? null
              : (reviewNote?.trim().isEmpty ?? true ? null : reviewNote!.trim()),
          'reviewedAt': FieldValue.serverTimestamp(),
        }),
      );

  /// Fire-and-forget impression/click counters. Rules permit exactly a
  /// same-request +1 to one of these two fields and nothing else — see the
  /// `adCampaigns` update rule. Errors are swallowed: a missed impression
  /// count is not worth surfacing to the viewer it was measuring.
  Future<void> recordImpression(String campaignId) => Refs.adCampaign(campaignId)
      .update({'impressions': FieldValue.increment(1)}).catchError((_) {});

  Future<void> recordClick(String campaignId) => Refs.adCampaign(campaignId)
      .update({'clicks': FieldValue.increment(1)}).catchError((_) {});
}
