import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/domain/draw/fixture_generator.dart';

/// The single-match format — the club's own internal game, and one player
/// against another.
///
/// These are the two facts the rest of the feature rests on: a single match
/// opens ready to play rather than as a draft, and it is never handed to the
/// draw generator. Both are easy to break by adding a format and forgetting
/// one of them, and both fail silently — the first as an event nobody can
/// start, the second as a duplicate fixture beside the real one.
void main() {
  Competition comp(CompetitionFormat format,
          {List<String>? participantOrgIds}) =>
      Competition(
        id: 'c1',
        orgId: 'org1',
        name: 'Sunday internal',
        sportId: 'badminton',
        sportName: 'Badminton',
        archetype: CompetitionArchetype.versus,
        entrantType: EntrantType.individual,
        format: format,
        status: CompetitionStatus.draft,
        category: CompetitionCategory.presets().first,
        scoringPluginKey: 'set_based',
        participantOrgIds: participantOrgIds,
        createdBy: 'uid1',
      );

  group('single match opens ready to play', () {
    test('a single match is created in progress, not as a draft', () {
      final wire = comp(CompetitionFormat.singleMatch).toCreate();
      expect(wire['status'], 'in_progress');
    });

    test('every other format still starts as a draft', () {
      for (final f in CompetitionFormat.values) {
        if (f.isSingleMatch) continue;
        expect(
          comp(f).toCreate()['status'],
          'draft',
          reason: '${f.wire} must still be configured before entries open',
        );
      }
    });

    test('an inter-club match still starts scheduled', () {
      // The three starting states are mutually exclusive and the rules admit
      // exactly these three. A regression here denies the write outright.
      final wire = comp(
        CompetitionFormat.knockout,
        participantOrgIds: ['org1', 'org2'],
      ).toCreate();
      expect(wire['status'], 'scheduled');
    });

    test('the wire value is stable', () {
      // Written into every quick match ever created, and read by
      // `firestore.rules` to decide whether a member may open it. Changing it
      // silently locks members out of matches they already have.
      expect(CompetitionFormat.singleMatch.wire, 'single_match');
      expect(
        CompetitionFormat.fromWire('single_match'),
        CompetitionFormat.singleMatch,
      );
    });
  });

  group('single match is never drawn', () {
    test('the generator produces nothing for it', () {
      // The fixture is written alongside the competition in one batch. If the
      // generator also produced one, a quick match would show two fixtures
      // and the second would be unplayable.
      final planned = const FixtureGenerator().generate(
        format: CompetitionFormat.singleMatch,
        entrants: const [
          Entrant(
              id: 'a',
              displayName: 'Aarav',
              entrantType: EntrantType.individual),
          Entrant(
              id: 'b',
              displayName: 'Bhavya',
              entrantType: EntrantType.individual),
        ],
      );
      expect(planned, isEmpty);
    });

    test('the same two entrants in a knockout still produce a match', () {
      // Guards against the previous test passing for the wrong reason.
      final planned = const FixtureGenerator().generate(
        format: CompetitionFormat.knockout,
        entrants: const [
          Entrant(
              id: 'a',
              displayName: 'Aarav',
              entrantType: EntrantType.individual),
          Entrant(
              id: 'b',
              displayName: 'Bhavya',
              entrantType: EntrantType.individual),
        ],
      );
      expect(planned, hasLength(1));
    });
  });
}
