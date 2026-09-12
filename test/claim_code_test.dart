import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/claim_code.dart';

void main() {
  group('ClaimCode', () {
    // The exact shape the `claimCodes` create rule in firestore.rules accepts.
    // A generated code that failed it would make every guardian's "Get code"
    // tap end in "Could not generate a code right now".
    final ruleShape = RegExp(r'^[0-9ABCDEFGHJKMNPQRSTVWXYZ]{12}$');

    test('generates twelve characters the rules will accept', () {
      for (var i = 0; i < 500; i++) {
        expect(ClaimCode.generate(), matches(ruleShape));
      }
    });

    test('forgives case, dashes and spaces', () {
      expect(ClaimCode.normalize(' k7m2-q4xp-z9ab '), 'K7M2Q4XPZ9AB');
      expect(ClaimCode.normalize('K7M2 Q4XP Z9AB'), 'K7M2Q4XPZ9AB');
    });

    test('reads O as zero and I or L as one', () {
      expect(ClaimCode.normalize('O0I1-L0O1-ABCD'), '00111001ABCD');
    });

    test('refuses the old six-digit codes and any other length', () {
      expect(ClaimCode.normalize('482913'), isNull);
      expect(ClaimCode.normalize('K7M2Q4XPZ9A'), isNull);
      expect(ClaimCode.normalize('K7M2Q4XPZ9ABC'), isNull);
    });

    test('refuses U, which the alphabet leaves out', () {
      expect(ClaimCode.normalize('UUUU-UUUU-UUUU'), isNull);
    });

    test('formats into groups of four for reading aloud', () {
      expect(ClaimCode.format('K7M2Q4XPZ9AB'), 'K7M2-Q4XP-Z9AB');
    });

    test('a formatted code normalizes back to itself', () {
      for (var i = 0; i < 100; i++) {
        final code = ClaimCode.generate();
        expect(ClaimCode.normalize(ClaimCode.format(code)), code);
      }
    });
  });
}
