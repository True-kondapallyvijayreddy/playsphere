import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/play_sphere_store.dart';
import '../../../../shared/widgets/portal_scaffold.dart';

class OrgSettingsScreen extends ConsumerWidget {
  const OrgSettingsScreen({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(playSphereStoreProvider);

    return PortalScaffold(
      title: 'Owner Console & Organization Settings',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.shield, color: Color(0xFF16A34A)),
              title: Text(store.activeOrganization.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('Organization ID: $orgId • Tier: ${store.organization.tier.toUpperCase()}'),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Feature Flags & Subscription', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          SwitchListTile(
            title: const Text('Enable AI Team Balancing Engine'),
            subtitle: const Text('Snake draft balancing via ELO rating ledger'),
            value: true,
            onChanged: (val) {},
          ),
          SwitchListTile(
            title: const Text('Enable Real-Time Score Broadcast'),
            subtitle: const Text('Websocket fan-out for stadium screens'),
            value: true,
            onChanged: (val) {},
          ),
          const Divider(height: 32),
          ElevatedButton.icon(
            icon: const Icon(Icons.delete_forever),
            label: const Text('Soft Delete Organization (Owner Only)'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Owner Action: Soft Delete require 2-Factor Confirmation')),
              );
            },
          ),
        ],
      ),
    );
  }
}
