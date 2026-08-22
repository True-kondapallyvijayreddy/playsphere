import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/ads/promo.dart';
import '../core/providers.dart';
import 'identity.dart';
import 'ui_kit.dart';

/// A row of promos at the foot of a screen, scrolled rather than dismissed.
///
/// ## Why a strip and not another banner
///
/// [PromoBanner] is an interruption: one card, in the reading path, with a
/// close button and a five-second delay before that button works. It earns
/// its place at the top of a shop or a grounds list, where a person is
/// already shopping.
///
/// The bottom of a dashboard is a different situation. Nobody arrived to look
/// at ads, so an interruption there is pure cost — but a row a thumb flicks
/// through costs nothing to ignore and is genuinely useful to the person who
/// does look. So this one has no close button, because there is nothing to
/// close: it never covers anything and never blocks the way to anything.
///
/// Impressions are billed on the cards that are actually BUILT, not on the
/// strip appearing. A campaign eighth in a row nobody scrolled to was not
/// seen, and charging for it is the thing that makes advertisers stop
/// trusting a network.
class PromoStrip extends ConsumerStatefulWidget {
  const PromoStrip({
    super.key,
    required this.slot,
    this.title = 'Sponsored',
  });

  final PromoSlot slot;
  final String title;

  @override
  ConsumerState<PromoStrip> createState() => _PromoStripState();
}

class _PromoStripState extends ConsumerState<PromoStrip> {
  /// Campaign ids already billed this widget's lifetime. A rebuild must not
  /// count the same viewing twice — same rule [PromoBanner] follows.
  final _billed = <String>{};

  String? _campaignIdOf(Promo promo) => promo.id.startsWith('campaign-')
      ? promo.id.substring('campaign-'.length)
      : null;

  void _bill(Promo promo) {
    final id = _campaignIdOf(promo);
    if (id == null || !_billed.add(id)) return;
    // After the frame: this runs from build, and a provider write during
    // build is a framework error.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(ref.read(adRepositoryProvider).recordImpression(id));
      }
    });
  }

  void _open(Promo promo) {
    final id = _campaignIdOf(promo);
    if (id != null) {
      unawaited(ref.read(adRepositoryProvider).recordClick(id));
    }
    final target = promo.destination;
    // In-app routes only, for the reason spelled out in [PromoBanner._open]:
    // a tap on a small card must not be able to launch a browser.
    if (target != null && target.startsWith('/')) context.push(target);
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = ref.watch(isPremiumProvider);
    // Premium is sold partly on "no ads", so the strip is not built at all —
    // no heading, no impressions, no row of cards to scroll past.
    if (isPremium) return const SizedBox.shrink();

    final isMinor = ref.watch(currentUserProvider).valueOrNull?.isMinor ?? false;

    // The same gate `PromoBanner` applies, applied here too. It was missing
    // from the strip, which meant a minor scrolling to the foot of the
    // dashboard was served third-party advertising the banner above would
    // have refused them — see [mayShowPromo], and India's DPDP Act, which
    // makes this a legal line rather than a preference.
    final promos = [
      for (final p in ref.watch(promoStripProvider(widget.slot)))
        if (mayShowPromo(p, isPremium: isPremium, isMinor: isMinor)) p,
    ];
    if (promos.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
            widget.title.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: Ps.faint,
            ),
          ),
        ),
        SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: promos.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final promo = promos[i];
              _bill(promo);
              return _PromoCard(promo: promo, onTap: () => _open(promo));
            },
          ),
        ),
      ],
    );
  }
}

class _PromoCard extends StatelessWidget {
  const _PromoCard({required this.promo, required this.onTap});

  final Promo promo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 232,
      child: Material(
        color: Ps.surface,
        borderRadius: BorderRadius.circular(Ps.radius),
        child: InkWell(
          onTap: promo.destination == null ? null : onTap,
          borderRadius: BorderRadius.circular(Ps.radius),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Ps.radius),
              border: Border.all(color: Ps.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 26,
                        height: 26,
                        child: PsNetworkImage(
                          url: promo.imageUrl,
                          fallback: Center(
                            child: Text(promo.emoji,
                                style: const TextStyle(fontSize: 20)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (promo.advertiser case final name?)
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                            color: Ps.faint,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  promo.headline,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                    color: Ps.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Text(
                    promo.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.3,
                      color: Ps.muted,
                    ),
                  ),
                ),
                if (promo.destination != null)
                  Text(
                    promo.ctaLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Ps.primary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
