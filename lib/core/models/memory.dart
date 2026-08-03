import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_codec.dart';

enum MemoryKind {
  photo('photo'),
  video('video');

  const MemoryKind(this.wire);
  final String wire;

  static MemoryKind fromWire(String? w) => MemoryKind.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => MemoryKind.photo,
      );
}

/// A photo or short clip attached to a match, at
/// `orgs/{orgId}/competitions/{compId}/fixtures/{fixtureId}/memories/{id}`.
///
/// ## Why this document exists at all, given the file is in Cloud Storage
///
/// Storage rules cannot read Firestore, so an object's URL is only as private
/// as it is unguessable. This document is the access-controlled *reference*:
/// Firestore rules decide who may list it, and listing it is the only way to
/// learn the URL. Deleting this document therefore makes a memory
/// undiscoverable even while the bytes linger — which is what lets a club admin
/// moderate immediately without waiting on a storage cleanup job.
///
/// It also carries [taggedUids], which is what turns a pile of match photos
/// into a *player's* memories. Without it the profile grid could only ever show
/// "matches my club played", not "moments I was in".
class Memory {
  const Memory({
    required this.id,
    required this.orgId,
    required this.compId,
    required this.fixtureId,
    required this.uploaderUid,
    required this.storagePath,
    required this.url,
    required this.kind,
    required this.audience,
    this.caption,
    this.taggedUids = const [],
    this.width,
    this.height,
    this.sizeBytes = 0,
    this.createdAt,
  });

  final String id;
  final String orgId;
  final String compId;
  final String fixtureId;
  final String uploaderUid;

  /// The Storage object path. Kept alongside [url] because a download URL
  /// cannot be turned back into a path, and deleting the object needs the path.
  final String storagePath;

  final String url;
  final MemoryKind kind;
  final String? caption;

  /// Who this memory may be listed to: the literal string `public`, or the id
  /// of the club that owns it.
  ///
  /// It exists only because of how Firestore evaluates a collection-group
  /// query. Rules for a `list` are checked against the QUERY's constraints,
  /// not against the documents it would return, so a rule reading a field the
  /// query does not constrain is an evaluation error and the whole query is
  /// denied. The career-profile grid queries every club at once, so
  /// "is this club public, or am I in it?" has to be answerable from a field
  /// the query itself pins down — hence one denormalized value that the query
  /// filters on directly.
  ///
  /// Set at creation from the club's visibility, and frozen thereafter; the
  /// rules verify it against the club document on the way in, so it cannot be
  /// self-declared as `public` by an uploader in an unlisted club.
  final String audience;

  static const publicAudience = 'public';

  /// The [audience] value a club's memories take.
  static String audienceFor({required String orgId, required bool orgIsPublic}) =>
      orgIsPublic ? publicAudience : orgId;

  /// Players appearing in this memory. Drives the career profile grid.
  ///
  /// Kept as uids rather than names so that a memory follows a player when
  /// they change clubs — the whole point of a portable lifelong profile.
  final List<String> taggedUids;

  /// Intrinsic dimensions, so a grid can reserve the right aspect ratio before
  /// the image arrives instead of reflowing as each one loads.
  final int? width;
  final int? height;

  final int sizeBytes;
  final DateTime? createdAt;

  bool get isVideo => kind == MemoryKind.video;

  double get aspectRatio {
    final w = width, h = height;
    if (w == null || h == null || w <= 0 || h <= 0) return 1;
    return w / h;
  }

  factory Memory.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Memory(
      id: doc.id,
      orgId: Fs.str(d['orgId']),
      compId: Fs.str(d['compId']),
      fixtureId: Fs.str(d['fixtureId']),
      uploaderUid: Fs.str(d['uploaderUid']),
      storagePath: Fs.str(d['storagePath']),
      url: Fs.str(d['url']),
      kind: MemoryKind.fromWire(Fs.strOrNull(d['kind'])),
      audience: Fs.str(d['audience']),
      caption: Fs.strOrNull(d['caption']),
      taggedUids: Fs.strList(d['taggedUids']),
      width: d['width'] == null ? null : Fs.integer(d['width']),
      height: d['height'] == null ? null : Fs.integer(d['height']),
      sizeBytes: Fs.integer(d['sizeBytes']),
      createdAt: Fs.dateOrNull(d['createdAt']),
    );
  }

  Map<String, Object?> toCreate() => {
        'orgId': orgId,
        'compId': compId,
        'fixtureId': fixtureId,
        'uploaderUid': uploaderUid,
        'storagePath': storagePath,
        'url': url,
        'kind': kind.wire,
        'audience': audience,
        'caption': caption,
        'taggedUids': taggedUids,
        'width': width,
        'height': height,
        'sizeBytes': sizeBytes,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
