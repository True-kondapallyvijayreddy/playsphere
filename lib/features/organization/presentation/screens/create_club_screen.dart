import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/play_sphere_store.dart';
import '../../../../core/network/firebase_service.dart';
import '../../../../shared/widgets/portal_scaffold.dart';

class CreateClubScreen extends ConsumerStatefulWidget {
  const CreateClubScreen({super.key, required this.orgId});

  final String orgId;

  @override
  ConsumerState<CreateClubScreen> createState() => _CreateClubScreenState();
}

class _CreateClubScreenState extends ConsumerState<CreateClubScreen> {
  final _nameController = TextEditingController(text: 'Kakatiya Sunday Sports Club');
  final _descriptionController = TextEditingController(
    text: 'A community sports club for cricket, badminton, and table tennis enthusiasts.',
  );
  final _districtController = TextEditingController(text: 'Warangal');
  String _primarySport = 'Cricket';
  String _visibility = 'Invite Only';

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _districtController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PortalScaffold(
      title: 'Create New Sports Club / Group',
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Banner
          Card(
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(Icons.groups, color: Theme.of(context).colorScheme.primary, size: 36),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Become a Club Admin (WhatsApp Style)',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Create your independent club, generate invite codes/links, approve member join requests, and host custom tournaments for your club members.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Club / Group Name *',
              hintText: 'e.g. Kakatiya Sunday Sports Club',
              prefixIcon: Icon(Icons.groups_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: _descriptionController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Club Description',
              prefixIcon: Icon(Icons.description_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _districtController,
                  decoration: const InputDecoration(
                    labelText: 'District / City',
                    prefixIcon: Icon(Icons.location_on_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _primarySport,
                  decoration: const InputDecoration(
                    labelText: 'Primary Sport',
                    prefixIcon: Icon(Icons.sports),
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Cricket', child: Text('Cricket')),
                    DropdownMenuItem(value: 'Badminton', child: Text('Badminton')),
                    DropdownMenuItem(value: 'Table Tennis', child: Text('Table Tennis')),
                    DropdownMenuItem(value: 'Football', child: Text('Football')),
                    DropdownMenuItem(value: 'Kabaddi', child: Text('Kabaddi')),
                    DropdownMenuItem(value: 'Multi-Sport', child: Text('Multi-Sport')),
                  ],
                  onChanged: (val) => setState(() => _primarySport = val!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          DropdownButtonFormField<String>(
            value: _visibility,
            decoration: const InputDecoration(
              labelText: 'Join Permission & Visibility',
              prefixIcon: Icon(Icons.lock_outline),
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'Invite Only', child: Text('Invite Only (Admin Approval Required)')),
              DropdownMenuItem(value: 'Open Public', child: Text('Open Public (Anyone Can Join)')),
            ],
            onChanged: (val) => setState(() => _visibility = val!),
          ),
          const SizedBox(height: 24),

          ElevatedButton.icon(
            icon: const Icon(Icons.check_circle),
            label: const Text('Create Club & Become Admin', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => _createClub(),
          ),
        ],
      ),
    );
  }

  void _createClub() {
    final store = ref.read(playSphereStoreProvider);
    final newOrgId = 'club-${DateTime.now().millisecondsSinceEpoch}';
    final inviteCode = '${_nameController.text.split(" ").first.toUpperCase()}-2026';

    store.createClub(
      id: newOrgId,
      name: _nameController.text,
      description: _descriptionController.text,
      district: _districtController.text,
      inviteCode: inviteCode,
    );

    // Save directly to Firebase Firestore
    FirebaseService.createClub(
      clubId: newOrgId,
      name: _nameController.text,
      description: _descriptionController.text,
      district: _districtController.text,
      inviteCode: inviteCode,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🎉 Club "${_nameController.text}" created in Firebase Firestore! Share code: $inviteCode'),
        duration: const Duration(seconds: 4),
      ),
    );

    context.go('/org/$newOrgId');
  }
}
