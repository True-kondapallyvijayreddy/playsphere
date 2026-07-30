import 'firestore_codec.dart';

/// One assigned match official / umpire on a fixture.
class MatchOfficial {
  const MatchOfficial({
    required this.uid,
    required this.name,
    this.role = 'main_umpire',
    this.grantedScoringAccess = true,
  });

  final String uid;
  final String name;

  /// Official role — e.g. 'main_umpire', 'square_leg_umpire', 'referee', 'third_umpire', 'linesman'.
  final String role;

  final bool grantedScoringAccess;

  factory MatchOfficial.fromMap(Map<String, dynamic> d) => MatchOfficial(
        uid: Fs.str(d['uid']),
        name: Fs.str(d['name'], 'Official'),
        role: Fs.str(d['role'], 'main_umpire'),
        grantedScoringAccess: Fs.boolean(d['grantedScoringAccess'], true),
      );

  Map<String, Object?> toMap() => {
        'uid': uid,
        'name': name,
        'role': role,
        'grantedScoringAccess': grantedScoringAccess,
      };

  static List<MatchOfficial> listFrom(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((e) => MatchOfficial.fromMap(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  static List<Map<String, Object?>> listTo(List<MatchOfficial> officials) =>
      officials.map((o) => o.toMap()).toList();
}
