import 'dart:math';

import 'player_code.dart';

/// The one-time code a guardian reads out to hand a managed child's profile
/// onto the child's own phone — `K7M2-Q4XP-Z9AB`.
///
/// ## Why twelve characters and not six digits
///
/// It used to be six digits. `redeemClaimCode` (functions/family.js) has to
/// be callable signed out — the child has no session yet — and a hit returns
/// a sign-in token for the child's account. 900,000 codes is a sweep a script
/// finishes well inside a code's 30-minute life. Twelve characters of
/// [PlayerCode.alphabet] is about 60 bits, which no request rate that
/// function can serve comes anywhere near. `firestore.rules` refuses any
/// other shape on `claimCodes`, so no build can mint a weak one.
///
/// The same alphabet as [PlayerCode] for the same reason: it is read aloud
/// across a room, so the letters that are heard wrong are not in it.
///
/// Stored and sent without dashes; [format] adds them for reading.
class ClaimCode {
  const ClaimCode._();

  static const length = 12;

  static const _groupSize = 4;

  static final _random = Random.secure();

  /// A fresh candidate. Uniqueness comes from creating `claimCodes/{code}`,
  /// which fails if the document already exists — see
  /// `UserRepository.createClaimCode`.
  static String generate() {
    const alphabet = PlayerCode.alphabet;
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.write(alphabet[_random.nextInt(alphabet.length)]);
    }
    return buffer.toString();
  }

  /// What somebody typed, as stored — or null if it cannot be a claim code.
  ///
  /// Forgiving in the same ways as [PlayerCode.normalize]: case, spaces and
  /// dashes, and "oh" or "eye" heard for zero or one. Mirrored by
  /// `normalizeClaimCode` in functions/family.js.
  static String? normalize(String input) {
    final s = input
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '')
        .replaceAll('O', '0')
        .replaceAll('I', '1')
        .replaceAll('L', '1');
    if (s.length != length) return null;
    for (final ch in s.split('')) {
      if (!PlayerCode.alphabet.contains(ch)) return null;
    }
    return s;
  }

  /// `K7M2Q4XPZ9AB` → `K7M2-Q4XP-Z9AB`.
  static String format(String code) {
    final groups = <String>[];
    for (var i = 0; i < code.length; i += _groupSize) {
      groups.add(code.substring(i, min(i + _groupSize, code.length)));
    }
    return groups.join('-');
  }
}
