import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/core/models/match_official.dart';
import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/domain/memory_tagging.dart';

/// Bug #3 — a memory should tag everyone who was at the match, umpires
/// included, so it lands on each of their profiles.
///
/// Two separate failures were behind the report. Officials were never offered
/// as tags at all, so an umpire could stand for a whole tournament and appear
/// in none of its photos. And nothing was pre-selected, so an uploader on a
/// ground would have had to tap twenty-two chips — which nobody did, so
/// memories were being saved tagging nobody and reaching no profile.
void main() {
  MatchPlayer player(String uid, String name) =>
      MatchPlayer(id: uid, uid: uid, name: name);

  MatchOfficial official(String uid, String name, {String role = 'main_umpire'}) =>
      MatchOfficial(uid: uid, name: name, role: role);

  Fixture fixture({
    List<MatchPlayer> a = const [],
    List<MatchPlayer> b = const [],
    List<MatchOfficial> officials = const [],
  }) =>
      Fixture(
        id: 'f1',
        orgId: 'o1',
        compId: 'c1',
        entrantAId: 'ea',
        entrantBId: 'eb',
        entrantAName: 'Nizampet',
        entrantBName: 'Kompally',
        status: FixtureStatus.completed,
        lineupA: a,
        lineupB: b,
        officials: officials,
      );

  group('who counts as a participant', () {
    test('both line-ups and the officials are offered', () {
      final f = fixture(
        a: [player('u1', 'Ravi'), player('u2', 'Kiran')],
        b: [player('u3', 'Anil')],
        officials: [official('u9', 'Anand R')],
      );

      expect(
        MemoryTagging.participantsOf(f).map((p) => p.uid),
        ['u1', 'u2', 'u3', 'u9'],
      );
    });

    test('an umpire is labelled as one rather than passing for a player', () {
      final f = fixture(
        a: [player('u1', 'Ravi')],
        officials: [official('u9', 'Anand R', role: 'square_leg_umpire')],
      );

      final people = MemoryTagging.participantsOf(f);
      expect(people.first.isOfficial, isFalse);
      expect(people.first.label, 'Ravi');
      expect(people.last.isOfficial, isTrue);
      expect(people.last.label, 'Anand R · Square leg umpire');
    });

    test('a guest with no account is not taggable', () {
      // There is no profile for the memory to land on, and inventing one
      // would be worse than omitting them.
      final f = fixture(
        a: [
          player('u1', 'Ravi'),
          const MatchPlayer(id: 'guest_1', name: 'Visitor'),
        ],
      );

      expect(MemoryTagging.participantsOf(f).map((p) => p.uid), ['u1']);
    });

    test('a playing captain who also officiates appears once', () {
      final f = fixture(
        a: [player('u1', 'Ravi')],
        officials: [official('u1', 'Ravi', role: 'referee')],
      );

      final people = MemoryTagging.participantsOf(f);
      expect(people.length, 1);
      // Listed as the player they were, not demoted to an official.
      expect(people.single.isOfficial, isFalse);
    });

    test('a match with nobody recorded offers nobody', () {
      expect(MemoryTagging.participantsOf(fixture()), isEmpty);
    });
  });

  group('what a new memory starts tagged with', () {
    test('everyone at the match, umpire included', () {
      // The heart of the bug: the umpire has to be in the DEFAULT set, not
      // merely available to somebody who thinks to add them.
      final f = fixture(
        a: [player('u1', 'Ravi'), player('u2', 'Kiran')],
        b: [player('u3', 'Anil')],
        officials: [official('u9', 'Anand R')],
      );

      expect(
        MemoryTagging.defaultTagsFor(f),
        {'u1', 'u2', 'u3', 'u9'},
      );
    });

    test('a full cricket match tags all twenty-two plus the officials', () {
      final f = fixture(
        a: [for (var i = 0; i < 11; i++) player('a$i', 'A$i')],
        b: [for (var i = 0; i < 11; i++) player('b$i', 'B$i')],
        officials: [official('ump1', 'Umpire One'), official('ump2', 'Umpire Two')],
      );

      final tags = MemoryTagging.defaultTagsFor(f);
      expect(tags.length, 24);
      expect(tags, contains('ump1'));
      expect(tags, contains('ump2'));
    });

    test('never exceeds the ceiling the rules enforce', () {
      // firestore.rules rejects taggedUids longer than 30. Going over would
      // fail the write AFTER the photo had already been uploaded, which is
      // the worst possible moment to find out.
      final f = fixture(
        a: [for (var i = 0; i < 40; i++) player('a$i', 'A$i')],
        officials: [official('ump1', 'Umpire One')],
      );

      expect(
        MemoryTagging.defaultTagsFor(f).length,
        MemoryTagging.maxTags,
      );
    });

    test('a match with no line-ups recorded tags nobody, and does not throw', () {
      expect(MemoryTagging.defaultTagsFor(fixture()), isEmpty);
    });
  });

  group('the fixture knows who was there', () {
    test('officials are kept out of playerUids', () {
      // playerUids is what firestore.rules checks before letting a scorer
      // write ratings and career stats onto a profile. An umpire did not
      // play, so a result must never accrue to them.
      final f = fixture(
        a: [player('u1', 'Ravi')],
        officials: [official('u9', 'Anand R')],
      );

      expect(f.playerUids, ['u1']);
      expect(f.officialUids, ['u9']);
      expect(f.participantUids, ['u1', 'u9']);
    });
  });
}
