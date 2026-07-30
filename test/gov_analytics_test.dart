import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/geo.dart';
import 'package:playsphere/core/models/organization.dart';
import 'package:playsphere/domain/gov/age_group.dart';
import 'package:playsphere/domain/gov/gov_aggregator.dart';
import 'package:playsphere/domain/gov/gov_export.dart';
import 'package:playsphere/domain/gov/participation_entry.dart';

void main() {
  // ==========================================================================
  group('GeoLocation rollup', () {
    const full = GeoLocation(
      state: 'Telangana',
      district: 'Warangal',
      mandal: 'Hanamkonda',
      village: 'Kazipet',
    );

    test('a village aggregates into its mandal, district and state', () {
      expect(full.rollUpTo(GeoLevel.village), 'Kazipet');
      expect(full.rollUpTo(GeoLevel.mandal), 'Hanamkonda');
      expect(full.rollUpTo(GeoLevel.district), 'Warangal');
      expect(full.rollUpTo(GeoLevel.state), 'Telangana');
    });

    test('a level never captured rolls up to null, not a guess', () {
      const districtOnly =
          GeoLocation(state: 'Telangana', district: 'Warangal');
      expect(districtOnly.rollUpTo(GeoLevel.mandal), isNull);
      expect(districtOnly.rollUpTo(GeoLevel.village), isNull);
      expect(districtOnly.rollUpTo(GeoLevel.district), 'Warangal');
    });

    test('GeoLevel.parent walks up the hierarchy and stops at state', () {
      expect(GeoLevel.village.parent, GeoLevel.mandal);
      expect(GeoLevel.mandal.parent, GeoLevel.district);
      expect(GeoLevel.district.parent, GeoLevel.state);
      expect(GeoLevel.state.parent, isNull);
    });

    test('equality and toMap round-trip', () {
      expect(GeoLocation.fromMap(full.toMap()), full);
      expect(full.toMap(), {
        'state': 'Telangana',
        'district': 'Warangal',
        'mandal': 'Hanamkonda',
        'village': 'Kazipet',
      });
    });
  });

  // ==========================================================================
  group('geo model backward compatibility with old flat documents', () {
    test('a document with no geo field and no legacy fields is empty', () {
      final geo = GeoLocation.fromDocData(const {'name': 'X'});
      expect(geo.isEmpty, isTrue);
    });

    test('a nested geo map is parsed when present', () {
      final geo = GeoLocation.fromDocData(const {
        'geo': {
          'state': 'Telangana',
          'district': 'Karimnagar',
          'mandal': 'Huzurabad',
          'village': 'Veenavanka',
        },
      });
      expect(geo.district, 'Karimnagar');
      expect(geo.mandal, 'Huzurabad');
      expect(geo.village, 'Veenavanka');
    });

    test(
        'an old org document (flat district/city, no geo map) falls back '
        'correctly — this is what every org written before GeoLocation '
        'existed looks like', () {
      final geo = GeoLocation.fromDocData(
        const {'district': 'Warangal', 'city': 'Kazipet'},
        legacyDistrictKey: 'district',
        legacyVillageKey: 'city',
      );
      expect(geo.district, 'Warangal');
      expect(geo.village, 'Kazipet');
      expect(geo.mandal, isNull, reason: 'never existed on the old shape');
      expect(geo.state, isNull);
    });

    test('a nested geo map wins over legacy flat fields when both exist', () {
      final geo = GeoLocation.fromDocData(
        const {
          'district': 'StaleDistrict',
          'city': 'StaleCity',
          'geo': {
            'state': 'Telangana',
            'district': 'Nizamabad',
            'mandal': 'Armoor',
            'village': 'Ramaraopet',
          },
        },
        legacyDistrictKey: 'district',
        legacyVillageKey: 'city',
      );
      expect(geo.district, 'Nizamabad');
      expect(geo.mandal, 'Armoor');
      expect(geo.village, 'Ramaraopet');
    });

    test('Organization.fromDoc-equivalent construction keeps geo populated '
        'via toCreate for new writes going forward', () {
      const org = Organization(
        id: 'o4',
        name: 'Future Club',
        orgType: OrgType.village,
        visibility: OrgVisibility.public,
        ownerUid: 'owner1',
        inviteCode: 'FUT001',
        district: 'Warangal',
        city: 'Kazipet',
        geo: GeoLocation(
          state: 'Telangana',
          district: 'Warangal',
          mandal: 'Hanamkonda',
          village: 'Kazipet',
        ),
      );
      final payload = org.toCreate();
      expect(payload['geo'], {
        'state': 'Telangana',
        'district': 'Warangal',
        'mandal': 'Hanamkonda',
        'village': 'Kazipet',
      });
      // The legacy flat fields are still written too, unchanged, so any
      // screen still reading them directly keeps working.
      expect(payload['district'], 'Warangal');
      expect(payload['city'], 'Kazipet');
    });

    test('an Organization built with the default geo has an empty geo map',
        () {
      const org = Organization(
        id: 'o5',
        name: 'No Location Club',
        orgType: OrgType.residentialCommunity,
        visibility: OrgVisibility.public,
        ownerUid: 'owner1',
        inviteCode: 'NOLOC1',
      );
      expect(org.geo.isEmpty, isTrue);
      expect(org.toCreate()['geo'], <String, Object?>{});
    });
  });

  // ==========================================================================
  group('AgeGroup derivation at cut-off date boundaries', () {
    test('turns 14 exactly on the reference date -> still U-14', () {
      final dob = DateTime(2012, 7, 29);
      final ref = DateTime(2026, 7, 29); // exactly 14 today
      expect(AgeGroup.fromDateOfBirth(dob, referenceDate: ref), AgeGroup.u14);
    });

    test('turns 15 the day after the reference date -> still U-14', () {
      final dob = DateTime(2011, 7, 30);
      final ref = DateTime(2026, 7, 29); // birthday is tomorrow: still 14
      expect(AgeGroup.fromDateOfBirth(dob, referenceDate: ref), AgeGroup.u14);
    });

    test('turned 15 the day before the reference date -> U-17 band', () {
      final dob = DateTime(2011, 7, 28);
      final ref = DateTime(2026, 7, 29); // birthday was yesterday: now 15
      expect(AgeGroup.fromDateOfBirth(dob, referenceDate: ref), AgeGroup.u17);
    });

    test('exact boundaries for every band', () {
      DateTime dobForAge(int age) =>
          DateTime(2026 - age, 7, 29); // exactly `age` on the reference date
      final ref = DateTime(2026, 7, 29);
      expect(AgeGroup.fromDateOfBirth(dobForAge(14), referenceDate: ref),
          AgeGroup.u14);
      expect(AgeGroup.fromDateOfBirth(dobForAge(15), referenceDate: ref),
          AgeGroup.u17);
      expect(AgeGroup.fromDateOfBirth(dobForAge(17), referenceDate: ref),
          AgeGroup.u17);
      expect(AgeGroup.fromDateOfBirth(dobForAge(18), referenceDate: ref),
          AgeGroup.u19);
      expect(AgeGroup.fromDateOfBirth(dobForAge(19), referenceDate: ref),
          AgeGroup.u19);
      expect(AgeGroup.fromDateOfBirth(dobForAge(20), referenceDate: ref),
          AgeGroup.u21);
      expect(AgeGroup.fromDateOfBirth(dobForAge(21), referenceDate: ref),
          AgeGroup.u21);
      expect(AgeGroup.fromDateOfBirth(dobForAge(22), referenceDate: ref),
          AgeGroup.senior);
      expect(AgeGroup.fromDateOfBirth(dobForAge(45), referenceDate: ref),
          AgeGroup.senior);
    });

    test('a mid-tournament birthday does not reclassify the player (§12.8)',
        () {
      // A player who is 16 on the season cut-off stays U-17 for the whole
      // season, even after a birthday that happens during it.
      final dob = DateTime(2010, 8, 15);
      final seasonCutOff = DateTime(2026, 1, 1); // 15 as of cut-off
      expect(
        AgeGroup.fromDateOfBirth(dob, referenceDate: seasonCutOff),
        AgeGroup.u17,
      );
      // The *same fixed* cut-off must always be used for a period's report,
      // never "now" — passing "now" would drift the classification purely
      // based on when someone happened to run the query.
      final afterBirthday = DateTime(2026, 9, 1); // 16 by "now"
      expect(
        AgeGroup.fromDateOfBirth(dob, referenceDate: seasonCutOff),
        AgeGroup.u17,
        reason: 'the cut-off date passed to the query must not drift',
      );
      expect(
        AgeGroup.fromDateOfBirth(dob, referenceDate: afterBirthday),
        AgeGroup.u17,
        reason: 'coincidentally still U-17 at 16, but for the right reason',
      );
    });
  });

  // ==========================================================================
  group('GovAggregator rollup correctness', () {
    const aggregator = GovAggregator();
    final ref = DateTime(2026, 1, 1);

    GeoLocation geoIn(String village, String mandal, String district) =>
        GeoLocation(
          state: 'Telangana',
          district: district,
          mandal: mandal,
          village: village,
        );

    // Two villages in the same mandal, one village in a different mandal of
    // the same district — enough to prove village -> mandal -> district ->
    // state all sum correctly.
    final entries = [
      for (var i = 0; i < 3; i++)
        ParticipationEntry(
          uid: 'kazipet-$i',
          dateOfBirth: DateTime(2010, 1, 1),
          gender: Gender.male,
          geo: geoIn('Kazipet', 'Hanamkonda', 'Warangal'),
          sportId: 'kabaddi',
        ),
      for (var i = 0; i < 2; i++)
        ParticipationEntry(
          uid: 'elkathurthy-$i',
          dateOfBirth: DateTime(2010, 1, 1),
          gender: Gender.male,
          geo: geoIn('Elkathurthy', 'Hanamkonda', 'Warangal'),
          sportId: 'kabaddi',
        ),
      for (var i = 0; i < 4; i++)
        ParticipationEntry(
          uid: 'jangaon-$i',
          dateOfBirth: DateTime(2010, 1, 1),
          gender: Gender.male,
          geo: geoIn('JangaonTown', 'Jangaon', 'Warangal'),
          sportId: 'kabaddi',
        ),
    ];

    test('village level: one row per village', () {
      final rows = aggregator.aggregate(entries,
          period: '2026-01', level: GeoLevel.village, referenceDate: ref);
      final byArea = {for (final r in rows) r.area: r.participants};
      expect(byArea['Kazipet'], 3);
      expect(byArea['Elkathurthy'], 2);
      expect(byArea['JangaonTown'], 4);
    });

    test('mandal level: villages in the same mandal sum together', () {
      final rows = aggregator.aggregate(entries,
          period: '2026-01', level: GeoLevel.mandal, referenceDate: ref);
      final byArea = {for (final r in rows) r.area: r.participants};
      expect(byArea['Hanamkonda'], 3 + 2, reason: 'Kazipet + Elkathurthy');
      expect(byArea['Jangaon'], 4);
    });

    test('district level: all mandals in the district sum together', () {
      final rows = aggregator.aggregate(entries,
          period: '2026-01', level: GeoLevel.district, referenceDate: ref);
      expect(rows, hasLength(1));
      expect(rows.single.area, 'Warangal');
      expect(rows.single.participants, 3 + 2 + 4);
    });

    test('state level: the whole district sums into the state', () {
      final rows = aggregator.aggregate(entries,
          period: '2026-01', level: GeoLevel.state, referenceDate: ref);
      expect(rows, hasLength(1));
      expect(rows.single.area, 'Telangana');
      expect(rows.single.participants, 3 + 2 + 4);
    });

    test('an entry missing the requested granularity is excluded, not guessed',
        () {
      final noVillage = ParticipationEntry(
        uid: 'district-only',
        dateOfBirth: DateTime(2010, 1, 1),
        gender: Gender.male,
        geo: const GeoLocation(state: 'Telangana', district: 'Nalgonda'),
        sportId: 'kabaddi',
      );
      final rows = aggregator.aggregate([noVillage],
          period: '2026-01', level: GeoLevel.village, referenceDate: ref);
      expect(rows, isEmpty);

      final districtRows = aggregator.aggregate([noVillage],
          period: '2026-01', level: GeoLevel.district, referenceDate: ref);
      expect(districtRows.single.participants, 1);
    });

    test('distinct matches/events/clubs are counted, not one per participant',
        () {
      final withMatch = [
        for (var i = 0; i < 6; i++)
          ParticipationEntry(
            uid: 'p$i',
            dateOfBirth: DateTime(2010, 1, 1),
            gender: Gender.male,
            geo: geoIn('Kazipet', 'Hanamkonda', 'Warangal'),
            sportId: 'kabaddi',
            matchId: 'match-1', // all 6 played the same single match
            clubId: 'club-1',
          ),
      ];
      final rows = aggregator.aggregate(withMatch,
          period: '2026-01', level: GeoLevel.village, referenceDate: ref);
      expect(rows.single.participants, 6);
      expect(rows.single.matches, 1);
      expect(rows.single.clubs, 1);
    });
  });

  // ==========================================================================
  group('k-anonymity suppression (DPDP §2.7)', () {
    const aggregator = GovAggregator();
    final ref = DateTime(2026, 1, 1);

    List<ParticipationEntry> peopleOf(int n,
            {String village = 'SmallVillage'}) =>
        [
          for (var i = 0; i < n; i++)
            ParticipationEntry(
              uid: '$village-$i',
              dateOfBirth: DateTime(2012, 1, 1),
              gender: Gender.female,
              geo: GeoLocation(
                state: 'Telangana',
                district: 'Warangal',
                mandal: 'Hanamkonda',
                village: village,
              ),
              sportId: 'athletics',
            ),
        ];

    test('a cell below the default threshold of 5 is fully suppressed', () {
      final rows = aggregator.aggregate(peopleOf(3),
          period: '2026-01', level: GeoLevel.village, referenceDate: ref);
      final safe = aggregator.applyKAnonymity(rows);
      expect(safe.single.suppressed, isTrue);
      expect(safe.single.participants, isNull,
          reason: 'the true count of 3 must never be published');
    });

    test('a cell at or above the threshold is published as-is', () {
      final rows = aggregator.aggregate(peopleOf(5),
          period: '2026-01', level: GeoLevel.village, referenceDate: ref);
      final safe = aggregator.applyKAnonymity(rows);
      expect(safe.single.suppressed, isFalse);
      expect(safe.single.participants, 5);
    });

    test('the threshold is configurable', () {
      final rows = aggregator.aggregate(peopleOf(8),
          period: '2026-01', level: GeoLevel.village, referenceDate: ref);
      final safe = aggregator.applyKAnonymity(rows, threshold: 10);
      expect(safe.single.suppressed, isTrue);
      expect(safe.single.participants, isNull);
    });

    test('no entries means no row is produced — a true zero is never a '
        'suppressed small number', () {
      final rows = aggregator.aggregate(const [],
          period: '2026-01', level: GeoLevel.village, referenceDate: ref);
      expect(rows, isEmpty);
    });

    test(
        'a small talent-selected count is suppressed even when total '
        'participants is safely large', () {
      final entries = [
        for (var i = 0; i < 20; i++)
          ParticipationEntry(
            uid: 'p$i',
            dateOfBirth: DateTime(2011, 1, 1),
            gender: Gender.female,
            geo: const GeoLocation(
              state: 'Telangana',
              district: 'Warangal',
              mandal: 'Hanamkonda',
              village: 'BigVillage',
            ),
            sportId: 'athletics',
            // Only 2 of the 20 were ever selected for a state trial — the
            // exact scenario that would de-anonymise two specific minors if
            // published, even though 20 total participants is plenty safe.
            talentStage: i < 2 ? TalentStage.selected : TalentStage.none,
          ),
      ];
      final rows = aggregator.aggregate(entries,
          period: '2026-01', level: GeoLevel.village, referenceDate: ref);
      final safe = aggregator.applyKAnonymity(rows);

      expect(safe.single.suppressed, isTrue);
      expect(safe.single.participants, 20,
          reason: 'the large, safe total is still published');
      expect(safe.single.talentSelected, isNull,
          reason: 'the small, sensitive count is redacted independently');
    });

    test('venue utilization is never suppressed — it is not personal data',
        () {
      final rows = aggregator.aggregate(
        peopleOf(2),
        period: '2026-01',
        level: GeoLevel.village,
        referenceDate: ref,
        venueUtilizationByAreaSport: const {('SmallVillage', 'athletics'): 0.4},
      );
      final safe = aggregator.applyKAnonymity(rows);
      expect(safe.single.suppressed, isTrue);
      expect(safe.single.participants, isNull);
      expect(safe.single.venueUtilization, 0.4);
    });
  });

  // ==========================================================================
  group("women's and para participation KPIs", () {
    const aggregator = GovAggregator();
    final ref = DateTime(2026, 1, 1);

    ParticipationEntry entry({
      required String uid,
      required Gender gender,
      bool isPara = false,
    }) =>
        ParticipationEntry(
          uid: uid,
          dateOfBirth: DateTime(2005, 1, 1),
          gender: gender,
          geo: const GeoLocation(
            state: 'Telangana',
            district: 'Warangal',
            mandal: 'Hanamkonda',
            village: 'Kazipet',
          ),
          sportId: 'athletics',
          isPara: isPara,
        );

    test('women and para counts are summed independently of each other', () {
      final entries = [
        for (var i = 0; i < 6; i++) entry(uid: 'f$i', gender: Gender.female),
        for (var i = 0; i < 6; i++) entry(uid: 'm$i', gender: Gender.male),
        for (var i = 0; i < 6; i++)
          entry(uid: 'para$i', gender: Gender.male, isPara: true),
      ];
      final rows = aggregator.aggregate(entries,
          period: '2026-01', level: GeoLevel.village, referenceDate: ref);
      final safe = aggregator.applyKAnonymity(rows);

      expect(aggregator.womensParticipation(safe), 6);
      expect(aggregator.paraParticipation(safe), 6);
    });

    test('a suppressed cell contributes 0, not its true small count', () {
      final entries = [
        for (var i = 0; i < 2; i++) entry(uid: 'f$i', gender: Gender.female),
      ];
      final rows = aggregator.aggregate(entries,
          period: '2026-01', level: GeoLevel.village, referenceDate: ref);
      final safe = aggregator.applyKAnonymity(rows);
      expect(aggregator.womensParticipation(safe), 0);
    });
  });

  // ==========================================================================
  group('talent-pipeline funnel', () {
    const aggregator = GovAggregator();
    final ref = DateTime(2026, 1, 1);

    test('identified -> trialed -> selected counts are cumulative', () {
      // One cohort of eight, at three different stages. The funnel is
      // cumulative — a selected athlete was also trialed and identified — so
      // the same person must not be counted as a separate body at each stage.
      // Building two cohorts here would silently double the pipeline.
      final entries = [
        for (var i = 0; i < 8; i++)
          ParticipationEntry(
            uid: 'athlete$i',
            dateOfBirth: DateTime(2010, 1, 1),
            gender: Gender.male,
            geo: const GeoLocation(
              state: 'Telangana',
              district: 'Warangal',
              mandal: 'Hanamkonda',
              village: 'Kazipet',
            ),
            sportId: 'athletics',
            // 3 selected, a further 3 trialed, a further 2 identified only.
            talentStage: i < 3
                ? TalentStage.selected
                : (i < 6 ? TalentStage.trialed : TalentStage.identified),
          ),
      ];
      final rows = aggregator.aggregate(entries,
          period: '2026-01', level: GeoLevel.village, referenceDate: ref);
      final funnel = aggregator.talentFunnel(rows);

      expect(funnel.identified, 8, reason: '8 uids reached >= identified');
      expect(funnel.trialed, 6, reason: '6 uids reached >= trialed');
      expect(funnel.selected, 3, reason: '3 uids reached >= selected');
      expect(funnel.identifiedToTrialedRate, closeTo(6 / 8, 1e-9));
      expect(funnel.trialedToSelectedRate, closeTo(3 / 6, 1e-9));
    });

    test('an empty funnel has zero, not undefined, conversion rates', () {
      const funnel =
          TalentFunnelTotals(identified: 0, trialed: 0, selected: 0);
      expect(funnel.identifiedToTrialedRate, 0);
      expect(funnel.trialedToSelectedRate, 0);
    });
  });

  // ==========================================================================
  group('export record shape', () {
    const aggregator = GovAggregator();
    final ref = DateTime(2026, 1, 1);

    test('a published row maps to a stable, fully-populated export record',
        () {
      final entries = [
        for (var i = 0; i < 6; i++)
          ParticipationEntry(
            uid: 'p$i',
            dateOfBirth: DateTime(2015, 1, 1), // U-14 on the reference date
            gender: Gender.female,
            geo: const GeoLocation(
              state: 'Telangana',
              district: 'Warangal',
              mandal: 'Hanamkonda',
              village: 'Kazipet',
            ),
            sportId: 'kabaddi',
            matchId: 'match-1',
            clubId: 'club-1',
          ),
      ];
      final rows = aggregator.aggregate(
        entries,
        period: '2026-01',
        level: GeoLevel.village,
        referenceDate: ref,
        venueUtilizationByAreaSport: const {('Kazipet', 'kabaddi'): 0.75},
      );
      final safe = aggregator.applyKAnonymity(rows);
      final records = toExportRecords(safe);

      expect(records, hasLength(1));
      final r = records.single;
      expect(r.schemaVersion, 1);
      expect(r.period, '2026-01');
      expect(r.geoLevel, 'village');
      expect(r.area, 'Kazipet');
      expect(r.sportId, 'kabaddi');
      expect(r.ageGroup, 'U-14');
      expect(r.gender, 'female');
      expect(r.isPara, isFalse);
      expect(r.participants, 6);
      expect(r.matches, 1);
      expect(r.clubs, 1);
      expect(r.venueUtilizationPct, 75.0);
      expect(r.suppressed, isFalse);

      final map = r.toMap();
      expect(map['schemaVersion'], 1);
      expect(map['area'], 'Kazipet');
      expect(map['participants'], 6);
    });

    test('a suppressed row exports null counts but keeps the coordinate', () {
      final entries = [
        for (var i = 0; i < 2; i++)
          ParticipationEntry(
            uid: 'p$i',
            dateOfBirth: DateTime(2015, 1, 1),
            gender: Gender.female,
            geo: const GeoLocation(
              state: 'Telangana',
              district: 'Warangal',
              mandal: 'Hanamkonda',
              village: 'Kazipet',
            ),
            sportId: 'kabaddi',
          ),
      ];
      final rows = aggregator.aggregate(entries,
          period: '2026-01', level: GeoLevel.village, referenceDate: ref);
      final safe = aggregator.applyKAnonymity(rows);
      final r = toExportRecords(safe).single;

      expect(r.suppressed, isTrue);
      expect(r.participants, isNull);
      // The coordinate stays visible even when the counts are redacted —
      // that is what lets a dashboard show "data suppressed" instead of the
      // cell vanishing without explanation.
      expect(r.area, 'Kazipet');
      expect(r.sportId, 'kabaddi');
    });
  });
}
