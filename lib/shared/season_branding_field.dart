import 'package:flutter/material.dart';

import '../data/competition_repository.dart';
import '../data/image_composer.dart';
import '../data/tournament_repository.dart';
import 'image_upload.dart';
import 'ps_banner.dart';
import 'ui_kit.dart';

/// The crest and the header artwork a season or a tournament is being created
/// with, held in memory until there is a document to attach them to.
///
/// ## Why the pictures are staged rather than uploaded on the spot
///
/// Every other branding upload in the app happens on a thing that already
/// exists — a club, a team, a ground — so it can upload straight away and
/// write the URL onto the document in the same call. A season's artwork is
/// chosen on the create form, where there is no season id yet, and
/// `MediaUploader` puts the id in the storage path. Uploading to some staging
/// path first would mean a bucket object for every organizer who opened the
/// form and changed their mind, with nothing pointing at it and nothing to
/// clean it up.
///
/// So the bytes sit here through the form and go up in [uploadTo] the moment
/// `createTournament` returns an id. The cost is that artwork is the one part
/// of the form that can fail after the season is saved, which is why
/// [uploadTo] reports rather than throws: a season that exists with no crest
/// is a season, and losing it because a photo upload timed out would be much
/// worse than the missing picture.
class SeasonBranding {
  SeasonBranding({this.logo, this.banner});

  /// The badge. Square, downscaled to 512px by [ImageShape.square].
  PickedImage? logo;

  /// The header photograph, at [ImageShape.banner]'s 1600px.
  PickedImage? banner;

  bool get isEmpty => logo == null && banner == null;

  /// Uploads whatever was staged onto a season that now exists, and returns
  /// null when everything landed or one sentence describing what did not.
  ///
  /// Deliberately never throws. It runs after the season and its events have
  /// been written, so the only thing left to decide is whether the organizer
  /// is told about a missing picture — and the answer is yes, in a snackbar,
  /// on a screen that has already moved on to the season it just made.
  Future<String?> uploadTo({
    required TournamentRepository repo,
    required String orgId,
    required String tournamentId,
    required String uid,
  }) =>
      _upload(
        subject: 'season',
        page: 'season page',
        putLogo: (image) => repo.uploadSeasonLogo(
          orgId: orgId,
          tournamentId: tournamentId,
          uid: uid,
          bytes: image.bytes,
          contentType: image.contentType,
        ),
        putBanner: (image) => repo.uploadSeasonBanner(
          orgId: orgId,
          tournamentId: tournamentId,
          uid: uid,
          bytes: image.bytes,
          contentType: image.contentType,
        ),
      );

  /// The same thing for a standalone event, which is what the product calls a
  /// tournament when it is not inside a season.
  Future<String?> uploadToEvent({
    required CompetitionRepository repo,
    required String orgId,
    required String compId,
    required String uid,
  }) =>
      _upload(
        subject: 'event',
        page: 'event page',
        putLogo: (image) => repo.uploadEventLogo(
          orgId: orgId,
          compId: compId,
          uid: uid,
          bytes: image.bytes,
          contentType: image.contentType,
        ),
        putBanner: (image) => repo.uploadEventBanner(
          orgId: orgId,
          compId: compId,
          uid: uid,
          bytes: image.bytes,
          contentType: image.contentType,
        ),
      );

  /// Both uploads, each allowed to fail on its own.
  ///
  /// Separately rather than in one try, because the two pictures are
  /// independent: a banner that times out must not take a crest that already
  /// uploaded down with it, and the organizer should be told which one is
  /// missing rather than that "artwork" failed.
  Future<String?> _upload({
    required String subject,
    required String page,
    required Future<void> Function(PickedImage image) putLogo,
    required Future<void> Function(PickedImage image) putBanner,
  }) async {
    final failed = <String>[];

    final crest = logo;
    if (crest != null) {
      try {
        await putLogo(crest);
      } catch (_) {
        failed.add('logo');
      }
    }

    final art = banner;
    if (art != null) {
      try {
        await putBanner(art);
      } catch (_) {
        failed.add('banner');
      }
    }

    if (failed.isEmpty) return null;
    return 'The $subject was created, but its ${failed.join(' and ')} could '
        'not be uploaded. You can add it from the $page.';
  }
}

/// The block on a create form that gives a season its look: a live header
/// preview, a button for the crest and a button for the artwork.
///
/// ## Why it is a preview and not two file rows
///
/// The two pictures do different jobs at different sizes, and an organizer
/// cannot tell whether the crest they picked survives being drawn at 44pt on
/// top of the photograph they picked by reading two file names. Showing the
/// real [PsBanner] — the same widget the season page and the public link use,
/// with the same generated fallback art — means the answer to "what will this
/// look like" is on screen before the season is created rather than after.
///
/// It also carries the argument [PsBanner] makes about the empty state: with
/// nothing picked this is not an empty box, it is the generated header the
/// season will genuinely have. Skipping both pictures is a legitimate choice
/// and the form should not look broken when somebody makes it.
class SeasonBrandingField extends StatelessWidget {
  const SeasonBrandingField({
    super.key,
    required this.branding,
    required this.name,
    required this.onChanged,
    this.logoUrl,
    this.bannerUrl,
    this.seed,
    this.sportId,
    this.subject = 'Season',
    this.title = 'Season look',
    this.helper = 'Optional. Both show on the season page and on the public '
        'link you share — the logo on the header, in lists, and beside every '
        'result.',
  });

  /// The staged pictures, mutated in place and reported through [onChanged].
  final SeasonBranding branding;

  /// What the season is called so far, drawn on the preview. Empty is fine —
  /// the preview simply shows the artwork with no title over it.
  final String name;

  /// Called after a pick or a clear so the hosting form can `setState`.
  final VoidCallback onChanged;

