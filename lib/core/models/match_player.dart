import 'firestore_codec.dart';

/// One person taking part in a match.
///
/// Scoring engines record *who* did each thing, not just which side it
/// happened to. Without this there is no scorecard, no batting average, no
/// goal scorer, and nothing for a rating to be computed from — the entire
/// "lifelong portable player profile" rests on every event naming a person.
///
/// [uid] is nullable on purpose. Grassroots reality is that a team turns up
/// one player short and borrows someone who has never installed the app. That
/// player must still be scorable and still appear on the scorecard; they
/// simply accumulate no career stats until somebody claims them. Refusing to
/// score a match because a substitute has no account is how a product gets
/// abandoned at the ground.
class MatchPlayer {
  const MatchPlayer({
    required this.id,
    required this.name,
    this.uid,
    this.jerseyNumber,
    this.isCaptain = false,
    this.isKeeper = false,
  });

  /// Stable within the match. Equal to [uid] for registered players, and a
  /// generated local id for guests.
  final String id;

  final String name;

  /// The PlaySphere account, when this player has one. Null for a guest.
  /// Career statistics and ratings only accrue where this is set.
  final String? uid;

  final String? jerseyNumber;
  final bool isCaptain;

  /// Wicket-keeper in cricket, goalkeeper in football/hockey. Byes are charged
  /// against the keeper rather than the bowler, so the engine needs to know.
  final bool isKeeper;

  bool get isGuest => uid == null;

  factory MatchPlayer.fromMap(Map<String, dynamic> d) => MatchPlayer(
        id: Fs.str(d['id']),
        name: Fs.str(d['name'], 'Player'),
        uid: Fs.strOrNull(d['uid']),
        jerseyNumber: Fs.strOrNull(d['jerseyNumber']),
        isCaptain: Fs.boolean(d['isCaptain']),
        isKeeper: Fs.boolean(d['isKeeper']),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'uid': uid,
        'jerseyNumber': jerseyNumber,
        'isCaptain': isCaptain,
        'isKeeper': isKeeper,
      };

  static List<MatchPlayer> listFrom(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((e) => MatchPlayer.fromMap(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  static List<Map<String, Object?>> listTo(List<MatchPlayer> players) =>
      players.map((p) => p.toMap()).toList();
}
