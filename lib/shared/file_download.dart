import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

/// Hands a generated file — a schedule PDF today — to the person who asked
/// for it.
///
/// One code path for all three platforms, because `share_plus` 12 already has
/// the branch that matters: on Android and iOS it opens the share sheet, and
/// on the web it tries `navigator.share` and falls back to an anchor download
/// when the browser will not take a file attachment (desktop Chrome on macOS
/// and Linux will not). Writing that fallback here by hand — a `Blob`, an
/// object URL, a detached anchor — is code we would own forever to replace
/// code the dependency already ships and tests.
///
/// Bytes rather than a temp file, exactly as `certificates_screen.dart` does:
/// no filesystem permission, no `path_provider` dependency, and nothing left
/// behind in a cache directory afterwards.
Future<void> saveFileBytes({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
  String? shareText,
}) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(bytes, mimeType: mimeType, name: filename)],
      // `XFile.fromData` has no path, so several platform channels invent a
      // name like "share.pdf" unless told otherwise. A file called
      // "U19-Badminton-schedule.pdf" is the whole point of the feature.
      fileNameOverrides: [filename],
      text: shareText,
    ),
  );
}