  /// Artwork already on the thing being edited, drawn when nothing newer has
  /// been staged. Null on a create form, which is the usual case.
  final String? logoUrl;
  final String? bannerUrl;

  /// Varies the generated art, exactly as on [PsBanner]. The season id where
  /// there is one; anything stable otherwise.
  final String? seed;

  final String? sportId;

  /// What the thing being branded is called, capitalised — 'Season',
  /// 'Tournament', 'Event'. Only used to word the two picker sheets, so a
  /// form headed "Event look" does not open a sheet headed "Season logo".
  final String subject;

  final String title;
  final String helper;

  bool get _hasLogo =>
      branding.logo != null ||
      (logoUrl != null && logoUrl!.trim().isNotEmpty);

  bool get _hasBanner =>
      branding.banner != null ||
      (bannerUrl != null && bannerUrl!.trim().isNotEmpty);

  Future<void> _pickLogo(BuildContext context) async {
    final picked = await pickLocalImage(
      context: context,
      title: '$subject logo',
      shape: ImageShape.square,
      note: 'A crest or badge. Squared off, and shown small — a wordmark with '
          'fine print will not be readable.',
    );
    if (picked == null) return;
    branding.logo = picked;
    onChanged();
  }

  Future<void> _pickBanner(BuildContext context) async {
    final picked = await pickLocalImage(
      context: context,
      title: '$subject banner',
      shape: ImageShape.banner,
      note: 'A wide photograph across the top of the page. Leave it out and a '
          'header is generated from the sport.',
    );
    if (picked == null) return;
    branding.banner = picked;
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trimmed = name.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          helper,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),

        // Tappable art, because the preview is the biggest and most obvious
        // target on the block and somebody who wants to change the picture
        // will try the picture first.
        InkWell(
          onTap: () => _pickBanner(context),
          borderRadius: BorderRadius.circular(Ps.radius),
          child: PsBanner(
            height: 148,
            imageUrl: branding.banner == null ? bannerUrl : null,
            imageBytes: branding.banner?.bytes,
            logoUrl: branding.logo == null ? logoUrl : null,
            logoBytes: branding.logo?.bytes,
            logoName: trimmed,
            sportId: sportId,
            seed: seed ?? trimmed,
            fallbackIcon: Icons.emoji_events_outlined,
            fallbackColor: const Color(0xFF0F766E),
            trailing: const _CameraBadge(),
            child: trimmed.isEmpty
                ? null
                : Text(
                    trimmed,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.15,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 12),

        // Named buttons under the preview as well as the tap target above it.
        // The picture alone is discoverable only to somebody who already
        // suspects it is a button, and "I could not find where to add the
        // logo" is exactly how this block failed to exist in the first place.
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickLogo(context),
                icon: const Icon(Icons.shield_outlined, size: 18),
                label: Text(_hasLogo ? 'Change logo' : 'Add logo'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickBanner(context),
                icon: const Icon(Icons.image_outlined, size: 18),
                label: Text(_hasBanner ? 'Change banner' : 'Add banner'),
              ),
            ),
          ],
        ),

        // Only a staged pick can be taken back here. Clearing artwork that is
        // already on a saved season is the season page's job, where the
        // removal is a write rather than a change of mind.
        if (branding.logo != null || branding.banner != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                branding.logo = null;
                branding.banner = null;
                onChanged();
              },
              icon: const Icon(Icons.undo, size: 16),
              label: const Text('Clear picked images'),
            ),
          ),
      ],
    );
  }
}

/// The affordance in the corner of the preview saying the art is changeable.
class _CameraBadge extends StatelessWidget {
  const _CameraBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: const BoxDecoration(
        color: Color(0xCC000000),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.photo_camera, size: 16, color: Colors.white),
    );
  }
}

/// The header a season or a tournament will actually open with, drawn on a
/// wizard's review step from the pictures staged on the details step.
///
/// ## Why the review step needs this
///
/// The review step is the last thing an organizer sees before publishing, and
/// it summarised everything the wizard had collected *except* the artwork: a
/// generic trophy tile and the name, identical whether a crest and a banner
/// had been picked or not. The organizer's reading of that is the obvious one
/// — the pictures did not take — and it is wrong, which is worse than an
/// honest omission would be. Nothing was lost; the review simply never looked
/// at [SeasonBranding].
///
/// Deliberately the same [PsBanner] the season page, the public link and the
/// picker on the details step use, so "what will this look like" has one
/// answer everywhere it is asked rather than three that have to be kept in
/// step by hand.
class SeasonBrandingPreview extends StatelessWidget {
  const SeasonBrandingPreview({
    super.key,
    required this.branding,
    required this.name,
    this.fallbackName = 'Untitled season',
    this.sportId,
    this.height = 132,
  });

  /// The pictures picked earlier in the wizard, still in memory — there is no
  /// document to have uploaded them to yet. See [SeasonBranding].
  final SeasonBranding branding;

  final String name;

  /// Shown when the organizer has not named it yet, matching the row this
  /// replaced.
  final String fallbackName;

  /// The sport whose colour and glyph the generated art uses when no banner
  /// was picked. Null for a season running more than one sport — the trophy
  /// is the honest mark for that, exactly as it is on the season page.
  final String? sportId;

  final double height;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final shown = trimmed.isEmpty ? fallbackName : trimmed;

    return PsBanner(
      height: height,
      imageBytes: branding.banner?.bytes,
      logoBytes: branding.logo?.bytes,
      logoName: shown,
      sportId: sportId,
      seed: trimmed,
      fallbackIcon: Icons.emoji_events_outlined,
      fallbackColor: const Color(0xFF0F766E),
      child: Text(
        shown,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          height: 1.15,
        ),
      ),
    );
  }
}
