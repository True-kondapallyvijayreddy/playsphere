import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/player_code.dart';

/// The public player identifier.
///
/// Two properties carry the whole feature: it must be safe to read aloud at a
/// ground, and it must round-trip whatever a person types back into the code
/// that was issued. A code that resolves to nobody because the reader said
/// "oh" and the typist wrote "O" is a code that gets abandoned for typing
/// somebody's name in as a guest — which is exactly the outcome the feature
/// exists to prevent, since a guest builds no career record.
void main() {
  group('generated codes', () {
    test('look like PSOS-XXXXX', () {
      for (var i = 0; i < 200; i++) {
        expect(PlayerCode.generate(), matches(RegExp(r'^PSOS-[0-9A-Z]{5}$')));
      }
    });

    test('never contain a character that is misread', () {
      // I, L, O and U are absent by construction: the first three are
      // indistinguishable from 1 and 0 in the fonts this will be read in, and
      // U's absence is what stops the generator spelling something obscene.
      for (var i = 0; i < 500; i++) {
        final body = PlayerCode.generate().substring(5);
        for (final banned in ['I', 'L', 'O', 'U']) {
          expect(body.contains(banned), isFalse,
              reason: '$body contains $banned');
        }
      }
    });

    test('every generated code normalizes back to itself', () {
      // The round trip is the property that matters. If normalize() rewrote a
      // character the generator can emit, a real player's code would resolve
      // to nobody.
      for (var i = 0; i < 500; i++) {
        final code = PlayerCode.generate();
        expect(PlayerCode.normalize(code), code);
      }
    });

    test('are not all the same', () {
      final seen = {for (var i = 0; i < 200; i++) PlayerCode.generate()};
      expect(seen.length, greaterThan(190));
    });
  });

  group('normalizing what somebody typed', () {
    test('accepts the forms people actually type', () {
      const canonical = 'PSOS-4K7M2';
      for (final typed in [
        'PSOS-4K7M2',
        'psos-4k7m2',
        'PSOS4K7M2',
        '  psos 4k7m2  ',
        '4K7M2',
        '4k7m2',
      ]) {
        expect(PlayerCode.normalize(typed), canonical, reason: typed);
      }
    });

    test('repairs the misreadings the alphabet was chosen to avoid', () {
      // Somebody reads "zero" aloud as "oh" and the listener types O. Since no
      // real code contains O, mapping it to 0 can only ever fix a mistake —
      // it can never turn one valid code into a different valid one.
      expect(PlayerCode.normalize('PSOS-4K7MO'), 'PSOS-4K7M0');
      expect(PlayerCode.normalize('PSOS-4K7MI'), 'PSOS-4K7M1');
      expect(PlayerCode.normalize('PSOS-4K7ML'), 'PSOS-4K7M1');
    });

    test('rejects anything that is not one of ours', () {
      for (final bad in [
        '',
        'PSOS-',
        'PSOS-123',        // too short
        'PSOS-1234567',    // too long
        'hello there',
        'PSOS-4K7MU',      // U is not in the alphabet
      ]) {
        expect(PlayerCode.normalize(bad), isNull, reason: bad);
        expect(PlayerCode.isValid(bad), isFalse, reason: bad);
      }
    });

    test('a rejected code is never silently turned into a valid one', () {
      // The lookup treats null as "no such player". If normalize invented a
      // code out of nonsense, a typo would resolve to a real stranger and put
      // them on somebody's team sheet.
      expect(PlayerCode.normalize('!!!!!'), isNull);
    });
  });
}
