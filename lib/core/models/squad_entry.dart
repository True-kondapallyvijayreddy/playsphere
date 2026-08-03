import 'package:cloud_firestore/cloud_firestore.dart';

import 'enums.dart';
import 'firestore_codec.dart';

/// A member putting their hand up for their own club's side of a match, at
/// `orgs/{hostOrgId}/competitions/{compId}/fixtures/{fixtureId}/squadEntries/{uid}`.
///
/// ## Why this is not an ordinary registration
///
/// A [Registration] is an entry into a *competition*, and the competition
/// decides one field. An inter-club challenge has two fields, chosen by two
/// clubs that do not answer to each other — "ABC challenges XYZ" is one
/// fixture and two independent selection problems. A single competition-level
/// registration list cannot express "the first eleven XYZ members who
/// register are playing", because it cannot say which club a slot belongs to.
///
/// So squad entries hang off the FIXTURE and carry a side. The document id is
/// the member's uid, which makes a double entry impossible, and the side is
/// derived from the club they belong to rather than anything they can type.
class SquadEntry {
  const SquadEntry({
    required this.uid,
    required this.displayName,
    required this.side,
    required this.orgId,
    required this.status,
    this.photoUrl,
    this.waitlistPosition,
    this.addedByAdmin = false,
    this.createdAt,
  });

  final String uid;
  final String displayName;

  /// 'a' or 'b' — which side of the fixture this entry is for.
  final String side;

  /// The club whose side this is. Stored so the rules can check membership of
  /// the right club without reaching back to the fixture on every write.
  final String orgId;

  final RegistrationStatus status;
  final String? photoUrl;

  /// Place in the queue, 1-based, for a reserve.
  final int? waitlistPosition;

  /// True when the club's admin added this player directly rather than the
  /// player registering themselves — the two ways onto a team sheet, kept
  /// distinguishable so the members who registered can see how many slots
  /// were ever really open to them.
  final bool addedByAdmin;

  final DateTime? createdAt;

  bool get isPlaying => status == RegistrationStatus.confirmed;

  factory SquadEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return SquadEntry(
      uid: doc.id,
      displayName: Fs.str(d['displayName'], 'Player'),
      side: Fs.str(d['side'], 'a'),
      orgId: Fs.str(d['orgId']),
      status: RegistrationStatus.fromWire(Fs.str(d['status'])),
      photoUrl: Fs.strOrNull(d['photoUrl']),
      waitlistPosition: d['waitlistPosition'] == null
          ? null
          : Fs.integer(d['waitlistPosition']),
      addedByAdmin: Fs.boolean(d['addedByAdmin']),
      createdAt: Fs.dateOrNull(d['createdAt']),
    );
  }

  Map<String, Object?> toCreate() => {
        'uid': uid,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'side': side,
        'orgId': orgId,
        'status': status.wire,
        'waitlistPosition': waitlistPosition,
        'addedByAdmin': addedByAdmin,
        'createdAt': FieldValue.serverTimestamp(),
      };
}

/// How one club is filling its side of a match.
///
/// The per-side mirror of [ParticipationModel]. It is deliberately narrower:
/// a club filling its own eleven either opens it to members or does not, and
/// the "approval" case is just the admin picking directly, which is the
/// behaviour that already exists.
class SquadCall {
  const SquadCall({
    this.open = false,
    this.capacity,
    this.confirmed = 0,
    this.waitlisted = 0,
    this.waitlistEnabled = true,
  });

  /// Whether members of this club may register themselves for this side.
  final bool open;

  /// How many players this club is picking. Null means no limit, which for a
  /// squad is unusual but legal — a club may want everyone who turns up.
  final int? capacity;

  final int confirmed;
  final int waitlisted;
  final bool waitlistEnabled;

  int? get slotsRemaining {
    final cap = capacity;
    if (cap == null) return null;
    final left = cap - confirmed;
    return left < 0 ? 0 : left;
  }

  bool get isFull {
    final left = slotsRemaining;
    return left != null && left == 0;
  }

  bool get acceptsEntries => open && (!isFull || waitlistEnabled);

  /// What registering right now would produce for this side.
  RegistrationStatus get outcomeOfJoiningNow =>
      isFull ? RegistrationStatus.waitlisted : RegistrationStatus.confirmed;

  factory SquadCall.fromMap(Map<String, dynamic>? d) {
    if (d == null) return const SquadCall();
    return SquadCall(
      open: Fs.boolean(d['open']),
      capacity: d['capacity'] == null ? null : Fs.integer(d['capacity']),
      confirmed: Fs.integer(d['confirmed']),
      waitlisted: Fs.integer(d['waitlisted']),
      waitlistEnabled: d['waitlistEnabled'] == null
          ? true
          : Fs.boolean(d['waitlistEnabled']),
    );
  }

  Map<String, Object?> toMap() => {
        'open': open,
        'capacity': capacity,
        'confirmed': confirmed,
        'waitlisted': waitlisted,
        'waitlistEnabled': waitlistEnabled,
      };
}
