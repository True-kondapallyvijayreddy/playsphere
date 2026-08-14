import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/errors/app_exception.dart';
import '../core/firebase/firestore_refs.dart';
import '../domain/scout/talent_board.dart';
import 'org_repository.dart' show guardStream;

/// Reads the precomputed talent-discovery boards.
///
/// ## Why there is almost nothing here
///
/// Everything expensive and everything sensitive about talent discovery
/// happens in `functions/talent.js`: the scan across profiles no client may
/// read, the rising-score ranking, and the decision about who may be named on
/// which board. By the time a board document exists, all of that is settled.
/// This repository's whole job is to turn a chosen scope into a document id
/// and hand back what comes out.
///
/// That asymmetry is the design working, not a gap. A fat client repository
/// here would mean filtering happening on the device — and a privacy filter
/// on the device is a privacy filter an attacker can skip.
///
/// ## What a denied read means
///
/// A `__scout` board is refused by `firestore.rules` to anyone without the
/// `scout` claim. [watchBoard] surfaces that as an empty board rather than an
/// error, the same way `ScoutRepository` treats a denied profile: "you may
/// not see this" and "there is nothing here" are the same outcome for a
/// reader, and rendering an error would tell them a gated board exists.
class TalentBoardRepository {
  const TalentBoardRepository();

  /// Watches one board. Emits null while the board has never been built —
  /// which is a real and common state (a district with no rising players
  /// simply has no document), and reads differently in the UI from an empty
  /// board that was built and found nobody.
  Stream<TalentBoard?> watchBoard(TalentBoardKey key) async* {
    try {
      yield* guardStream(
        () => Refs.talentBoard(key.docId).snapshots().map((doc) {
          if (!doc.exists) return null;
          final computedAt = doc.data()?['computedAt'];
          return TalentBoard.fromMap(
            doc.data(),
            doc.id,
            computedAt: computedAt is Timestamp ? computedAt.toDate() : null,
          );
        }),
      );
    } on PermissionDeniedException {
      // Emitted, not rethrown, and deliberately not swallowed either:
      // swallowing would leave the stream open and the screen spinning
      // forever, while an error would tell an unprivileged reader that a
      // gated board exists at this scope. Null is the same answer they get
      // for a scope nobody has built a board for.
      yield null;
    }
  }
}
