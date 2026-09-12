import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/app_user.dart';
import 'package:playsphere/core/models/billing.dart';

/// The constants that exist in two or three languages at once.
///
/// ## Why these need a test rather than a comment
///
/// Four facts in this product are written down more than once, in files that
/// cannot import each other — Dart, JavaScript and the Firestore rules DSL.
/// Every one of them carries a comment saying "keep these in sync by hand",
/// and a comment is not a mechanism. The review found four such mirrors and
/// exactly one of them (`TRAIL_LENGTH`) had a test.
///
/// The sharpest is the launch offer. `Pricing.introOfferActive`,
/// `INTRO_OFFER_ACTIVE` in razorpay.js and `introOfferActive()` in
/// firestore.rules all say plans are free. The day that changes, all three have
/// to change together: leave the rules one `true` and the database still
/// accepts any client writing itself Premium against a ₹0 ledger row, on the
/// day real cards start being charged. The rules file says so in its own
/// comment. Nothing checked it.
///
/// Grepping source from a test is ugly and it is the only tool available
/// across three languages. The alternative is codegen, which is a build step
/// and a generator to maintain for four constants.
void main() {
  String read(String path) => File(path).readAsStringSync();

  group('the launch offer', () {
    test('all three mirrors agree', () {
      final rules = read('firestore.rules');
      final razorpay = read('functions/razorpay.js');

      // The rules function is a literal `return true;`/`return false;`.
      final rulesMatch = RegExp(
        r'function introOfferActive\(\)\s*\{\s*return\s+(true|false);',
      ).firstMatch(rules);
      expect(rulesMatch, isNotNull,
          reason: 'introOfferActive() is gone from firestore.rules, or no '
              'longer a plain boolean. If the offer is now decided some other '
              'way, this test has to learn how.');
      final rulesValue = rulesMatch!.group(1) == 'true';

      final jsMatch = RegExp(
        r'const INTRO_OFFER_ACTIVE\s*=\s*(true|false);',
      ).firstMatch(razorpay);
      expect(jsMatch, isNotNull);
      final jsValue = jsMatch!.group(1) == 'true';

      expect(
        [Pricing.introOfferActive, jsValue, rulesValue],
        everyElement(equals(Pricing.introOfferActive)),
        reason: 'The launch-offer flag disagrees across its three mirrors: '
            'billing.dart=${Pricing.introOfferActive}, '
            'razorpay.js=$jsValue, firestore.rules=$rulesValue. '
            'While the rules one is true, any client can write itself a paid '
            'plan against a zero-amount ledger row.',
      );
    });
  });

  group('the price list', () {
    test('the server charges what the app advertises', () {
      // `PRICE_TABLE` in razorpay.js is what a card is actually debited. A
      // drift here is either an undercharge or a customer seeing one price and
      // paying another.
      final razorpay = read('functions/razorpay.js');
      final club = RegExp(r'org_plan:\s*\{\s*club:\s*([\d_]+)\s*\}')
          .firstMatch(razorpay)
          ?.group(1)
          ?.replaceAll('_', '');
      final premium = RegExp(r'member_plan:\s*\{\s*premium:\s*([\d_]+)\s*\}')
          .firstMatch(razorpay)
          ?.group(1)
          ?.replaceAll('_', '');

      expect(club, isNotNull, reason: 'PRICE_TABLE lost its org_plan row');
      expect(premium, isNotNull, reason: 'PRICE_TABLE lost its member_plan row');
      expect(int.parse(club!), Pricing.clubYearlyPaise);
      expect(int.parse(premium!), Pricing.premiumYearlyPaise);
    });

    test('the agreed prices are the ones in the code', () {
      // Stated as the actual figures rather than only as a cross-check, so a
      // change to BOTH mirrors at once still has to be a deliberate one.
      // ₹999 a year for a club, ₹99 a year for an individual.
      expect(Pricing.clubYearlyPaise, 99900);
      expect(Pricing.premiumYearlyPaise, 9900);
    });

    test('nothing is charged while the offer is on', () {
      // The offer's whole meaning, asserted rather than assumed.
      if (Pricing.introOfferActive) {
        expect(Pricing.memberPricePaise(MemberPlan.premium), 0);
        expect(Pricing.orgPricePaise(OrgPlan.club), 0);
      } else {
        expect(Pricing.memberPricePaise(MemberPlan.premium),
            Pricing.premiumYearlyPaise);
        expect(Pricing.orgPricePaise(OrgPlan.club), Pricing.clubYearlyPaise);
      }
    });
  });

  group('the rating trail', () {
    test('the server keeps as many snapshots as the client reads', () {
      // A server keeping fewer than the client's window expects silently
      // shortens every trend it can measure, with no error anywhere. This
      // mirror already had a test; it is repeated here so all four live in one
      // place and none can be the one nobody thought about.
      final index = read('functions/index.js');
      final serverLength = RegExp(r'const TRAIL_LENGTH = (\d+);')
          .firstMatch(index)
          ?.group(1);
      expect(serverLength, isNotNull);

      final trail = read('lib/domain/scout/talent_trend.dart');
      final clientLength =
          RegExp(r'maxLength = (\d+)').firstMatch(trail)?.group(1);
      expect(clientLength, isNotNull,
          reason: 'RatingTrail.maxLength is gone or renamed');
      expect(serverLength, clientLength);
    });
  });

  group('community visibility depth', () {
    test('the rule checks as many clubs as the model claims', () {
      // `sharesActiveOrgWith` unrolls a fixed number of `isActive()` calls
      // because rules cannot loop and a single-document read may make only ten
      // document lookups. The number is invisible from Dart unless it is
      // asserted, and the consequence of it drifting is silent: a club-mate's
      // profile simply does not open, with no error anywhere.
      final rules = read('firestore.rules');
      final fn = RegExp(
        r'function sharesActiveOrgWith\(data\) \{(.*?)\n    \}',
        dotAll: true,
      ).firstMatch(rules);
      expect(fn, isNotNull, reason: 'sharesActiveOrgWith is gone or renamed');

      final checks = RegExp(r'isActive\(data\.orgIds\[\d+\]\)')
          .allMatches(fn!.group(1)!)
          .length;
      expect(
        checks,
        AppUser.communityVisibilityDepth,
        reason: 'the rule checks $checks clubs but '
            'AppUser.communityVisibilityDepth says '
            '${AppUser.communityVisibilityDepth}',
      );
    });
  });

  group('critical notification types', () {
    test('every type the server pushes immediately is critical in Dart too', () {
      // `CRITICAL_NOTIFICATION_TYPES` decides what buzzes a phone now versus
      // what waits for the digest. A type marked critical in Dart and absent
      // from the server set is a reminder that silently arrives hours late —
      // which for "your match starts in an hour" is the difference between
      // turning up and not.
      final index = read('functions/index.js');
      final block = RegExp(
        r'const CRITICAL_NOTIFICATION_TYPES = new Set\(\[(.*?)\]\)',
        dotAll: true,
      ).firstMatch(index);
      expect(block, isNotNull);
      final serverTypes = RegExp(r"'([a-z_]+)'")
          .allMatches(block!.group(1)!)
          .map((m) => m.group(1)!)
          .toSet();

      final model = read('lib/core/notifications/notification_model.dart');
      // Wire values carrying `isCritical: true` in the Dart enum.
      final dartCritical = <String>{};
      for (final m in RegExp(
        r"\(\s*'([a-z_]+)'[^)]*?isCritical:\s*true",
        dotAll: true,
      ).allMatches(model)) {
        dartCritical.add(m.group(1)!);
      }

      expect(dartCritical, isNotEmpty,
          reason: 'no critical types found in the Dart enum — the pattern this '
              'test greps for has changed');
      expect(
        dartCritical.difference(serverTypes),
        isEmpty,
        reason: 'these types are critical in Dart but are routed through the '
            'digest by the server, so they arrive late',
      );
    });
  });
}
