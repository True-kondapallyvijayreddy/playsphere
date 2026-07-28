import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'enums.dart';
import 'firestore_codec.dart';

/// A tenant: a residential community, school, college, academy, club,
/// district association or state council. Stored at `orgs/{orgId}`.
///
/// Orgs form a tree via [parentOrgId] so a district association can sit above
/// the schools inside it, which is what lets a result earned at school level
/// be promoted into a district competition later.
class Organization {
  const Organization({
    required this.id,
    required this.name,
    required this.orgType,
    required this.visibility,
    required this.ownerUid,
    required this.inviteCode,
    this.parentOrgId,
    this.description,
    this.district,
    this.city,
    this.logoUrl,
    this.memberCount = 0,
    this.requiresApprovalToJoin = true,
    this.createdBy,
    this.createdAt,
    this.deletedAt,
  });

  final String id;
  final String name;
  final OrgType orgType;
  final OrgVisibility visibility;

  /// Exactly one owner uid lives here. Security rules read it to decide who
  /// may transfer ownership or change org-level governance settings.
  final String ownerUid;

  /// Short human-shareable code. A coach reads it out in a WhatsApp group and
  /// players join without needing to be found by search.
  final String inviteCode;

  final String? parentOrgId;
  final String? description;
  final String? district;
  final String? city;
  final String? logoUrl;
  final int memberCount;

  /// When false, anyone with the invite code becomes active immediately.
  /// Schools generally want this true; a casual apartment community usually
  /// does not, and forcing approval there just means nobody ever gets let in.
  final bool requiresApprovalToJoin;

  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;
  bool get isPublic => visibility == OrgVisibility.public;

  factory Organization.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Organization(
      id: doc.id,
      name: Fs.str(d['name'], 'Unnamed organization'),
      orgType: OrgType.fromWire(Fs.str(d['orgType'])),
      visibility: OrgVisibility.fromWire(Fs.str(d['visibility'])),
      ownerUid: Fs.str(d['ownerUid']),
      inviteCode: Fs.str(d['inviteCode']),
      parentOrgId: Fs.strOrNull(d['parentOrgId']),
      description: Fs.strOrNull(d['description']),
      district: Fs.strOrNull(d['district']),
      city: Fs.strOrNull(d['city']),
      logoUrl: Fs.strOrNull(d['logoUrl']),
      memberCount: Fs.integer(d['memberCount']),
      requiresApprovalToJoin: Fs.boolean(d['requiresApprovalToJoin'], true),
      createdBy: Fs.strOrNull(d['createdBy']),
      createdAt: Fs.dateOrNull(d['createdAt']),
      deletedAt: Fs.dateOrNull(d['deletedAt']),
    );
  }

  Map<String, Object?> toCreate() => {
        'name': name,
        'nameLower': name.toLowerCase(),
        'orgType': orgType.wire,
        'visibility': visibility.wire,
        'ownerUid': ownerUid,
        'inviteCode': inviteCode,
        'parentOrgId': parentOrgId,
        'description': description,
        'district': district,
        'city': city,
        'logoUrl': logoUrl,
        'memberCount': 1,
        'requiresApprovalToJoin': requiresApprovalToJoin,
        'createdBy': ownerUid,
        'createdAt': FieldValue.serverTimestamp(),
        'deletedAt': null,
      };

  Map<String, Object?> toUpdate() => Fs.prune({
        'name': name,
        'nameLower': name.toLowerCase(),
        'description': description,
        'district': district,
        'city': city,
        'logoUrl': logoUrl,
        'requiresApprovalToJoin': requiresApprovalToJoin,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// Six characters from an alphabet with no `0/O`, `1/I/L` — codes get read
  /// aloud and copied off whiteboards, and those pairs are where it goes
  /// wrong.
  static String generateInviteCode([Random? random]) {
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final rng = random ?? Random.secure();
    return List.generate(6, (_) => alphabet[rng.nextInt(alphabet.length)])
        .join();
  }

  Organization copyWith({
    String? name,
    String? description,
    String? district,
    String? city,
    String? logoUrl,
    bool? requiresApprovalToJoin,
    OrgVisibility? visibility,
  }) {
    return Organization(
      id: id,
      name: name ?? this.name,
      orgType: orgType,
      visibility: visibility ?? this.visibility,
      ownerUid: ownerUid,
      inviteCode: inviteCode,
      parentOrgId: parentOrgId,
      description: description ?? this.description,
      district: district ?? this.district,
      city: city ?? this.city,
      logoUrl: logoUrl ?? this.logoUrl,
      memberCount: memberCount,
      requiresApprovalToJoin:
          requiresApprovalToJoin ?? this.requiresApprovalToJoin,
      createdBy: createdBy,
      createdAt: createdAt,
      deletedAt: deletedAt,
    );
  }
}

/// A person's role inside one organization, at `orgs/{orgId}/members/{uid}`.
///
/// The document id is the uid, which makes "one membership per person per
/// org" a structural guarantee rather than something a query has to police.
class Membership {
  const Membership({
    required this.uid,
    required this.orgId,
    required this.role,
    required this.status,
    required this.displayName,
    this.photoUrl,
    this.joinedAt,
    this.invitedBy,
    this.approvedBy,
    this.jerseyNumber,
    this.notes,
  });

  final String uid;
  final String orgId;
  final MembershipRole role;
  final MembershipStatus status;

  /// Denormalized from the user profile so a roster list renders from a
  /// single query instead of N profile fetches. Refreshed on approval.
  final String displayName;
  final String? photoUrl;

  final DateTime? joinedAt;
  final String? invitedBy;
  final String? approvedBy;
  final String? jerseyNumber;
  final String? notes;

  bool get isActive => status == MembershipStatus.active;
  bool get isPending => status == MembershipStatus.pending;

  factory Membership.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Membership(
      uid: doc.id,
      orgId: Fs.str(d['orgId']),
      role: MembershipRole.fromWire(Fs.str(d['role'])),
      status: MembershipStatus.fromWire(Fs.str(d['status'])),
      displayName: Fs.str(d['displayName'], 'Member'),
      photoUrl: Fs.strOrNull(d['photoUrl']),
      joinedAt: Fs.dateOrNull(d['joinedAt']),
      invitedBy: Fs.strOrNull(d['invitedBy']),
      approvedBy: Fs.strOrNull(d['approvedBy']),
      jerseyNumber: Fs.strOrNull(d['jerseyNumber']),
      notes: Fs.strOrNull(d['notes']),
    );
  }

  Map<String, Object?> toCreate() => {
        'uid': uid,
        'orgId': orgId,
        'role': role.wire,
        'status': status.wire,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'joinedAt': FieldValue.serverTimestamp(),
        'invitedBy': invitedBy,
        'approvedBy': approvedBy,
      };
}
