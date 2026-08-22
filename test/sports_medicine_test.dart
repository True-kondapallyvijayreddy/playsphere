import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/sports_medic.dart';
import 'package:playsphere/domain/medical/sports_medicine_library.dart';
import 'package:playsphere/domain/scoring/scoring_registry.dart';

/// The library is `const` data that people act on while somebody is hurt, so
/// the tests here are about the invariants that make it safe to publish
/// rather than about any single entry's wording.
void main() {
  group('sports medicine library', () {
    test('every injury names a red flag', () {
      // The one rule that must never be broken. An injury guide that tells
      // somebody how to manage a knee but never says when to stop managing it
      // is the dangerous kind, and this is the test that keeps a new entry
      // from being added without an exit condition.
      for (final injury in SportsMedicineLibrary.injuries) {
        expect(
          injury.redFlags,
          isNotEmpty,
          reason: '${injury.id} has no red flags',
        );
        expect(injury.firstAid, isNotEmpty, reason: '${injury.id}');
      }
    });

    test('every emergency protocol says what never to do', () {
      // The instinctive action — popping a shoulder back, sitting a heat
      // stroke casualty up, moving a player with neck pain — is very often
      // the wrong one, so no protocol ships without the list that says so.
      for (final p in SportsMedicineLibrary.emergencies) {
        expect(p.neverDo, isNotEmpty, reason: '${p.id} has no "never" list');
        expect(p.steps, isNotEmpty, reason: '${p.id}');
        expect(p.oneLine, isNotEmpty, reason: '${p.id}');
      }
    });

    test('every warm-up step carries a coaching cue', () {
      // Without the cue these are names of exercises, which is how warm-ups
      // get done badly by people who believe they are doing them.
      for (final w in SportsMedicineLibrary.workouts) {
        expect(w.steps, isNotEmpty, reason: w.id);
        for (final s in w.steps) {
          expect(s.cue, isNotEmpty, reason: '${w.id} · ${s.name}');
          expect(s.dose, isNotEmpty, reason: '${w.id} · ${s.name}');
        }
      }
    });

    test('ids are unique within each catalogue', () {
      void unique(Iterable<String> ids, String what) {
        final seen = <String>{};
        for (final id in ids) {
          expect(seen.add(id), isTrue, reason: 'duplicate $what id: $id');
        }
      }

      unique(SportsMedicineLibrary.workouts.map((w) => w.id), 'workout');
      unique(SportsMedicineLibrary.injuries.map((i) => i.id), 'injury');
      unique(SportsMedicineLibrary.emergencies.map((e) => e.id), 'emergency');
    });

    test('every sport referenced is one the app actually knows', () {
      // A typo in a sport id would silently drop a routine out of the filter
      // it was written for, and nothing on screen would look wrong.
      final known = {for (final s in SportCatalog.all) s.id};
      for (final w in SportsMedicineLibrary.workouts) {
        for (final id in w.sportIds) {
          expect(known, contains(id), reason: 'workout ${w.id}');
        }
      }
      for (final i in SportsMedicineLibrary.injuries) {
        for (final id in i.sportIds) {
          expect(known, contains(id), reason: 'injury ${i.id}');
        }
      }
    });

    test('every video reference resolves to a YouTube url', () {
      // Ids are deliberately unset today — see the library doc — so what is
      // asserted is that the fallback actually produces a live search page
      // rather than an empty one.
      final videos = [
        ...SportsMedicineLibrary.workouts.map((w) => w.video),
        ...SportsMedicineLibrary.injuries.map((i) => i.video),
        ...SportsMedicineLibrary.emergencies.map((e) => e.video),
      ];
      for (final v in videos) {
        expect(v.source, isNotEmpty);
        expect(v.url.host, 'www.youtube.com');
        if (v.videoId == null) {
          expect(v.search, isNotEmpty);
          expect(v.url.queryParameters['search_query'], v.search);
        } else {
          expect(v.url.queryParameters['v'], v.videoId);
        }
      }
    });

    test('a sport filter returns its own routines before the general ones',
        () {
      final list = SportsMedicineLibrary.workoutsFor('cricket');
      expect(list.first.sportIds, contains('cricket'));
      // The general routines are still there — a cricketer still cools down.
      expect(list.any((w) => w.sportIds.isEmpty), isTrue);
    });

    test('the body part filter never offers a chip that returns nothing', () {
      for (final sport in SportCatalog.all) {
        final parts =
            SportsMedicineLibrary.bodyPartsWithInjuries(sportId: sport.id);
        for (final p in parts) {
          expect(
            SportsMedicineLibrary.injuriesFor(sportId: sport.id, part: p),
            isNotEmpty,
            reason: '${sport.id} · ${p.wire}',
          );
        }
      }
    });

    test('an injury with no sports listed belongs to every sport', () {
      final ankle = SportsMedicineLibrary.injuries
          .firstWhere((i) => i.id == 'ankle_lateral_sprain');
      expect(ankle.sportIds, isEmpty);
      for (final sport in SportCatalog.all) {
        expect(ankle.appliesTo(sport.id), isTrue);
      }
    });
  });

  group('SportsMedicProfile', () {
    SportsMedicProfile profile({
      List<String> sportIds = const [],
      List<ConsultationMode> modes = const [ConsultationMode.clinic],
    }) =>
        SportsMedicProfile(
          uid: 'u1',
          displayName: 'Dr Anita Rao',
          role: SportsMedicRole.physiotherapist,
          qualifications: const ['MPT (Sports)'],
          city: 'Warangal',
          clinicName: 'Kakatiya Sports Clinic',
          sportIds: sportIds,
          consultationModes: modes,
        );

    test('an empty sport list means every sport, unlike a coach listing', () {
      // The opposite of `CoachProfile.sportIds` on purpose: a general
      // orthopaedic surgeon fixes the knee whichever game tore it, and hiding
      // them from a kabaddi player would withhold the right answer on a
      // technicality.
      expect(profile().treats('kabaddi'), isTrue);
      expect(profile(sportIds: ['cricket']).treats('kabaddi'), isFalse);
      expect(profile(sportIds: ['cricket']).treats('cricket'), isTrue);
    });

    test('search tokens cover the name, the clinic and the city', () {
      final tokens = profile().searchTokens.toSet();
      expect(tokens, containsAll(['anita', 'rao', 'warangal', 'kakatiya']));
      // Single characters are dropped — they match nearly every document.
      expect(tokens.any((t) => t.length < 2), isFalse);
    });

    test('a query tokenizes the same way the stored array was built', () {
      final tokens = profile().searchTokens.toSet();
      final words = SportsMedicProfile.tokenizeQuery('Warangal  Sports!');
      expect(words, ['warangal', 'sports']);
      expect(words.every(tokens.contains), isTrue);
    });

    test('an unpriced consultation reads as on request, never as free', () {
      // "₹0" would promise free treatment nobody offered.
      expect(profile().feeLabel, 'Fee on request');
    });

    test('wire values survive a round trip through Firestore strings', () {
      for (final role in SportsMedicRole.values) {
        expect(SportsMedicRole.fromWire(role.wire), role);
      }
      for (final mode in ConsultationMode.values) {
        expect(ConsultationMode.fromWire(mode.wire), mode);
      }
      for (final part in BodyPart.values) {
        expect(BodyPart.fromWire(part.wire), part);
      }
    });

    test('an unknown wire value degrades rather than throwing', () {
      // A document written by a newer client must still be readable by an
      // older one — `enums.dart` sets this rule for the whole product.
      expect(
        SportsMedicRole.fromWire('chiropractor'),
        SportsMedicRole.physiotherapist,
      );
      expect(ConsultationMode.fromWire(null), ConsultationMode.clinic);
    });

    test('the update map never carries the fields a client may not write', () {
      final map = profile().toUpdate();
      expect(map.containsKey('isVerified'), isFalse);
      expect(map.containsKey('createdAt'), isFalse);
      // cityKey is what the directory queries, so it is written every time
      // rather than derived at read.
      expect(map['cityKey'], 'warangal');
      expect(map['consultationModes'], ['clinic']);
    });

    test('the create map pins the badge to false', () {
      final map = profile().toCreate();
      expect(map['isVerified'], false);
      expect(map.containsKey('createdAt'), isTrue);
    });
  });
}
