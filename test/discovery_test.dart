import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/app_user.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/geo.dart';
import 'package:playsphere/core/models/membership_application.dart';
import 'package:playsphere/core/models/organization.dart';
import 'package:playsphere/core/models/player_listing.dart';
import 'package:playsphere/core/router/app_router.dart';
import 'package:playsphere/data/discovery_repository.dart';
import 'package:playsphere/domain/gov/age_group.dart';

/// The parts of discovery that are pure and therefore worth pinning here.
///
/// The rules half — who may read an applicant's profile, and who may put
/// themselves in the directory — lives in `test/security/discovery.test.mjs`,
/// against the emulator, because none of it is decidable in Dart.
void main() {
  group('GeoLocation labels', () {
    test('reads finest first, and skips what was never captured', () {
      const geo = GeoLocation(
        state: 'Telangana',
        district: 'Warangal',
        village: 'Kazipet',
      );
      expect(geo.label, 'Kazipet, Warangal, Telangana');
    });

    test('the stranger-facing label stops at the district', () {
      const geo = GeoLocation(
        state: 'Telangana',
        district: 'Warangal',
        village: 'Kazipet',
      );
      // A village name places somebody precisely enough to find them, which
      // is not what a discovery card is for.
      expect(geo.areaLabel, 'Warangal, Telangana');
      expect(geo.areaLabel.contains('Kazipet'), isFalse);
    });

    test('an empty location produces an empty string, not a stray comma', () {
      expect(GeoLocation.empty.label, '');
      expect(GeoLocation.empty.areaLabel, '');
    });
  });

  group('a join request that introduces the applicant', () {
    final user = AppUser(
      uid: 'u1',
      displayName: 'Asha',
      email: 'asha@example.com',
      dateOfBirth: DateTime(2000, 1, 1),
      gender: Gender.female,
      playerCode: 'PSOS-4K7M2',
      geo: const GeoLocation(
        state: 'Telangana',
        district: 'Warangal',
        village: 'Kazipet',
      ),
    );

    MembershipApplication build({String? note}) => MembershipApplication(
          note: note,
          ageYears: user.ageAt(DateTime(2026, 1, 2)),
          gender: user.gender,
          locationLabel: user.geo.areaLabel,
          playerCode: user.playerCode,
          sports: const [ApplicantSport(sportId: 'cricket', matchesPlayed: 12)],
          submittedAt: DateTime(2026, 1, 2),
        );

    test('survives a round trip through Firestore\'s shape', () {
      final wire = build(note: 'Just moved here.').toMap();
      final back = MembershipApplication.fromMap(
        wire.map((k, v) => MapEntry(k, v as dynamic)),
      );

      expect(back.note, 'Just moved here.');
      expect(back.ageYears, 26);
      expect(back.gender, Gender.female);
      expect(back.locationLabel, 'Warangal, Telangana');
      expect(back.playerCode, 'PSOS-4K7M2');
      expect(back.sports.single.sportId, 'cricket');
      expect(back.sports.single.matchesPlayed, 12);
    });

    test('carries no birth date, email or phone', () {
      // What a club needs to decide is what it gets. An identifier that could
      // be used to reach a minor off-platform is not on that list.
      final wire = build().toMap();
      expect(wire.containsKey('dateOfBirth'), isFalse);
      expect(wire.containsKey('email'), isFalse);
      expect(wire.containsKey('phone'), isFalse);
    });

    test('places the applicant by district, never by village', () {
      expect(build().locationLabel, 'Warangal, Telangana');
    });

    test('an application nobody filled in writes nothing at all', () {
      // Rather than a map of six nulls on every membership row.
      expect(MembershipApplication.empty.toMap(), isEmpty);
      expect(MembershipApplication.empty.isEmpty, isTrue);
    });

    test('a membership with no application reads back as the empty one', () {
      expect(MembershipApplication.fromMap(const {}).isEmpty, isTrue);
    });

    test('totals the matches across every sport listed', () {
      const app = MembershipApplication(sports: [
        ApplicantSport(sportId: 'cricket', matchesPlayed: 12),
        ApplicantSport(sportId: 'kabaddi', matchesPlayed: 5),
      ]);
      expect(app.totalMatches, 17);
    });
  });

  group('a directory listing', () {
    final me = AppUser(
      uid: 'u1',
      displayName: 'Asha',
      email: 'asha@example.com',
      dateOfBirth: DateTime(2010, 6, 1),
      gender: Gender.female,
      geo: const GeoLocation(state: 'Telangana', district: 'Warangal'),
    );

    test('publishes district and state, and drops anything finer', () {
      final listing = PlayerListing.refreshedFor(
        me,
        sportIds: const ['cricket'],
        intents: const [PlayerIntent.club],
        // A caller that hands over a village gets it dropped here rather than
        // at the call site, so no screen can publish one by forgetting to.
        geo: const GeoLocation(
          state: 'Telangana',
          district: 'Warangal',
          village: 'Kazipet',
          pincode: '506001',
        ),
        now: DateTime(2026, 1, 1),
      );

      expect(listing.geo.district, 'Warangal');
      expect(listing.geo.state, 'Telangana');
      expect(listing.geo.village, isNull);
      expect(listing.geo.pincode, isNull);
    });

    test('stores no geohash when its owner published no point', () {
      final listing = PlayerListing.refreshedFor(
        me,
        sportIds: const ['cricket'],
        intents: const [],
        geo: const GeoLocation(district: 'Warangal'),
      );
      expect(listing.geohash, isNull);
      expect(listing.hasPoint, isFalse);
    });

    test('stores one when they did', () {
      final listing = PlayerListing.refreshedFor(
        me,
        sportIds: const ['cricket'],
        intents: const [],
        geo: const GeoLocation(district: 'Warangal', lat: 17.98, lng: 79.53),
      );
      expect(listing.geohash, isNotNull);
      expect(listing.hasPoint, isTrue);
    });

    test('recomputes the age band rather than storing a number that ages', () {
      final young = PlayerListing.refreshedFor(
        me,
        sportIds: const ['cricket'],
        intents: const [],
        geo: const GeoLocation(district: 'Warangal'),
        now: DateTime(2024, 1, 1),
      );
      final older = PlayerListing.refreshedFor(
        me,
        sportIds: const ['cricket'],
        intents: const [],
        geo: const GeoLocation(district: 'Warangal'),
        now: DateTime(2032, 1, 1),
      );
      expect(young.ageGroup, AgeGroup.u14);
      expect(older.ageGroup, AgeGroup.u21);
    });

    test('the district is written flat as well as nested, for the query', () {
      final wire = PlayerListing.refreshedFor(
        me,
        sportIds: const ['cricket'],
        intents: const [PlayerIntent.club, PlayerIntent.practice],
        geo: const GeoLocation(state: 'Telangana', district: 'Warangal'),
      ).toMap();

      expect(wire['district'], 'Warangal');
      expect(wire['state'], 'Telangana');
      expect((wire['geo']! as Map)['district'], 'Warangal');
      expect(wire['intents'], ['club', 'practice']);
      expect(wire['updatedAt'], isA<FieldValue>());
    });

    test('an intent nobody recognises is dropped rather than guessed', () {
      expect(PlayerIntent.setFrom(['club', 'nonsense']), [PlayerIntent.club]);
    });
  });

  group('club filtering', () {
    const repo = DiscoveryRepository();

    Organization club(
      String id,
      String name, {
      GeoLocation geo = GeoLocation.empty,
      String? legacyCity,
      int memberCount = 10,
    }) =>
        Organization(
          id: id,
          name: name,
          orgType: OrgType.cityClub,
          visibility: OrgVisibility.public,
          ownerUid: 'owner',
          inviteCode: 'ABC234',
          geo: geo,
          city: legacyCity,
          memberCount: memberCount,
        );

    final clubs = [
      club('a', 'Kazipet Cricket Club',
          geo: const GeoLocation(state: 'Telangana', district: 'Warangal'),
          memberCount: 40),
      club('b', 'Hyderabad Sports Academy',
          geo: const GeoLocation(state: 'Telangana', district: 'Hyderabad'),
          memberCount: 200),
      // Written before GeoLocation existed: its location is in the flat
      // fields only, and a place search still has to find it.
      club('c', 'Old Town Club', legacyCity: 'Warangal', memberCount: 5),
      club('d', 'Nowhere United'),
    ];

    test('matches a district on the modern hierarchy', () {
      final hits = repo.filterClubs(
        clubs,
        const DiscoveryFilters(district: 'warangal'),
      );
      expect(hits.map((o) => o.id), ['a', 'c']);
    });

    test('matches a legacy club that only ever stored a city', () {
      final hits = repo.filterClubs(
        clubs,
        const DiscoveryFilters(district: 'Warangal'),
      );
      expect(hits.map((o) => o.id), contains('c'));
    });

    test('excludes a club that never said where it is', () {
      // Not evidence that it is here. Silence is not a match.
      final hits = repo.filterClubs(
        clubs,
        const DiscoveryFilters(district: 'Warangal'),
      );
      expect(hits.map((o) => o.id), isNot(contains('d')));
    });

    test('matches a name regardless of case', () {
      final hits =
          repo.filterClubs(clubs, const DiscoveryFilters(query: 'ACADEMY'));
      expect(hits.map((o) => o.id), ['b']);
    });

    test('honours a sport set derived from what clubs actually run', () {
      final hits = repo.filterClubs(
        clubs,
        const DiscoveryFilters(sportId: 'cricket'),
        sportOrgIds: {'a', 'b'},
      );
      // Biggest first: a newcomer with no other signal is better served by
      // the club that has people in it.
      expect(hits.map((o) => o.id), ['b', 'a']);
    });

    test('an empty filter set returns everything, biggest first', () {
      final hits = repo.filterClubs(clubs, DiscoveryFilters.none);
      expect(hits.map((o) => o.id), ['b', 'a', 'd', 'c']);
    });
  });

  group('ranking directory hits', () {
    const repo = DiscoveryRepository();

    PlayerListing person(
      String uid, {
      String name = 'Player',
      List<String> sports = const ['cricket'],
      AgeGroup? band,
      Gender? gender,
      List<PlayerIntent> intents = const [],
      double? lat,
      double? lng,
      int matches = 0,
      String? district,
    }) =>
        PlayerListing(
          uid: uid,
          displayName: name,
          sportIds: sports,
          ageGroup: band,
          gender: gender,
          intents: intents,
          matchesPlayed: matches,
          geo: GeoLocation(district: district, lat: lat, lng: lng),
        );

    test('drops anybody outside the radius, and sorts by real distance', () {
      // Warangal ~17.98/79.53; Hanamkonda is a couple of km away, Hyderabad
      // is about 140.
      final hits = repo.rankPlayers(
        [
          person('far', lat: 17.385, lng: 78.486),
          person('near', lat: 17.99, lng: 79.55),
        ],
        const DiscoveryFilters(
          lat: 17.98,
          lng: 79.53,
          useMyLocation: true,
          radius: SearchRadius.city,
        ),
      );

      expect(hits.map((h) => h.listing.uid), ['near']);
      expect(hits.single.distanceKm, isNotNull);
      expect(hits.single.distanceKm! < SearchRadius.city.km, isTrue);
    });

    test('skips a listing with no point when the search is a radius one', () {
      final hits = repo.rankPlayers(
        [person('nopoint')],
        const DiscoveryFilters(lat: 17.98, lng: 79.53, useMyLocation: true),
      );
      expect(hits, isEmpty);
    });

    test('falls back to the fullest record when there is no distance', () {
      final hits = repo.rankPlayers(
        [person('quiet', matches: 2), person('busy', matches: 90)],
        DiscoveryFilters.none,
      );
      expect(hits.map((h) => h.listing.uid), ['busy', 'quiet']);
      expect(hits.first.distanceKm, isNull);
      expect(hits.first.distanceLabel, isNull);
    });

    test('narrows by sport, band, gender and intent together', () {
      final all = [
        person('match',
            sports: ['cricket'],
            band: AgeGroup.u19,
            gender: Gender.female,
            intents: [PlayerIntent.club]),
        person('wrongSport', sports: ['hockey'], band: AgeGroup.u19),
        person('wrongBand', band: AgeGroup.senior),
        person('wrongIntent',
            band: AgeGroup.u19,
            gender: Gender.female,
            intents: [PlayerIntent.coaching]),
      ];
      final hits = repo.rankPlayers(
        all,
        const DiscoveryFilters(
          sportId: 'cricket',
          ageGroup: AgeGroup.u19,
          gender: Gender.female,
          intent: PlayerIntent.club,
        ),
      );
      expect(hits.map((h) => h.listing.uid), ['match']);
    });

    test('matches a typed name or a player code', () {
      final all = [
        person('a', name: 'Asha Reddy'),
        person('b', name: 'Bhavya Rao'),
      ];
      expect(
        repo.rankPlayers(all, const DiscoveryFilters(query: 'reddy'))
            .map((h) => h.listing.uid),
        ['a'],
      );
    });

    test('composes a district with a radius instead of one winning', () {
      final hits = repo.rankPlayers(
        [
          person('here', lat: 17.99, lng: 79.55, district: 'Warangal'),
          person('alsoNear', lat: 17.99, lng: 79.55, district: 'Hanamkonda'),
        ],
        const DiscoveryFilters(
          district: 'Warangal',
          lat: 17.98,
          lng: 79.53,
          useMyLocation: true,
        ),
      );
      expect(hits.map((h) => h.listing.uid), ['here']);
    });

    test('renders a sub-kilometre distance in metres', () {
      final hits = repo.rankPlayers(
        [person('close', lat: 17.9805, lng: 79.5305)],
        const DiscoveryFilters(
            lat: 17.98, lng: 79.53, useMyLocation: true),
      );
      expect(hits.single.distanceLabel, endsWith('m away'));
    });
  });

  group('what reaches Firestore, and what does not', () {
    test('typing does not change the server query', () {
      // The whole reason DiscoveryQuery exists: a search box must not be a
      // network request per keystroke.
      const base = DiscoveryFilters(district: 'Warangal', sportId: 'cricket');
      expect(
        base.serverQuery == base.copyWith(query: 'ash').serverQuery,
        isTrue,
      );
      expect(
        base.serverQuery == base.copyWith(ageGroup: AgeGroup.u19).serverQuery,
        isTrue,
      );
    });

    test('changing the place or the sport does', () {
      const base = DiscoveryFilters(district: 'Warangal', sportId: 'cricket');
      expect(base.serverQuery == base.copyWith(district: 'Khammam').serverQuery,
          isFalse);
      expect(base.serverQuery == base.copyWith(sportId: 'hockey').serverQuery,
          isFalse);
    });

    test('a point that "near me" is switched off for is not sent', () {
      const off = DiscoveryFilters(lat: 17.98, lng: 79.53);
      expect(off.serverQuery.isRadiusSearch, isFalse);
      expect(off.copyWith(useMyLocation: true).serverQuery.isRadiusSearch,
          isTrue);
    });

    test('a filter can be cleared, not only replaced', () {
      const set = DiscoveryFilters(district: 'Warangal', sportId: 'cricket');
      expect(set.copyWith(clearDistrict: true).district, isNull);
      expect(set.copyWith(clearSport: true).sportId, isNull);
    });
  });

  group('a shared link that outlives the sign-in wall', () {
    setUp(PendingDestination.forget);

    test('remembers the invite code, not just the path', () {
      // The query string IS the invite. Remembering `/orgs/join` alone would
      // land the new member on an empty code box.
      PendingDestination.remember('/orgs/join?code=ABC234');
      expect(PendingDestination.take(), '/orgs/join?code=ABC234');
    });

    test('is read once, so it cannot replay on a later sign-in', () {
      PendingDestination.remember('/orgs/join?code=ABC234');
      PendingDestination.take();
      expect(PendingDestination.take(), isNull);
    });

    test('never remembers home or the sign-in screen itself', () {
      PendingDestination.remember(Routes.home);
      expect(PendingDestination.take(), isNull);
      PendingDestination.remember(Routes.signIn);
      expect(PendingDestination.take(), isNull);
    });

    test('signing out drops it', () {
      PendingDestination.remember('/orgs/join?code=ABC234');
      PendingDestination.forget();
      expect(PendingDestination.take(), isNull);
    });
  });
}
