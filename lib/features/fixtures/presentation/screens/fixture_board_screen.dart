import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/play_sphere_store.dart';
import '../../../../domain/domain.dart';
import '../../../../shared/widgets/portal_scaffold.dart';

class FixtureBoardScreen extends ConsumerStatefulWidget {
  const FixtureBoardScreen({
    super.key,
    required this.orgId,
    required this.eventId,
  });

  final String orgId;
  final String eventId;

  @override
  ConsumerState<FixtureBoardScreen> createState() => _FixtureBoardScreenState();
}

class _FixtureBoardScreenState extends ConsumerState<FixtureBoardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(playSphereStoreProvider);
    final fixtures = store.fixtures;
    final standings = store.standings;

    return PortalScaffold(
      title: 'Bracket & Standings Hub',
      child: Column(
        children: [
          // Sub-navigation Tabs
          Container(
            color: const Color(0xFF0F172A),
            child: TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFF16A34A),
              labelColor: const Color(0xFF16A34A),
              unselectedLabelColor: Colors.white70,
              tabs: const [
                Tab(icon: Icon(Icons.account_tree), text: 'Knockout Brackets'),
                Tab(icon: Icon(Icons.table_rows), text: 'Match Schedule'),
                Tab(icon: Icon(Icons.leaderboard), text: 'League Standings'),
              ],
            ),
          ),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Interactive Knockout Bracket View
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(20),
                  child: SingleChildScrollView(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Quarter Finals Column
                        _buildBracketColumn(
                          title: 'QUARTER FINALS',
                          matches: [
                            {'teamA': 'Warangal Warriors', 'scoreA': '3', 'teamB': 'Telangana Titans', 'scoreB': '1', 'winner': 'teamA'},
                            {'teamA': 'Kakatiya Strikers', 'scoreA': '2', 'teamB': 'Hanamkonda Heroes', 'scoreB': '0', 'winner': 'teamA'},
                            {'teamA': 'Deccan Dynamos', 'scoreA': '4', 'teamB': 'Secunderabad Stars', 'scoreB': '2', 'winner': 'teamA'},
                            {'teamA': 'Charminar Champions', 'scoreA': '1', 'teamB': 'Nizam Knights', 'scoreB': '3', 'winner': 'teamB'},
                          ],
                        ),
                        const SizedBox(width: 30),
                        const Icon(Icons.arrow_forward_ios, color: Color(0xFF16A34A), size: 24),
                        const SizedBox(width: 30),

                        // Semi Finals Column
                        _buildBracketColumn(
                          title: 'SEMI FINALS',
                          matches: [
                            {'teamA': 'Warangal Warriors', 'scoreA': '2', 'teamB': 'Kakatiya Strikers', 'scoreB': '1', 'winner': 'teamA'},
                            {'teamA': 'Deccan Dynamos', 'scoreA': '0', 'teamB': 'Nizam Knights', 'scoreB': '2', 'winner': 'teamB'},
                          ],
                        ),
                        const SizedBox(width: 30),
                        const Icon(Icons.arrow_forward_ios, color: Color(0xFF16A34A), size: 24),
                        const SizedBox(width: 30),

                        // Grand Final Column
                        _buildBracketColumn(
                          title: 'GRAND FINAL CHAMPIONSHIP 🏆',
                          matches: [
                            {'teamA': 'Warangal Warriors', 'scoreA': 'TBD', 'teamB': 'Nizam Knights', 'scoreB': 'TBD', 'winner': 'none'},
                          ],
                          isFinal: true,
                        ),
                      ],
                    ),
                  ),
                ),

                // Tab 2: Match Schedule List
                ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: fixtures.length,
                  itemBuilder: (context, index) {
                    final fixture = fixtures[index];
                    final scores = store.fixtureScores[fixture.id] ?? {};
                    final scoreA = scores[fixture.entrantAId] ?? 0.0;
                    final scoreB = scores[fixture.entrantBId] ?? 0.0;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Stage: ${fixture.stageId.toUpperCase()}',
                                  style: const TextStyle(color: Color(0xFF16A34A), fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: fixture.status == FixtureStatus.live
                                        ? const Color(0xFF16A34A).withValues(alpha: 0.15)
                                        : Colors.blue.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    fixture.status.name.toUpperCase(),
                                    style: TextStyle(
                                      color: fixture.status == FixtureStatus.live ? const Color(0xFF16A34A) : Colors.blue,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Entrant A vs Entrant B Match Card
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    children: [
                                      const CircleAvatar(
                                        backgroundColor: Color(0xFF16A34A),
                                        child: Icon(Icons.person, color: Colors.white),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        fixture.entrantAId.replaceAll('prof-', '').toUpperCase(),
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${scoreA.toInt()} - ${scoreB.toInt()}',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF16A34A),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    children: [
                                      const CircleAvatar(
                                        backgroundColor: Color(0xFFDC2626),
                                        child: Icon(Icons.person_outline, color: Colors.white),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        fixture.entrantBId.replaceAll('prof-', '').toUpperCase(),
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Venue: ${fixture.venueId ?? "Stadium Court 1"}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                Text('Tier: ${fixture.verificationTier.name.toUpperCase()}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

                // Tab 3: Standings Table Tab
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Rank', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Entrant', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('P', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('W', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('L', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Pts', style: TextStyle(fontWeight: FontWeight.bold))),
                      ],
                      rows: standings.map((s) {
                        return DataRow(
                          cells: [
                            DataCell(Text('#${s.rank}')),
                            DataCell(Text(s.entrantId.replaceAll('prof-', '').toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold))),
                            DataCell(Text('${s.played}')),
                            DataCell(Text('${s.wins}')),
                            DataCell(Text('${s.losses}')),
                            DataCell(
                              Text(
                                '${s.points.toInt()}',
                                style: const TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBracketColumn({
    required String title,
    required List<Map<String, String>> matches,
    bool isFinal = false,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isFinal ? const Color(0xFFDC2626) : const Color(0xFF15803D),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            title,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
        const SizedBox(height: 16),
        ...matches.map((m) => Container(
              width: 200,
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isFinal ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                  width: 1.5,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          m['teamA']!,
                          style: TextStyle(
                            color: m['winner'] == 'teamA' ? const Color(0xFF16A34A) : Colors.white,
                            fontWeight: m['winner'] == 'teamA' ? FontWeight.bold : FontWeight.normal,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Text(m['scoreA']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Divider(color: Colors.white24, height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          m['teamB']!,
                          style: TextStyle(
                            color: m['winner'] == 'teamB' ? const Color(0xFF16A34A) : Colors.white,
                            fontWeight: m['winner'] == 'teamB' ? FontWeight.bold : FontWeight.normal,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Text(m['scoreB']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            )),
      ],
    );
  }
}
