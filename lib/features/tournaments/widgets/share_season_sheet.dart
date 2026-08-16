import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

import '../../../core/models/tournament.dart';

/// Modal bottom sheet to share a season/tournament invitation via WhatsApp,
/// direct link, or system share sheet.
class ShareSeasonSheet extends StatelessWidget {
  const ShareSeasonSheet({
    super.key,
    required this.tournament,
  });

  final Tournament tournament;

  String _formatDate(DateTime? d) {
    if (d == null) return '';
    return DateFormat('d MMM yyyy').format(d);
  }

  String get _shareUrl =>
      'https://playsphere.app/t/${tournament.orgId}/${tournament.id}';

  String get _invitationMessage {
    final dates = tournament.startDate != null
        ? '📅 Dates: ${_formatDate(tournament.startDate)}${tournament.endDate != null && tournament.endDate != tournament.startDate ? ' to ${_formatDate(tournament.endDate)}' : ''}'
        : '';

    return '🏆 *${tournament.name}*\n'
        'Registrations are now OPEN on PlaySphere!\n\n'
        '$dates\n'
        '⚡ ${tournament.eventCount} Categories\n\n'
        'Register your team / enter the draws here:\n'
        '$_shareUrl';
  }

  void _shareViaWhatsApp(BuildContext context) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: _invitationMessage,
          subject: 'Join ${tournament.name} on PlaySphere',
        ),
      );
    } catch (_) {
      // Fallback to generic share
      await SharePlus.instance.share(
        ShareParams(text: _invitationMessage),
      );
    }
  }

  void _copyLink(BuildContext context) {
    Clipboard.setData(ClipboardData(text: _shareUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tournament link copied to clipboard!'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.share_outlined, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Share Tournament',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Preview Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tournament.name,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Entries Open · ${tournament.eventCount} Categories',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                ),
                const SizedBox(height: 8),
                Text(
                  _shareUrl,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Share options
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFF25D366),
              child: Icon(Icons.chat_bubble_outline, color: Colors.white),
            ),
            title: const Text('Share to WhatsApp'),
            subtitle: const Text('Send formatted invite to groups and players'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).pop();
              _shareViaWhatsApp(context);
            },
          ),
          const Divider(),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(Icons.link, color: theme.colorScheme.onPrimaryContainer),
            ),
            title: const Text('Copy Invitation Link'),
            subtitle: const Text('Paste link anywhere on chats or social media'),
            trailing: const Icon(Icons.copy),
            onTap: () => _copyLink(context),
          ),
          const Divider(),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.secondaryContainer,
              child: Icon(Icons.share, color: theme.colorScheme.onSecondaryContainer),
            ),
            title: const Text('More Share Options'),
            subtitle: const Text('Share via Email, SMS, Instagram, or other apps'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).pop();
              SharePlus.instance.share(
                ShareParams(text: _invitationMessage),
              );
            },
          ),
        ],
      ),
    );
  }
}
