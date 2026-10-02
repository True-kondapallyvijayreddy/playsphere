import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/tournament.dart';
import 'package:playsphere/domain/scoring/scoring_registry.dart';
import 'package:playsphere/domain/tournament/house_roster.dart';
import 'package:playsphere/domain/tournament/season_blueprint.dart';
import 'package:playsphere/domain/tournament/season_date_shift.dart';

/// The one builder both season forms and the add-sport sheet save through.
///
/// Every case here is a season that used to be created wrong: open over draft
/// events, U-14 and U-17 cricket with the same name, a removed ground still
/// pinned, ages measured on a date nobody chose, the rest gap dropped.
void main() {
  final now = DateTime(2026, 9, 13, 10);
  final start = DateTime(2026, 10, 2);
  final end = DateTime(2026, 10, 4);

  CompetitionCategory preset(String label) => CompetitionCategory.presets(
        cutOff: DateTime(2026, 9, 13),
      ).firstWhere((c) => c.label == label);

  SeasonCategorySpec spec(
    String sportId, {
    String? side,
    String category = 'Open',
    String? equipment,
    Set<String> venueIds = const {},
    DateTime? from,
    DateTime? to,
    int? minutes,
    int? maxEntrants,
    int fee = 0,
  }) {
    final sport = SportCatalog.byId(sportId);
    return SeasonCategorySpec(
      sportId: sportId,
      sideFormat: side == null
          ? sport.defaultSideFormat
          : sport.sideFormats.firstWhere((f) => f.id == side),
      category: preset(category),
      format: sport.defaultCompetitionFormat,
      equipment: equipment,
      venueIds: venueIds,
      startDate: from,
      endDate: to,
      matchMinutes: minutes,
      maxEntrants: maxEntrants,
      entryFeeRupees: fee,
    );
  }

  SeasonBlueprint season({
    List<SeasonCategorySpec>? categories,
    List<String> grounds = const ['g1', 'g2'],
    DateTime? startDate,
    DateTime? endDate,
    bool external = false,
    SeasonFeeMode feeMode = SeasonFeeMode.wholeSeason,
    int seasonFee = 0,
    int? seasonMinutes,
    int changeover = 10,
    int rest = 45,
    String name = 'Nizampet Sports Week 2026',
  }) =>
      SeasonBlueprint(
        orgId: 'org1',
        name: name,
        createdBy: 'uid1',
        startDate: startDate ?? start,
        endDate: endDate ?? end,
        groundIds: grounds,
        categories: categories ??
            [spec('cricket', category: 'U-14 Boys'), spec('badminton')],
        externalEntries: external,
        feeMode: feeMode,
        seasonFeeRupees: seasonFee,
        seasonMatchMinutes: seasonMinutes,
        changeoverMinutes: changeover,
        restGapMinutes: rest,
      );

  group('what is refused', () {
    test('a complete season has no problems', () {
      expect(season().problems(now: now), isEmpty);
    });

    test('a start today or earlier is refused', () {
      final p = season(startDate: DateTime(2026, 9, 13)).problems(now: now);
      expect(p.single, contains('tomorrow'));
    });

    test('no grounds, no categories, short name', () {
      final p = season(grounds: const [], categories: const [], name: 'ab')
          .problems(now: now);
      expect(p, hasLength(3));
    });

    test('the same draw twice is refused, a different ball is not', () {
      expect(
        season(categories: [spec('cricket'), spec('cricket')])
            .problems(now: now),
        [contains('twice')],
      );
      expect(
        season(categories: [
          spec('cricket', equipment: 'Hard Tennis Ball'),
          spec('cricket', equipment: 'Red Leather Ball'),
        ]).problems(now: now),
        isEmpty,
      );
    });

    test('a category pinned to a ground the season dropped is refused', () {
      final p = season(
        grounds: const ['g1'],
        categories: [spec('cricket', venueIds: {'g2'})],
      ).problems(now: now);
      expect(p.single, contains('no longer uses'));
    });

    test('a category window outside the season is refused', () {
      final p = season(categories: [
        spec('badminton', from: DateTime(2026, 10, 1)),
        spec('cricket', to: DateTime(2026, 10, 9)),
      ]).problems(now: now);
      expect(p, [contains('starts outside'), contains('ends outside')]);
    });

    test('entries must close on or before the first day', () {
      SeasonBlueprint withDeadline(DateTime d) => SeasonBlueprint(
            orgId: 'o',
            name: 'District Open',
            createdBy: 'u',
            startDate: start,
            entriesCloseOn: d,
            groundIds: const ['g1'],
            categories: [spec('badminton')],
          );
      expect(withDeadline(DateTime(2026, 9, 30)).problems(now: now), isEmpty);
      expect(withDeadline(start).problems(now: now), isEmpty);
      expect(
        withDeadline(DateTime(2026, 10, 3)).problems(now: now).single,
        contains('on or before'),
      );
      final e = withDeadline(DateTime(2026, 9, 30)).events('s').single;
      expect(e.registrationClosesAt, DateTime(2026, 9, 30, 23, 59, 59));
      expect(
        withDeadline(DateTime(2026, 9, 30)).tournament().entryDeadline,
        DateTime(2026, 9, 30, 23, 59, 59),
      );
    });

    test('an entry limit of one is refused', () {
      final p = season(categories: [spec('cricket', maxEntrants: 1)])
          .problems(now: now);
      expect(p.single, contains('at least 2'));
    });
  });

  group('the season document', () {
    test('is published as it is created and counts its events', () {
      final t = season().tournament();
      expect(t.status, TournamentStatus.entriesOpen);
      expect(t.eventCount, 2);
      expect(t.toCreate()['eventCount'], 2);
      expect(t.toCreate()['status'], 'entries_open');
    });

    test('keeps the organiser’s changeover and rest gap', () {
      final t = season(changeover: 10, rest: 45).tournament();
      expect(t.changeoverMinutes, 10);
      expect(t.restGapMinutes, 45);
    });

    test('lays the court grid at the shortest match anybody plays', () {
      final t = season(categories: [
        spec('cricket'),
        spec('badminton', minutes: 40),
      ]).tournament();
      expect(t.matchMinutesDefault, 40);
    });

    test('a one-day season ends on its first day', () {
      final t = SeasonBlueprint(
        orgId: 'o',
        name: 'Sunday Meet',
        createdBy: 'u',
        startDate: start,
        groundIds: const ['g1'],
        categories: [spec('badminton')],
      ).tournament();
      expect(t.endDate, start);
    });

    test('a per-sport season carries no season fee', () {
      final t = season(feeMode: SeasonFeeMode.perEvent, seasonFee: 300)
          .tournament();
      expect(t.entryFeeRupees, 0);
    });
  });

  group('the events', () {
    test('names include category and ball, so no two read the same', () {
      final events = season(categories: [
        spec('cricket', category: 'U-14 Boys', equipment: 'Hard Tennis Ball'),
        spec('cricket', category: 'U-17 Boys'),
        spec('badminton', side: 'doubles'),
      ]).events('s1');
      final names = events.map((e) => e.name).toList();
      expect(names.toSet(), hasLength(3));
      expect(names[0], contains('U-14 Boys'));
      expect(names[0], contains('Hard Tennis Ball'));
      expect(names[2], contains('Doubles'));
      expect(events[0].rulesNote, 'Played with: Hard Tennis Ball');
    });

    test('ages are measured on the season’s first day', () {
      final e = season(categories: [spec('cricket', category: 'U-14 Boys')])
          .events('s1')
          .single;
      expect(e.category.ageCutOffDate, start);
    });

    test('a team sport inside a school is entered by house', () {
      final e = season(categories: [spec('cricket')]).events('s1').single;
      expect(e.teamEntryMode, TeamEntryMode.houseBatch);
      expect(e.presetHouses, HouseTemplates.schoolColours);
      expect(e.participationModel, ParticipationModel.open);
    });

    test('opened to other clubs, teams enter whole and wait for approval', () {
      final e = season(external: true, categories: [spec('cricket')])
          .events('s1')
          .single;
      expect(e.teamEntryMode, TeamEntryMode.preformedTeam);
      expect(e.presetHouses, isEmpty);
      expect(e.participationModel, ParticipationModel.approval);
      expect(e.openToNonMembers, isTrue);
    });

    test('an individual sport has no houses', () {
      final e = season(categories: [spec('badminton')]).events('s1').single;
      expect(e.teamEntryMode, TeamEntryMode.individual);
      expect(e.presetHouses, isEmpty);
    });

    test('each sport keeps its own match length unless the season sets one', () {
      final own = season(categories: [spec('cricket'), spec('badminton')])
          .events('s1');
      expect(
        own[0].scheduleConfig.matchMinutes,
        greaterThan(own[1].scheduleConfig.matchMinutes),
      );
      final fixed = season(
        seasonMinutes: 60,
        categories: [spec('cricket'), spec('badminton', minutes: 25)],
      ).events('s1');
      expect(fixed[0].scheduleConfig.matchMinutes, 60);
      expect(fixed[1].scheduleConfig.matchMinutes, 25);
    });

    test('pins and timings reach the schedule config', () {
      final e = season(categories: [
        spec('cricket', venueIds: {'g2'}),
      ], changeover: 15, rest: 30)
          .events('s1')
          .single;
      expect(e.scheduleConfig.venueIds, ['g2']);
      expect(e.scheduleConfig.changeoverMinutes, 15);
      expect(e.scheduleConfig.restGapMinutes, 30);
      expect(e.tournamentId, 's1');
      // Taking entries from the first moment, with the season.
      expect(e.status, CompetitionStatus.registrationOpen);
      expect(e.toCreate(openForEntries: true)['status'], 'registration_open');
      // Only the season paths ask for that; everything else stays a draft.
      expect(e.toCreate()['status'], 'draft');
    });

    test('fees land on the event only under per-sport pricing', () {
      expect(
        season(categories: [spec('cricket', fee: 500)])
            .events('s1')
            .single
            .entryFeeRupees,
        0,
      );
      expect(
        season(
          feeMode: SeasonFeeMode.perEvent,
          categories: [spec('cricket', fee: 500)],
        ).events('s1').single.entryFeeRupees,
        500,
      );
    });
  });

  group('moving a season moves its events', () {
    final os = DateTime(2026, 10, 2), oe = DateTime(2026, 10, 4);

    test('a postponement moves every window by the same days', () {
      final moved = SeasonDateShift.moveEvent(
        eventStart: DateTime(2026, 10, 3),
        eventEnd: DateTime(2026, 10, 3),
        oldStart: os,
        oldEnd: oe,
        newStart: DateTime(2026, 10, 9),
        newEnd: DateTime(2026, 10, 11),
      );
      expect(moved.start, DateTime(2026, 10, 10));
      expect(moved.end, DateTime(2026, 10, 10));
    });

    test('an event following the first day follows the new first day', () {
      final moved = SeasonDateShift.moveEvent(
        eventStart: os,
        eventEnd: null,
        oldStart: os,
        oldEnd: oe,
        newStart: DateTime(2026, 10, 1),
        newEnd: oe,
      );
      expect(moved.start, DateTime(2026, 10, 1));
      expect(moved.end, isNull);
    });

    test('a postponement keeps the start time the organizer typed', () {
      final moved = SeasonDateShift.moveEvent(
        eventStart: DateTime(2026, 10, 3, 9, 30),
        eventEnd: null,
        oldStart: os,
        oldEnd: oe,
        newStart: DateTime(2026, 10, 10),
        newEnd: DateTime(2026, 10, 12),
      );
      expect(moved.start, DateTime(2026, 10, 11, 9, 30));
      expect(moved.end, isNull);
    });

    test('a start sent back to the new first day keeps its time too', () {
      final moved = SeasonDateShift.moveEvent(
        eventStart: DateTime(2026, 10, 2, 16, 45),
        eventEnd: null,
        oldStart: os,
        oldEnd: oe,
        newStart: DateTime(2026, 10, 1),
        newEnd: oe,
      );
      expect(moved.start, DateTime(2026, 10, 1, 16, 45));
    });

    test('an event that does not move compares equal to what is stored', () {
      final stored = DateTime(2026, 10, 3, 9, 30, 15);
      final moved = SeasonDateShift.moveEvent(
        eventStart: stored,
        eventEnd: null,
        oldStart: os,
        oldEnd: oe,
        newStart: os,
        newEnd: DateTime(2026, 10, 5),
      );
      expect(moved.start, stored);
    });

    test('a window left outside a shortened season follows the season', () {
      final moved = SeasonDateShift.moveEvent(
        eventStart: DateTime(2026, 10, 4),
        eventEnd: DateTime(2026, 10, 4),
        oldStart: os,
        oldEnd: oe,
        newStart: os,
        newEnd: DateTime(2026, 10, 3),
      );
      expect(moved.start, os);
      expect(moved.end, isNull);
    });
  });
}
