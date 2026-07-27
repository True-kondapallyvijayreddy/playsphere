import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/play_sphere_store.dart';
import '../../../../domain/domain.dart';
import '../../../../shared/widgets/portal_scaffold.dart';

class MemberProfileScreen extends ConsumerWidget {
  const MemberProfileScreen({
    super.key,
    required this.orgId,
    required this.memberId,
  });

  final String orgId;
  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(playSphereStoreProvider);
    final member = store.member;
    final achievements = store.achievements;

    return PortalScaffold(
      title: 'Portable Player Profile',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Text(
                      member.name[0],
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(member.name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('Portable Identity ID: ${member.id}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Chip(
                              label: const Text('Statewide Verified'),
                              backgroundColor: Colors.blue.withValues(alpha: 0.15),
                              labelStyle: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                            const SizedBox(width: 8),
                            Chip(
                              label: Text('${member.rating} ELO'),
                              backgroundColor: Colors.green.withValues(alpha: 0.15),
                              labelStyle: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ELO Rating Progress Chart
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('ELO Rating Progression (Table Tennis)', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const Chip(
                        avatar: Icon(Icons.trending_up, color: Colors.green, size: 16),
                        label: Text('+40 pts this season'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 180,
                    child: LineChart(
                      LineChartData(
                        gridData: const FlGridData(show: false),
                        titlesData: const FlTitlesData(show: false),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: const [
                              FlSpot(0, 1200),
                              FlSpot(1, 1250),
                              FlSpot(2, 1240),
                              FlSpot(3, 1310),
                              FlSpot(4, 1380),
                              FlSpot(5, 1420),
                            ],
                            isCurved: true,
                            color: Theme.of(context).colorScheme.primary,
                            barWidth: 4,
                            isStrokeCapRound: true,
                            dotData: const FlDotData(show: true),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Portable Achievement Timeline
          Text('Portable Achievement History', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          ...achievements.map((ach) {
            final isSanctioned = ach.verificationTier == VerificationTier.sanctioned;
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: isSanctioned ? Colors.amber.shade100 : Colors.blue.shade100,
                  child: Icon(
                    isSanctioned ? Icons.emoji_events : Icons.military_tech,
                    color: isSanctioned ? Colors.amber[800] : Colors.blue,
                  ),
                ),
                title: Text(ach.description, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('Verification Tier: ${ach.verificationTier.name.toUpperCase()} • Visibility: ${ach.visibilityOverride.name}'),
                trailing: Chip(
                  label: Text(isSanctioned ? 'SANCTIONED' : 'CASUAL'),
                  backgroundColor: isSanctioned ? Colors.amber.withValues(alpha: 0.2) : Colors.blue.withValues(alpha: 0.2),
                ),
              ),
            );
          }),

          const SizedBox(height: 20),

          // Trust & Safety / Minor Protection Section
          Card(
            color: Colors.purple.withValues(alpha: 0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.shield_outlined, color: Colors.purple, size: 28),
                      const SizedBox(width: 8),
                      Text('Trust & Safety / Guardian Dashboard', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('Guardian Link Status: Verified Parent (Aarav Sharma)', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text('Minor Profile Visibility Lock: Hard-locked to private until verified by guardian attestation.'),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.share),
                    label: const Text('Generate Public Career Resume Slug'),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Generated Shareable Career Link: playsphere.org/p/aarav-sharma-2026')),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
