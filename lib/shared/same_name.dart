/// Telling two people with the same name apart.
///
/// ## Why a list has to do this at all
///
/// Real rosters contain repeats. A school has two students called the same
/// thing, a family runs three accounts, and a test club had two members both
/// named "vijayreddy kondapally" — identical rows in the Members list and
/// identical rows in the team picker, with nothing on either to say which was
/// which. Picking one for a squad was a guess, and the wrong guess is somebody
/// else's match record.
///
/// ## Why a tag and not the player code
///
/// The player code (`PSOS-5NGMR`) is the right thing to show, and it lives on
/// the user document — which a roster does not read: a membership carries the
/// name and photo it was written with, and one document read per row would
/// turn a four-hundred-member roster into four hundred reads to render a list
/// nobody has scrolled yet. The tag is derived from the account id already on
/// the row, so it costs nothing, is stable for the life of the account, and is
/// the same four characters everywhere the person appears.
///
/// It is shown ONLY where a name actually repeats. A tag beside every name in
/// a club where nobody shares one is noise that makes the roster harder to
/// read, not easier.
library;

/// The display names in [names] that more than one person carries.
///
/// Compared case- and space-insensitively: "Priya Reddy" and "priya  reddy"
/// are the same name to everyone reading the list, so they are the same name
/// here too.
Set<String> repeatedNames(Iterable<String> names) {
  final seen = <String, int>{};
  for (final name in names) {
    final key = normalizeName(name);
    if (key.isEmpty) continue;
    seen[key] = (seen[key] ?? 0) + 1;
  }
  return {
    for (final e in seen.entries)
      if (e.value > 1) e.key,
  };
}

/// The comparison form of a display name — lowercase, with runs of whitespace
/// collapsed.
String normalizeName(String name) =>
    name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Whether [name] needs disambiguating within a list whose repeats are
/// [repeats] (from [repeatedNames]).
bool needsTag(String name, Set<String> repeats) =>
    repeats.contains(normalizeName(name));

/// A short, stable label for one account: the first four characters of its id,
/// uppercased, as `#A4F2`.
///
/// Not a secret and not an identifier anybody types — a uid is already on
/// every roster row the client can read, and four characters is enough to tell
/// two rows apart while staying short enough to sit inside a list row.
String accountTag(String uid) {
  final clean = uid.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  if (clean.isEmpty) return '';
  final take = clean.length < 4 ? clean.length : 4;
  return '#${clean.substring(0, take).toUpperCase()}';
}

/// [name], with an account tag appended only when this list holds somebody
/// else by the same name.
String nameWithTag(String name, String uid, Set<String> repeats) =>
    needsTag(name, repeats) ? '$name ${accountTag(uid)}' : name;
