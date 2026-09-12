import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/domain/club_events.dart';

/// Sorting a club's events into the four shapes it runs them in.
///
/// The classification is read back off the stored competition — nothing
/// writes an `EventType` onto it — so these tests pin the readings that are
/// easy to get backwards, above all the multi-sport challenge, which carries
/// a `tournamentId` exactly as a season does and would otherwise file itself
/// under "Seasons".
void main() {
  Competition comp(
    String id, {
    String? tournamentId,
    CompetitionFormat format = CompetitionFormat.knockout,
    CompetitionStatus status = CompetitionStatus.registrationOpen,
    List<String>? participantOrgIds,
    DateTime? registrationClosesAt,
  }) =>
      Competition(
        id: id,
        orgId: 'org1',
        name: 'Event $id',
        sportId: 'badminton',
        sportName: 'Badminton',
        archetype: CompetitionArchetype.versus,
        entrantType: EntrantType.individual,
        format: format,
        status: status,
        category: const CompetitionCategory(label: 'Open'),
        scoringPluginKey: 'goal_based',
        tournamentId: tournamentId,
        participantOrgIds: participantOrgIds,
        registrationClosesAt: registrationClosesAt,
      );

  group('what kind of event this is', () {
    test('a plain competition is a tournament', () {
      expect(ClubEventKind.of(comp('c1')), ClubEventKind.tournament);
    });

    test('a competition under a tournament id is part of a season', () {
      expect(
        ClubEventKind.of(comp('c1', tournamentId: 't1')),
        ClubEventKind.season,
      );
    });

    test('a single-match format is a single match', () {
      expect(
        ClubEventKind.of(comp('c1', format: CompetitionFormat.singleMatch)),
        ClubEventKind.singleMatch,
      );
    });

    test('an inter-club competition is a challenge', () {
      expect(
        ClubEventKind.of(comp('c1', participantOrgIds: const ['org1', 'org2'])),
        ClubEventKind.challenge,
      );
    });

    test('a multi-sport challenge is still a challenge, not a season', () {
      // `CommunityRepository.acceptChallenge` groups a multi-leg challenge
      // under a tournament exactly as a season is grouped. Being contested by
      // two clubs is the more specific fact and has to win.
      final leg = comp(
        'c1',
        tournamentId: 't_challenge',
        participantOrgIds: const ['org1', 'org2'],
      );
      expect(ClubEventKind.of(leg), ClubEventKind.challenge);
    });
  });

  group('the index a club page is built from', () {
    test('counts a five-sport season as one season', () {
      final index = ClubEventIndex.of([
        for (var i = 0; i < 5; i++) comp('c$i', tournamentId: 't1'),
      ]);
      expect(index.count(ClubEventKind.season), 1);
      // The rows are still all five: the season card groups them further
      // down, in `groupEventFeed`.
      expect(index.events(ClubEventKind.season), hasLength(5));
    });

    test('counts two seasons separately', () {
      final index = ClubEventIndex.of([
        comp('a', tournamentId: 't1'),
        comp('b', tournamentId: 't1'),
        comp('c', tournamentId: 't2'),
      ]);
      expect(index.count(ClubEventKind.season), 2);
    });

    test('a kind the club has none of is empty, not absent', () {
      final index = ClubEventIndex.of([comp('c1')]);
      expect(index.has(ClubEventKind.challenge), isFalse);
      expect(index.count(ClubEventKind.challenge), 0);
      expect(index.events(ClubEventKind.challenge), isEmpty);
    });
  });

  group('filtering by stage', () {
    test('scheduled and in-progress both read as playing', () {
      final index = ClubEventIndex.of([
        comp('a', status: CompetitionStatus.scheduled),
        comp('b', status: CompetitionStatus.inProgress),
        comp('c', status: CompetitionStatus.completed),
      ]);
      expect(
        index.events(ClubEventKind.tournament, stage: ClubEventStage.playing),
        hasLength(2),
      );
      expect(
        index.events(ClubEventKind.tournament, stage: ClubEventStage.played),
        hasLength(1),
      );
    });

    test('a passed deadline files an event under entries closed', () {
      // `displayStatus` moves registrationOpen → registrationClosed once the
      // deadline has gone, without anybody editing the event. The filter has
      // to agree with the status chip on the card.
      final now = DateTime(2026, 6, 1);
      final index = ClubEventIndex.of(
        [
          comp(
            'a',
            status: CompetitionStatus.registrationOpen,
            registrationClosesAt: DateTime(2026, 5, 1),
          ),
          comp('b', status: CompetitionStatus.registrationOpen),
        ],
        now: now,
      );
      expect(
        index
            .events(ClubEventKind.tournament,
                stage: ClubEventStage.entriesOpen)
            .map((c) => c.id)
            .toList(),
        ['b'],
      );
      expect(
        index
            .events(ClubEventKind.tournament,
                stage: ClubEventStage.entriesClosed)
            .map((c) => c.id)
            .toList(),
        ['a'],
      );
    });

    test('only the stages that actually occur are offered', () {
      final index = ClubEventIndex.of([
        comp('a', status: CompetitionStatus.completed),
        comp('b', status: CompetitionStatus.completed),
      ]);
      expect(
        index.stagesPresent(ClubEventKind.tournament),
        [ClubEventStage.all, ClubEventStage.played],
      );
    });

    test('stages are asked of one kind at a time', () {
      final index = ClubEventIndex.of([
        comp('a', status: CompetitionStatus.draft),
        comp(
          'b',
          format: CompetitionFormat.singleMatch,
          status: CompetitionStatus.completed,
        ),
      ]);
      expect(
        index.stagesPresent(ClubEventKind.tournament),
        [ClubEventStage.all, ClubEventStage.draft],
      );
      expect(
        index.stagesPresent(ClubEventKind.singleMatch),
        [ClubEventStage.all, ClubEventStage.played],
      );
    });

    test('the all stage matches everything', () {
      final index = ClubEventIndex.of([
        comp('a', status: CompetitionStatus.draft),
        comp('b', status: CompetitionStatus.cancelled),
      ]);
      expect(
        index.events(ClubEventKind.tournament, stage: ClubEventStage.all),
        hasLength(2),
      );
    });
  });
}
