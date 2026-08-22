import 'package:shared_preferences/shared_preferences.dart';

import 'uuid_v7.dart';

/// A stable identifier for this installation of the app.
///
/// ## Why a device id exists at all
///
/// Two questions look the same and are not: "who is scoring this match" and
/// "which screen is the pen on". A uid answers the first. It cannot answer
/// the second, and the second is the one that decides whether a tap is the
/// authoritative record of a point or a duplicate of one already recorded on
/// a phone in somebody else's hand.
///
/// A scorer signed in on a phone and a tablet — or who reinstalled mid-season
/// and left the old install signed in — is one uid with two pads, and every
/// event either device writes is legitimate by uid. They still race for the
/// same sequence number, and the loser's action is discarded. Pinning the pen
/// to one *device* is what makes "only one person is scoring" true in the
/// only sense the scorer experiences it.
///
/// ## Why SharedPreferences and not a hardware id
///
/// Platform device identifiers need a plugin, differ per OS, are restricted
/// on iOS, and are exactly the kind of thing a privacy review asks about. A
/// random id minted on first launch is enough: the only thing it has to do is
/// stay the same on this install and differ from every other one. A reinstall
/// minting a fresh id is correct behaviour, not a bug — the app has genuinely
/// lost the local queue and the cache along with the id, so it *is* a new
/// device as far as scoring is concerned, and it has to reclaim the pen.
class DeviceId {
  DeviceId._();

  static const _key = 'playsphere_device_id_v1';

  /// Cached for the process, because this is read on every pad build and on
  /// every score write. `SharedPreferences` is itself in-memory after the
  /// first load, but the async hop is not free on a rebuild path.
  static String? _cached;

  /// The id for this install, minting one on first call.
  static Future<String> get(SharedPreferences prefs) async {
    final existing = _cached ?? prefs.getString(_key);
    if (existing != null && existing.isNotEmpty) return _cached = existing;
    final minted = UuidV7.generate();
    await prefs.setString(_key, minted);
    return _cached = minted;
  }

  /// The id if it has already been read this process, else null.
  ///
  /// For synchronous call sites — a `build` method deciding whether to show
  /// the pad or the live view — that must not await. The pad resolves the id
  /// once when it opens and holds it, so this is only null for the first
  /// frame, which renders as "checking" rather than as "not your device".
  static String? get cached => _cached;

  /// A device id for this process only, for when storage cannot be read.
  ///
  /// Stable within the run — the pad claims once and keeps matching — and
  /// deliberately not persisted, because the reason this is being called is
  /// that persisting did not work.
  static String session() => _cached ??= UuidV7.generate();

  /// Tests only.
  static void resetForTest() => _cached = null;
}
