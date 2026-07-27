import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/play_sphere_store.dart';
import '../../../../shared/widgets/portal_scaffold.dart';

class MyScoringAssignmentsScreen extends ConsumerWidget {
  const MyScoringAssignmentsScreen({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(playSphereStoreProvider);

    return PortalScaffold(
      title: 'My Official Match Scoring Assignments',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            color: Color(0xFF15803D),
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Icon(Icons.gavel, color: Colors.white, size: 28),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Official Judge & Scorer Console: Assigned matches require real-time point logging and rule finalization.',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          Text('Assigned Fixtures (Live & Scheduled)', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),

          ...store.fixtures.map((fix) => Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFDC2626),
                    child: Icon(Icons.flash_on, color: Colors.white, size: 20),
                  ),
                  title: Text('${fix.entrantAId} vs ${fix.entrantBId}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('Venue: ${fix.venueId ?? "Court 1"} • Status: ${fix.status.name.toUpperCase()}'),
                  trailing: ElevatedButton.icon(
                    icon: const Icon(Icons.edit_note),
                    label: const Text('Open Console'),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16A34A), foregroundColor: Colors.white),
                    onPressed: () => context.go('/org/$orgId/events/${fix.id}/live'),
                  ),
                ),
              )),
        ],
      ),
    );
  }
}
