import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/play_sphere_store.dart';
import '../../../../domain/domain.dart';
import '../../../../shared/widgets/portal_scaffold.dart';

class EventDetailScreen extends ConsumerStatefulWidget {
  const EventDetailScreen({
    super.key,
    required this.orgId,
    required this.eventId,
  });

  final String orgId;
  final String eventId;

  @override
  ConsumerState<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends ConsumerState<EventDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(playSphereStoreProvider);
    final comp = store.competitions.firstWhere(
      (c) => c.id == widget.eventId,
      orElse: () => store.competitions.first,
    );
    final isAdmin = store.role == PortalRole.admin;

    return PortalScaffold(
      title: comp.name,
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabs: const [
              Tab(icon: Icon(Icons.info_outline), text: 'Overview'),
              Tab(icon: Icon(Icons.auto_awesome), text: 'AI Team Studio'),
              Tab(icon: Icon(Icons.live_tv), text: 'Fixtures & Live'),
              Tab(icon: Icon(Icons.leaderboard), text: 'Standings'),
              Tab(icon: Icon(Icons.gavel), text: 'Premier Auction'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(context, store, comp),
                _buildAITeamStudioTab(context, store, comp, isAdmin),
                _buildFixturesTab(context, store, comp),
                _buildStandingsTab(context, store),
                _buildAuctionTab(context, store),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab(BuildContext context, PlaySphereStore store, SportCompetitionEntity comp) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(comp.name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Chip(label: Text('Sport: ${comp.sportId.toUpperCase()}')),
                    const SizedBox(width: 8),
                    Chip(label: Text('Format: ${comp.format.name}')),
                    const SizedBox(width: 8),
                    Chip(
                      label: Text('Status: ${comp.status.name}'),
                      backgroundColor: Colors.green.withValues(alpha: 0.2),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Configured Points System: Win = 3.0 pts, Draw = 1.0 pt, Loss = 0.0 pts. Tiebreaker order: Points -> Score Difference -> Wins.',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Registered Players (${store.playerProfiles.length})', style: Theme.of(context).textTheme.titleLarge),
            ElevatedButton.icon(
              icon: const Icon(Icons.how_to_reg),
              label: const Text('Register Me'),
              onPressed: () {
                final success = store.register(comp.id);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success ? 'Successfully registered for ${comp.name}!' : 'Already registered or full.'),
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...store.playerProfiles.map((prof) {
          return Card(
            child: ListTile(
              leading: CircleAvatar(child: Text(prof.displayName[0])),
              title: Text(prof.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('Primary: ${prof.primarySportIds.join(", ")}'),
              trailing: const Icon(Icons.verified, color: Colors.blue),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildAITeamStudioTab(BuildContext context, PlaySphereStore store, SportCompetitionEntity comp, bool isAdmin) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome, color: Colors.amber, size: 28),
                    const SizedBox(width: 8),
                    Text('AI Team Formation Engine', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Uses each player\'s per-sport ELO rating to balance average team skill using greedy snake-draft optimization.',
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.shuffle),
                  label: const Text('Run AI-Balanced ELO Shuffle'),
                  onPressed: () {
                    store.triggerAITeamShuffle(comp.id, strategy: TeamFormationStrategyType.aiBalanced);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('AI Team Formation completed! Balanced 2 teams.')),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Formed Teams (${store.formedTeams.length})', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (store.formedTeams.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32.0),
            child: Center(child: Text('No teams formed yet. Click "Run AI-Balanced ELO Shuffle" above.')),
          )
        else
          ...store.formedTeams.map((ft) {
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(ft.team.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        Row(
                          children: [
                            Chip(
                              avatar: const Icon(Icons.star, size: 16, color: Colors.amber),
                              label: Text('Avg ELO: ${ft.averageRating.toInt()}'),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.edit_note, color: Colors.blue),
                              tooltip: 'Edit Team & Member Names',
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (ctx) {
                                    final teamNameController = TextEditingController(text: ft.team.name);
                                    return AlertDialog(
                                      title: const Text('Edit Formed Team & Member Roster'),
                                      content: SingleChildScrollView(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            TextFormField(
                                              controller: teamNameController,
                                              decoration: const InputDecoration(
                                                labelText: 'Team Name',
                                                border: OutlineInputBorder(),
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            const Text('Team Roster Members:', style: TextStyle(fontWeight: FontWeight.bold)),
                                            const SizedBox(height: 8),
                                            ...ft.memberProfileIds.map(
                                              (mem) => Padding(
                                                padding: const EdgeInsets.only(bottom: 6.0),
                                                child: TextFormField(
                                                  initialValue: mem,
                                                  decoration: const InputDecoration(
                                                    labelText: 'Member Name',
                                                    prefixIcon: Icon(Icons.person),
                                                    border: OutlineInputBorder(),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx),
                                          child: const Text('Cancel'),
                                        ),
                                        ElevatedButton(
                                          onPressed: () {
                                            Navigator.pop(ctx);
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('Updated roster for ${teamNameController.text}!')),
                                            );
                                          },
                                          child: const Text('Save Changes'),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Roster (${ft.memberProfileIds.length} players): ${ft.memberProfileIds.join(", ")}'),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildFixturesTab(BuildContext context, PlaySphereStore store, SportCompetitionEntity comp) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Scheduled & Live Fixtures', style: Theme.of(context).textTheme.titleLarge),
            ElevatedButton.icon(
              icon: const Icon(Icons.sensors),
              label: const Text('Open Live Scoring Studio'),
              onPressed: () => context.go('/org/${widget.orgId}/events/${comp.id}/live'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...store.fixtures.map((f) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.sports_tennis, color: Colors.green),
              title: Text('${f.entrantAId} vs ${f.entrantBId}', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('Status: ${f.status.name} • Dispute Window: 24h'),
              trailing: ElevatedButton(
                child: const Text('Score Match'),
                onPressed: () => context.go('/org/${widget.orgId}/events/${comp.id}/live'),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildStandingsTab(BuildContext context, PlaySphereStore store) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Live Points & Standings Table', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          DataTable(
            columns: const [
              DataColumn(label: Text('Rank')),
              DataColumn(label: Text('Entrant')),
              DataColumn(label: Text('P')),
              DataColumn(label: Text('W')),
              DataColumn(label: Text('D')),
              DataColumn(label: Text('L')),
              DataColumn(label: Text('Diff')),
              DataColumn(label: Text('PTS')),
            ],
            rows: store.standings.map((s) {
              return DataRow(
                cells: [
                  DataCell(Text('#${s.rank}', style: const TextStyle(fontWeight: FontWeight.bold))),
                  DataCell(Text(s.entrantId)),
                  DataCell(Text(s.played.toString())),
                  DataCell(Text(s.wins.toString())),
                  DataCell(Text(s.draws.toString())),
                  DataCell(Text(s.losses.toString())),
                  DataCell(Text((s.tiebreakValues['score_diff'] ?? 0).toString())),
                  DataCell(Text(s.points.toInt().toString(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green))),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAuctionTab(BuildContext context, PlaySphereStore store) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: Colors.amber.withValues(alpha: 0.15),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.gavel, color: Colors.amber, size: 32),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'State Premier League Franchise Auction Hub • Live Bidding System',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        ...store.auctionLots.map((lot) {
          final isLive = lot.status == AuctionLotStatus.live;

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.amber.shade100,
                    child: const Icon(Icons.person, color: Colors.amber),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Player: ${lot.playerProfileId}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text('Base Price: ₹${(lot.basePrice / 100).toInt()}'),
                        if (lot.winningTeamId != null)
                          Text(
                            'Highest Bidder: ${lot.winningTeamId} (₹${((lot.finalPrice ?? lot.basePrice) / 100).toInt()})',
                            style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                          ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.gavel),
                    label: Text(isLive ? 'Bid +₹1,000' : 'Start Bid'),
                    onPressed: () {
                      final current = lot.finalPrice ?? lot.basePrice;
                      store.placeAuctionBid(lot.id, 'Hyderabad Hawks', current + 100000);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Placed bid ₹${((current + 100000) / 100).toInt()} for ${lot.playerProfileId}')),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
