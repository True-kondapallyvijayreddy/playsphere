import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/app_user.dart';
import '../../core/models/umpire_profile.dart';
import '../../core/providers.dart';

class UmpireRegistryScreen extends ConsumerStatefulWidget {
  const UmpireRegistryScreen({
    super.key,
    required this.user,
    this.existingProfile,
  });

  final AppUser user;
  final UmpireProfile? existingProfile;

  @override
  ConsumerState<UmpireRegistryScreen> createState() =>
      _UmpireRegistryScreenState();
}

class _UmpireRegistryScreenState
    extends ConsumerState<UmpireRegistryScreen> {
  final _allSports = const [
    ('cricket', 'Cricket'),
    ('football', 'Football'),
    ('basketball', 'Basketball'),
    ('kabaddi', 'Kabaddi'),
    ('volleyball', 'Volleyball'),
    ('kho_kho', 'Kho-Kho'),
    ('tennis', 'Tennis'),
    ('table_tennis', 'Table Tennis'),
    ('hockey', 'Hockey'),
  ];

  late Set<String> _selectedSports;
  late String _badgeLevel;
  late bool _isAvailable;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedSports = Set.from(widget.existingProfile?.sports ?? ['cricket']);
    _badgeLevel = widget.existingProfile?.badgeLevel ?? 'community';
    _isAvailable = widget.existingProfile?.isAvailable ?? true;
  }

  Future<void> _saveProfile() async {
    if (_selectedSports.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one sport to officiate')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final profile = UmpireProfile(
        uid: widget.user.uid,
        displayName: widget.user.displayName,
        photoUrl: widget.user.photoUrl,
        phone: widget.user.phone,
        sports: _selectedSports.toList(),
        badgeLevel: _badgeLevel,
        matchesOfficiated: widget.existingProfile?.matchesOfficiated ?? 0,
        isAvailable: _isAvailable,
      );

      await ref.read(umpireRepositoryProvider).registerUmpire(profile);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Umpire profile registered successfully!')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save profile: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Umpire & Official Registration'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Register as an Official',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Officiate matches across sports in your community, district or state.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            Text(
              'Certified Sports',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _allSports.map((sport) {
                final isSelected = _selectedSports.contains(sport.$1);
                return FilterChip(
                  label: Text(sport.$2),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedSports.add(sport.$1);
                      } else {
                        _selectedSports.remove(sport.$1);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            Text(
              'Certification Tier',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _badgeLevel,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'community',
                  child: Text('Community / Local Umpire'),
                ),
                DropdownMenuItem(
                  value: 'district_certified',
                  child: Text('District Certified Official'),
                ),
                DropdownMenuItem(
                  value: 'state_certified',
                  child: Text('State Certified Official'),
                ),
                DropdownMenuItem(
                  value: 'association_certified',
                  child: Text('Association Certified Ref'),
                ),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _badgeLevel = val);
              },
            ),
            const SizedBox(height: 24),
            SwitchListTile(
              title: const Text('Available for Match Assignments'),
              subtitle: const Text(
                  'Allow competition managers to map you to upcoming live matches'),
              value: _isAvailable,
              onChanged: (val) => setState(() => _isAvailable = val),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveProfile,
                child: _isSaving
                    ? const CircularProgressIndicator()
                    : const Text('Save Umpire Registration'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
