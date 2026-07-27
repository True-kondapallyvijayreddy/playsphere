import 'package:equatable/equatable.dart';

enum TransactionType { income, expense }

/// Blueprint §16 - Finance (income, expenses, sponsors, prize money,
/// invoices, receipts, budgets).
class TransactionEntity extends Equatable {
  const TransactionEntity({
    required this.id,
    required this.orgId,
    required this.type,
    required this.amountCents,
    required this.category,
    required this.occurredAt,
    this.eventId,
    this.notes,
  });

  final String id;
  final String orgId;
  final TransactionType type;
  final int amountCents;
  final String category; // e.g. 'sponsorship', 'prize_money', 'equipment'
  final DateTime occurredAt;
  final String? eventId;
  final String? notes;

  @override
  List<Object?> get props =>
      [id, orgId, type, amountCents, category, occurredAt, eventId, notes];
}
