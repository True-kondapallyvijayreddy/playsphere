import '../core/firebase/firestore_refs.dart';
import '../core/models/sport_stat_row.dart';
import 'org_repository.dart' show guardStream;

/// Reads the per-sport directory totals written by `functions/sports.js`.
///
/// One stream for the whole collection rather than a document read per sport.
/// The directory renders every sport in `SportCatalog.all` on one screen, so
/// a per-sport read would be fifteen listeners on a screen that exists to be
/// scrolled once — and fifteen is the count today, on a catalogue built to
/// grow.
class SportStatsRepository {
  const SportStatsRepository();

  /// Keyed by sport id so the directory can look a row up by the catalogue
  /// entry it is already iterating, and fall back to
  /// [SportStatRow.empty] for a sport the rollup has not seen yet.
  Stream<Map<String, SportStatRow>> watchAll() => guardStream(
        () => Refs.sportStats.snapshots().map(
              (s) => {
                for (final doc in s.docs) doc.id: SportStatRow.fromDoc(doc),
              },
            ),
      );
}
