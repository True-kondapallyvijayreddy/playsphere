import 'package:flutter/material.dart';

/// The one place the "we do not take this money" wording lives.
///
/// ## Why the copy is a constant and not typed into each screen
///
/// An entry fee and a ground's hourly rate are numbers PlaySphere *displays*
/// on behalf of somebody else. It never collects them, never holds them, and
/// never refunds them — see `GroundRepository.book`, which writes
/// `amountPaise` as what is OWED with a null `paymentId`, and
/// `PlanPaymentKind`, which has no entry-fee kind to write a ledger row with.
///
/// A number rendered next to a currency symbol in an app that also sells
/// subscriptions reads as "tap to pay" unless something says otherwise. Six
/// screens showing that number is six chances for one of them to be reworded
/// into an implied guarantee, so the sentence itself is a constant and the
/// screens render it rather than restating it.
///
/// ## Why the wording is deliberately flat
///
/// "Paid directly to the organiser" and never "pay safely at the venue".
/// PlaySphere cannot yet verify that an organiser is genuine — that is the
/// entire reason the money stays offline — so any phrasing that sounds like
/// reassurance is a promise the product cannot keep. Stating plainly who
/// holds the money tells a player exactly where they stand and who to chase,
/// which is the honest version of the same sentence.
class FeeSettlement {
  const FeeSettlement._();

  /// For an event's entry fee.
  static const entry =
      'Paid directly to the organiser at the venue. PlaySphere does not '
      'collect or hold entry fees.';

  /// The short form, for a chip or a list row where the long one will not fit.
  static const entryShort = 'paid at the venue';

  /// For a ground's hourly rate.
  static const ground =
      'Paid directly to the ground at the venue. PlaySphere does not collect '
      'or hold ground fees — booking here only holds the slot.';

  /// The short form.
  static const groundShort = 'paid at the ground';

  /// The sentence that actually stops the fraud, wherever a ground's phone
  /// number or rate is shown.
  ///
  /// ## Why this is separate from [ground], and stronger
  ///
  /// [ground] states who holds the money. That is honest and it is not
  /// enough: a person who reads "paid directly to the ground at the venue"
  /// and is then rung up by somebody claiming to be the ground, asking for
  /// ₹2000 on UPI to hold Sunday evening, has not been told that the second
  /// thing contradicts the first. The scam works precisely in that gap.
  ///
  /// So this names the demand and tells them what to do about it. "Never" and
  /// "nobody" rather than "PlaySphere will not" — the fraudster is not
  /// PlaySphere and a sentence about what PlaySphere does leaves them room.
  static const neverPayAdvance =
      'Never pay an advance to hold a slot. Nobody — not the ground, not '
      'PlaySphere — should ask you to send money before you arrive. If anyone '
      'does, report the listing.';

  /// The short form, for a chip or a dense row.
  static const neverPayAdvanceShort = 'Never pay in advance to hold a slot';

  /// What an organiser is told while typing the number in.
  static const organiserHelper =
      'Leave at 0 for a free event. Whatever you enter is shown to entrants '
      'up front and collected by you at the venue — PlaySphere does not '
      'collect it.';
}

/// The settlement sentence, rendered as a quiet informational line.
///
/// Deliberately low-contrast and un-iconed by default: this is a fact a
/// reader needs available, not a warning that should compete with the event's
/// own information. It earns an icon only where it sits next to a payable
/// number that could be mistaken for a checkout.
class OfflineFeeNotice extends StatelessWidget {
  const OfflineFeeNotice({
    super.key,
    required this.message,
    this.icon = Icons.info_outline,
    this.showIcon = true,
  });

  /// The ground variant, spelled out so call sites read as what they mean.
  const OfflineFeeNotice.entry({super.key})
      : message = FeeSettlement.entry,
        icon = Icons.info_outline,
        showIcon = true;

  const OfflineFeeNotice.ground({super.key})
      : message = FeeSettlement.ground,
        icon = Icons.info_outline,
        showIcon = true;

  final String message;
  final IconData icon;
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showIcon) ...[
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 7),
        ],
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
