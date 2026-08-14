import 'package:cloud_functions/cloud_functions.dart';

import '../core/errors/app_exception.dart';
import '../core/firebase/firestore_refs.dart';
import '../core/models/gov_aggregate_row.dart';
import 'org_repository.dart' show guard, guardStream;

/// Reads the district rollups, and triggers a recompute.
///
/// Read access is enforced by `firestore.rules`' `admin`-claim check on
/// `gov_aggregates` — this repository does not re-check the claim itself,
/// the same posture `AdConsoleScreen`/`GiveCollectionCentersScreen` take
/// with their own gates. A non-admin calling [recompute] gets the
/// callable's own `permission-denied`; a non-admin reading [watchAll] gets
/// an empty stream once the rules deny it, not a crash.
class GovRepository {
  const GovRepository();

  Stream<List<GovAggregateRow>> watchAll() => guardStream(
        () => Refs.govAggregates.orderBy('memberCount', descending: true).snapshots().map(
              (s) => s.docs.map(GovAggregateRow.fromDoc).toList(growable: false),
            ),
      );

  /// Re-runs `computeGovAggregates` and overwrites every row. Bounded to
  /// platform staff by the callable itself — see `functions/gov.js`.
  Future<int> recompute() => guard(() async {
        try {
          final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
              .httpsCallable('computeGovAggregates');
          final result = await callable.call<Map<String, dynamic>>();
          return result.data['districtCount'] as int? ?? 0;
        } on FirebaseFunctionsException catch (e) {
          throw ValidationException(
            e.message ?? 'Could not recompute the dashboard. Try again.',
          );
        }
      });
}
