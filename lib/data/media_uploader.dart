import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import '../core/errors/app_exception.dart';

/// Puts one image in the bucket and hands back the URL to link it by.
///
/// Every branding upload in the app — a club crest, a team logo, a season
/// banner, a member's photo, a ground's picture — is the same four steps with
/// a different path, and before this each one was going to be a fifth copy of
/// them inside a fifth repository. The rules the copies have to agree on are
/// not obvious, so they live here once:
///
/// **The uid is a path segment.** `storage.rules` cannot read Firestore, so
/// "only an admin may write this club's crest" is not expressible there. What
/// it *can* check is that you are writing under your own uid. The real gate
/// stays on the Firestore side, in the document that references the object —
/// which is why callers upload first and link second, and why an object
/// nobody linked is an object nobody can find.
///
/// **The path is versioned by timestamp.** A replaced crest at a fixed path
/// is served from the old CDN entry for up to a year; at a new path it cannot
/// be. This is what makes the aggressive cache header below safe.
///
/// **The previous object is not deleted.** A URL may already be sitting in a
/// cached feed, a notification payload or somebody's open tab, and breaking
/// those to reclaim a few hundred kilobytes is a poor trade. Reclaiming them
/// is a bucket lifecycle rule's job, not a client's.
///
/// Deliberately does not wrap itself in `guard` — the calling repository has
/// to wrap the upload and the Firestore link together anyway, so wrapping
/// here would only translate the same exception twice.
class MediaUploader {
  const MediaUploader({FirebaseStorage? storage}) : _storage = storage;

  /// Injectable so a test can drive an upload against a fake bucket, matching
  /// [MemoryRepository], [ClubFileRepository] and [OrgRepository].
  final FirebaseStorage? _storage;

  FirebaseStorage get _bucket => _storage ?? FirebaseStorage.instance;

  /// Uploads [bytes] under `{folder}/{uid}/{timestamp}.{ext}` and returns the
  /// download URL.
  ///
  /// [folder] carries no trailing slash and no uid — this adds both, because
  /// the uid segment is load-bearing for the rules and a caller that forgets
  /// it writes an object the rules will reject at best and mis-scope at
  /// worst.
  ///
  /// [maxMegabytes] must stay at or below the ceiling `storage.rules` sets for
  /// the matching path. Checking it here as well is not redundant: a rules
  /// rejection arrives after the whole file has gone up a mobile connection,
  /// whereas this refuses before a single byte is sent.
  Future<String> putImage({
    required String folder,
    required String uid,
    required Uint8List bytes,
    required String contentType,
    int maxMegabytes = 4,
  }) async {
    if (bytes.lengthInBytes >= maxMegabytes * 1024 * 1024) {
      throw ValidationException(
        'That image is too large. Please keep it under $maxMegabytes MB.',
      );
    }

    final path = '$folder/$uid/'
        '${DateTime.now().millisecondsSinceEpoch}${_extensionFor(contentType)}';

    final ref = _bucket.ref(path);
    await ref.putData(
      bytes,
      SettableMetadata(
        contentType: contentType,
        // An image at a versioned path never changes, so let devices and the
        // CDN keep it. Re-fetching something the user has already seen is the
        // biggest avoidable data cost on a metered connection.
        cacheControl: 'public, max-age=31536000, immutable',
      ),
    );
    return ref.getDownloadURL();
  }

  static String _extensionFor(String contentType) => switch (contentType) {
        'image/png' => '.png',
        'image/webp' => '.webp',
        _ => '.jpg',
      };
}
