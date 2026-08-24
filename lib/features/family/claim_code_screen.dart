import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../shared/app_scaffold.dart';

/// The guardian's half of the handoff: generates a short-lived code and
/// shows it big enough to read across a room, for the child to type into
/// [ClaimEntryScreen] on their own device.
///
/// Auto-generates on open rather than behind a button — the guardian only
/// reaches this screen by tapping "Get code" on a specific child already,
/// so there is no accidental-tap risk worth an extra step for.
class ClaimCodeScreen extends ConsumerStatefulWidget {
  const ClaimCodeScreen({super.key, required this.childUid});

  final String childUid;

  @override
  ConsumerState<ClaimCodeScreen> createState() => _ClaimCodeScreenState();
}

class _ClaimCodeScreenState extends ConsumerState<ClaimCodeScreen> {
  String? _code;
  String? _error;
  bool _busy = false;
  DateTime? _expiresAt;
  Timer? _ticker;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final guardianUid = ref.read(currentUidProvider);
    if (guardianUid == null) return;
    try {
      final code = await ref.read(userRepositoryProvider).createClaimCode(
            childUid: widget.childUid,
            guardianUid: guardianUid,
          );
      // Mirrors the 25-minute window UserRepository.createClaimCode actually
      // writes — see that method for why it's short of the 30-minute rules
      // ceiling.
      final expiresAt = DateTime.now().add(const Duration(minutes: 25));
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      if (!mounted) return;
      setState(() {
        _code = code;
        _expiresAt = expiresAt;
        _remaining = expiresAt.difference(DateTime.now());
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _tick() {
    final expiresAt = _expiresAt;
    if (expiresAt == null) return;
    final left = expiresAt.difference(DateTime.now());
    if (!mounted) return;
    setState(() => _remaining = left.isNegative ? Duration.zero : left);
  }

  @override
  Widget build(BuildContext context) {
    final child = ref.watch(userProfileProvider(widget.childUid)).valueOrNull;
    final expired = _code != null && _remaining <= Duration.zero;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title:
            Text(child == null ? 'Claim code' : "${child.displayName}'s code"),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "On your child's phone, open PlaySphere, choose "
                '"I have a code" and enter:',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.hintColor),
              ),
              const SizedBox(height: 24),
              if (_busy && _code == null)
                const CircularProgressIndicator()
              else if (_error != null)
                Text(_error!, style: TextStyle(color: theme.colorScheme.error))
              else if (_code != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 20,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _code!,
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 6,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  expired
                      ? 'This code has expired.'
                      : 'Valid for ${_remaining.inMinutes}:'
                          '${(_remaining.inSeconds % 60).toString().padLeft(2, '0')}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: expired ? theme.colorScheme.error : theme.hintColor,
                  ),
                ),
              ],
              const SizedBox(height: 32),
              OutlinedButton(
                onPressed: _busy ? null : _generate,
                child: Text(
                    _code == null ? 'Generate code' : 'Generate a new code'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
