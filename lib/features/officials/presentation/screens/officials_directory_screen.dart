import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/portal_scaffold.dart';

class Official {
  const Official({
    required this.id,
    required this.name,
    required this.role,
    required this.sport,
    required this.certificationLevel,
    required this.matchesOfficiated,
  });

  final String id;
  final String name;
  final String role;
  final String sport;
  final String certificationLevel;
  final int matchesOfficiated;
}

class OfficialsDirectoryScreen extends ConsumerStatefulWidget {
  const OfficialsDirectoryScreen({super.key, required this.orgId});

  final String orgId;

  @override
  ConsumerState<OfficialsDirectoryScreen> createState() => _OfficialsDirectoryScreenState();
}

class _OfficialsDirectoryScreenState extends ConsumerState<OfficialsDirectoryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final List<Official> _officials = const [
    Official(
      id: 'off-1',
      name: 'Vikram Reddy',
      role: 'Certified Referee',
      sport: 'Table Tennis',
      certificationLevel: 'State Grade A',
      matchesOfficiated: 42,
    ),
    Official(
      id: 'off-2',
      name: 'Sunita Rao',
      role: 'Chief Umpire',
      sport: 'Cricket',
      certificationLevel: 'National Level 2',
      matchesOfficiated: 88,
    ),
    Official(
      id: 'off-3',
      name: 'Mahesh Kumar',
      role: 'Kabaddi Judge',
      sport: 'Kabaddi',
      certificationLevel: 'State Certified',
      matchesOfficiated: 31,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PortalScaffold(
      title: 'Officials & Volunteers Hub',
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(icon: Icon(Icons.verified_user), text: 'Certified Referees & Officials'),
              Tab(icon: Icon(Icons.volunteer_activism), text: 'Volunteer Corps & Signups'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Referees & Officials Registry Tab
                ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _officials.length,
                  itemBuilder: (context, index) {
                    final off = _officials[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.amber.withValues(alpha: 0.2),
                          child: Icon(Icons.security, color: Colors.amber[800]),
                        ),
                        title: Text(off.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('${off.role} • ${off.sport} • ${off.certificationLevel}'),
                        trailing: Chip(
                          label: Text('${off.matchesOfficiated} Matches'),
                          backgroundColor: Colors.blue.withValues(alpha: 0.15),
                          labelStyle: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      ),
                    );
                  },
                ),

                // Volunteer Portal Tab
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(Icons.handshake, color: Theme.of(context).colorScheme.primary, size: 32),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('State Community Volunteer Program', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                                  const Text('Log hours, assist event logistics, and earn government community service certificates.', style: TextStyle(fontSize: 12)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildVolunteerOpportunity(
                      context,
                      title: 'Venue Registration Marshal',
                      sport: 'Monsoon TT League',
                      date: '28 July 2026',
                      hours: '4 Hours',
                      slotsLeft: 3,
                    ),
                    _buildVolunteerOpportunity(
                      context,
                      title: 'First Aid & Medical Coordinator',
                      sport: 'Kabaddi Village Championship',
                      date: '02 August 2026',
                      hours: '6 Hours',
                      slotsLeft: 2,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVolunteerOpportunity(
    BuildContext context, {
    required String title,
    required String sport,
    required String date,
    required String hours,
    required int slotsLeft,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text('$sport • $date • $hours', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Successfully signed up as $title! Check-in pass generated.')),
                );
              },
              child: const Text('Volunteer'),
            ),
          ],
        ),
      ),
    );
  }
}
