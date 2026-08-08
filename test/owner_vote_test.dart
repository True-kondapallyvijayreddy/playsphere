import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/domain/governance/owner_vote.dart';

/// Feature #3 — a club may have several owners, and removing one takes two
/// thirds of the others.
///
/// The threshold is the whole feature. Get it one too high and a club can
/// never resolve a dispute; one too low and a bare majority ejects the rest,
/// which is the monopoly the feature exists to prevent, arrived at from the
/// other direction.
///
/// These numbers are also implemented a second time, in JavaScript, inside
/// `functions/index.js` — the client draws its progress bar from this and the
/// removal actually happens on that. They must not drift.
void main() {
  group('votes needed', () {
    test('a sole owner cannot be voted out by nobody', () {
      // Zero, not one: there is no electorate. `passes` treats this as never
      // passing rather than as "0 votes is enough", which would remove the
      // only owner the moment a motion existed.
      expect(OwnerVote.votesNeeded(1), 0);
      expect(OwnerVote.passes(votes: 0, ownerCount: 1), isFalse);
      expect(OwnerVote.passes(votes: 5, ownerCount: 1), isFalse);
    });

    test('two owners: either may remove the other, alone', () {
      // Deliberate. The alternative is a two-owner club with no way to resolve
      // anything, and the symmetry is the safeguard: whoever moves first can
      // be moved against on the same terms.
      expect(OwnerVote.votesNeeded(2), 1);
      expect(OwnerVote.passes(votes: 1, ownerCount: 2), isTrue);
    });

    test('three owners need both of the others — unanimous', () {
      expect(OwnerVote.votesNeeded(3), 2);
      expect(OwnerVote.passes(votes: 1, ownerCount: 3), isFalse);
      expect(OwnerVote.passes(votes: 2, ownerCount: 3), isTrue);
    });

    test('four owners need two of the three others', () {
      // ceil(2/3 × 3) = 2. A bare majority of the remainder, which at this
      // size is the same thing.
      expect(OwnerVote.votesNeeded(4), 2);
      expect(OwnerVote.passes(votes: 2, ownerCount: 4), isTrue);
    });

    test('the threshold is a ceiling, never a floor', () {
      // The property that matters at every size: two thirds ROUNDED UP, so a
      // block holding exactly one third can never carry a motion.
      for (var owners = 2; owners <= 30; owners++) {
        final electorate = owners - 1;
        final needed = OwnerVote.votesNeeded(owners);
        expect(
          needed * 3,
          greaterThanOrEqualTo(2 * electorate),
          reason: '$owners owners: $needed votes is under two thirds',
        );
        expect(
          (needed - 1) * 3,
          lessThan(2 * electorate),
          reason: '$owners owners: $needed votes is more than needed',
        );
      }
    });

    test('seven owners need four of the six others', () {
      expect(OwnerVote.votesNeeded(7), 4);
      expect(OwnerVote.passes(votes: 3, ownerCount: 7), isFalse);
      expect(OwnerVote.passes(votes: 4, ownerCount: 7), isTrue);
    });
  });

  group('resigning', () {
    test('the last owner may not step down', () {
      // A club with no owner has nobody who can appoint one, so it would be
      // permanently un-administrable.
      expect(OwnerVote.canResign(1), isFalse);
    });

    test('any owner with a co-owner may step down', () {
      expect(OwnerVote.canResign(2), isTrue);
      expect(OwnerVote.canResign(9), isTrue);
    });
  });
}
