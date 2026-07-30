import 'dart:math';
import 'dart:typed_data';

/// Client-generated UUIDv7 identifiers (RFC 9562), used as the durable
/// idempotency key for every locally-originated record — sync queue entries,
/// match events — per CLAUDE.md §4 ("Client generates UUIDv7 for every
/// record") and §12.3 ("Idempotent sync ingestion keyed on client UUIDv7").
///
/// ## Why not `Object.hashCode`
///
/// An idempotency key has to satisfy one property nothing else the client
/// already had lying around satisfies: it must stay byte-for-byte identical,
/// for the entire life of a record, across retries, across the process being
/// killed and restarted, and across the app being rebuilt from JIT (debug)
/// to AOT (release). `String.hashCode` fails that immediately — the Dart VM
/// does not promise the same string hashes to the same integer between runs,
/// and can legitimately differ between JIT and AOT for identical input. A
/// key derived from it can silently change identity for the *same* logical
/// record between "we wrote it" and "we checked whether the server has it",
/// which defeats the entire point of an idempotency key: a server (or a
/// local reconcile pass) comparing the new value against the one it already
/// saw would see a stranger, not a retry, and apply the delivery twice.
///
/// The fix is not a better hash function. It is generating a real id exactly
/// once, at the moment a record is created, and then carrying that value
/// everywhere the record goes — never recomputing it from the record's
/// content.
///
/// ## Why v7 specifically, not v4
///
/// A v4 (fully random) UUID would satisfy the stability requirement too, but
/// v7 additionally encodes a millisecond timestamp in its high bits, so ids
/// sort lexicographically in creation order. That is worth having here for
/// two independent reasons: the offline sync queue can order a fixture's
/// queued actions correctly by comparing ids as plain strings without a
/// separate column, and — per §4 of the architecture spec — a Postgres
/// primary key built from UUIDv7 does not fragment its B-tree index under
/// insert the way v4 does, which is why the spec mandates it for every
/// record server-side too, not just this queue.
class UuidV7 {
  UuidV7._();

  static final Random _random = Random.secure();

  /// Millisecond timestamp of the most recently generated id, and the
  /// 12-bit counter used to keep ids strictly increasing when several are
  /// generated inside the same millisecond — routine on a fast device, where
  /// a double-tap on the scoring pad can easily produce two events inside
  /// one millisecond. Both are process-local mutable state on purpose: a
  /// monotonic counter is meaningless unless it persists across calls within
  /// the process that is making them.
  static int _lastTimestampMs = 0;
  static int _counter = 0;

  /// Generates a new, time-ordered, RFC 9562-compliant UUIDv7 string in
  /// canonical `xxxxxxxx-xxxx-7xxx-yxxx-xxxxxxxxxxxx` form.
  static String generate() => _format(_generateBytes());

  static Uint8List _generateBytes() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    int timestampMs;
    int counter;

    if (nowMs > _lastTimestampMs) {
      // The clock has genuinely advanced since the last id: start a fresh
      // counter. Randomising its starting value (rather than zeroing it)
      // means an observer cannot infer how many ids this process has
      // generated so far this millisecond just by reading the counter.
      timestampMs = nowMs;
      counter = _random.nextInt(1 << 11);
    } else {
      // Either called again inside the same millisecond, or the wall clock
      // moved backwards (an NTP step, a DST edge case). Either way the only
      // safe way to keep ids strictly increasing is to stay on the last
      // timestamp used and advance the counter instead of trusting the
      // clock.
      timestampMs = _lastTimestampMs;
      counter = _counter + 1;
      if (counter > 0xFFF) {
        // Counter exhausted — 4096 ids inside a single millisecond, which
        // will not happen at scoring-tap rates but must still be handled
        // correctly: force the timestamp forward by one millisecond rather
        // than wrapping the counter, which would produce an id that sorts
        // *before* ones already handed out this millisecond.
        timestampMs += 1;
        counter = 0;
      }
    }
    _lastTimestampMs = timestampMs;
    _counter = counter;

    final bytes = Uint8List(16);
    // 48-bit big-endian Unix timestamp in milliseconds — octets 0-5.
    bytes[0] = (timestampMs >> 40) & 0xff;
    bytes[1] = (timestampMs >> 32) & 0xff;
    bytes[2] = (timestampMs >> 24) & 0xff;
    bytes[3] = (timestampMs >> 16) & 0xff;
    bytes[4] = (timestampMs >> 8) & 0xff;
    bytes[5] = timestampMs & 0xff;

    // Octet 6: 4-bit version (0111 = 7) then the top 4 bits of the 12-bit
    // counter, which doubles as the spec's `rand_a` field.
    bytes[6] = 0x70 | ((counter >> 8) & 0x0f);
    // Octet 7: the remaining 8 bits of the counter.
    bytes[7] = counter & 0xff;

    // Octet 8: 2-bit variant (10) then the top 6 bits of `rand_b`.
    bytes[8] = 0x80 | (_random.nextInt(1 << 6) & 0x3f);
    // Octets 9-15: the remaining 56 bits of `rand_b` — pure entropy with no
    // ordering role, just enough that two ids from the same millisecond
    // (after the counter above is accounted for) are astronomically
    // unlikely to collide even across different devices.
    for (var i = 9; i < 16; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }

  static const _hexChars = '0123456789abcdef';

  static String _format(Uint8List bytes) {
    final buffer = StringBuffer();
    for (var i = 0; i < bytes.length; i++) {
      if (i == 4 || i == 6 || i == 8 || i == 10) buffer.write('-');
      final byte = bytes[i];
      buffer.write(_hexChars[(byte >> 4) & 0x0f]);
      buffer.write(_hexChars[byte & 0x0f]);
    }
    return buffer.toString();
  }
}
