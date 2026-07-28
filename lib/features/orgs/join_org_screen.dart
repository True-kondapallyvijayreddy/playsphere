import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/enums.dart';
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
  InviteTarget? _found;
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
    final target = _found;
    final user = ref.read(currentUserProvider).valueOrNull;
    if (target == null || user == null) return;

    setState(() => _busy = true);
    try {
      // The repository reports the status actually written. The screen used to
      // announce "You have joined" purely from the club's setting while the
      // membership was written as pending regardless — the user walked away
      // believing they were in.
      final status = await ref.read(orgRepositoryProvider).requestToJoin(
            orgId: target.orgId,
            user: user,
            requiresApproval: target.requiresApprovalToJoin,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == MembershipStatus.active
                ? 'You have joined ${target.orgName}.'
                : 'Request sent. An admin at ${target.orgName} will review it.',
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
    final target = _found;

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
              if (target == null)
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
                      child: Text(
                        target.orgName.characters.first.toUpperCase(),
                      ),
                    ),
                    title: Text(target.orgName),
                    subtitle: Text(
                      [
                        target.orgType.label,
                        if (target.city != null) target.city!,
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
                        : target.requiresApprovalToJoin
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
