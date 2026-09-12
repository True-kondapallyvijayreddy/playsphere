import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/app_user.dart';
import '../../core/models/geo.dart';
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
  late final TextEditingController _district;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedSports = Set.from(widget.existingProfile?.sports ?? ['cricket']);
    _badgeLevel = widget.existingProfile?.badgeLevel ?? 'community';
    _isAvailable = widget.existingProfile?.isAvailable ?? true;
    // Seeded from the account's own profile so the common case is a glance
    // and a Save, not a form. An official whose listing already names a
    // district keeps that — they may officiate somewhere other than where
    // they live, and re-deriving it from the account would quietly undo
    // their choice on every edit.
    _district = TextEditingController(
      text: widget.existingProfile?.geo.district ??
          widget.user.geo.district ??
          '',
    );
  }

  @override
  void dispose() {
    _district.dispose();
    super.dispose();
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
      final district = _district.text.trim();
      final profile = UmpireProfile(
        uid: widget.user.uid,
        displayName: widget.user.displayName,
        photoUrl: widget.user.photoUrl,
        phone: widget.user.phone,
        sports: _selectedSports.toList(),
        badgeLevel: _badgeLevel,
        // Built rather than copyWith'd: `GeoLocation.copyWith` takes plain
        // nullables, so a null argument means "keep", and clearing a district
        // through it is impossible. Keeps the account's state/mandal for the
        // gov aggregates and puts the typed district on top — that is the
        // only level the directory filters on.
        geo: GeoLocation(
          state: widget.user.geo.state,
          district: district.isEmpty ? null : district,
          mandal: widget.user.geo.mandal,
          village: widget.user.geo.village,
          pincode: widget.user.geo.pincode,
        ),
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
            Text(
              'District',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Where you can actually reach a ground. Clubs search on this — '
              'a district left blank means you only appear in unfiltered '
              'searches.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _district,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'e.g. Nalgonda',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            SwitchListTile(
              title: const Text('Available for Match Assignments'),
              subtitle: const Text(
                  'Allow competition managers to map you to upcoming live matches'),
              value: _isAvailable,
              onChanged: (val) => setState(() => _isAvailable = val),
            ),
            const SizedBox(height: 20),

            // Said plainly because it is now true and was not before. This
            // form has always copied `AppUser.phone` onto the profile, but
            // until the officials directory existed nothing ever displayed
            // it — so a registration that used to be invisible now publishes
            // a contact route to every signed-in account. Somebody agreeing
            // to be found by organisers should be told that is what they are
            // agreeing to. See `OfficialsDirectoryScreen`'s class doc.
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'What organisers will see',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.user.phone == null
                          ? 'Your name, sports, tier, district and '
                              'availability appear in the officials '
                              'directory, along with a count of matches you '
                              'have officiated. You have no phone number on '
                              'your profile, so nobody can call you — add one '
                              'there if you want to be reachable.'
                          : 'Your name, sports, tier, district, availability '
                              'and your number (${widget.user.phone}) appear '
                              'in the officials directory, along with a count '
                              'of matches you have officiated, so a club with '
                              'a fixture and no umpire can call you directly. '
                              'Turn off availability above to stop being '
                              'offered work.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),
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
