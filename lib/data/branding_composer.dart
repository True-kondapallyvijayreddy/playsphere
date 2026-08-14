import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// An image picked and downscaled for use as branding — a club crest, a
/// season logo, a season banner.
class ComposedImage {
  const ComposedImage({required this.bytes, required this.contentType});

  final Uint8List bytes;
  final String contentType;

  int get sizeBytes => bytes.lengthInBytes;
}

/// What a branding image is going to be used as.
///
/// The two differ in shape, not merely in size, and picking one number for
/// both gets one of them wrong: a crest is rendered at 26–72 logical pixels
/// in a list row and never needs to be large, while a banner spans the full
/// width of a phone and looks soft the moment it is under-sampled.
enum BrandingKind {
  /// A club crest or season logo. Square-ish, small, shown at list size.
  logo('logo', 512),

  /// A season's header image, shown full-bleed across the top of a card.
  banner('banner', 1600);

  const BrandingKind(this.wire, this.maxDimension);

  final String wire;

  /// Long edge, in logical pixels, after downscale.
  final double maxDimension;
}

/// Picks and downscales a branding image.
///
/// The counterpart to [MemoryComposer] and deliberately a separate class
/// rather than another mode on it: a memory is a record of a match with a
/// caption, tagged players and an audience, and a crest is a decoration a club
/// admin replaces occasionally. Sharing a type would mean every branding
/// upload carrying five fields that mean nothing to it.
///
/// ## Why the resize happens in the picker
///
/// Same reason as [MemoryComposer]: `image_picker` does it natively, so no
/// image-processing package is needed and no decode happens on the platform
/// thread. It also means the bytes are already inside the 4 MB ceiling
/// `storage.rules` enforces by the time an upload is attempted, rather than
/// being refused after the organizer has waited for it.
class BrandingComposer {
  BrandingComposer({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// JPEG quality. 82 is the usual knee of the size/quality curve — above it
  /// bytes grow fast for changes nobody sees on a phone.
  static const int jpegQuality = 82;

  /// Returns null when the picker was dismissed without choosing anything.
  Future<ComposedImage?> pick({
    required BrandingKind kind,
    ImageSource source = ImageSource.gallery,
  }) async {
    final file = await _picker.pickImage(
      source: source,
      maxWidth: kind.maxDimension,
      maxHeight: kind.maxDimension,
      imageQuality: jpegQuality,
    );
    if (file == null) return null;

    return ComposedImage(
      bytes: await file.readAsBytes(),
      // `image_picker` re-encodes to JPEG whenever it resizes, so the picked
      // file's own extension is not a reliable indicator of what we hold.
      // Declaring it honestly matters more than usual here: `storage.rules`
      // gates on `request.resource.contentType`, so a wrong value is a
      // refused upload rather than a cosmetic error.
      contentType: 'image/jpeg',
    );
  }
}
