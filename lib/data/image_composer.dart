import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

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
  /// `image_picker` re-encodes whenever it resizes — true, but it only
  /// resizes when the source is *larger* than the ceiling. A 300px PNG logo,
  /// which is exactly the sort of file a club has lying around, comes back
  /// untouched and would be stored under a content type it does not have.
  /// `storage.rules` accepts both, so the object uploads either way and the
  /// error surfaces later as a browser refusing to render it.
  @visibleForTesting
  static String contentTypeOf(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }
}
