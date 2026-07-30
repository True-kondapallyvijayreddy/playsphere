import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/challenge.dart';
import '../../core/models/organization.dart';
import '../../core/providers.dart';

class ChallengesScreen extends ConsumerWidget {
  const ChallengesScreen({
    super.key,
    required this.org,
  });

  final Organization org;

  void _showIssueChallengeDialog(BuildContext context, WidgetRef ref) {
    final opponentOrgCtrl = TextEditingController();
    final opponentNameCtrl = TextEditingController();
    var selectedSport = 'cricket';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Issue Inter-Club Challenge'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: opponentOrgCtrl,
                decoration: const InputDecoration(
                  labelText: 'Opponent Club ID',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: opponentNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Opponent Club Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedSport,
                decoration: const InputDecoration(
                  labelText: 'Sport',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'cricket', child: Text('Cricket')),
                  DropdownMenuItem(value: 'football', child: Text('Football')),
                  DropdownMenuItem(value: 'kabaddi', child: Text('Kabaddi')),
                  DropdownMenuItem(value: 'volleyball', child: Text('Volleyball')),
                  DropdownMenuItem(value: 'kho_kho', child: Text('Kho-Kho')),
                ],
                onChanged: (v) {
                  if (v != null) selectedSport = v;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (opponentOrgCtrl.text.trim().isEmpty ||
                  opponentNameCtrl.text.trim().isEmpty) return;

              final challenge = Challenge(
                id: '',
                fromOrgId: org.id,
                toOrgId: opponentOrgCtrl.text.trim(),
                fromOrgName: org.name,
                toOrgName: opponentNameCtrl.text.trim(),
                sportId: selectedSport,
                status: 'pending',
                proposedSlots: [DateTime.now().add(const Duration(days: 2))],
              );

              await ref
                  .read(communityRepositoryProvider)
                  .createChallenge(challenge);

              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Send Challenge'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(communityRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inter-Club Challenges'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showIssueChallengeDialog(context, ref),
        icon: const Icon(Icons.sports_score),
        label: const Text('Challenge a Club'),
      ),
      body: StreamBuilder<List<Challenge>>(
        stream: repo.watchChallengesForOrg(org.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final challenges = snapshot.data ?? [];
          if (challenges.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sports_score, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    'No inter-club challenges yet for ${org.name}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text('Challenge a rival school, village, or club to a match!'),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: challenges.length,
            itemBuilder: (context, index) {
              final c = challenges[index];
              final isIncoming = c.toOrgId == org.id;

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
                          Text(
                            '${c.fromOrgName} vs ${c.toOrgName}',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          Chip(
                            label: Text(
                              c.status.toUpperCase(),
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('Sport: ${c.sportId.toUpperCase()}'),
                      const SizedBox(height: 12),
                      if (isIncoming && c.isPending) ...[
                        Row(
                          children: [
                            ElevatedButton.icon(
                              onPressed: () async {
                                final slot = c.proposedSlots.isNotEmpty
                                    ? c.proposedSlots.first
                                    : DateTime.now().add(const Duration(days: 1));

                                await repo.acceptChallenge(
                                  challenge: c,
                                  selectedSlot: slot,
                                );

                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Challenge accepted! Fixture created.'),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.check),
                              label: const Text('Accept Challenge'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
