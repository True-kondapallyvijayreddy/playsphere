import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/domain/ranking/ranking_points.dart';
import 'package:playsphere/domain/tournament/certificate.dart';

/// A grassroots player finishes a tournament and receives nothing — the result
/// goes to a Telegram channel, the channel scrolls, and a year later there is
/// no evidence they were there. Every field on a certificate comes from the
/// fixtures, so one cannot claim a result the matches do not support.
void main() {
  Certificate certificate({
    required CertificateTitle title,
    String name = 'Ravi Kumar',
    String? category = 'U-17 Boys',
  }) =>
      Certificate(
        recipientName: name,
        title: title,
        eventName: 'Singles',
        tournamentName: 'Hyderabad District Championship',
        organizerName: 'Kompally Sports Academy',
        sportName: 'Badminton',
        categoryLabel: category,
        date: DateTime(2026, 9, 13),
      );

  group('what a finish is worth on paper', () {
    test('the podium places get their own titles', () {
      expect(
        CertificateTitle.fromRound(FinishingRound.winner),
        CertificateTitle.champion,
      );
      expect(
        CertificateTitle.fromRound(FinishingRound.runnerUp),
        CertificateTitle.runnerUp,
      );
      expect(
        CertificateTitle.fromRound(FinishingRound.semiFinal),
        CertificateTitle.semiFinalist,
      );
    });

    test('an early exit reads as participation, never as "Last 32"', () {
      // A ranking table needs to separate a last-32 exit from a last-16 one.
      // A certificate does not, and one saying "Last 32" would be a worse
      // thing to hand somebody than one saying they took part.
      for (final round in [
        FinishingRound.lastSixteen,
        FinishingRound.lastThirtyTwo,
        FinishingRound.groupStage,
        FinishingRound.participated,
      ]) {
        expect(
          CertificateTitle.fromRound(round),
          CertificateTitle.participation,
          reason: round.wire,
        );
      }
    });

    test('only the podium counts as a placing', () {
      expect(CertificateTitle.champion.isPodium, isTrue);
      expect(CertificateTitle.semiFinalist.isPodium, isTrue);
      expect(CertificateTitle.quarterFinalist.isPodium, isFalse);
      expect(CertificateTitle.participation.isPodium, isFalse);
    });
  });

  group('the wording matches the award', () {
    test('a champion does not read like a participant', () {
      final champ = certificate(title: CertificateTitle.champion);
      final part = certificate(title: CertificateTitle.participation);
      expect(champ.achievement, 'for winning');
      expect(part.achievement, 'for taking part in');
      expect(champ.citation, isNot(part.citation));
    });

    test('every title has wording — none falls through to a blank', () {
      for (final t in CertificateTitle.values) {
        final c = certificate(title: t);
        expect(c.achievement, isNotEmpty, reason: t.wire);
        expect(c.citation, isNotEmpty, reason: t.wire);
      }
    });
  });

  group('what is printed', () {
    test('the category is named when it is not simply Open', () {
      expect(
        certificate(title: CertificateTitle.champion).eventLine,
        'U-17 Boys · Singles',
      );
    });

    test('an Open category is not printed as a qualifier', () {
      // "Open · Singles" reads as a category nobody entered.
      expect(
        certificate(title: CertificateTitle.champion, category: 'Open')
            .eventLine,
        'Singles',
      );
      expect(
        certificate(title: CertificateTitle.champion, category: null).eventLine,
        'Singles',
      );
    });

    test('the date is written out, never as digits alone', () {
      // A certificate that says 09/13/2026 is ambiguous outside one country.
      expect(Certificate.formatDate(DateTime(2026, 9, 13)), '13 September 2026');
    });
  });

  group('the file it becomes', () {
    test('the name still makes sense in a downloads folder a year later', () {
      final c = certificate(title: CertificateTitle.champion);
      expect(c.fileName, endsWith('.png'));
      expect(c.fileName, contains('Ravi_Kumar'));
      expect(c.fileName, contains('Hyderabad'));
    });

    test('punctuation and spacing cannot produce an unusable file name', () {
      final c = certificate(
        title: CertificateTitle.champion,
        name: 'M. S.  Dhoni / Jr.',
      );
      expect(RegExp(r'^[A-Za-z0-9_]+\.png$').hasMatch(c.fileName), isTrue,
          reason: c.fileName);
    });
  });
}
