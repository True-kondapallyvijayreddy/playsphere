import '../../core/models/enums.dart';
import '../../core/models/fixture.dart';

/// Which earlier matches feed their result into [target].
///
/// A knockout fixture never names its own feeders — the draw generator writes
/// the arrow the other way round, from the earlier match to the later one
/// ([Fixture.feedsWinnerToFixtureId] and [Fixture.feedsLoserToFixtureId]) so
/// that advancement is a single write on the match that just finished. That is
/// right for advancing and useless for asking "may this final be decided
/// yet", which is the question here, so the arrow is walked backwards.
Iterable<Fixture> feedersOf(Fixture target, Iterable<Fixture> all) =>
    all.where((f) =>
        f.id != target.id &&
        (f.feedsWinnerToFixtureId == target.id ||
            f.feedsLoserToFixtureId == target.id));

/// The feeders of [target] whose own result is frozen under protest.
///
/// ## Why a result downstream of a protest must wait
///
/// A protest freezes a result without finishing anything — see
/// `ScoringService.setFixtureOutcome`, which deliberately stamps no
/// `completedAt` on a disputed match. The bracket, though, had already moved:
/// the winner was advanced when the match first completed, and nothing then
/// stopped the next round being played, or awarded, on the strength of a
/// result that was still being argued about.
///
/// That is how a season reached a walkover final sitting over a disputed
/// semi-final. Upholding the protest reopens the semi, and if the other player
/// then wins it, the final that was already decided was played by the wrong
/// person — and there is no honest way back, because the final has a result
/// of its own and a champion has been published from it.
///
/// So the later match waits. The organizer decides the protest first, which is
/// a decision they already have on the Result screen, and only then does the
/// next round become playable. Marking the sport "Needs a ruling" made the
/// problem visible; this is what refuses it.
List<Fixture> protestedFeeders(Fixture target, Iterable<Fixture> all) => [
      for (final f in feedersOf(target, all))
        if (f.status == FixtureStatus.disputed) f,
    ];

/// What to tell whoever is holding the pen, naming the match they are waiting
/// on so they know where to go. Null when nothing is blocking.
String? feederProtestBlock(Fixture target, Iterable<Fixture> all) {
  final blocked = protestedFeeders(target, all);
  if (blocked.isEmpty) return null;
  final names = [
    for (final f in blocked) _name(f),
  ];
  final which = names.length == 1
      ? names.single
      : '${names.take(names.length - 1).join(', ')} and ${names.last}';
  return blocked.length == 1
      ? 'This match is waiting on a ruling. $which is under protest, and '
          'whoever comes through it may change. Decide that protest first.'
      : 'This match is waiting on a ruling. $which are under protest, and '
          'who comes through them may change. Decide those protests first.';
}

/// How a blocking match is named in that message: the round it belongs to and
/// the two sides, because "Match 3" alone tells an organizer looking at a
/// bracket nothing about which match they are being sent to.
String _name(Fixture f) {
  final a = f.displayNameA().trim();
  final b = f.displayNameB().trim();
  final sides = (a.isEmpty || b.isEmpty) ? '' : '$a v $b';
  final round = f.roundLabel?.trim() ?? '';
  if (round.isEmpty) return sides.isEmpty ? 'an earlier match' : sides;
  return sides.isEmpty ? round : '$round ($sides)';
}
