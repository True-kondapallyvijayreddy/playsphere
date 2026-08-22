import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/models/organization.dart';
import '../core/router/app_router.dart';

/// The club's public id, shown beside its name — to every member, not just
/// the people who can administer it.
///
/// ## Why an ordinary member needs this
///
/// The only club identifier the app showed was [Organization.inviteCode], and
/// it was admin-only for a good reason: typing it into "join a club" starts a
/// membership, and in a club that does not require approval it completes one.
/// It is a key, so it stays with the people who hold the keys.
///
/// That left every ordinary member with no way to say *which club they mean*.
/// The person most likely to talk a club up is not its secretary — it is a
/// player telling a friend at another school which team they play for, and
/// "we're called Sunrise" is not an answer when four clubs are. So this is the
/// half of the invite card that grants nothing: an identifier and a link to a
/// page, shareable by anybody, that opens the club rather than joining it.
///
/// See [Organization.clubCode] for why the code is derived rather than stored,
/// and why it is not the document id.
class ClubIdChip extends StatelessWidget {
  const ClubIdChip({
    super.key,
    required this.org,
    this.compact = false,
  });

  final Organization org;

  /// Inside a dense list row: the code alone, no label and no actions, with
  /// the whole row's tap already doing something else. The full form belongs
  /// on a club's own page, where sharing it is a thing somebody came to do.
  final bool compact;

  /// What gets shared or copied. The name first, then the id, then the link —
  /// a bare code pasted into a group chat says nothing about what it opens,
  /// which is the mistake this is here to avoid making twice.
  String get shareText =>
      '${org.name} (Club ID ${org.clubCodeLabel}) on PlaySphere: '
      '${Routes.publicOrigin}${Routes.org(org.id)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (compact) {
      return Tooltip(
        message: 'Club ID — tap and hold the club to share it',
        child: Text(
          org.clubCodeLabel,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'ID',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 6),
              SelectableText(
                org.clubCodeLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          tooltip: 'Copy',
          icon: const Icon(Icons.copy_outlined),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: shareText));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Club copied.')),
              );
            }
          },
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          tooltip: 'Share this club',
          icon: const Icon(Icons.ios_share),
          onPressed: () => SharePlus.instance.share(
            ShareParams(text: shareText, subject: org.name),
          ),
        ),
      ],
    );
  }
}
