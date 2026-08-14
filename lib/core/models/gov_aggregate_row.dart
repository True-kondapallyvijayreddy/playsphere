import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_codec.dart';

/// One district's rollup, as written by `functions/gov.js`'s
/// `computeGovAggregates` — see that file's doc comment for why this is a
/// coarser cube than `lib/domain/gov/gov_aggregate.dart`'s full model.
class GovAggregateRow {
  const GovAggregateRow({
    required this.id,
    required this.state,
    required this.district,
    required this.clubCount,
    required this.memberCount,
    required this.competitionCount,
    required this.completedMatchCount,
    this.computedAt,
  });

  final String id;
  final String state;
  final String district;
  final int clubCount;
  final int memberCount;
  final int competitionCount;
  final int completedMatchCount;
  final DateTime? computedAt;

  factory GovAggregateRow.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return GovAggregateRow(
      id: doc.id,
      state: Fs.str(d['state'], 'Unspecified'),
      district: Fs.str(d['district'], 'Unspecified'),
      clubCount: Fs.integer(d['clubCount']),
      memberCount: Fs.integer(d['memberCount']),
      competitionCount: Fs.integer(d['competitionCount']),
      completedMatchCount: Fs.integer(d['completedMatchCount']),
      computedAt: Fs.dateOrNull(d['computedAt']),
    );
  }
}
