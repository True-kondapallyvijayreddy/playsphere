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
