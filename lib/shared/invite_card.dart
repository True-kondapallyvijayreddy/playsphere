import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../core/models/organization.dart';
import '../core/router/app_router.dart';

/// How a club actually grows.
///
/// A six-character code that has to be read out over a phone, retyped, and
/// got wrong is the narrowest possible door into a club — and it was the only
/// one. This gives the same invite three shapes: a code for someone standing
/// next to you, a link to paste into a WhatsApp group, and a QR to hold up in
/// front of a classroom or print on a poster at the ground.
///
/// Shared between the Members screen and the account panel's "My clubs"
/// list — anywhere an admin needs to hand this club's door to someone else.
class InviteCard extends StatelessWidget {
  const InviteCard({super.key, required this.org});
  final Organization org;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final link = Routes.inviteUrl(org.inviteCode);

    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Invite code',
                        style: theme.textTheme.labelMedium,
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        org.inviteCode,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          letterSpacing: 6,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Scan, tap the link, or type the code.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                // White plate behind the QR regardless of theme: a scanner
                // needs the quiet zone and the contrast, and a dark-mode QR
                // rendered on a dark card does not scan.
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: QrImageView(
                    data: link,
                    size: 108,
                    padding: EdgeInsets.zero,
                    backgroundColor: Colors.white,
                    // A club name under the code would be nice and is
                    // deliberately absent: embedded text costs error
                    // correction, and this gets scanned off a phone screen in
                    // sunlight.
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => SharePlus.instance.share(
                    ShareParams(
                      text: 'Join ${org.name} on PlaySphere: $link',
                      subject: 'Join ${org.name}',
                    ),
                  ),
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: const Text('Share invite'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: link));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Invite link copied.')),
                      );
                    }
                  },
                  icon: const Icon(Icons.link, size: 18),
                  label: const Text('Copy link'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
