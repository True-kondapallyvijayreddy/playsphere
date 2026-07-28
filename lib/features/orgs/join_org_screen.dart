import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/organization.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../shared/app_scaffold.dart';

class JoinOrgScreen extends ConsumerStatefulWidget {
  const JoinOrgScreen({super.key});

  @override
  ConsumerState<JoinOrgScreen> createState() => _JoinOrgScreenState();
}

class _JoinOrgScreenState extends ConsumerState<JoinOrgScreen> {
  final _code = TextEditingController();
  Organization? _found;
  bool _busy = false;
  String? _notFound;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final code = _code.text.trim();
    if (code.length < 4) return;

    setState(() {
      _busy = true;
      _notFound = null;
      _found = null;
    });
    try {
      final org = await ref.read(orgRepositoryProvider).findByInviteCode(code);
      setState(() {
        _found = org;
        _notFound = org == null
            ? 'No organization uses that code. Check it with whoever invited '
                'you — codes never contain the letter O or the digit 0.'
            : null;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    final org = _found;
    final user = ref.read(currentUserProvider).valueOrNull;
    if (org == null || user == null) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(orgRepositoryProvider)
          .requestToJoin(orgId: org.id, user: user);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            org.requiresApprovalToJoin
                ? 'Request sent. An admin at ${org.name} will approve you.'
                : 'You have joined ${org.name}.',
          ),
        ),
      );
      context.go(Routes.orgs);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final org = _found;

    return Scaffold(
      appBar: AppBar(title: const Text('Join an organization')),
      body: SingleChildScrollView(
        child: ContentBounds(
          maxWidth: 480,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Enter the invite code',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                'Your coach, teacher or club admin will have shared a '
                'six-character code.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).hintColor,
                    ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _code,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 26,
                  letterSpacing: 8,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: 'ABC123',
                  border: const OutlineInputBorder(),
                  errorText: _notFound,
                  errorMaxLines: 3,
                ),
                onSubmitted: (_) => _lookup(),
                onChanged: (_) {
                  if (_found != null || _notFound != null) {
                    setState(() {
                      _found = null;
                      _notFound = null;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              if (org == null)
                FilledButton(
                  onPressed: _busy ? null : _lookup,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Text(_busy ? 'Looking…' : 'Find organization'),
                )
              else ...[
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(org.name.characters.first.toUpperCase()),
                    ),
                    title: Text(org.name),
                    subtitle: Text(
                      [
                        org.orgType.label,
                        if (org.city != null) org.city!,
                      ].join(' · '),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _join,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Text(
                    _busy
                        ? 'Sending…'
                        : org.requiresApprovalToJoin
                            ? 'Request to join'
                            : 'Join',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
