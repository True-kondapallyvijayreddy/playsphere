import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import '../core/errors/app_exception.dart';
import '../core/firebase/firestore_refs.dart';
import '../core/models/club_file.dart';
import 'org_repository.dart' show guard, guardStream;

/// Documents a club shares with its members.
///
/// Follows the same upload order as `MemoryRepository`, and for the same
/// reason: bytes to Cloud Storage first, Firestore record second. Reversed,
/// a failure leaves a row pointing at nothing — a permanently broken entry no
/// retry can heal. This way it leaves an invisible orphaned object instead.
/// Given a choice of which half to leak, leak the half nobody can see.
class ClubFileRepository {
  const ClubFileRepository({FirebaseStorage? storage}) : _storage = storage;

  final FirebaseStorage? _storage;

  FirebaseStorage get _bucket => _storage ?? FirebaseStorage.instance;

  /// 10 MB. A club circulates a fixtures list and a rules PDF, not video —
  /// memories already exist for that, with their own ceiling. A generous
  /// limit here would turn every club into free file hosting.
  static const maxBytes = 10 * 1024 * 1024;

  Stream<List<ClubFile>> watch(String orgId) => guardStream(
        () => Refs.clubFiles(orgId)
            .orderBy('createdAt', descending: true)
            .limit(200)
            .snapshots()
            .map((s) => s.docs.map(ClubFile.fromDoc).toList()),
      );

  Future<ClubFile> upload({
    required String orgId,
    required String name,
    required Uint8List bytes,
    required String contentType,
    required String uploaderUid,
    required String uploaderName,
  }) =>
      guard(() async {
        if (bytes.lengthInBytes >= maxBytes) {
          throw const ValidationException(
            'That file is too large. Please keep club files under 10 MB.',
          );
        }
        if (name.trim().isEmpty) {
          throw const ValidationException('Give the file a name.');
        }

        // The document id is generated first so the Storage path and the
        // record agree without a second write, and so the object path is
        // unguessable — which `storage.rules` relies on.
        final docRef = Refs.clubFiles(orgId).doc();
        final path = 'clubFiles/$orgId/$uploaderUid/${docRef.id}';

        try {
          final ref = _bucket.ref(path);
          await ref.putData(
            bytes,
            SettableMetadata(contentType: contentType),
          );
          final url = await ref.getDownloadURL();

          final file = ClubFile(
            id: docRef.id,
            orgId: orgId,
            name: name.trim(),
            url: url,
            storagePath: path,
            uploaderUid: uploaderUid,
            uploaderName: uploaderName,
            sizeBytes: bytes.lengthInBytes,
            contentType: contentType,
          );
          await docRef.set(file.toCreate());
          return file;
        } on FirebaseException catch (e) {
          throw _mapStorageError(e);
        }
      });

  /// Removes the record and the bytes behind it.
  ///
  /// The object goes first: a Firestore row whose object is already gone is a
  /// dead link, while an object whose row is gone is merely invisible and
  /// billed — and the storage delete is the one more likely to fail, since
  /// `storage.rules` only lets the original uploader remove it.
  Future<void> delete(ClubFile file) => guard(() async {
        try {
          await _bucket.ref(file.storagePath).delete();
        } on FirebaseException catch (e) {
          // An object that is already gone is not a reason to leave the row
          // behind pointing at it.
          if (e.code != 'object-not-found') throw _mapStorageError(e);
        }
        await Refs.clubFiles(file.orgId).doc(file.id).delete();
      });

  AppException _mapStorageError(FirebaseException e) => switch (e.code) {
        'unauthorized' => const PermissionDeniedException(),
        'canceled' => const ValidationException('That upload was cancelled.'),
        'retry-limit-exceeded' || 'unknown' => const NetworkException(),
        _ => ValidationException(e.message ?? 'That file could not be saved.'),
      };
}
