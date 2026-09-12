import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../core/models/organization.dart';
import '../core/providers.dart';
import '../core/router/app_router.dart';

/// The club's code, shown beside its name.
///
/// ## Which code, and why it depends on who is looking
///
/// A club has two identifiers and they are not interchangeable.
/// [Organization.inviteCode] is a key: typing it into "join a club" starts a
/// membership, and in a club with `requiresApprovalToJoin: false` it completes
/// one. [Organization.clubCodeLabel] is derived from the document id, grants
/// nothing, and exists so an ordinary member can say *which club they mean*.
///
/// Showing the derived id to a member was confusing rather than safe: a
/// member looking at their own club saw `4K7X-Q2M9` beside its name and the
/// invite code somewhere else entirely, with nothing on screen explaining
/// that the two are different things. So this chip now shows the code that is
/// actually useful to the person reading it:
///
/// * an **active member** sees the invite code, because inviting people is
///   what a member of a club does with a code, and `orgs/{orgId}` is already
///   readable to them — the field was never hidden from them, only unshown;
/// * **everybody else** — someone browsing a public club they have not
///   joined — still sees the derived club id, which opens the club rather
///   than joining it.
///
/// Tapping either form opens [showClubInviteSheet]: the code at readable
/// size, its QR, and a share button that hands the invite to WhatsApp.
class ClubIdChip extends ConsumerWidget {
  const ClubIdChip({
    super.key,
    required this.org,
    this.compact = false,
  });

  final Organization org;

  /// Inside a dense list row: the code alone, no label and no icon buttons.
  /// It stays tappable — the tap is the whole point of putting a code beside
  /// a club's name — and opens the same sheet the full form does.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isMember = ref.watch(_isMyClubProvider(org.id));
    final code = isMember ? org.inviteCode : org.clubCodeLabel;
    final label = isMember ? 'Invite' : 'ID';

    if (compact) {
      return Tooltip(
        message: isMember
            ? 'Invite code — tap for the QR and to share'
            : 'Club ID — tap to share this club',
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => showClubInviteSheet(context, org, isMember: isMember),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isMember ? Icons.vpn_key_outlined : Icons.tag,
                  size: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  code,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // A Wrap rather than a Row: the full form now carries a QR thumbnail as
    // well as the code and two actions, and on a 360pt phone that is wide
    // enough to overflow the club header it sits in.
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
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
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 6),
              SelectableText(
                code,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
        // The QR itself, small, on the club's own page — the thing a member
        // holds up at a ground or screenshots into a group. Tapping it opens
        // the scannable size rather than pretending a 40pt square is one.
        ClubQrThumb(org: org, isMember: isMember),
        IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          tooltip: 'Copy',
          icon: const Icon(Icons.copy_outlined),
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(text: _shareText(org, isMember)),
            );
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(isMember ? 'Invite copied.' : 'Club copied.'),
                ),
              );
            }
          },
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          tooltip: isMember ? 'Share this invite' : 'Share this club',
          icon: const Icon(Icons.ios_share),
          onPressed: () => SharePlus.instance.share(
            ShareParams(text: _shareText(org, isMember), subject: org.name),
          ),
        ),
      ],
    );
  }
}

/// A 40pt QR that is a button, not a picture.
///
/// Small enough to sit inside a club header row and too small to scan off a
/// phone screen in sunlight, which is deliberate: it is the affordance that
/// says "there is a QR here", and the tap is what produces the scannable one.
class ClubQrThumb extends StatelessWidget {
  const ClubQrThumb({
    super.key,
    required this.org,
    required this.isMember,
    this.size = 40,
  });

  final Organization org;
  final bool isMember;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isMember ? 'Invite QR — tap to share' : 'Club QR — tap to share',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => showClubInviteSheet(context, org, isMember: isMember),
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            // White plate regardless of theme: a scanner needs the quiet zone
            // and the contrast, and a dark-mode QR on a dark card does not
            // scan even once it is big enough to try.
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: QrImageView(
            data: _linkFor(org, isMember),
            size: size,
            padding: EdgeInsets.zero,
            backgroundColor: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// The club's code at readable size, its QR, and the two ways to hand it on.
///
/// One sheet for both codes rather than two nearly identical ones: what
/// changes between a member's invite and a visitor's club id is the link
/// behind the QR and the words around it, not the shape of the thing.
Future<void> showClubInviteSheet(
  BuildContext context,
  Organization org, {
  required bool isMember,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 460),
    builder: (_) => _ClubInviteSheet(org: org, isMember: isMember),
  );
}

class _ClubInviteSheet extends StatelessWidget {
  const _ClubInviteSheet({required this.org, required this.isMember});

  final Organization org;
  final bool isMember;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final link = _linkFor(org, isMember);
    final code = isMember ? org.inviteCode : org.clubCodeLabel;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            org.name,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isMember ? 'Invite code' : 'Club ID',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            code,
            style: theme.textTheme.headlineSmall?.copyWith(
              letterSpacing: 6,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: QrImageView(
              data: link,
              size: 200,
              padding: EdgeInsets.zero,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isMember
                ? 'Scan, tap the link, or type the code to join ${org.name}.'
                : 'Scan or tap the link to open ${org.name} on PlaySphere.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => SharePlus.instance.share(
                    ShareParams(
                      text: _shareText(org, isMember),
                      subject: isMember
                          ? 'Join ${org.name}'
                          : '${org.name} on PlaySphere',
                    ),
                  ),
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: const Text('Share'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: _shareText(org, isMember)),
                    );
                    if (context.mounted) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            isMember ? 'Invite copied.' : 'Club copied.',
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.link, size: 18),
                  label: const Text('Copy link'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Where the QR points: an invite link for a member, the club's public page
/// for anybody else.
String _linkFor(Organization org, bool isMember) => isMember
    ? Routes.inviteUrl(org.inviteCode)
    : '${Routes.publicOrigin}${Routes.org(org.id)}';

/// What gets shared or copied. The name first, then the link — a bare code
/// pasted into a group chat says nothing about what it opens, which is the
/// mistake this is here to avoid making twice.
String _shareText(Organization org, bool isMember) => isMember
    ? 'Join ${org.name} on PlaySphere — code ${org.inviteCode}: '
        '${Routes.inviteUrl(org.inviteCode)}'
    : '${org.name} (Club ID ${org.clubCodeLabel}) on PlaySphere: '
        '${_linkFor(org, false)}';

/// Whether the signed-in profile is an ACTIVE member of this club.
///
/// Pending does not count: someone waiting for an admin to approve them has
/// not been handed the club's door, and showing them the invite code would
/// let them walk anyone else through it before they are through it themselves.
final _isMyClubProvider = Provider.family<bool, String>((ref, orgId) {
  final memberships = ref.watch(myMembershipsProvider).valueOrNull ?? const [];
  return memberships.any((m) => m.orgId == orgId && m.isActive);
});
