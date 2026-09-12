import '../ranking/ranking_points.dart';

/// What a certificate is awarded *for*.
///
/// Deliberately coarser than [FinishingRound]. A ranking table needs to
/// separate a last-32 exit from a last-16 one; a certificate does not, and one
/// that said "Last 32" would be a worse thing to hand somebody than one that
/// said they took part.
enum CertificateTitle {
  champion('champion', 'Champion'),
  runnerUp('runner_up', 'Runner-up'),
  semiFinalist('semi_finalist', 'Semi-finalist'),
  quarterFinalist('quarter_finalist', 'Quarter-finalist'),
  participation('participation', 'Certificate of Participation');

  const CertificateTitle(this.wire, this.label);

  final String wire;
  final String label;

  /// Whether this is a placing rather than an attendance.
  bool get isPodium =>
      this == CertificateTitle.champion ||
      this == CertificateTitle.runnerUp ||
      this == CertificateTitle.semiFinalist;

  static CertificateTitle fromRound(FinishingRound round) => switch (round) {
        FinishingRound.winner => CertificateTitle.champion,
        FinishingRound.runnerUp => CertificateTitle.runnerUp,
        FinishingRound.semiFinal => CertificateTitle.semiFinalist,
        FinishingRound.quarterFinal => CertificateTitle.quarterFinalist,
        _ => CertificateTitle.participation,
      };
}

/// Everything printed on one certificate.
///
/// ## Why this is worth building
///
/// A grassroots player currently finishes a tournament and receives nothing.
/// The result is announced on a Telegram channel, the channel scrolls, and a
/// year later there is no evidence they were ever there. A certificate is the
/// cheapest possible fix for that and the one with the most obvious value to
/// the person holding it — which is why it is worth more than its two days of
/// work suggests.
///
/// Every field is a fact already in the database. Nothing here is entered by
/// hand, so a certificate cannot claim a result the fixtures do not support.
class Certificate {
  const Certificate({
    required this.recipientName,
    required this.title,
    required this.eventName,
    required this.tournamentName,
    required this.organizerName,
    required this.sportName,
    required this.date,
    this.categoryLabel,
    this.venueName,
    this.orgId,
    this.tournamentId,
    this.compId,
    this.entrantId,
  });

  final String recipientName;
  final CertificateTitle title;
  final String eventName;
  final String tournamentName;

  /// The club or association that ran it — the body whose word this is.
  final String organizerName;

  final String sportName;
  final DateTime date;
  final String? categoryLabel;
  final String? venueName;

  // --- Verification -------------------------------------------------------
  //
  // ## Why a certificate needs to be checkable, and why it is not a record
  //
  // SRS §27.4 asks for an embedded QR and a public verification URL, and the
  // pitch the whole feature rests on is "verifiable proof of achievements for
  // a career resume". Without it this is a PNG, and a PNG is something anybody
  // can produce in an image editor with a different name on it — which makes
  // the resume claim worth nothing and is worse than handing out nothing,
  // because it looks like evidence.
  //
  // The obvious implementation is a `certificates/{id}` collection written by
  // a function. That is not what this does, and the reason is in this class's
  // own doc comment: every field here is already a fact in the database. A
  // written record would be a SECOND copy of those facts, which can disagree
  // with the fixtures it came from, and which somebody then has to keep in
  // step when a result is corrected or a protest is upheld.
  //
  // So verification RE-DERIVES instead. The three ids below are enough to
  // recompute the award from the same public documents `CertificatesScreen`
  // reads — `RankingPoints.award` over the event's own fixtures — and the
  // verify page either produces the identical certificate or says there is no
  // such award. A forged certificate fails because the fixtures do not support
  // it; a corrected result changes what verifies, which is right, because the
  // certificate was always a statement about the result and not about itself.
  //
  // Nullable because a certificate rendered for preview inside the app already
  // knows its own context and needs no code on it. Only the ones handed out
  // carry them.
  final String? orgId;

