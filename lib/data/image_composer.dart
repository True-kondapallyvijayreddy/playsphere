import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../core/errors/app_exception.dart';

/// One picked, downscaled, ready-to-upload image.
class PickedImage {
  const PickedImage({required this.bytes, required this.contentType});

  final Uint8List bytes;
  final String contentType;

  int get sizeBytes => bytes.lengthInBytes;
}

/// What the picked image is going to be used as, which is the only thing that
/// changes how hard it gets shrunk.
enum ImageShape {
  /// A crest, a logo, a face. Displayed at 96pt at the very largest, so 512px
  /// is already twice what a 3x screen can show.
  square,

  /// A banner across the top of an event, a season or a ground. Displayed
  /// edge to edge, so it keeps the same 1600px long edge match memories use.
  banner,
}

/// Picks an image from the camera or gallery and shrinks it before it ever
/// touches the network.
///
/// The generalisation of [MemoryComposer], which does the same job for match
/// photos and videos and is tied to `MemoryKind`. The reasoning there applies
/// unchanged and is worth restating: PlaySphere targets ₹8k Android phones on
/// spotty 4G, a photo straight off a mid-range camera is 4–8 MB, and uploading
/// the original costs the user roughly twenty times the data for no visible
/// gain. On a weak connection it is the difference between an upload that
/// finishes and one that is abandoned halfway.
///
/// A crest is shrunk harder than a memory because it is *displayed* smaller:
/// nothing in the app draws a club logo above 96pt, so anything past 512px is
/// bytes nobody will ever see.
///
/// `image_picker` resizes natively on both Android and iOS, so this needs no
/// image-processing package and does no decode on the platform thread.
class ImageComposer {
  ImageComposer({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Long edge for a crest or a profile photo, in pixels.
  static const double squareMaxDimension = 512;

  /// Long edge for a banner, in pixels. Matches [MemoryComposer.maxDimension]
  /// — a banner is a full-bleed photo and wants the same fidelity.
  static const double bannerMaxDimension = 1600;

  /// 82 is the usual knee of the size/quality curve; above it bytes grow fast
  /// for changes nobody sees on a phone.
  static const int jpegQuality = 82;

  Future<PickedImage?> pick({
    required ImageSource source,
    ImageShape shape = ImageShape.square,
  }) async {
    final maxEdge = switch (shape) {
      ImageShape.square => squareMaxDimension,
      ImageShape.banner => bannerMaxDimension,
    };

    final file = await _picker.pickImage(
      source: source,
      maxWidth: maxEdge,
      maxHeight: maxEdge,
      imageQuality: jpegQuality,
    );
    if (file == null) return null;

    final bytes = await file.readAsBytes();
    return PickedImage(bytes: bytes, contentType: contentTypeOf(bytes));
  }

  /// Reads the content type off the first few bytes rather than trusting the
  /// picked file's extension.
  ///
  /// [MemoryComposer] hard-codes `image/jpeg` on the reasoning that
  /// `image_picker` re-encodes whenever it resizes — true on Android and iOS,
  /// and **false on the web**, where `image_picker` ignores `maxWidth`,
  /// `maxHeight` and `imageQuality` completely and hands back the file the
  /// person chose, byte for byte. So on the web whatever came off their disk
  /// is what gets uploaded, and this is the only thing standing between a
  /// `.HEIC` straight off an iPhone and an object labelled `image/jpeg`.
  ///
  /// ## Why an unknown format is an error and not a guess
  ///
  /// This used to end `return 'image/jpeg';` — every format it did not
  /// recognise was uploaded under a content type it did not have. That is the
  /// worst possible failure for this feature, because every layer reports
  /// success: the picker returns a file, `storage.rules` sees an allowed
  /// `image/jpeg`, the object lands in the bucket, Firestore stores the URL,
  /// the app says "Picture updated." And then no browser will decode it, so
  /// `PsBanner` draws its generated art forever and the person is looking at
  /// a banner they are certain they uploaded. Nothing anywhere says why.
  ///
  /// HEIC is the case that actually bites: it is the iPhone camera default,
  /// `storage.rules` accepts it, and no browser on earth decodes it. Naming
  /// the format and refusing is the only honest answer — the person can
  /// convert or pick something else, which takes a moment, whereas an image
  /// that uploads and never appears is unfalsifiable from their side.
  static String contentTypeOf(Uint8List bytes) {
    final type = sniff(bytes);
    if (type == null) {
      throw const ValidationException(
        'That file does not look like an image. Please pick a JPG, PNG or '
        'WebP.',
      );
    }
    if (!webSafeTypes.contains(type)) {
      throw ValidationException(
        'PlaySphere cannot display ${_labelFor(type)} images in a browser. '
        'Please save the picture as a JPG or PNG and pick it again.',
      );
    }
    return type;
  }

  /// The formats every browser the product targets can actually draw.
  ///
  /// Narrower than `storage.rules` allows on purpose. The rules also accept
  /// `image/heic`, because a native iOS build could in principle display one;
  /// nothing in this app does, and the web build certainly cannot.
  static const webSafeTypes = {'image/jpeg', 'image/png', 'image/webp'};

  /// The real format of [bytes], or null if it is not an image this knows.
  ///
  /// Split out from [contentTypeOf] so the detection is testable without the
  /// throwing, and so the list of what is *recognised* stays separate from
  /// the list of what is *acceptable* — they change for different reasons.
  @visibleForTesting
  static String? sniff(Uint8List b) {
    bool at(int offset, List<int> magic) {
      if (b.length < offset + magic.length) return false;
      for (var i = 0; i < magic.length; i++) {
        if (b[offset + i] != magic[i]) return false;
      }
      return true;
    }

    if (at(0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
      return 'image/png';
    }
    // JPEG: SOI marker. Checked before the RIFF/ISO families because it is by
    // far the common case.
    if (at(0, [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
    // RIFF....WEBP
    if (at(0, [0x52, 0x49, 0x46, 0x46]) && at(8, [0x57, 0x45, 0x42, 0x50])) {
      return 'image/webp';
    }
    if (at(0, [0x47, 0x49, 0x46, 0x38])) return 'image/gif';
    if (at(0, [0x42, 0x4D])) return 'image/bmp';
    // TIFF, either endianness. Also what many camera RAW files look like.
    if (at(0, [0x49, 0x49, 0x2A, 0x00]) || at(0, [0x4D, 0x4D, 0x00, 0x2A])) {
      return 'image/tiff';
    }
    // The ISO base-media family — HEIC, HEIF and AVIF all carry an `ftyp` box
    // at offset 4 and differ only in the brand that follows it. An iPhone
    // photo is `heic`; Android 12+ and Chrome screenshots can be `avif`.
    if (at(4, [0x66, 0x74, 0x79, 0x70]) && b.length >= 12) {
      final brand = String.fromCharCodes(b.sublist(8, 12)).toLowerCase();
      if (brand.startsWith('hei') || brand == 'mif1' || brand == 'msf1') {
        return 'image/heic';
      }
      if (brand.startsWith('avi')) return 'image/avif';
    }
    return null;
  }

  static String _labelFor(String contentType) => switch (contentType) {
        'image/heic' => 'HEIC (iPhone)',
        'image/avif' => 'AVIF',
        'image/gif' => 'GIF',
        'image/bmp' => 'BMP',
        'image/tiff' => 'TIFF',
        _ => contentType,
      };
}
