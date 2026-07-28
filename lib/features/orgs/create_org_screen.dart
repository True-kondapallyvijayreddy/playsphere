import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/enums.dart';
import '../../core/models/organization.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../shared/app_scaffold.dart';

class CreateOrgScreen extends ConsumerStatefulWidget {
  const CreateOrgScreen({super.key});

  @override
  ConsumerState<CreateOrgScreen> createState() => _CreateOrgScreenState();
}

class _CreateOrgScreenState extends ConsumerState<CreateOrgScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _city = TextEditingController();

  OrgType _type = OrgType.school;
  OrgVisibility _visibility = OrgVisibility.public;
  bool _requireApproval = true;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;

    setState(() => _busy = true);
    try {
      final orgId = await ref.read(orgRepositoryProvider).createOrganization(
            org: Organization(
              id: '',
              name: _name.text.trim(),
              orgType: _type,
              visibility: _visibility,
              ownerUid: user.uid,
              inviteCode: Organization.generateInviteCode(),
              description: _description.text.trim().isEmpty
                  ? null
                  : _description.text.trim(),
              city: _city.text.trim().isEmpty ? null : _city.text.trim(),
              requiresApprovalToJoin: _requireApproval,
            ),
            founder: user,
          );
      if (mounted) context.go(Routes.org(orgId));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create an organization')),
      body: SingleChildScrollView(
        child: ContentBounds(
          maxWidth: 560,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'e.g. St. Xavier\'s High School',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().length < 3)
                      ? 'At least 3 characters'
                      : null,
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<OrgType>(
                  value: _type,
                  decoration: const InputDecoration(
                    labelText: 'Type',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final t in OrgType.values)
                      DropdownMenuItem(value: t, child: Text(t.label)),
                  ],
                  onChanged: (v) => setState(() => _type = v ?? _type),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _city,
                  decoration: const InputDecoration(
                    labelText: 'City or district (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _description,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        value: _visibility == OrgVisibility.public,
                        onChanged: (v) => setState(() => _visibility =
                            v ? OrgVisibility.public : OrgVisibility.unlisted),
                        title: const Text('Public'),
                        subtitle: const Text(
                          'Anyone can find this organization and follow its '
                          'live matches without an account. Turn this off and '
                          'only members can see anything.',
                        ),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        value: _requireApproval,
                        onChanged: (v) => setState(() => _requireApproval = v),
                        title: const Text('Approve new members'),
                        subtitle: const Text(
                          'Recommended for schools and colleges — people who '
                          'use the invite code wait for an admin before they '
                          'can enter competitions.',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: _busy ? null : _create,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Text(_busy ? 'Creating…' : 'Create organization'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
