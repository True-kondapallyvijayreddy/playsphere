import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_codec.dart';

/// A document a club has shared with its members, at
/// `orgs/{orgId}/files/{fileId}`.
///
/// The fixtures list a school sends round, a tournament's rules PDF, a consent
/// form for a trial. The flow puts files inside a club next to announcements
/// and polls, and until now there was nowhere to put one — which in practice
/// means they live in a WhatsApp group and are gone by the time anyone needs
/// them again.
///
/// The bytes live in Cloud Storage; this is the record that makes them
/// findable and tells the rules who may see them.
class ClubFile {
  const ClubFile({
    required this.id,
    required this.orgId,
    required this.name,
    required this.url,
    required this.storagePath,
    required this.uploaderUid,
    required this.uploaderName,
    this.sizeBytes = 0,
    this.contentType,
    this.createdAt,
  });

  final String id;
  final String orgId;

  /// What the club calls it, which is not necessarily the filename — "Ground
  /// rules" reads better in a list than "IMG_20260731_final_v2.pdf".
  final String name;

  final String url;

  /// Kept so the object can be deleted along with this record. Without it a
  /// removed file leaves its bytes behind, billed forever.
  final String storagePath;

  final String uploaderUid;
  final String uploaderName;
  final int sizeBytes;
  final String? contentType;
  final DateTime? createdAt;

  /// A size a person can read, rather than a number of bytes.
  String get readableSize {
    if (sizeBytes <= 0) return '';
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  factory ClubFile.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return ClubFile(
      id: doc.id,
      orgId: Fs.str(d['orgId']),
      name: Fs.str(d['name'], 'File'),
      url: Fs.str(d['url']),
      storagePath: Fs.str(d['storagePath']),
      uploaderUid: Fs.str(d['uploaderUid']),
      uploaderName: Fs.str(d['uploaderName'], 'Admin'),
      sizeBytes: Fs.integer(d['sizeBytes']),
      contentType: Fs.strOrNull(d['contentType']),
      createdAt: Fs.dateOrNull(d['createdAt']),
    );
  }

  Map<String, Object?> toCreate() => {
        'orgId': orgId,
        'name': name,
        'url': url,
        'storagePath': storagePath,
        'uploaderUid': uploaderUid,
        'uploaderName': uploaderName,
        'sizeBytes': sizeBytes,
        'contentType': contentType,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
