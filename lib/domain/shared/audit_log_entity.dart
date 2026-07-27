import 'package:equatable/equatable.dart';

/// Money is always an integer count of the smallest currency unit
/// (paise for INR). Never store or compute money as a double/float
/// anywhere in the app — see Appendix, "Money fields are integers in
/// the smallest currency unit (paise), never floats."
typedef Paise = int;

/// Every domain object in the spec implicitly carries `created_at` /
/// `updated_at`, and every object gets soft-delete via `deleted_at`.
/// Mix this into entities instead of repeating the three fields.
///
/// TODO(repository-layer): enforce "soft-delete only" — no entity with
/// any downstream reference (ratings, results, memberships, etc.) may
/// ever be hard-deleted. `deletedAt` is the only deletion mechanism.
mixin TimestampedSoftDeletable {
  DateTime get createdAt;
  DateTime get updatedAt;
  DateTime? get deletedAt;

  bool get isDeleted => deletedAt != null;
}

/// Purpose: append-only ledger of every write to a scoring-relevant
/// object. Not optional — this is what makes disputed results
/// resolvable later (spec §0, Conventions).
///
/// TODO(repository-layer): every write to Fixture, MatchEvent,
/// Standing, RatingRecord, RatingHistoryEntry, Achievement,
/// OrganizationMembership.role, and Season/SportCompetition status
/// transitions must append a row here, inside the same transaction as
/// the write it documents.
class AuditLogEntry extends Equatable {
  const AuditLogEntry({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.actorUserId,
    required this.action,
    required this.diffJson,
    required this.createdAt,
  });

  final String id;

  /// The class name of the entity being audited, e.g. "Fixture".
  final String entityType;
  final String entityId;
  final String actorUserId;

  /// Free-form action label, e.g. "status_transition", "score_edit".
  final String action;

  /// Structured before/after diff. Kept as a raw map rather than a
  /// typed shape because it must represent the diff of *any* entity.
  final Map<String, dynamic> diffJson;
  final DateTime createdAt;

  @override
  List<Object?> get props =>
      [id, entityType, entityId, actorUserId, action, diffJson, createdAt];
}
