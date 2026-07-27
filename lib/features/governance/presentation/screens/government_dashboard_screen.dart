import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../shared/widgets/portal_scaffold.dart';

class GovernmentDashboardScreen extends StatelessWidget {
  const GovernmentDashboardScreen({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context) {
    return PortalScaffold(
      title: "State Sports Council & CM's Executive Dashboard",
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Banner
          Card(
            color: Colors.amber.withValues(alpha: 0.15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.amber.shade700.withValues(alpha: 0.3)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.account_balance, color: Colors.amber[900], size: 36),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Telangana CM's Cup & State Games Monitoring Hub",
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Real-time data telemetry across all 33 Districts • 540,000+ Participants',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Overview KPI Cards
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(context, 'Active Districts', '33 / 33', Icons.map, Colors.indigo),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(context, 'Disciplines Conducted', '46 Sports', Icons.sports, Colors.teal),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(context, 'Female Participation', '44.8%', Icons.female, Colors.purple),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(context, 'Talent Scout Nominations', '1,280 Athletes', Icons.star, Colors.orange),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // District Medal Tally Table
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("CM's Cup 2025 District Medal Tally", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('District')),
                        DataColumn(label: Text('🥇 Gold')),
                        DataColumn(label: Text('🥈 Silver')),
                        DataColumn(label: Text('🥉 Bronze')),
                        DataColumn(label: Text('Total')),
                      ],
                      rows: const [
                        DataRow(cells: [
                          DataCell(Text('Hyderabad', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataCell(Text('24')),
                          DataCell(Text('18')),
                          DataCell(Text('15')),
                          DataCell(Text('57', style: TextStyle(fontWeight: FontWeight.bold))),
                        ]),
                        DataRow(cells: [
                          DataCell(Text('Rangareddy', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataCell(Text('19')),
                          DataCell(Text('14')),
                          DataCell(Text('12')),
                          DataCell(Text('45', style: TextStyle(fontWeight: FontWeight.bold))),
                        ]),
                        DataRow(cells: [
                          DataCell(Text('Warangal', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataCell(Text('15')),
                          DataCell(Text('12')),
                          DataCell(Text('10')),
                          DataCell(Text('37', style: TextStyle(fontWeight: FontWeight.bold))),
                        ]),
                        DataRow(cells: [
                          DataCell(Text('Suryapet', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataCell(Text('11')),
                          DataCell(Text('9')),
                          DataCell(Text('8')),
                          DataCell(Text('28', style: TextStyle(fontWeight: FontWeight.bold))),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Gender & Age Group Distribution Pie/Bar Chart
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('State Demographic Breakdown', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 180,
                    child: PieChart(
                      PieChartData(
                        sections: [
                          PieChartSectionData(color: Colors.indigo, value: 55, title: 'Male 55%', radius: 50, titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          PieChartSectionData(color: Colors.purple, value: 45, title: 'Female 45%', radius: 50, titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Open Data Export Button
          ElevatedButton.icon(
            icon: const Icon(Icons.table_chart),
            label: const Text('Export Official State Sports Report (Open Data CSV / PDF)'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Downloaded State Government MIS Report: telangana-cmcup-2025-analytics.pdf')),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(BuildContext context, String title, String value, IconData icon, Color color) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
            Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
