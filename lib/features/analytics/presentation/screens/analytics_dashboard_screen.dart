import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../shared/widgets/portal_scaffold.dart';

class AnalyticsDashboardScreen extends StatelessWidget {
  const AnalyticsDashboardScreen({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context) {
    return PortalScaffold(
      title: 'Organization Analytics & Growth',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // KPI Cards Row
          Row(
            children: [
              Expanded(
                child: _buildKPICard(
                  context,
                  title: 'Total Members',
                  value: '142',
                  subtitle: '+18% this season',
                  icon: Icons.groups,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildKPICard(
                  context,
                  title: 'Matches Played',
                  value: '38',
                  subtitle: '100% officiated',
                  icon: Icons.sports_score,
                  color: Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildKPICard(
                  context,
                  title: 'Revenue Collected',
                  value: '₹42,500',
                  subtitle: 'Fees & Sponsorships',
                  icon: Icons.account_balance_wallet,
                  color: Colors.purple,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildKPICard(
                  context,
                  title: 'Volunteer Hours',
                  value: '124 hrs',
                  subtitle: '12 Referees active',
                  icon: Icons.volunteer_activism,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Registration & Participation Growth Chart
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Monthly Participation Growth',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text('Unique active players per month', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 200,
                    child: BarChart(
                      BarChartData(
                        borderData: FlBorderData(show: false),
                        titlesData: const FlTitlesData(
                          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        barGroups: [
                          BarChartGroupData(x: 1, barRods: [BarChartRodData(toY: 35, color: const Color(0xFF16A34A))]),
                          BarChartGroupData(x: 2, barRods: [BarChartRodData(toY: 50, color: const Color(0xFF16A34A))]),
                          BarChartGroupData(x: 3, barRods: [BarChartRodData(toY: 75, color: const Color(0xFF16A34A))]),
                          BarChartGroupData(x: 4, barRods: [BarChartRodData(toY: 90, color: const Color(0xFF16A34A))]),
                          BarChartGroupData(x: 5, barRods: [BarChartRodData(toY: 120, color: const Color(0xFFDC2626))]),
                          BarChartGroupData(x: 6, barRods: [BarChartRodData(toY: 142, color: const Color(0xFF16A34A))]),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Sport Popularity Breakdown
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sport Distribution & Engagement', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _buildSportProgressRow('Cricket', 0.45, const Color(0xFF16A34A)),
                  const SizedBox(height: 8),
                  _buildSportProgressRow('Badminton', 0.35, const Color(0xFFDC2626)),
                  const SizedBox(height: 8),
                  _buildSportProgressRow('Table Tennis', 0.15, const Color(0xFF10B981)),
                  const SizedBox(height: 8),
                  _buildSportProgressRow('Kabaddi', 0.05, const Color(0xFFF59E0B)),
                ],
              ),
            ),
          ),
          // GCP BigQuery Data Warehouse Integration Card
          Card(
            color: const Color(0xFF0F2314),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFF16A34A), width: 1.2),
            ),
            child: const Padding(
              padding: EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Icon(Icons.cloud_sync, color: Color(0xFF16A34A), size: 28),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('GCP BigQuery Analytics Warehouse', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        Text('Synced live with playsphere-aacfb.playsphere_analytics_dw', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Export Report Button
          ElevatedButton.icon(
            icon: const Icon(Icons.download),
            label: const Text('Export GCP BigQuery Analytics Report (PDF / CSV)'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Exporting BigQuery Dataset playsphere-aacfb:playsphere_analytics_dw.pdf')),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildKPICard(
    BuildContext context, {
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 24),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: Icon(Icons.arrow_upward, color: color, size: 14),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(value, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildSportProgressRow(String label, double percentage, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('${(percentage * 100).toInt()}%'),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: percentage,
          color: color,
          backgroundColor: color.withValues(alpha: 0.15),
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
      ],
    );
  }
}
