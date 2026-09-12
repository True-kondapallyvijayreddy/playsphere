import 'package:cloud_firestore/cloud_firestore.dart' show FieldValue, SetOptions;

import '../core/firebase/firestore_refs.dart';
import '../core/models/platform_staff.dart';
import 'org_repository.dart' show guard, guardStream;

/// The PlaySphere operations roster — see [StaffMember]'s class doc for why
/// it exists next to the `admin` custom claim rather than in place of it.
///
/// Every method here is gated by `firestore.rules` on the claim, so this
/// repository is only ever usable from a console screen that has already
/// checked `isPlatformAdminProvider` — the check on the screen exists so the
/// UI does not present a queue it cannot load, not as the gate itself.
class StaffRepository {
  const StaffRepository();

  /// The whole team. Small by definition — this is a handful of people, not
  /// a collection that grows with usage — so it is read whole and sorted on
  /// the client rather than indexed.
  Stream<List<StaffMember>> watchStaff() => guardStream(
        () => Refs.platformStaff.snapshots().map((s) {
          final rows = s.docs.map(StaffMember.fromDoc).toList();
          rows.sort((a, b) => a.displayName
              .toLowerCase()
              .compareTo(b.displayName.toLowerCase()));
          return List<StaffMember>.unmodifiable(rows);
        }),
      );

  /// This account's own row, or null if they are not on the roster.
  ///
  /// Null is a real, ordinary answer and not an error: the very first admin
  /// — the owner — holds the claim before any row exists, which is exactly
  /// the state [addSelf] is for.
  Stream<StaffMember?> watchMe(String uid) => guardStream(
        () => Refs.staffMember(uid).snapshots().map(
              (d) => d.exists ? StaffMember.fromDoc(d) : null,
            ),
      );

  /// Puts somebody on the roster, or updates the desks of somebody already
  /// on it. A `set` with merge rather than a create so re-adding a teammate
  /// who is already there changes their desks instead of failing — the
  /// roster screen offers exactly one control for both.
  Future<void> upsert(
    StaffMember member, {
    required String addedByUid,
  }) =>
      guard(
        () => Refs.staffMember(member.uid).set(
          member.toCreate(addedByUid: addedByUid),
          SetOptions(merge: true),
        ),
      );

  /// Changes which queues one member is paged for, without touching who
  /// added them or when.
  Future<void> setDesks(String uid, List<StaffDesk> desks) => guard(
        () => Refs.staffMember(uid).update({
          'desks': desks.map((d) => d.wire).toList(growable: false),
          'updatedAt': FieldValue.serverTimestamp(),
        }),
      );

  /// Takes somebody off the notification roster.
  ///
  /// Deliberately does NOT revoke their access — that is the `admin` claim,
  /// granted server-side, and pretending a delete here removed it would be
  /// the more dangerous lie of the two. See [StaffMember]'s class doc.
  Future<void> remove(String uid) => guard(
        () => Refs.staffMember(uid).delete(),
      );
}
