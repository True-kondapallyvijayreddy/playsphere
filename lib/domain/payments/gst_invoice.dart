/// Integer round-half-up of `numerator / denominator`, both non-negative.
///
/// Written as `(2*numerator + denominator) ~/ (2*denominator)` instead of
/// `(numerator / denominator).round()` so the computation never touches a
/// `double`. GST figures end up on a legal invoice; the rounding rule that
/// produces them needs to be exactly reproducible by anyone checking the
/// arithmetic by hand, and IEEE-754 division is not guaranteed to agree
/// with schoolbook long division on every input.
int _roundHalfUp(int numerator, int denominator) {
  assert(denominator > 0);
  return (2 * numerator + denominator) ~/ (2 * denominator);
}

/// One line of a GST invoice's breakdown (taxable value, each tax head,
/// total), for direct display on a receipt.
class GstInvoiceLine {
  const GstInvoiceLine(this.label, this.amountPaise);

  final String label;
  final int amountPaise;
}

/// A GST-compliant breakdown of one gross (tax-inclusive) amount collected
/// from a payer.
///
/// India's GST is charged on top of a taxable value, but PlaySphere collects
/// one all-in entry fee — the payer sees "₹590", not "₹500 + 18% GST". The
/// taxable value therefore has to be backed out of the gross rather than
/// summed up to it: `taxableValuePaise = round(gross × 10000 / (10000 +
/// rateBps))`, and the tax itself is defined as `gross - taxableValuePaise`
/// (not recomputed independently), which is what guarantees
/// `taxableValuePaise + totalGstPaise == grossAmountPaise` exactly — the
/// same "compute one part, the other is the remainder" trick used for the
/// Route split, for the same reason: two independently-rounded numbers can
/// each be individually correct and still fail to sum to the total.
///
/// For an intra-state supply, GST law splits the tax into CGST + SGST in
/// equal halves rather than one combined line; [interState] selects IGST
/// (a single line) instead. The CGST/SGST halves use the same
/// remainder trick (`sgst = totalGst - cgst`) so they sum to the tax total
/// even when the tax paise figure is odd (e.g. 101 paise → ₹0.50 + ₹0.51).
class GstInvoice {
  const GstInvoice({
    required this.grossAmountPaise,
    required this.gstRateBps,
    required this.interState,
    required this.taxableValuePaise,
    required this.cgstPaise,
    required this.sgstPaise,
    required this.igstPaise,
    required this.totalGstPaise,
  });

  final int grossAmountPaise;

  /// GST rate in basis points (1800 = 18%). Configurable per event/sport
  /// category rather than hard-coded — GST rates on sporting event entry
  /// fees are a matter of current tax law, not something to freeze in code.
  final int gstRateBps;

  final bool interState;

  final int taxableValuePaise;
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;
  final int totalGstPaise;

  int get totalPaise => taxableValuePaise + totalGstPaise;

  List<GstInvoiceLine> get lines => [
        GstInvoiceLine('Taxable value', taxableValuePaise),
        if (interState)
          GstInvoiceLine('IGST', igstPaise)
        else ...[
          GstInvoiceLine('CGST', cgstPaise),
          GstInvoiceLine('SGST', sgstPaise),
        ],
        GstInvoiceLine('Total', totalPaise),
      ];
}

/// Backs a [GstInvoice] out of a gross, tax-inclusive amount actually
/// collected from a payer. See [GstInvoice] for why the arithmetic is
/// ordered the way it is — every field here is either the one independently
/// rounded value or a remainder against something already computed, never
/// two independent roundings of the same total.
GstInvoice computeGstInvoice({
  required int grossAmountPaise,
  required int gstRateBps,
  bool interState = false,
}) {
  if (grossAmountPaise < 0) {
    throw ArgumentError.value(
      grossAmountPaise,
      'grossAmountPaise',
      'must not be negative',
    );
  }
  if (gstRateBps < 0) {
    throw ArgumentError.value(gstRateBps, 'gstRateBps', 'must not be negative');
  }

  final taxableValuePaise = _roundHalfUp(
    grossAmountPaise * 10000,
    10000 + gstRateBps,
  );
  final totalGstPaise = grossAmountPaise - taxableValuePaise;

  var cgstPaise = 0;
  var sgstPaise = 0;
  var igstPaise = 0;
  if (interState) {
    igstPaise = totalGstPaise;
  } else {
    cgstPaise = totalGstPaise ~/ 2;
    sgstPaise = totalGstPaise - cgstPaise;
  }

  return GstInvoice(
    grossAmountPaise: grossAmountPaise,
    gstRateBps: gstRateBps,
    interState: interState,
    taxableValuePaise: taxableValuePaise,
    cgstPaise: cgstPaise,
    sgstPaise: sgstPaise,
    igstPaise: igstPaise,
    totalGstPaise: totalGstPaise,
  );
}
