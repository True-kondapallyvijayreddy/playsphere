import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import '../core/errors/app_exception.dart';
import '../core/firebase/firestore_refs.dart';
import '../core/models/memory.dart';

/// Uploads and reads match memories — the photos that make a career profile
/// worth opening.
///
/// ## Upload order matters
///
/// The bytes go to Cloud Storage first, and only once that succeeds is the
/// Firestore document written. Reversing it would leave a memory document
/// pointing at nothing, which renders as a permanently broken tile that no
/// retry can heal. This way a failed upload leaves an orphaned object instead —
/// invisible, costs a fraction of a paisa, and is reclaimable by a lifecycle
/// rule. Given a choice of which half to leak, leak the half nobody can see.
class MemoryRepository {
  const MemoryRepository({FirebaseStorage? storage}) : _storage = storage;

  final FirebaseStorage? _storage;

  FirebaseStorage get _bucket => _storage ?? FirebaseStorage.instance;

  /// Hard ceiling mirrored from `storage.rules`. Checked client-side too so a
  /// scorer on a village ground gets an instant, explanatory refusal rather
  /// than uploading for ninety seconds into a rules rejection.
  static const int maxImageBytes = 8 * 1024 * 1024;
  static const int maxVideoBytes = 50 * 1024 * 1024;

  Stream<List<Memory>> watchFixtureMemories({
    required String orgId,
    required String compId,
    required String fixtureId,
  }) {
    return Refs.memories(orgId, compId, fixtureId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(Memory.fromDoc).toList());
  }

  /// Every memory a player is tagged in, newest first.
  ///
  /// Capped rather than unbounded: a profile grid shows a page, and an
  /// uncapped collectionGroup listener on a ten-year career is a bill.
  Stream<List<Memory>> watchPlayerMemories(String uid, {int limit = 60}) {
    return Refs.allMemoriesQuery
        .where('taggedUids', arrayContains: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(Memory.fromDoc).toList());
  }

  /// Uploads one memory and returns the stored record.
  ///
  /// [bytes] must already be downscaled by the caller — see
  /// `MemoryComposer`. This method deliberately does no resizing: doing it here
  /// would mean decoding an image inside a repository, on the platform thread,
  /// on the cheapest phone we support.
  Future<Memory> upload({
    required String orgId,
    required String compId,
    required String fixtureId,
    required String uploaderUid,
    required Uint8List bytes,
    required String contentType,
    required MemoryKind kind,
    String? caption,
    List<String> taggedUids = const [],
    int? width,
    int? height,
  }) async {
    final limit = kind == MemoryKind.video ? maxVideoBytes : maxImageBytes;
    if (bytes.lengthInBytes >= limit) {
      throw ValidationException(
        kind == MemoryKind.video
            ? 'That clip is too large. Please keep videos under 50 MB.'
            : 'That photo is too large. Please keep photos under 8 MB.',
      );
    }

    // Firestore generates the id first so the Storage path and the document
    // agree without a second write. The id is also what makes the object
    // unguessable, which storage.rules relies on — see its header comment.
    final docRef = Refs.memories(orgId, compId, fixtureId).doc();
    final ext = _extensionFor(contentType);
    final path = 'memories/$orgId/$fixtureId/$uploaderUid/${docRef.id}$ext';

    try {
      final ref = _bucket.ref(path);
      await ref.putData(
        bytes,
        SettableMetadata(
          contentType: contentType,
          // A memory never changes, so let devices and the CDN keep it for a
          // year. Re-fetching a photo the user has already seen is the single
          // biggest avoidable data cost on a metered rural connection.
          cacheControl: 'public, max-age=31536000, immutable',
        ),
      );
      final url = await ref.getDownloadURL();

      final memory = Memory(
        id: docRef.id,
        orgId: orgId,
        compId: compId,
        fixtureId: fixtureId,
        uploaderUid: uploaderUid,
        storagePath: path,
        url: url,
        kind: kind,
        caption: caption,
        taggedUids: taggedUids,
        width: width,
        height: height,
        sizeBytes: bytes.lengthInBytes,
      );

      await docRef.set(memory.toCreate());
      return memory;
    } on FirebaseException catch (e) {
      throw _mapStorageError(e);
    }
  }

  /// Removes a memory: document first, then the object.
  ///
  /// Document first is the deliberate inverse of upload. The document is what
  /// makes a memory discoverable, so deleting it is the part that actually
  /// honours the request — if the object delete then fails, the photo is
  /// already gone from every screen. Doing it the other way round would leave a
  /// visible tile pointing at deleted bytes.
  Future<void> delete(Memory memory) async {
    try {
      await Refs.memory(
        memory.orgId,
        memory.compId,
        memory.fixtureId,
        memory.id,
      ).delete();
      await _bucket.ref(memory.storagePath).delete();
    } on FirebaseException catch (e) {
      // A missing object is a success for the caller's purpose: the memory is
      // gone. Anything else is real.
      if (e.code == 'object-not-found') return;
      throw _mapStorageError(e);
    }
  }

  Future<void> updateCaption(Memory memory, String? caption) async {
    await Refs.memory(
      memory.orgId,
      memory.compId,
      memory.fixtureId,
      memory.id,
    ).update({'caption': caption});
  }

  String _extensionFor(String contentType) => switch (contentType) {
        'image/png' => '.png',
        'image/webp' => '.webp',
        'image/heic' => '.heic',
        'video/mp4' => '.mp4',
        'video/quicktime' => '.mov',
        'video/webm' => '.webm',
        _ => '.jpg',
      };

  AppException _mapStorageError(FirebaseException e) => switch (e.code) {
        'unauthorized' || 'permission-denied' => const PermissionDeniedException(
            'You are not allowed to add memories to this match.',
          ),
        'canceled' => const NetworkException('The upload was cancelled.'),
        'quota-exceeded' => const ConflictException(
            'Storage is full. Please contact the club owner.',
          ),
        'retry-limit-exceeded' || 'unknown' => const NetworkException(
            'The upload could not finish. Check your connection and try again.',
          ),
        _ => NetworkException(e.message ?? 'The upload failed.'),
      };
}