  /// The tournament the event sat in.
  ///
  /// Part of the identity rather than looked up from the competition, because
  /// the award's weighting comes from the tournament's grade — so a verifier
  /// that had to discover it would be re-deriving the award from a document it
  /// guessed at. Certificates are only ever issued from a tournament's own
  /// screen, so this is always known at the point one is made.
  final String? tournamentId;

  final String? compId;

  /// The entrant this was awarded to — a uid for an individual event, a team
  /// id for a team one. The same id `RankingPoints.award` returns, so the
  /// verify page looks for exactly what the issuing screen found.
  final String? entrantId;

  /// Whether this certificate can be checked by somebody holding it.
  bool get isVerifiable =>
      orgId != null &&
      tournamentId != null &&
      compId != null &&
      entrantId != null;

  /// The path a verifier opens. Null when the certificate carries no identity.
  ///
  /// Deliberately the three raw ids rather than an opaque token. A token needs
  /// a lookup table, which is the second copy of the facts this avoids; and an
  /// id a verifier can read is an id they can check against the event page
  /// beside it.
  String? get verifyPath => isVerifiable
      ? '/verify/$orgId/$tournamentId/$compId/$entrantId'
      : null;

  /// The full URL, which is what a QR code on a printed certificate carries.
  String? get verifyUrl =>
      verifyPath == null ? null : 'https://playsphere-os.web.app$verifyPath';

  /// A short code for a human to read out or type, derived from the same ids.
  ///
  /// Not a secret and not a checksum anybody relies on — the URL is the
  /// mechanism. This exists because a certificate is a piece of paper handed
  /// across a table, and "quote me the code at the bottom" is how somebody
  /// with a phone and no scanner checks one.
  String? get verifyCode {
    if (!isVerifiable) return null;
    // FNV-1a over the three ids. Short, stable, and no dependency — a
    // cryptographic digest would suggest the code is doing security work that
    // the URL is actually doing.
    var hash = 0x811c9dc5;
    for (final unit in '$orgId/$tournamentId/$compId/$entrantId'.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    // Crockford-ish alphabet: no I, L, O or U, so a code read off paper
    // cannot be mistyped into a different valid-looking one.
    const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
    final out = StringBuffer('PS-');
    for (var i = 0; i < 6; i++) {
      out.write(alphabet[(hash >> (i * 5)) & 0x1F]);
    }
    return out.toString();
  }

  /// "U-17 Boys Singles · Badminton", or just the event where no category was
  /// set. What the certificate is actually *for*, on one line.
  String get eventLine {
    final parts = [
      if (categoryLabel != null && categoryLabel != 'Open') categoryLabel!,
      eventName,
    ];
    return parts.join(' · ');
  }

  /// "for finishing as Runner-up in" — the sentence the title sits inside.
  ///
  /// A champion's certificate should not read like a participation one, and a
  /// participation certificate should not pretend to be a placing.
  String get citation => switch (title) {
        CertificateTitle.champion => 'awarded to',
        CertificateTitle.runnerUp ||
        CertificateTitle.semiFinalist ||
        CertificateTitle.quarterFinalist =>
          'awarded to',
        CertificateTitle.participation => 'presented to',
      };

  String get achievement => switch (title) {
        CertificateTitle.champion => 'for winning',
        CertificateTitle.runnerUp => 'for finishing runner-up in',
        CertificateTitle.semiFinalist => 'for reaching the semi-finals of',
        CertificateTitle.quarterFinalist =>
          'for reaching the quarter-finals of',
        CertificateTitle.participation => 'for taking part in',
      };

  /// A stable, human file name — the thing that ends up in somebody's
  /// downloads folder and has to still make sense there in a year.
  String get fileName {
    final safe = '${recipientName}_${eventName}_$tournamentName'
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return '$safe.png';
  }

  static String formatDate(DateTime d) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}
