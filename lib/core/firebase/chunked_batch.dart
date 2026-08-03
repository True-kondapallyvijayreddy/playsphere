import 'package:cloud_firestore/cloud_firestore.dart';

/// A write that is too big for one Firestore batch.
///
/// Firestore caps a `WriteBatch` at 500 operations. A draw for a real
/// tournament blows straight through that: 38 entrants in a round robin is 703
/// fixtures, and regenerating adds a delete per existing fixture on top — so
/// roughly 1,400 operations for one tap of "Generate the draw".
///
/// Before this existed, `generateDraw` put all of them in a single batch and
/// committed it with `unawaited(...catchError(...))`. The batch was rejected,
/// the sink swallowed the error, and the organizer was shown
/// "703 matches created" for a draw that did not exist.
///
/// ## Why the chunks are not awaited in order
///
/// The obvious shape — `for (final b in batches) await b.commit();` — breaks
/// offline scoring, and does so silently. With persistence enabled a
/// `commit()` future does not complete until the SERVER acknowledges, so on a
/// ground with no signal the first `await` never returns and chunks two
/// onward are never even handed to Firestore. Nothing after the 400th
/// operation would reach the local cache, and the organizer would see a
/// half-drawn tournament with no error.
///
/// So every chunk is committed immediately and independently. Firestore
/// applies each one to the local cache synchronously, which is what makes the
/// whole draw readable offline the moment it is generated, and flushes them
/// when the network returns.
///
/// ## What that costs, stated plainly
///
/// Atomicity across chunks is genuinely lost. A draw can land partially — say
/// the server accepts three chunks and rejects the fourth. That is why
/// [CompetitionRepository.verifyDraw] exists and why every fixture carries a
/// `drawId`: the honest response to "this is not atomic" is a way to detect
/// and repair a partial write, not a comment claiming it will not happen.
class ChunkedBatch {
  ChunkedBatch(this._db, {this.limit = _defaultLimit})
      : assert(limit > 0 && limit <= 500, 'Firestore caps a batch at 500');

  /// Deliberately below Firestore's 500. The margin is not superstition:
  /// callers routinely append a trailing update (a status change, a counter)
  /// after the bulk of the work, and a limit of exactly 500 turns that last
  /// innocuous line into a rejected batch.
  static const _defaultLimit = 400;

  final FirebaseFirestore _db;
  final int limit;

  final List<WriteBatch> _batches = [];
  WriteBatch? _current;
  int _opsInCurrent = 0;
  int _total = 0;

  int get operationCount => _total;
  int get chunkCount => _batches.length;

  WriteBatch get _batch {
    if (_current == null || _opsInCurrent >= limit) {
      _current = _db.batch();
      _batches.add(_current!);
      _opsInCurrent = 0;
    }
    _opsInCurrent++;
    _total++;
    return _current!;
  }

  void set(DocumentReference<Map<String, dynamic>> ref, Map<String, Object?> data) =>
      _batch.set(ref, data);

  void update(DocumentReference<Map<String, dynamic>> ref, Map<String, Object?> data) =>
      _batch.update(ref, data);

  void delete(DocumentReference<Map<String, dynamic>> ref) => _batch.delete(ref);

  /// Fires every chunk at once and returns a future that completes when they
  /// all have — or fails with the first failure.
  ///
  /// The caller decides whether to await it. On the scoring and draw paths
  /// nobody does: the local cache already has the writes, and awaiting would
  /// hang until the server answered.
  Future<void> commitAll() =>
      Future.wait(_batches.map((b) => b.commit())).then((_) {});
}
