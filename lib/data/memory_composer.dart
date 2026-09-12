import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../core/models/memory.dart';
import 'image_composer.dart';

/// One picked, downscaled, ready-to-upload memory.
class ComposedMemory {
  const ComposedMemory({
    required this.bytes,
    required this.contentType,
    required this.kind,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final String contentType;
  final MemoryKind kind;
  final int width;
  final int height;

  int get sizeBytes => bytes.lengthInBytes;
}

/// Picks media from the camera or gallery and shrinks it before it ever
/// touches the network.
///
/// ## Why downscale on the device
///
/// CLAUDE.md §2.8 targets ₹8k Android phones on spotty 4G. A photo straight off
/// a mid-range camera is 4–8 MB; the same image at 1600px on the long edge is
/// 200–400 KB and indistinguishable in a profile grid. Uploading the original
/// would cost the user roughly twenty times the data for no visible gain, and on
/// a weak connection it is the difference between an upload that completes and
/// one that is abandoned.
///
/// `image_picker` does the resizing natively on both Android and iOS, so no
/// image-processing package is needed and no decode happens on the platform
/// thread.
class MemoryComposer {
  MemoryComposer({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Long edge, in logical pixels, after downscale.
  ///
  /// 1600 is chosen to still look sharp full-screen on a modern phone while
  /// staying comfortably inside the 8 MB rules ceiling even for a busy photo.
  static const double maxDimension = 1600;

  /// JPEG quality. 82 is the usual knee of the size/quality curve — above it
  /// bytes grow fast for changes nobody sees on a phone.
  static const int jpegQuality = 82;

  Future<ComposedMemory?> pickPhoto({required ImageSource source}) async {
    final file = await _picker.pickImage(
      source: source,
      maxWidth: maxDimension,
      maxHeight: maxDimension,
      imageQuality: jpegQuality,
    );
    if (file == null) return null;

    final bytes = await file.readAsBytes();
    final size = await _decodeSize(bytes);

    return ComposedMemory(
      bytes: bytes,
      // Sniffed from the bytes, not assumed.
      //
      // This said `image/jpeg` unconditionally, on the reasoning that
      // `image_picker` re-encodes whenever it resizes. That holds on Android
      // and iOS. On the WEB `image_picker` ignores `maxWidth`, `maxHeight`
      // and `imageQuality` outright and returns the chosen file untouched —
      // so a PNG screenshot or a `.HEIC` straight off an iPhone was stored
      // under a type it did not have, and a HEIC no browser can decode was
      // indistinguishable from a photo that simply never appeared.
      //
      // `ImageComposer.contentTypeOf` throws a `ValidationException` naming
      // the format for anything a browser cannot draw, which is what the
      // pickers upstream already show to the person.
      contentType: ImageComposer.contentTypeOf(bytes),
      kind: MemoryKind.photo,
      width: size?.width.round() ?? 0,
      height: size?.height.round() ?? 0,
    );
  }

  /// The container [bytes] actually holds, defaulting to MP4.
  ///
  /// Defaulting is safe here in a way it was not for images: the three types
  /// `storage.rules` accepts are the three this recognises, and an
  /// unrecognised clip is far more likely to be an MP4 variant this does not
  /// have a signature for than a format the browser cannot play.
  static String _videoTypeOf(Uint8List b) {
    bool at(int offset, List<int> magic) {
      if (b.length < offset + magic.length) return false;
      for (var i = 0; i < magic.length; i++) {
        if (b[offset + i] != magic[i]) return false;
      }
      return true;
    }

    // EBML header — WebM and Matroska.
    if (at(0, [0x1A, 0x45, 0xDF, 0xA3])) return 'video/webm';
    // The ISO base-media `ftyp` box, whose brand separates QuickTime from MP4.
    if (at(4, [0x66, 0x74, 0x79, 0x70]) && b.length >= 12) {
      final brand = String.fromCharCodes(b.sublist(8, 12)).toLowerCase();
      if (brand.startsWith('qt')) return 'video/quicktime';
    }
    return 'video/mp4';
  }

  /// Picks a short clip.
  ///
  /// Note there is no transcoding step: `image_picker` caps duration but cannot
  /// re-encode, so a long 4K clip can still exceed the 50 MB ceiling and will
  /// be refused by [MemoryRepository.upload] with an explanatory message. A
  /// real compression pass needs a native plugin and is deliberately out of
  /// scope until video is more than a nice-to-have.
  Future<ComposedMemory?> pickVideo({
    required ImageSource source,
    Duration maxDuration = const Duration(seconds: 30),
  }) async {
    final file = await _picker.pickVideo(
      source: source,
      maxDuration: maxDuration,
    );
    if (file == null) return null;

    final videoBytes = await file.readAsBytes();
    return ComposedMemory(
      bytes: videoBytes,
      // Same problem as the photo path, same reason: on the web the picked
      // file is whatever the person chose, and a `.mov` from an iPhone
      // labelled `video/mp4` is a clip that will not play. `storage.rules`
      // accepts all three of these container types.
      contentType: _videoTypeOf(videoBytes),
      kind: MemoryKind.video,
      // Dimensions need a video decoder to read, and the grid falls back to a
      // square tile when they are absent. Not worth a plugin.
      width: 0,
      height: 0,
    );
  }

  /// Reads intrinsic dimensions so the grid can reserve the right aspect ratio
  /// instead of reflowing as each tile loads.
  ///
  /// Failure is non-fatal by design: a memory whose dimensions we cannot read
  /// is still a memory, and refusing the upload over a layout hint would be
  /// the wrong trade.
  Future<ui.Size?> _decodeSize(Uint8List bytes) async {
    try {
      final descriptor = await ui.ImageDescriptor.encoded(
        await ui.ImmutableBuffer.fromUint8List(bytes),
      );
      final size = ui.Size(
        descriptor.width.toDouble(),
        descriptor.height.toDouble(),
      );
      descriptor.dispose();
      return size;
    } catch (e) {
      debugPrint('[PlaySphere] could not read image dimensions: $e');
      return null;
    }
  }
}
