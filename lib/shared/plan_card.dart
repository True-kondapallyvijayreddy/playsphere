import 'package:flutter/material.dart';

import '../core/models/billing.dart';

/// The price line: what it normally costs, and what you pay today.
///
/// Both numbers are always shown while the launch offer is on. Showing only
/// "Free" would be the easier design and the wrong one — a product that looks
/// free and then grows a ₹999 price reads as a bait-and-switch, whereas ₹999
/// struck through next to ₹0 tells the club exactly what they are getting and
/// what it will cost at renewal. That is also the number they have to take to
/// whoever signs off the club's spending.
class PlanPriceRow extends StatelessWidget {
  const PlanPriceRow({
    super.key,
    required this.payablePaise,
    required this.listPricePaise,
    required this.period,
  });

  final int payablePaise;
  final int listPricePaise;

  /// "per year", "per club per year" — the unit the list price is quoted in.
  final String period;

  bool get _discounted => payablePaise < listPricePaise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          payablePaise == 0 ? '₹0' : Pricing.formatPaise(payablePaise),
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: 10),
        if (_discounted)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(
              Pricing.formatPaise(listPricePaise),
              style: theme.textTheme.titleMedium?.copyWith(
                decoration: TextDecoration.lineThrough,
                color: theme.hintColor,
              ),
            ),
          ),
        const SizedBox(width: 6),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(period, style: theme.textTheme.bodySmall),
        ),
      ],
    );
  }
}

/// The "Launch offer" flag. Rendered only while [Pricing.introOfferActive],
/// so the day the offer ends every screen carrying one loses it at once
/// rather than each needing to be found and edited.
class LaunchOfferChip extends StatelessWidget {
  const LaunchOfferChip({super.key, this.label = 'Launch offer'});

  final String label;

  @override
  Widget build(BuildContext context) {
    if (!Pricing.introOfferActive) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onTertiaryContainer,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// One "✓ this is included" line.
class PlanFeatureLine extends StatelessWidget {
  const PlanFeatureLine(this.text, {super.key, this.icon = Icons.check});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// What a plan costs and what it contains, as one card.
///
/// Shared by the club checkout and the Premium screen so the two purchases in
/// the product look like the same product. They are sold to different people
/// for different reasons, but a member who has seen their club buy a plan
/// should recognise the shape of the thing they are being offered.
class PlanCard extends StatelessWidget {
  const PlanCard({
    super.key,
    required this.title,
    required this.blurb,
    required this.payablePaise,
    required this.listPricePaise,
    required this.period,
    required this.features,
    this.footnote,
    this.highlighted = true,
  });

  final String title;
  final String blurb;
  final int payablePaise;
  final int listPricePaise;
  final String period;
  final List<String> features;
  final String? footnote;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: highlighted ? 2 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: highlighted
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: highlighted ? 1.6 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const LaunchOfferChip(),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              blurb,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            PlanPriceRow(
              payablePaise: payablePaise,
              listPricePaise: listPricePaise,
              period: period,
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            for (final f in features) PlanFeatureLine(f),
            if (footnote != null) ...[
              const SizedBox(height: 12),
              Text(
                footnote!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
