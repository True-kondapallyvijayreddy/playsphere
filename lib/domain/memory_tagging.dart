import '../core/models/fixture.dart';

/// One person a match photo can be tagged with.
class TaggablePerson {
  const TaggablePerson({required this.uid, required this.name, this.role});

  final String uid;
  final String name;

  /// Set for officials — `main_umpire`, `referee`. Null for players.
  ///
  /// Carried so a chip can read "Anand R · Main umpire" rather than putting
  /// the umpire in a list that otherwise reads as a team sheet.
  final String? role;

  bool get isOfficial => role != null;

  /// "Anand R · Main umpire".
  String get label => role == null ? name : '$name · ${humanRole(role!)}';

  static String humanRole(String role) {
    if (role.isEmpty) return role;
    final spaced = role.replaceAll('_', ' ');
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  @override
  bool operator ==(Object other) =>
      other is TaggablePerson &&
      other.uid == uid &&
      other.name == name &&
      other.role == role;

  @override
  int get hashCode => Object.hash(uid, name, role);

  @override
  String toString() => 'TaggablePerson($uid, $label)';
}

/// Who a memory from a match may be tagged with, and who it starts tagged
/// with.
///
/// ## Why this is not just the line-ups
///
/// A memory is what turns a pile of club photos into a *player's* career, and
/// the connection is `taggedUids`. Two things were wrong with how that list
/// was built (Bug #3):
///
/// - **Officials were not offered at all.** Only line-up entries were listed,
///   so an umpire who stood for an entire tournament could not be tagged in a
///   single photo of it. They were at the match; the record should say so.
/// - **Nothing was pre-selected.** An uploader standing on a ground was not
///   going to tap twenty-two chips, so memories were saved with an empty tag
///   list and reached nobody's profile. The default has to be the common
///   case.
///
/// Everyone offered was at the match. Nobody else is ever offered, so a tag
/// cannot put a stranger's face on someone's profile.
class MemoryTagging {
  const MemoryTagging._();

  /// The rules cap `taggedUids` at 30 so one upload cannot tag a whole
  /// district (`firestore.rules`, memories create/update). Auto-selection has
  /// to respect the same ceiling or the write is rejected *after* the bytes
  /// have already been uploaded.
  static const int maxTags = 30;

  /// Everyone at [fixture] who has an account, in a stable order: side A,
  /// side B, then officials.
  ///
  /// Guests recorded by name alone are skipped — there is no profile for the
  /// memory to land on. Anyone appearing twice (a playing captain also listed
  /// as an official) appears once, as a player.
  static List<TaggablePerson> participantsOf(Fixture fixture) {
    final seen = <String>{};
    return [
      for (final p in [...fixture.lineupA, ...fixture.lineupB])
        if (p.uid != null && p.uid!.isNotEmpty && seen.add(p.uid!))
          TaggablePerson(uid: p.uid!, name: p.name),
      for (final o in fixture.officials)
        if (o.uid.isNotEmpty && seen.add(o.uid))
          TaggablePerson(uid: o.uid, name: o.name, role: o.role),
    ];
  }

  /// The tag set a new memory starts with: everyone, capped at [maxTags].
  ///
  /// A match with more than thirty registered participants is a squad list
  /// rather than a photo; the uploader adjusts from there.
  static Set<String> defaultTagsFor(Fixture fixture) => {
        for (final p in participantsOf(fixture).take(maxTags)) p.uid,
      };
}
