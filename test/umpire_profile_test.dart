import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/geo.dart';
import 'package:playsphere/core/models/umpire_profile.dart';

/// The two fields on an official's listing that nearly went wrong, and the
/// regressions that would put them back.
///
/// Both are about the same thing: a directory is only worth opening if what
/// it says about a person is true, and `UmpireProfile` is the only place that
/// is decided.
void main() {
  group('matchesOfficiated belongs to the server', () {
    test('a client save does not carry the count at all', () {
      // The regression this guards is silent and destructive. `toMap` used to
      // include `matchesOfficiated`, and `registerUmpire` writes it with
      // `SetOptions(merge: true)` — so an official opening the form to tick
      // one more sport wrote back whatever count their client had last read.
      // An edit racing a settled match would quietly undo the increment the
      // server had just made, and nothing anywhere would report it.
      const profile = UmpireProfile(
        uid: 'u1',
        displayName: 'R. Prasad',
        sports: ['cricket'],
        matchesOfficiated: 47,
      );

      expect(profile.toMap().containsKey('matchesOfficiated'), isFalse);
    });

    test('but it is still read back, because the directory ranks on it', () {
      final profile = UmpireProfile.fromMap(const {
        'uid': 'u1',
        'displayName': 'R. Prasad',
        'matchesOfficiated': 47,
      });

      expect(profile.matchesOfficiated, 47);
    });

    test('a listing that has never been counted reads as zero, not null', () {
      // Every profile written before `onMatchSettled` learned to count
      // officials has no such field. It must read as a number the directory
      // can sort on, not as an absence that throws.
      final profile = UmpireProfile.fromMap(const {'uid': 'u1'});

      expect(profile.matchesOfficiated, 0);
    });
  });

  group('district is what a club actually filters on', () {
    test('a saved listing carries a lowercased district key', () {
      // Firestore equality is case-sensitive, so a club typing "nalgonda" and
      // one typing "Nalgonda" must reach the same officials — the same mirror
      // trick `Ground.cityKey` and `GiveNeed.cityKey` use.
      const profile = UmpireProfile(
        uid: 'u1',
        displayName: 'R. Prasad',
        geo: GeoLocation(state: 'Telangana', district: 'Nalgonda'),
      );

      final map = profile.toMap();
      expect(map['districtKey'], 'nalgonda');
      expect((map['geo']! as Map)['district'], 'Nalgonda');
    });

    test('an official who named no district has no key to match on', () {
      const profile = UmpireProfile(uid: 'u1', displayName: 'R. Prasad');

      // Null rather than an empty string: an equality filter on '' would
      // match every unlocated official for a club that searched for nothing,
      // which is the opposite of what an empty district means.
      expect(profile.toMap()['districtKey'], isNull);
    });

    test('the state survives a save, for the government aggregates', () {
      // The registration form only asks for a district, but the account's geo
      // carries more. Dropping the rest on save would degrade the gov cube
      // every time somebody edited their officiating listing.
      const profile = UmpireProfile(
        uid: 'u1',
        displayName: 'R. Prasad',
        geo: GeoLocation(
          state: 'Telangana',
          district: 'Nalgonda',
          mandal: 'Kattangur',
        ),
      );

      final geo = profile.toMap()['geo']! as Map;
      expect(geo['state'], 'Telangana');
      expect(geo['mandal'], 'Kattangur');
    });

    test('geo round-trips through a stored document', () {
      final profile = UmpireProfile.fromMap(const {
        'uid': 'u1',
        'displayName': 'R. Prasad',
        'geo': {'state': 'Telangana', 'district': 'Nalgonda'},
      });

      expect(profile.geo.district, 'Nalgonda');
      expect(profile.geo.state, 'Telangana');
    });
  });
}
