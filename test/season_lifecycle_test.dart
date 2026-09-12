import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/tournament.dart';
import 'package:playsphere/domain/scoring/scoring_registry.dart';
import 'package:playsphere/domain/tournament/entrant_promoter.dart';

/// The season lifecycle, at the two joints where it used to come apart.
///
/// Create a season, people register, the schedule builds itself. Each of
/// those three is implemented and tested; what was missing was that the
/// second did not follow from the first and the third did not follow from
/// the second, and both gaps were invisible until an organizer hit them:
///
///  1. Every event is created as a `draft`, and a draft takes no entries. A
///     twelve-category season was published, the link went round, and the
///     people who followed it found twelve events they could not enter.
///  2. An entrant list is written when entries CLOSE, not when somebody
///     registers. So "Set up the whole season" reported "0 entered, needs at
///     least 2" on events showing twenty registrations.
///
/// These cover the invariants behind the fixes. The Firestore halves live in
/// `TournamentRepository.openEntriesForSeason` and `setUpWholeSeason`.
void main() {
  Competition event({
    CompetitionStatus status = CompetitionStatus.draft,
    EntrantType entrantType = EntrantType.individual,
    TeamEntryMode teamEntryMode = TeamEntryMode.individual,
  }) =>
      Competition(
        id: 'c1',
        orgId: 'org1',
        tournamentId: 't1',
        name: 'Sports Week — Badminton',
        sportId: 'badminton',
        sportName: 'Badminton',
        archetype: CompetitionArchetype.versus,
        entrantType: entrantType,
        teamEntryMode: teamEntryMode,
        format: CompetitionFormat.knockout,
        status: status,
        category: CompetitionCategory.presets().first,
        scoringPluginKey: 'badminton',
      );

  group('a published season starts closed, and says so in its data', () {
    test('a created event is a draft whatever status was asked for', () {
      // Both season forms ask for `registrationOpen`. `toCreate` overrides
      // it, and `firestore.rules` requires the override — an event must be
      // checkable before anybody can enter it. The bug was never this; it
      // was that nothing lifted the drafts afterwards.
      final wire = event(status: CompetitionStatus.registrationOpen)
          .toCreate()['status'];
      expect(wire, CompetitionStatus.draft.wire);
    });

    test('a draft accepts no registrations', () {
      expect(CompetitionStatus.draft.acceptsRegistrations, isFalse);
      expect(CompetitionStatus.registrationOpen.acceptsRegistrations, isTrue);
      expect(
        CompetitionStatus.registrationClosed.acceptsRegistrations,
        isFalse,
      );
    });

    test('an opened event is the one state entries flow through', () {
      // What `openEntriesForSeason` moves every draft to, and the only state
      // in which the register button does anything.
      expect(
        CompetitionStatus.registrationOpen.wire,
        'registration_open',
      );
    });
  });

  group('registrations become a field only when entries close', () {
    Registration reg(String uid, {String? house, String? team}) => Registration(
          uid: uid,
          displayName: uid,
          status: RegistrationStatus.confirmed,
          houseName: house,
          teamName: team,
        );

    test('individuals promote one entrant each', () {
      final result = const EntrantPromoter().promote(
        mode: TeamEntryMode.individual,
        confirmed: [reg('a'), reg('b'), reg('c'), reg('d')],
      );
      expect(result.isReady, isTrue);
      expect(result.entrants, hasLength(4));
    });

    test('a school team sport folds its houses into sides, not individuals',
        () {
      // The reason `teamEntryMode` has to be set at creation. Left at
      // `individual` — which the one-page season form used to do — twenty-two
      // cricketers promote to twenty-two entrants and the draw pairs
      // cricketers against each other.
      final confirmed = [
        for (var i = 0; i < 6; i++) reg('red$i', house: 'Red House'),
        for (var i = 0; i < 6; i++) reg('blue$i', house: 'Blue House'),
      ];

      final asIndividuals = const EntrantPromoter().promote(
        mode: TeamEntryMode.individual,
        confirmed: confirmed,
      );
      expect(asIndividuals.entrants, hasLength(12));

      final asHouses = const EntrantPromoter().promote(
        mode: TeamEntryMode.houseBatch,
        confirmed: confirmed,
      );
      expect(asHouses.isReady, isTrue);
      expect(asHouses.entrants, hasLength(2));
      expect(
        asHouses.entrants.map((e) => e.memberUids.length),
        everyElement(6),
      );
    });

    test('a visiting club entering as a team is one side', () {
      final result = const EntrantPromoter().promote(
        mode: TeamEntryMode.preformedTeam,
        confirmed: [
          for (var i = 0; i < 5; i++) reg('st$i', team: "St Mary's"),
          for (var i = 0; i < 5; i++) reg('kv$i', team: 'Kendriya Vidyalaya'),
        ],
      );
      expect(result.isReady, isTrue);
      expect(result.entrants, hasLength(2));
    });

    test('a field that cannot be assembled explains itself', () {
      // What `setUpWholeSeason` now surfaces per event instead of the
      // misleading "0 entered".
      final result = const EntrantPromoter().promote(
        mode: TeamEntryMode.houseBatch,
        confirmed: [reg('a'), reg('b'), reg('c')],
      );
      expect(result.isReady, isFalse);
      expect(result.problems, isNotEmpty);
      expect(result.problems.join(' '), contains('house'));
    });
  });

  group('the entry mode a season form must choose', () {
    // The rule both season forms now apply, stated once so the two cannot
    // drift apart again — they produced different seasons from the same
    // answers for as long as only one of them set it.
    TeamEntryMode modeFor({
      required EntrantType entrantType,
      required bool externalEntries,
    }) =>
        entrantType == EntrantType.individual
            ? TeamEntryMode.individual
            : (externalEntries
                ? TeamEntryMode.preformedTeam
                : TeamEntryMode.houseBatch);

    test('an individual sport is always individual entry', () {
      expect(
        modeFor(entrantType: EntrantType.individual, externalEntries: false),
        TeamEntryMode.individual,
      );
      expect(
        modeFor(entrantType: EntrantType.individual, externalEntries: true),
        TeamEntryMode.individual,
      );
    });

    test('a team sport inside one club splits into houses', () {
      expect(
        modeFor(entrantType: EntrantType.team, externalEntries: false),
        TeamEntryMode.houseBatch,
      );
    });

    test('a team sport open to other clubs takes whole teams', () {
      // House names belong to one school and mean nothing to a visiting club,
      // which is why the open season takes pre-formed sides instead.
      expect(
        modeFor(entrantType: EntrantType.team, externalEntries: true),
        TeamEntryMode.preformedTeam,
      );
    });
  });

  group('a sport the timetable cannot build says so', () {
    // Track, field and swimming produce measured marks, not pairwise
    // matches. `FixtureGenerator` builds nothing for them, and it returns the
    // same empty list it returns for "fewer than two entrants" — so the draw
    // used to refuse a 100m final with forty athletes entered by saying "Not
    // enough entrants to make a draw", sending the organizer to look for
    // entrants who were already there.
    test('performance formats are recognisable before the draw runs', () {
      expect(CompetitionFormat.finalOnly.isPerformanceFormat, isTrue);
      expect(CompetitionFormat.heatsThenFinal.isPerformanceFormat, isTrue);
      expect(CompetitionFormat.knockout.isPerformanceFormat, isFalse);
      expect(CompetitionFormat.roundRobin.isPerformanceFormat, isFalse);
      expect(CompetitionFormat.groupThenKnockout.isPerformanceFormat, isFalse);
    });

    test('the sports that carry them are the ones a season warns about', () {
      for (final id in const ['athletics_sprint', 'athletics_field', 'swimming']) {
        final sport = SportCatalog.byId(id);
        expect(sport.isPerformance, isTrue, reason: id);
        expect(
          sport.competitionFormats.every((f) => f.isPerformanceFormat),
          isTrue,
          reason: id,
        );
      }
    });

    test('an ordinary sport offers only buildable formats', () {
      final badminton = SportCatalog.byId('badminton');
      expect(badminton.isPerformance, isFalse);
      expect(
        badminton.competitionFormats.any((f) => f.isPerformanceFormat),
        isFalse,
      );
    });
  });

  group('a season stops calling itself a draft once a draw opens', () {
    // The third joint, found after the first two were fixed. Opening the
    // whole season moves the season document too; opening ONE draw from its
    // own page did not, so a season page said "Draft" while people were
    // registering through it and the home screen was — correctly — offering
    // it. `CompetitionRepository.setStatus` now carries the season along.
    test('draft yields, because entries being open contradicts it', () {
      expect(TournamentStatus.draft.yieldsToAnOpenDraw, isTrue);
    });

    test('nothing a person decided is overwritten', () {
      // Re-opening one draw of a season already scheduled, being played or
      // called off must not drag the whole season back to "Entries open".
      for (final status in TournamentStatus.values) {
        if (status == TournamentStatus.draft) continue;
        expect(status.yieldsToAnOpenDraw, isFalse, reason: status.wire);
      }
    });

    test('what it moves to is the status that accepts entries', () {
      expect(TournamentStatus.entriesOpen.acceptsEntries, isTrue);
      expect(TournamentStatus.draft.acceptsEntries, isFalse);
    });
  });
}
