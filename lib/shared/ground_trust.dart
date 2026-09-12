/// How a listing's trustworthiness is drawn, in the one place that decides
/// it.
///
/// ## Why the badge is a shared widget and not a chip per screen
///
/// The badge appears on a search hit, a card in the booking sheet, the
/// detail page and the owner's own list. Four copies of "if verified show a
/// tick" is four chances for one of them to keep showing a tick after the
/// listing is suspended — and the screen that lagged would be the one a
/// booker was looking at. There is one mapping from [GroundTrust] to colour
/// and icon, here, and the screens render it.
///
/// ## Why "not verified" is drawn quietly
///
/// Most unverified listings are honest ones that predate on-site capture, or
/// new ones waiting on a review. Painting them in warning colours would tell
/// a booker that half the marketplace is dangerous, which is both untrue and
/// self-defeating: a warning shown everywhere is a warning nobody reads. The
/// loud styling is reserved for [GroundTrust.blocked], which is the only
/// state that means somebody has actually done something wrong.
library;

import 'package:flutter/material.dart';

import '../core/models/ground.dart';
import '../core/models/ground_verification.dart';
import 'offline_fee_notice.dart';

/// The colour and icon for one trust state, resolved against the theme.
class _TrustStyle {
  const _TrustStyle(this.icon, this.color);
  final IconData icon;
  final Color color;
}

_TrustStyle _styleFor(GroundTrust trust, ColorScheme scheme) =>
    switch (trust) {
      GroundTrust.blocked => _TrustStyle(Icons.block, scheme.error),
      GroundTrust.unproven =>
        _TrustStyle(Icons.help_outline, scheme.onSurfaceVariant),
      GroundTrust.captured =>
        _TrustStyle(Icons.photo_camera_outlined, scheme.tertiary),
      GroundTrust.locationConfirmed =>
        _TrustStyle(Icons.where_to_vote_outlined, scheme.primary),
      GroundTrust.verified => _TrustStyle(Icons.verified, scheme.primary),
    };

/// The small badge that sits next to a ground's name.
class GroundTrustBadge extends StatelessWidget {
  const GroundTrustBadge({super.key, required this.trust, this.compact = false});

  GroundTrustBadge.of(Ground ground, {super.key, this.compact = false})
      : trust = ground.trust;

  final GroundTrust trust;

  /// Icon only, for a dense row where the label will not fit. The tooltip
  /// carries the words so the meaning is still reachable — an unlabelled icon
  /// that means "this listing has been taken down" is not something to leave
  /// to inference.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = _styleFor(trust, theme.colorScheme);

    if (compact) {
      return Tooltip(
        message: '${trust.label} — ${trust.blurb}',
        child: Icon(style.icon, size: 15, color: style.color),
      );
    }

    return Tooltip(
      message: trust.blurb,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 14, color: style.color),
          const SizedBox(width: 4),
          Text(
            trust.label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: style.color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// The full explanation, for a detail page where there is room to say it.
class GroundTrustPanel extends StatelessWidget {
  const GroundTrustPanel({super.key, required this.ground, this.onReport});

  final Ground ground;

  /// Offered on every state except the owner's own view. Reporting is put
  /// beside the badge deliberately: the moment somebody is weighing up how
  /// much to trust a listing is the moment they are most likely to have a
  /// reason to flag it.
  final VoidCallback? onReport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trust = ground.trust;
    final style = _styleFor(trust, theme.colorScheme);
    final blocked = trust == GroundTrust.blocked;

    return Card(
      color: blocked
          ? theme.colorScheme.errorContainer
          : theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(style.icon, size: 18, color: style.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    trust.label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: blocked
                          ? theme.colorScheme.onErrorContainer
                          : null,
                    ),
                  ),
                ),
                if (ground.checkInCount > 0)
                  Text(
                    '${ground.checkInCount} '
                    '${ground.checkInCount == 1 ? 'arrival' : 'arrivals'}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              trust.blurb,
              style: theme.textTheme.bodySmall?.copyWith(
                color: blocked ? theme.colorScheme.onErrorContainer : null,
              ),
            ),
            if (onReport != null) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onReport,
                  icon: const Icon(Icons.flag_outlined, size: 16),
                  label: const Text('Report this listing'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The warning that goes wherever a number somebody might pay is shown.
///
/// Styled as a caution rather than an aside, unlike [OfflineFeeNotice]. The
/// distinction is deliberate and is the reason both exist: the fee notice
/// states a fact about who holds the money, which a reader needs available;
/// this one contradicts something a fraudster is about to tell them on the
/// phone, and it has to still be in their head when that call comes.
class AdvancePaymentWarning extends StatelessWidget {
  const AdvancePaymentWarning({super.key, this.dense = false});

  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.error;

    if (dense) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.gpp_maybe_outlined, size: 15, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              FeeSettlement.neverPayAdvanceShort,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.gpp_maybe_outlined, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              FeeSettlement.neverPayAdvance,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
