import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_codec.dart';

enum OwnerProposalStatus {
  open('open', 'Open'),
  passed('passed', 'Passed'),
  withdrawn('withdrawn', 'Withdrawn');

  const OwnerProposalStatus(this.wire, this.label);
  final String wire;
  final String label;

  static OwnerProposalStatus fromWire(String? w) =>
      OwnerProposalStatus.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => OwnerProposalStatus.open,
      );
}

/// A motion to remove one of a club's owners, at
/// `orgs/{orgId}/ownerProposals/{proposalId}`.
///
/// The document id is the target's uid, which makes two simultaneous motions
/// against the same person structurally impossible — otherwise a determined
/// owner could open five and split the vote, or open one a day until the
/// others stopped reading them.
class OwnerProposal {
  const OwnerProposal({
    required this.targetUid,
    required this.targetName,
    required this.openedBy,
    required this.reason,
    required this.status,
    this.votes = const [],
    this.openedAt,
    this.resolvedAt,
  });

  final String targetUid;
  final String targetName;
  final String openedBy;

  /// Why, in the proposer's words. Required for the same reason a cancelled
  /// event's reason is: the other owners are being asked to agree to something
  /// and cannot do that from a name alone.
  final String reason;

  final OwnerProposalStatus status;

  /// The uids that have voted in favour.
  ///
  /// A list of uids rather than a count, because a count cannot be checked. A
  /// client incrementing a number could pass any threshold on its own; a list
  /// can only grow by one uid, that uid must be the caller's, and
  /// `firestore.rules` enforces exactly that. The tally is then whatever the
  /// list length says it is, and it cannot be inflated.
  ///
  /// Includes the proposer: opening a motion is voting for it.
  final List<String> votes;

  final DateTime? openedAt;
  final DateTime? resolvedAt;

  bool get isOpen => status == OwnerProposalStatus.open;

  bool hasVoted(String uid) => votes.contains(uid);

  static OwnerProposal fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const {};
    return OwnerProposal(
      targetUid: Fs.str(d['targetUid'], doc.id),
      targetName: Fs.str(d['targetName'], 'This owner'),
      openedBy: Fs.str(d['openedBy']),
      reason: Fs.str(d['reason']),
      status: OwnerProposalStatus.fromWire(Fs.strOrNull(d['status'])),
      votes: Fs.strList(d['votes']),
      openedAt: Fs.dateOrNull(d['openedAt']),
      resolvedAt: Fs.dateOrNull(d['resolvedAt']),
    );
  }

  Map<String, Object?> toCreate() => {
        'targetUid': targetUid,
        'targetName': targetName,
        'openedBy': openedBy,
        'reason': reason,
        'status': OwnerProposalStatus.open.wire,
        'votes': votes,
        'openedAt': FieldValue.serverTimestamp(),
      };
}
