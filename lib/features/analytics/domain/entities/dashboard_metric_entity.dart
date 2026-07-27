import 'package:equatable/equatable.dart';

/// Blueprint §19 - Analytics. A single metric/time-series point
/// feeding into dashboards (registrations, attendance, revenue, ...).
class DashboardMetricEntity extends Equatable {
  const DashboardMetricEntity({
    required this.key,
    required this.label,
    required this.value,
    this.periodStart,
    this.periodEnd,
  });

  final String key; // e.g. 'registrations', 'revenue', 'attendance'
  final String label;
  final num value;
  final DateTime? periodStart;
  final DateTime? periodEnd;

  @override
  List<Object?> get props => [key, label, value, periodStart, periodEnd];
}
