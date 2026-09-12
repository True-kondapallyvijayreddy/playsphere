import 'firestore_codec.dart';

/// One player's Arena record — `arenaStats/{uid}`.
///
/// ## Deliberately not a rating
///
/// Wins, draws and losses. No Glicko, no rating deviation, no ranking points,
/// and nothing here reaches `users/{uid}/ratings/*`, a career document or a
/// club standing. An Arena game is played on two phones with nobody watching;
/// treating its results as evidence about how well somebody plays would be
/// dishonest, and mixing them into the numbers that DO mean something would
/// quietly poison those too.
///
/// So this is a tally, and it says so wherever it is shown: something to
/// compare with the people in your club for the fun of it.
///
/// Written only by `functions/arena.js` from the finished match document. A
/// client cannot write it — see the `arenaStats` rule.
class ArenaStats {
  const ArenaStats({
    required this.uid,
    required this.displayName,
    this.photoUrl,
    this.played = 0,
    this.won = 0,
    this.drawn = 0,
    this.lost = 0,
    this.byGame = const {},
  });

  final String uid;
  final String displayName;
  final String? photoUrl;

  final int played;
  final int won;
  final int drawn;
  final int lost;

  /// Keyed by [ArenaGame.id]. Being the club's best at connect four and its
  /// worst at go is the interesting fact, and one combined number hides it.
  final Map<String, ArenaGameRecord> byGame;

  ArenaGameRecord get overall =>
      ArenaGameRecord(played: played, won: won, drawn: drawn, lost: lost);

  ArenaGameRecord recordFor(String? gameId) =>
      gameId == null ? overall : (byGame[gameId] ?? const ArenaGameRecord());

  static ArenaStats fromDoc(Map<String, dynamic> m, String id) {
    final raw = Fs.map(m['byGame']);
    return ArenaStats(
      uid: Fs.str(m['uid'], id),
      displayName: Fs.str(m['displayName'], 'Player'),
      photoUrl: Fs.strOrNull(m['photoUrl']),
      played: Fs.integer(m['played']),
      won: Fs.integer(m['won']),
      drawn: Fs.integer(m['drawn']),
      lost: Fs.integer(m['lost']),
      byGame: {
        for (final entry in raw.entries)
          entry.key: ArenaGameRecord.fromMap(Fs.map(entry.value)),
      },
    );
  }
}

class ArenaGameRecord {
  const ArenaGameRecord({
    this.played = 0,
    this.won = 0,
    this.drawn = 0,
    this.lost = 0,
  });

  final int played;
  final int won;
  final int drawn;
  final int lost;

  bool get isEmpty => played == 0;

  /// Win rate as a percentage, counting a draw as half — the convention every
  /// board game uses, and the only one under which a drawn game is not simply
  /// thrown away.
  double get score => played == 0 ? 0 : (won + drawn / 2) / played * 100;

  /// "4W · 1D · 2L".
  String get summary => '${won}W · ${drawn}D · ${lost}L';

  static ArenaGameRecord fromMap(Map<String, dynamic> m) => ArenaGameRecord(
        played: Fs.integer(m['played']),
        won: Fs.integer(m['won']),
        drawn: Fs.integer(m['drawn']),
        lost: Fs.integer(m['lost']),
      );
}
