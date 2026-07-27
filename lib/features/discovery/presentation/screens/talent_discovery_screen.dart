import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/play_sphere_store.dart';
import '../../../../domain/domain.dart';
import '../../../../shared/widgets/portal_scaffold.dart';

class TalentDiscoveryScreen extends ConsumerStatefulWidget {
  const TalentDiscoveryScreen({super.key, required this.orgId});

  final String orgId;

  @override
  ConsumerState<TalentDiscoveryScreen> createState() => _TalentDiscoveryScreenState();
}

class _TalentDiscoveryScreenState extends ConsumerState<TalentDiscoveryScreen> {
  String _selectedSport = 'All';
  double _minRating = 1200;

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(playSphereStoreProvider);
    final profiles = store.playerProfiles;

    final filtered = profiles.where((p) {
      final ratingRec = store.ratingRecords.firstWhere(
        (r) => r.playerProfileId == p.id,
        orElse: () => RatingRecordEntity(
          id: 'temp',
          playerProfileId: p.id,
          sportId: 'tt',
          currentRating: 1200,
          ratingStatus: RatingStatus.established,
          lastResultAt: DateTime.now(),
          matchesPlayed: 0,
        ),
      );

      final matchesSport = _selectedSport == 'All' || p.primarySportIds.contains(_selectedSport.toLowerCase());
      final matchesRating = ratingRec.currentRating >= _minRating;

      return matchesSport && matchesRating;
    }).toList();

    return PortalScaffold(
      title: 'Talent Graph & Discovery',
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Scout Search & Filter', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _selectedSport,
                            decoration: const InputDecoration(
                              labelText: 'Sport Category',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'All', child: Text('All Sports')),
                              DropdownMenuItem(value: 'tt', child: Text('Table Tennis')),
                              DropdownMenuItem(value: 'cricket', child: Text('Cricket')),
                              DropdownMenuItem(value: 'badminton', child: Text('Badminton')),
                            ],
                            onChanged: (val) => setState(() => _selectedSport = val ?? 'All'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Min ELO Rating: ${_minRating.toInt()}'),
                              Slider(
                                value: _minRating,
                                min: 1000,
                                max: 2000,
                                divisions: 10,
                                label: _minRating.toInt().toString(),
                                onChanged: (val) => setState(() => _minRating = val),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Verified Talent Profiles (${filtered.length})', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final profile = filtered[index];
                  final ratingRec = store.ratingRecords.firstWhere(
                    (r) => r.playerProfileId == profile.id,
                    orElse: () => RatingRecordEntity(
                      id: 'temp',
                      playerProfileId: profile.id,
                      sportId: 'tt',
                      currentRating: 1200,
                      ratingStatus: RatingStatus.established,
                      lastResultAt: DateTime.now(),
                      matchesPlayed: 0,
                    ),
                  );

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                        child: Text(profile.displayName[0]),
                      ),
                      title: Text(profile.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('Primary Sports: ${profile.primarySportIds.join(', ')} • ${ratingRec.matchesPlayed} matches'),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '${ratingRec.currentRating.toInt()} ELO',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
