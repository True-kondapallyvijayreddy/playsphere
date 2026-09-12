import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/enums.dart';
import '../../core/models/give_donation.dart';
import '../../core/models/give_need.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../shared/app_scaffold.dart';
import '../home/home_providers.dart';

/// Raising a verified-need candidate. Lands unverified — see `GiveNeed` for
/// why a need can't put itself on the public board.
///
/// Two shapes, one screen: a club/team need (requires managing that club's
/// competitions — mirrors `firestore.rules`) or a self-reported player need
/// (always allowed, always about the signed-in account — nobody may
/// nominate someone else's shortfall).
class GiveRaiseNeedScreen extends ConsumerStatefulWidget {
  const GiveRaiseNeedScreen({super.key});

  @override
  ConsumerState<GiveRaiseNeedScreen> createState() =>
      _GiveRaiseNeedScreenState();
}

class _GiveRaiseNeedScreenState extends ConsumerState<GiveRaiseNeedScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _city = TextEditingController();
  final _playersCount = TextEditingController();

  GiveBeneficiaryType _type = GiveBeneficiaryType.club;
  final Map<EquipmentCategory, int> _quantities = {};
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _city.dispose();
    _playersCount.dispose();
    super.dispose();
  }

  Future<void> _submit({required String orgId, String? orgName}) async {
    if (!_formKey.currentState!.validate()) return;
    if (_quantities.isEmpty) {
      showError(context, 'Add at least one item.');
      return;
    }
    final uid = ref.read(authUidProvider);
    if (uid == null) return;
    final me = ref.read(authUserProvider).valueOrNull;

    setState(() => _busy = true);
    try {
      final need = GiveNeed(
        id: '',
        beneficiaryType: _type,
        orgId: _type == GiveBeneficiaryType.player ? null : orgId,
        orgName: _type == GiveBeneficiaryType.player ? null : orgName,
        playerUid: _type == GiveBeneficiaryType.player ? uid : null,
        playerName: _type == GiveBeneficiaryType.player ? me?.displayName : null,
        title: _title.text.trim(),
        description:
            _description.text.trim().isEmpty ? null : _description.text.trim(),
        city: _city.text.trim(),
        playersCount: int.tryParse(_playersCount.text.trim()),
        items: [
          for (final e in _quantities.entries)
            GiveItemLine(category: e.key, quantity: e.value),
        ],
      );
      await ref
          .read(giveRepositoryProvider)
          .raiseNeed(need, createdByUid: uid);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
          'Need submitted. PlaySphere will verify it before it appears on '
          'the public board.',
        ),
      ));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final orgId = ref.watch(primaryOrgIdProvider);
    final org = orgId == null
        ? null
        : ref.watch(organizationProvider(orgId)).valueOrNull;
    final canManageClub = orgId == null
        ? false
        : ref
            .watch(myCapabilitiesProvider(orgId))
            .contains(Capability.manageCompetitions);

    return Scaffold(
      appBar: AppBar(title: const Text('Raise a need')),
      body: SingleChildScrollView(
        child: ContentBounds(
          maxWidth: 640,
          child: Form(
            key: _formKey,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (canManageClub && org != null)
                    SegmentedButton<GiveBeneficiaryType>(
                      segments: const [
                        ButtonSegment(
                          value: GiveBeneficiaryType.club,
                          label: Text('For my club'),
                          icon: Icon(Icons.groups_outlined),
                        ),
                        ButtonSegment(
                          value: GiveBeneficiaryType.player,
                          label: Text('For myself'),
                          icon: Icon(Icons.person_outline),
                        ),
                      ],
                      selected: {_type},
                      onSelectionChanged: (s) =>
                          setState(() => _type = s.first),
                    )
                  else
                    Card(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'This raises a need for yourself. To raise '
                                'one for a club, you need to manage that '
                                'club\'s competitions.',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _title,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      hintText: 'e.g. Cricket shoes for the village club',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _description,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _city,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'City',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  if (_type != GiveBeneficiaryType.player) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _playersCount,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Players affected (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'What\'s needed?',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in EquipmentCategory.values)
                        InputChip(
                          avatar:
                              Text(c.emoji, style: const TextStyle(fontSize: 16)),
                          label: Text(
                            (_quantities[c] ?? 0) > 0
                                ? '${c.label} × ${_quantities[c]}'
                                : c.label,
                          ),
                          selected: (_quantities[c] ?? 0) > 0,
                          showCheckmark: false,
                          onPressed: () => setState(
                            () => _quantities[c] = (_quantities[c] ?? 0) + 1,
                          ),
                          onDeleted: (_quantities[c] ?? 0) > 0
                              ? () => setState(() {
                                    final next = (_quantities[c] ?? 0) - 1;
                                    if (next <= 0) {
                                      _quantities.remove(c);
                                    } else {
                                      _quantities[c] = next;
                                    }
                                  })
                              : null,
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy || (_type != GiveBeneficiaryType.player && orgId == null)
                        ? null
                        : () => _submit(orgId: orgId ?? '', orgName: org?.name),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Submit for verification'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
