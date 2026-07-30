import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/fixture.dart';
import '../../../core/models/match_official.dart';
import '../../../core/models/umpire_profile.dart';
import '../../../data/umpire_repository.dart';

class AssignOfficialSheet extends ConsumerStatefulWidget {
  const AssignOfficialSheet({
    super.key,
    required this.fixture,
  });

  final Fixture fixture;

  @override
  ConsumerState<AssignOfficialSheet> createState() =>
      _AssignOfficialSheetState();
}

class _AssignOfficialSheetState extends ConsumerState<AssignOfficialSheet> {
  final _repository = const UmpireRepository();

  List<UmpireProfile> _availableUmpires = [];
  UmpireProfile? _selectedUmpire;
  String _selectedRole = 'main_umpire';
  bool _grantScoringAccess = true;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadUmpires();
  }

  Future<void> _loadUmpires() async {
    try {
      final list = await _repository
          .fetchUmpiresForSport(widget.fixture.scoringPluginKey);
      if (mounted) {
        setState(() {
          _availableUmpires = list;
          if (list.isNotEmpty) _selectedUmpire = list.first;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _assignOfficial() async {
    if (_selectedUmpire == null) return;

    setState(() => _isSaving = true);
    try {
      final official = MatchOfficial(
        uid: _selectedUmpire!.uid,
        name: _selectedUmpire!.displayName,
        role: _selectedRole,
        grantedScoringAccess: _grantScoringAccess,
      );

      await _repository.assignOfficialToFixture(
        orgId: widget.fixture.orgId,
        compId: widget.fixture.compId,
        fixtureId: widget.fixture.id,
        official: official,
        grantScoringAccess: _grantScoringAccess,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '${official.name} assigned as official to match!')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to assign official: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Assign Match Official / Umpire',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_availableUmpires.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No registered umpires available for this sport. '
                'Register umpires in the Org Officials directory.',
              ),
            )
          else ...[
            DropdownButtonFormField<UmpireProfile>(
              value: _selectedUmpire,
              decoration: const InputDecoration(
                labelText: 'Select Official',
                border: OutlineInputBorder(),
              ),
              items: _availableUmpires.map((umpire) {
                return DropdownMenuItem(
                  value: umpire,
                  child: Text('${umpire.displayName} (${umpire.badgeLevel})'),
                );
              }).toList(),
              onChanged: (val) => setState(() => _selectedUmpire = val),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedRole,
              decoration: const InputDecoration(
                labelText: 'Official Role',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'main_umpire',
                  child: Text('Main Umpire / Referee'),
                ),
                DropdownMenuItem(
                  value: 'square_leg_umpire',
                  child: Text('Square Leg Umpire'),
                ),
                DropdownMenuItem(
                  value: 'third_umpire',
                  child: Text('Third Umpire / VAR'),
                ),
                DropdownMenuItem(
                  value: 'linesman',
                  child: Text('Linesman / Field Judge'),
                ),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _selectedRole = val);
              },
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              title: const Text('Grant Live Scoring Access'),
              subtitle: const Text(
                  'Allows official to score or authorize scoring on ground'),
              value: _grantScoringAccess,
              onChanged: (val) {
                if (val != null) setState(() => _grantScoringAccess = val);
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _assignOfficial,
                child: _isSaving
                    ? const CircularProgressIndicator()
                    : const Text('Confirm Official Assignment'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
