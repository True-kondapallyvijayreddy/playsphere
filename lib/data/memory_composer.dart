import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../core/models/memory.dart';

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
      // `image_picker` re-encodes to JPEG whenever it resizes, so the picked
      // file's own extension is not a reliable indicator of what we hold.
      contentType: 'image/jpeg',
      kind: MemoryKind.photo,
      width: size?.width.round() ?? 0,
      height: size?.height.round() ?? 0,
    );
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

    return ComposedMemory(
      bytes: await file.readAsBytes(),
      contentType: 'video/mp4',
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
