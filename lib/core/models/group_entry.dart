import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_codec.dart';

enum GroupEntryStatus {
  /// Named, invited, waiting on the members to say yes.
  forming('forming', 'Waiting on members'),

  /// Everyone invited has accepted. Now it needs an organizer.
  pendingApproval('pending_approval', 'Waiting for the organizer'),

  approved('approved', 'Approved'),
  rejected('rejected', 'Rejected'),
  withdrawn('withdrawn', 'Withdrawn');

  const GroupEntryStatus(this.wire, this.label);
  final String wire;
  final String label;

  static GroupEntryStatus fromWire(String? w) =>
      GroupEntryStatus.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => GroupEntryStatus.forming,
      );
}

/// A set of club members entering an event together, at
/// `orgs/{orgId}/competitions/{compId}/groupEntries/{groupId}`.
///
/// ## Why entering as a group is not the same as entering several times
///
/// Registration was one document per person, so five friends who want to play
/// as one team had exactly one way to say so: enter individually and hope the
/// organizer guessed. The organizer then shuffled the field and split them up,
/// because nothing in the data said they belonged together. "We five are a
/// team" was a fact the app could not hold.
///
/// A group entry holds it. One document, one decision, one place in the field.
///
/// ## The two approvals, and why both are needed
///
/// **The members approve first.** [memberUids] is who the leader NAMED;
/// [acceptedUids] is who has actually agreed. Being added to somebody's team
/// without being asked is how a person ends up committed to a Saturday they
/// knew nothing about, so a group does not reach an organizer until everyone
/// in it has said yes.
///
/// That requirement also enforces "groups must be club members only" without
/// the security rules having to iterate a list, which they cannot do: accepting
/// is a write by the accepting member, and only an active member of the club is
/// allowed to make it. A non-member can be named and can never accept, so a
/// complete group is a group of members by construction.
///
/// **Then the organizer approves.** A complete, willing group is still an
/// entry, and an entry is the organizer's to accept or refuse — the field has a
/// size and a category, and five people agreeing among themselves does not
/// change either.
class GroupEntry {
  const GroupEntry({
    required this.id,
    required this.name,
    required this.leaderUid,
    required this.leaderName,
    required this.memberUids,
    required this.status,
    this.memberNames = const {},
    this.acceptedUids = const [],
    this.declinedUids = const [],
    this.decidedBy,
    this.decisionNote,
    this.createdAt,
  });

  final String id;

  /// What the group calls itself. Becomes the entrant name in the draw, so it
  /// is what appears on the scoreboard.
  final String name;

  final String leaderUid;
  final String leaderName;

  /// Everyone in the group INCLUDING the leader.
  ///
  /// The leader is a member of their own team, not an organizer of it. Leaving
  /// them out would make a group of five read as four everywhere the size is
  /// counted, and the field size is the number that decides whether the entry
  /// fits.
  final List<String> memberUids;

  /// uid → display name, so the list renders without a read per member.
  final Map<String, String> memberNames;

  /// Who has agreed. The leader is in here from creation — proposing the group
  /// is agreeing to it.
  final List<String> acceptedUids;

  /// Who has said no. A single decline is enough to stop the group: the
  /// alternative is a leader waiting forever on somebody who has already
  /// answered.
  final List<String> declinedUids;

  final String? decidedBy;
  final String? decisionNote;
  final DateTime? createdAt;

  int get size => memberUids.length;

  /// Members who have neither accepted nor declined.
  List<String> get pendingUids => [
        for (final uid in memberUids)
          if (!acceptedUids.contains(uid) && !declinedUids.contains(uid)) uid,
      ];

  bool get everyoneAccepted =>
      declinedUids.isEmpty &&
      memberUids.every(acceptedUids.contains) &&
      memberUids.isNotEmpty;

  bool get isSettled =>
      status == GroupEntryStatus.approved ||
      status == GroupEntryStatus.rejected ||
      status == GroupEntryStatus.withdrawn;

  /// Whether [uid] still owes this group an answer — what drives the "waiting
  /// on you" count and the notification.
  bool awaits(String uid) =>
      status == GroupEntryStatus.forming && pendingUids.contains(uid);

  final GroupEntryStatus status;

  String nameFor(String uid) => memberNames[uid] ?? 'Member';

  static GroupEntry fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return GroupEntry(
      id: doc.id,
      name: Fs.str(d['name'], 'Group'),
      leaderUid: Fs.str(d['leaderUid']),
      leaderName: Fs.str(d['leaderName'], 'Leader'),
      memberUids: Fs.strList(d['memberUids']),
      memberNames: {
        for (final e in Fs.map(d['memberNames']).entries)
          e.key: '${e.value}',
      },
      acceptedUids: Fs.strList(d['acceptedUids']),
      declinedUids: Fs.strList(d['declinedUids']),
      status: GroupEntryStatus.fromWire(Fs.strOrNull(d['status'])),
      decidedBy: Fs.strOrNull(d['decidedBy']),
      decisionNote: Fs.strOrNull(d['decisionNote']),
      createdAt: Fs.dateOrNull(d['createdAt']),
    );
  }

  Map<String, Object?> toCreate() => {
        'name': name,
        'leaderUid': leaderUid,
        'leaderName': leaderName,
        'memberUids': memberUids,
        'memberNames': memberNames,
        // Proposing the group is agreeing to it, so the leader is never asked
        // a question they have already answered.
        'acceptedUids': [leaderUid],
        'declinedUids': const <String>[],
        'status': GroupEntryStatus.forming.wire,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
