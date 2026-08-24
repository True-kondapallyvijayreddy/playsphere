import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/layout/responsive.dart';
import '../../core/providers.dart';
import '../../shared/app_scaffold.dart' show errorMessage;

enum _Step { enterCode, linkGoogle }

/// Where a child with no login of their own yet redeems the code their
/// guardian generated ([ClaimCodeScreen]) and turns it into a real,
/// durable account on their own device.
///
/// Public — see `_isPublicRoute` in app_router.dart — because there is no
/// Firebase Auth session at all until [_redeem] below creates one. Two
/// steps, and deliberately not skippable partway: `claimedAt` on the
/// profile only flips once [_linkGoogle] succeeds
/// (`UserRepository.completeClaim`), so a child who closes the app between
/// the two steps has changed nothing that matters — the profile still reads
/// as unclaimed to the guardian, who can simply generate a fresh code.
class ClaimEntryScreen extends ConsumerStatefulWidget {
  const ClaimEntryScreen({super.key});

  @override
  ConsumerState<ClaimEntryScreen> createState() => _ClaimEntryScreenState();
}

class _ClaimEntryScreenState extends ConsumerState<ClaimEntryScreen> {
  final _codeController = TextEditingController();
  _Step _step = _Step.enterCode;
  bool _busy = false;
  String? _error;
  String? _displayName;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter the code your guardian gave you.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final claimed =
          await ref.read(userRepositoryProvider).redeemClaimCode(code);
      await ref
          .read(authServiceProvider)
          .signInWithCustomToken(claimed.customToken);
      if (!mounted) return;
      setState(() {
        _displayName = claimed.displayName;
        _step = _Step.linkGoogle;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _linkGoogle() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).linkGoogleAccount();
      final uid = ref.read(authServiceProvider).currentUser?.uid;
      if (uid != null) {
        await ref.read(userRepositoryProvider).completeClaim(uid);
      }
      // Not a manual navigation: the moment this session shows up as
      // signed in with a complete profile, the router's own redirect —
      // already reacting to authStateProvider — takes it from here.
    } on AuthCancelledException {
      // Backed out of the Google chooser; stay put and let them retry.
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: ContentBounds(
            maxWidth: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.phonelink_lock,
                  size: 56,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 20),
                if (_step == _Step.enterCode)
                  ..._codeStep(theme)
                else
                  ..._linkStep(theme),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _codeStep(ThemeData theme) => [
        Text(
          'I have a code',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Enter the code your guardian gave you to claim your profile on '
          'this phone.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          autofocus: true,
          style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 6),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            counterText: '',
          ),
          maxLength: 6,
          onSubmitted: (_) => _busy ? null : _redeem(),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _busy ? null : _redeem,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: Text(_busy ? 'Checking…' : 'Continue'),
        ),
      ];

  List<Widget> _linkStep(ThemeData theme) => [
        Text(
          'Welcome${_displayName == null ? '' : ', $_displayName'}!',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'One last step: sign in with your own Google account to finish '
          "securing this profile. If you're already signed in to another "
          'PlaySphere account on this phone, that switches to this one.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
        ),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: _busy ? null : _linkGoogle,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.login),
          label: Text(_busy ? 'Signing in…' : 'Continue with Google'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
        ),
      ];
}
