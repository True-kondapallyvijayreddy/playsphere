import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_codec.dart';

/// Which queue a staff member is on the hook for.
///
/// A desk is a *routing* fact, not a permission: `firestore.rules` gates
/// every one of these queues on the single `admin` claim and nothing else,
/// exactly as it did before this roster existed. What a desk decides is who
/// gets woken up when something lands — an ops team of four where all four
/// are pinged by every donation is a team that stops reading the pings.
///
/// See `functions/index.js`'s `staffUidsForDesk`, the only thing that reads
/// this field, and `firestore.rules` on `platformStaff` for why a member can
/// never grant themselves a desk they were not given.
enum StaffDesk {
  /// Advertiser campaigns waiting for approval — `adCampaigns`.
  ads('ads', 'Advertising', 'New campaigns waiting for approval'),

  /// Donations arriving and needs raised — `giveDonations`, `giveNeeds`.
  give('give', 'Give', 'Donations arriving and needs raised'),

  /// Ground listings and reports — the queue `GroundReviewScreen` already
  /// serves. Listed here so one roster answers "who is on call for what"
  /// for every staff queue, not only the two this file was added for.
  grounds('grounds', 'Grounds', 'Listings and reports to verify');

  const StaffDesk(this.wire, this.label, this.blurb);

  final String wire;
  final String label;
  final String blurb;

  static StaffDesk? fromWire(String? w) {
    for (final d in StaffDesk.values) {
      if (d.wire == w) return d;
    }
    return null;
  }

  static List<StaffDesk> listFromRaw(Object? v) => v is List
      ? v
          .map((e) => StaffDesk.fromWire(e?.toString()))
          .whereType<StaffDesk>()
          .toList(growable: false)
      : const [];
}

/// One person on the PlaySphere operations team, at `platformStaff/{uid}`.
///
/// ## Why a roster document exists at all when a custom claim already does
///
/// The `admin` custom claim answers "may this account act on a staff queue",
/// and it is the only thing `firestore.rules` trusts. It cannot answer the
/// two questions the ops consoles actually need answered:
///
///  1. **Who should be told?** A claim lives on an auth token. Cloud
///     Functions cannot enumerate accounts by claim without walking every
///     user in the project, so a submitted campaign or an arriving donation
///     had nowhere to send a notification and silently went nowhere. This
///     collection is queryable, so `onAdCampaignSubmitted` and its Give
///     counterparts have a recipient list.
///  2. **Told about what?** See [StaffDesk].
///
/// The two are deliberately kept apart rather than folded together: a row
/// here grants nothing, and revoking someone's access is still a claim
/// change, not a delete. A stale row costs a notification sent to somebody
/// whose console will refuse to load — the harmless direction.
class StaffMember {
  const StaffMember({
    required this.uid,
    required this.displayName,
    this.photoUrl,
    this.playerCode,
    this.desks = const [],
    this.addedByUid,
    this.addedAt,
  });

  final String uid;
  final String displayName;
  final String? photoUrl;

  /// The PSOS code this person was added by, kept so the roster can be read
  /// back by a human who only knows teammates by their code.
  final String? playerCode;

  final List<StaffDesk> desks;

  final String? addedByUid;
  final DateTime? addedAt;

  bool isOn(StaffDesk desk) => desks.contains(desk);

  factory StaffMember.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return StaffMember(
      uid: doc.id,
      displayName: Fs.str(d['displayName'], 'Staff'),
      photoUrl: Fs.strOrNull(d['photoUrl']),
      playerCode: Fs.strOrNull(d['playerCode']),
      desks: StaffDesk.listFromRaw(d['desks']),
      addedByUid: Fs.strOrNull(d['addedByUid']),
      addedAt: Fs.dateOrNull(d['addedAt']),
    );
  }

  Map<String, Object?> toCreate({required String addedByUid}) => Fs.prune({
        'uid': uid,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'playerCode': playerCode,
        'desks': desks.map((d) => d.wire).toList(growable: false),
        'addedByUid': addedByUid,
        'addedAt': FieldValue.serverTimestamp(),
      });
}
