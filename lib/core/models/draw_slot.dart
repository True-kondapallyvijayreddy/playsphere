/// Where a fixture sits inside a draw, and who is going to fill it.
///
/// These two types used to live inside `FixtureGenerator`, which was fine
/// while they existed only for the few milliseconds between generating a draw
/// and writing it. They now have to survive in Firestore: without a persisted
/// [Bracket] nothing downstream can tell a group match from a knockout match,
/// and without a persisted [QualifierSource] nothing knows that a
/// quarter-final is waiting on the winner of Group B. Both are therefore wire
/// types, and they live here with the other wire enums rather than inside the
/// generator that happens to produce them.
library;

/// Which sub-bracket a fixture belongs to.
///
/// A plain knockout or a round robin only ever has one shape, so this used to
/// be implicit. Double elimination and groups+knockout both produce several
/// structurally different kinds of match in a single draw — a group-stage
/// match is not interchangeable with a losers-bracket match — and downstream
/// code (standings, the bracket UI, the scheduler) needs to know which is
/// which without guessing from round numbers.
enum Bracket {
  /// Single-elimination ladder — either the whole draw (plain knockout), or
  /// the qualifier stage of groups+knockout.
  knockout('knockout'),

  /// The undefeated side of a double-elimination draw.
  winners('winners'),

  /// The one-loss side of a double-elimination draw.
  losers('losers'),

  /// Winners-bracket champion vs. losers-bracket champion.
  grandFinal('grand_final'),

  /// Played only if the losers-bracket champion wins [grandFinal] — a
  /// double-elimination decider exists because a single loss must not be
  /// allowed to eliminate the side that came through undefeated.
  grandFinalReset('grand_final_reset'),

  /// Round robin within one group of a groups+knockout draw.
  group('group');

  const Bracket(this.wire);

  final String wire;

  /// Defaults to [knockout] rather than throwing, because every fixture
  /// written before this field existed has no `bracket` key at all, and a
  /// plain knockout is what those draws were.
  static Bracket fromWire(String? w) => Bracket.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => Bracket.knockout,
      );

  /// Whether this bracket's matches feed a league table. Only group matches
  /// do — a knockout match has no standings to contribute to.
  bool get hasTable => this == Bracket.group;
}

/// Identifies a not-yet-known knockout entrant by table position — "the
/// winner of Group B" — rather than by identity.
///
/// At draw time the group stage has not been played, so no real entrant
/// exists yet for a qualifier slot. This is what lets the knockout phase of a
/// groups+knockout draw be generated up front, in one pass, alongside the
/// groups: the bracket's *shape* (who plays whom, seeded so group-mates
/// cannot meet again immediately) is pure structure and does not depend on
/// results. Only the entrant identity does.
class QualifierSource {
  const QualifierSource({required this.groupId, required this.position});

  final String groupId;

  /// 1 = group winner, 2 = runner-up, and so on.
  final int position;

  /// `"A#1"`. A compact string rather than a nested map because this is read
  /// inside `firestore.rules`, where a scalar is far cheaper to validate than
  /// a map whose shape has to be checked field by field.
  String get wire => '$groupId#$position';

  static QualifierSource? fromWire(String? w) {
    if (w == null || w.isEmpty) return null;
    final parts = w.split('#');
    if (parts.length != 2) return null;
    final position = int.tryParse(parts[1]);
    if (position == null || parts[0].isEmpty) return null;
    return QualifierSource(groupId: parts[0], position: position);
  }

  /// "Group B winner" / "Group B 2nd" — what a spectator sees in an
  /// unresolved bracket slot, in place of "To be decided".
  String get label => switch (position) {
        1 => 'Group $groupId winner',
        2 => 'Group $groupId runner-up',
        _ => 'Group $groupId #$position',
      };

  @override
  String toString() => 'Group $groupId #$position';

  @override
  bool operator ==(Object other) =>
      other is QualifierSource &&
      other.groupId == groupId &&
      other.position == position;

  @override
  int get hashCode => Object.hash(groupId, position);
}
