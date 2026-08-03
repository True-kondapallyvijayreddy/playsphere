import 'dart:math';

/// The public player identifier — `PSOS-4K7M2`.
///
/// A Firebase uid is 28 characters of base64. Nobody reads one out at a
/// ground, writes one on a team sheet, or types one into a squad list. This
/// is the identifier a person actually gives somebody, and it is what lets a
/// captain add a borrowed player from another club to a match with their real
/// account attached — so the runs land on that player's own career record
/// instead of on a guest with the same name.
class PlayerCode {
  const PlayerCode._();

  static const prefix = 'PSOS';

  /// Crockford's base32, minus the letters that are read wrong.
  ///
  /// I, L and O are gone because they are indistinguishable from 1 and 0 in
  /// every font a village club will ever see this in, and U is gone because
  /// its absence stops the generator ever spelling an obscenity. The set is
  /// what makes a code safe to dictate over a phone, which is the only reason
  /// this exists rather than showing people a uid.
  static const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  /// Characters after the prefix. Five gives 32^5 ≈ 33.5 million codes; the
  /// reservation document makes collisions an inconvenience rather than a
  /// correctness problem, so this is sized for readability, not for birthday
  /// bounds.
  static const length = 5;

  static final _random = Random.secure();

  /// A fresh candidate. NOT guaranteed unique on its own — uniqueness comes
  /// from claiming `playerCodes/{code}` with a create, which fails if the
  /// document already exists. See `UserRepository.ensureCode`.
  static String generate() {
    final buffer = StringBuffer(prefix)..write('-');
    for (var i = 0; i < length; i++) {
      buffer.write(alphabet[_random.nextInt(alphabet.length)]);
    }
    return buffer.toString();
  }

  /// Turns what somebody typed into what is stored, or null if it could not
  /// be one of ours.
  ///
  /// Deliberately forgiving about everything except the characters: people
  /// type `psos 4k7m2`, `PSOS4K7M2`, and paste it with a trailing space. The
  /// two substitutions are the errors the alphabet was chosen to avoid making
  /// possible in the first place — somebody reading a code aloud says "oh"
  /// for zero and "eye" for one, and the listener types the letter.
  static String? normalize(String input) {
    var s = input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (s.startsWith(prefix)) s = s.substring(prefix.length);
    if (s.length != length) return null;

    s = s
        .replaceAll('O', '0')
        .replaceAll('I', '1')
        .replaceAll('L', '1');

    for (final ch in s.split('')) {
      if (!alphabet.contains(ch)) return null;
    }
    return '$prefix-$s';
  }

  static bool isValid(String input) => normalize(input) != null;
}
