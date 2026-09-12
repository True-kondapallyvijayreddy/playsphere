import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/domain/ranking/ranking_points.dart';
import 'package:playsphere/domain/tournament/certificate.dart';

/// A grassroots player finishes a tournament and receives nothing — the result
/// goes to a Telegram channel, the channel scrolls, and a year later there is
/// no evidence they were there. Every field on a certificate comes from the
/// fixtures, so one cannot claim a result the matches do not support.
void main() {
  _verificationTests();

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

/// Verification — the half that makes a certificate more than a picture.
///
/// SRS §27.4 asks for a public verification URL and none existed, which left
/// the "verifiable proof for a career resume" claim resting on a PNG that
/// anybody could reproduce with a different name on it.
void _verificationTests() {
  Certificate cert({
    String? orgId = 'org_1',
    String? tournamentId = 'trn_1',
    String? compId = 'comp_1',
    String? entrantId = 'uid_asha',
  }) =>
      Certificate(
        recipientName: 'Asha Reddy',
        title: CertificateTitle.champion,
        eventName: 'U-17 Girls Singles',
        tournamentName: 'Nalgonda District Championship',
        organizerName: 'Nalgonda DSA',
        sportName: 'Badminton',
        date: DateTime(2026, 8, 20),
        orgId: orgId,
        tournamentId: tournamentId,
        compId: compId,
        entrantId: entrantId,
      );

  group('verification', () {
    test('a certificate with a full identity is verifiable', () {
      final c = cert();
      expect(c.isVerifiable, isTrue);
      expect(c.verifyPath, '/verify/org_1/trn_1/comp_1/uid_asha');
      expect(c.verifyUrl,
          'https://playsphere-os.web.app/verify/org_1/trn_1/comp_1/uid_asha');
      expect(c.verifyCode, startsWith('PS-'));
      expect(c.verifyCode!.length, 9);
    });

    test('a preview certificate carries no code', () {
      // One rendered inside the app already knows its own context. Only the
      // ones handed out need to be checkable.
      for (final c in [
        cert(orgId: null),
        cert(tournamentId: null),
        cert(compId: null),
        cert(entrantId: null),
      ]) {
        expect(c.isVerifiable, isFalse);
        expect(c.verifyPath, isNull);
        expect(c.verifyUrl, isNull);
        expect(c.verifyCode, isNull);
      }
    });

    test('the code is stable for the same award', () {
      // It is printed on paper. A code that changed between two renders of the
      // same certificate would be worse than no code.
      expect(cert().verifyCode, cert().verifyCode);
    });

    test('the code depends on every part of the identity', () {
      // Two different awards must not read out the same code, or "quote me the
      // code" stops distinguishing anything.
      final codes = {
        cert().verifyCode,
        cert(orgId: 'org_2').verifyCode,
        cert(tournamentId: 'trn_2').verifyCode,
        cert(compId: 'comp_2').verifyCode,
        cert(entrantId: 'uid_bhavana').verifyCode,
      };
      expect(codes.length, 5, reason: 'the code collided across identities');
    });

    test('the code avoids the letters that get mistyped off paper', () {
      // Crockford-ish alphabet: no I, L, O or U, so a code read aloud cannot
      // be written down as a different valid-looking one.
      for (final id in ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']) {
        final code = cert(entrantId: id).verifyCode!.substring(3);
        expect(code, isNot(matches(RegExp('[ILOU]'))));
        expect(code, matches(RegExp(r'^[0-9ABCDEFGHJKMNPQRSTVWXYZ]{6}$')));
      }
    });

    test('the name on the certificate does not change the code', () {
      // Because the code identifies the AWARD, not the copy. A forger who
      // swaps the name keeps a code that resolves to the real winner, which is
      // exactly how the verify page catches them.
      final real = cert();
      final forged = Certificate(
        recipientName: 'Somebody Else',
        title: CertificateTitle.champion,
        eventName: real.eventName,
        tournamentName: real.tournamentName,
        organizerName: real.organizerName,
        sportName: real.sportName,
        date: real.date,
        orgId: real.orgId,
        tournamentId: real.tournamentId,
        compId: real.compId,
        entrantId: real.entrantId,
      );
      expect(forged.verifyCode, real.verifyCode);
      expect(forged.verifyPath, real.verifyPath);
    });
  });
}
