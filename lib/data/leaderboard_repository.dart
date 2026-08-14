import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/errors/app_exception.dart';
import '../core/firebase/firestore_refs.dart';
import '../domain/career/leaderboard.dart';
import 'org_repository.dart' show guardStream;

/// Reads the precomputed per-sport, per-stat leaderboards.
///
/// ## Why there is almost nothing here
///
/// Same shape as `TalentBoardRepository`, for the same reason: everything
/// expensive (the scan across every player's `career_stats`) and everything
/// sensitive (who is eligible to be ranked at all) already happened in
/// `functions/leaderboard.js`. By the time a board document exists, both
/// decisions are settled — this repository's whole job is turning a chosen
/// sport and stat into a document id and handing back what comes out.
class LeaderboardRepository {
  const LeaderboardRepository();

  /// Watches one board. Emits null while it has never been built — a sport
  /// with no eligible player yet has no document — which reads differently
  /// in the UI from a board that was built and is genuinely empty.
  Stream<Leaderboard?> watchBoard(LeaderboardKey key) async* {
    try {
      yield* guardStream(
        () => Refs.leaderboard(key.docId).snapshots().map((doc) {
          if (!doc.exists) return null;
          final updatedAt = doc.data()?['updatedAt'];
          return Leaderboard.fromMap(
            doc.data(),
            doc.id,
            updatedAt: updatedAt is Timestamp ? updatedAt.toDate() : null,
          );
        }),
      );
    } on PermissionDeniedException {
      // Leaderboards are world-readable, so this should never actually
      // trigger — kept for the same reason `TalentBoardRepository` keeps it:
      // a denied read surfaces as "nothing here" rather than an error the
      // screen would otherwise have to explain.
      yield null;
    }
  }
}
