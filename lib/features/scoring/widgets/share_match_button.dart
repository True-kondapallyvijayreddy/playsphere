import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/models/fixture.dart';
import '../../../core/router/app_router.dart';

/// Hands someone the live link to a match.
///
/// The public spectator route has existed since the router was written and was
/// reachable only by tapping through the app — which meant the one feature
/// aimed squarely at people who do NOT have the app could only be found by
/// people who did. A parent at work, a cousin in another district and a class
/// on a laptop all reach a match the same way: someone sends them a link.
///
/// Falls back to the clipboard rather than failing. On a desktop or an
/// unusual Android build the system share sheet may simply not be there, and
/// "copied to clipboard" still gets the link into the WhatsApp message the
/// user was going to send anyway.
class ShareMatchButton extends StatelessWidget {
  const ShareMatchButton({
    super.key,
    required this.fixture,
    this.compact = false,
  });

  final Fixture fixture;

  /// Renders as an icon button for an app bar rather than a labelled button.
  final bool compact;

  String get _url =>
      Routes.watchUrl(fixture.orgId, fixture.compId, fixture.id);

  String get _message =>
      '${fixture.entrantAName} v ${fixture.entrantBName}'
      '${fixture.summary.isEmpty ? '' : ' — ${fixture.summary}'}\n'
      'Follow it live: $_url';

  Future<void> _share(BuildContext context) => share(context, fixture);

  /// Shares [fixture] without needing a button on screen.
  ///
  /// The schedule board folds its per-row affordances into one overflow menu,
  /// so sharing has to be callable as an action rather than only as a widget.
  /// Same message and same clipboard fallback — there is one way to share a
  /// match, and this is it.
  static Future<void> share(BuildContext context, Fixture fixture) async {
    final button = ShareMatchButton(fixture: fixture);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: button._message,
          subject: '${fixture.entrantAName} v ${fixture.entrantBName}',
        ),
      );
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: button._url));
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Match link copied.')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IconButton(
        tooltip: 'Share this match',
        icon: const Icon(Icons.ios_share),
        onPressed: () => _share(context),
      );
    }
    return OutlinedButton.icon(
      onPressed: () => _share(context),
      icon: const Icon(Icons.ios_share),
      label: const Text('Share live link'),
    );
  }
}
