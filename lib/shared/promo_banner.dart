import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/ads/promo.dart';
import '../core/providers.dart';

/// A banner in one ad slot: shown with a five-second countdown, closable
/// after it, gone for the session once closed.
///
/// ## Why the close button waits five seconds
///
/// An immediately-dismissible banner gets dismissed reflexively, before it
/// has been read — which is worthless to the advertiser and still annoying to
/// the user, the worst of both. A banner that cannot be dismissed at all is
/// worse again. Five seconds is the familiar "skip ad" bargain: the ad gets
/// long enough to be read, and the person gets a guarantee that it will go
/// away when they decide it should.
///
/// It does *not* auto-hide at five seconds. The countdown unlocks the close
/// button; the banner then stays until it is closed. An ad that removes
/// itself has an impression measured in seconds and gives no dismissal signal
/// to learn from.
///
/// ## Why it disappears for the whole session once closed
///
/// A banner that comes back on the next screen has not been closed, it has
/// been postponed, and the second appearance costs far more goodwill than the
/// first one earned. [dismissedPromosProvider] holds the ids for the life of
/// the app process.
class PromoBanner extends ConsumerStatefulWidget {
  const PromoBanner({
    super.key,
    required this.slot,
    this.margin = const EdgeInsets.fromLTRB(12, 4, 12, 8),
  });

  final PromoSlot slot;
  final EdgeInsets margin;

  @override
  ConsumerState<PromoBanner> createState() => _PromoBannerState();
}

class _PromoBannerState extends ConsumerState<PromoBanner> {
  static const _countdownSeconds = 5;

  Timer? _timer;
  int _secondsLeft = _countdownSeconds;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        _secondsLeft -= 1;
        if (_secondsLeft <= 0) t.cancel();
      });
    });
  }

  @override
  void dispose() {
    // A periodic timer outlives the widget unless it is cancelled, and this
    // widget is on screens that get pushed and popped all day.
    _timer?.cancel();
    super.dispose();
  }

  bool get _closable => _secondsLeft <= 0;

  void _open(Promo promo) {
    final target = promo.destination;
    if (target == null) return;
    // Only in-app routes are navigated. An external URL in a promo is opened
    // by the shop screen, which already owns the link-out path and its
    // confirmation — a banner silently launching a browser is not something
    // a tap on a small card should be able to do.
    if (target.startsWith('/')) context.push(target);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = ref.watch(currentUserProvider).valueOrNull;
    final isPremium = ref.watch(isPremiumProvider);
    final dismissed = ref.watch(dismissedPromosProvider);

    // Premium members are never sent down this path at all — no slot, no
    // timer, no layout shift where a banner used to be.
    if (isPremium) return const SizedBox.shrink();

    final promo = PromoCatalog.forSlot(
      widget.slot,
      playerSportIds: ref.watch(myPromoSportIdsProvider),
      seed: PromoCatalog.dailySeed(DateTime.now()),
    );
    if (promo == null) return const SizedBox.shrink();
    if (dismissed.contains(promo.id)) return const SizedBox.shrink();
    if (!mayShowPromo(
      promo,
      isPremium: isPremium,
      isMinor: me?.isMinor ?? false,
    )) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: widget.margin,
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: promo.destination == null ? null : () => _open(promo),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(promo.emoji, style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        promo.disclosure,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.hintColor,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        promo.headline,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        promo.body,
                        style: theme.textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (promo.destination != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          '${promo.ctaLabel} →',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                _CloseAffordance(
                  closable: _closable,
                  secondsLeft: _secondsLeft,
                  onClose: () => ref
                      .read(dismissedPromosProvider.notifier)
                      .dismiss(promo.id),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The countdown, then the ✕ in the same place.
///
/// Same size and position throughout, so the banner does not reflow at the
/// moment the button appears — a layout that jumps under a thumb is how a
/// close button gets missed and something else gets tapped instead.
class _CloseAffordance extends StatelessWidget {
  const _CloseAffordance({
    required this.closable,
    required this.secondsLeft,
    required this.onClose,
  });

  final bool closable;
  final int secondsLeft;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 40,
      height: 40,
      child: closable
          ? IconButton(
              iconSize: 18,
              padding: EdgeInsets.zero,
              tooltip: 'Close',
              icon: const Icon(Icons.close),
              onPressed: onClose,
            )
          : Center(
              child: Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.surface,
                ),
                child: Text(
                  '$secondsLeft',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.hintColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
    );
  }
}

/// Promo ids closed during this run of the app.
///
/// Deliberately in memory and not persisted. A dismissal means "not now",
/// not "never again" — writing it to disk would permanently burn one of the
/// few slots the product has, on a single impatient tap.
class DismissedPromos extends StateNotifier<Set<String>> {
  DismissedPromos() : super(const {});

  void dismiss(String id) => state = {...state, id};
}

final dismissedPromosProvider =
    StateNotifierProvider<DismissedPromos, Set<String>>(
  (ref) => DismissedPromos(),
);
