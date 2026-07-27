import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/play_sphere_store.dart';
import '../../../../domain/domain.dart';
import '../../../../shared/widgets/portal_scaffold.dart';

class EventListScreen extends ConsumerStatefulWidget {
  const EventListScreen({super.key, required this.orgId});

  final String orgId;

  @override
  ConsumerState<EventListScreen> createState() => _EventListScreenState();
}

class _EventListScreenState extends ConsumerState<EventListScreen> {
  String _selectedSport = 'All';
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(playSphereStoreProvider);
    final competitions = store.competitions;
    final seasons = store.seasons;

    final filteredCompetitions = competitions.where((c) {
      final matchesSport = _selectedSport == 'All' || c.sportId.toLowerCase() == _selectedSport.toLowerCase();
      final matchesSearch = c.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          c.sportId.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesSport && matchesSearch;
    }).toList();

    return PortalScaffold(
      title: 'Seasons & Event Competitions',
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Create Event'),
        onPressed: () => context.go('/org/${widget.orgId}/create-activity'),
      ),
      child: Column(
        children: [
          // Filter & Search Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Search Bar
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search events, sports, tournaments...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
                const SizedBox(height: 12),

                // Sport Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['All', 'TT', 'Cricket', 'Badminton', 'Football', 'Chess'].map((sport) {
                      final isSelected = _selectedSport == sport;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: FilterChip(
                          label: Text(sport == 'All' ? 'All Sports' : sport.toUpperCase()),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() => _selectedSport = selected ? sport : 'All');
                          },
                          selectedColor: Theme.of(context).colorScheme.primaryContainer,
                          labelStyle: TextStyle(
                            color: isSelected ? Theme.of(context).colorScheme.primary : Colors.black87,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),

          // Active Season Banner
          if (seasons.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Card(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Icon(Icons.emoji_events, color: Theme.of(context).colorScheme.primary, size: 32),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Active Season: ${seasons.first.name}',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Status: ${seasons.first.status.name.toUpperCase()} • ${filteredCompetitions.length} Competitions',
                              style: const TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          const SizedBox(height: 12),

          // Competitions List
          Expanded(
            child: filteredCompetitions.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.event_busy, size: 48, color: Colors.grey),
                        SizedBox(height: 12),
                        Text('No competitions found matching filters'),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredCompetitions.length,
                    itemBuilder: (context, index) {
                      final comp = filteredCompetitions[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      comp.sportId.toUpperCase(),
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.primary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  Chip(
                                    label: Text(comp.status.name.toUpperCase()),
                                    backgroundColor: comp.status == SportCompetitionStatus.inProgress
                                        ? Colors.green.withValues(alpha: 0.15)
                                        : Colors.amber.withValues(alpha: 0.15),
                                    labelStyle: TextStyle(
                                      color: comp.status == SportCompetitionStatus.inProgress ? Colors.green : Colors.amber[900],
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                comp.name,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Format: ${comp.format.name} • Type: ${comp.entrantType.name}',
                                style: TextStyle(color: Colors.grey[600], fontSize: 13),
                              ),
                              const Divider(height: 24),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.info_outline, size: 18),
                                    label: const Text('Details'),
                                    onPressed: () => context.go('/org/${widget.orgId}/events/${comp.id}'),
                                  ),
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.leaderboard, size: 18),
                                    label: const Text('Fixtures'),
                                    onPressed: () => context.go('/org/${widget.orgId}/events/${comp.id}/fixtures'),
                                  ),
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.sports_score, size: 18),
                                    label: const Text('Live Ops'),
                                    onPressed: () => context.go('/org/${widget.orgId}/events/${comp.id}/live'),
                                  ),
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.how_to_reg, size: 18),
                                    label: const Text('Register'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
                                      foregroundColor: Theme.of(context).colorScheme.onTertiaryContainer,
                                    ),
                                    onPressed: () => context.go('/org/${widget.orgId}/events/${comp.id}/register'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
