import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/play_sphere_store.dart';
import '../../../../shared/widgets/portal_scaffold.dart';

class ParticipantHomeScreen extends ConsumerWidget {
  const ParticipantHomeScreen({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(playSphereStoreProvider);

    return PortalScaffold(
      title: 'Player Hub & Competitions',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Player Profile Header Card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 28,
                    backgroundColor: Color(0xFF16A34A),
                    child: Icon(Icons.person, color: Colors.white, size: 32),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(store.member.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const Text('1420 ELO Rating • Level 4 Verified Player', style: TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Registered Competitions
          Text('My Active Event Registrations', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),

          ...store.competitions.map((comp) => Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF16A34A),
                    child: Icon(Icons.emoji_events, color: Colors.white, size: 20),
                  ),
                  title: Text(comp.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('Status: CONFIRMED • Entrant: ${comp.entrantType.name}'),
                  trailing: ElevatedButton(
                    onPressed: () => context.go('/org/$orgId/events/${comp.id}'),
                    child: const Text('View Match'),
                  ),
                ),
              )),
        ],
      ),
    );
  }
}
