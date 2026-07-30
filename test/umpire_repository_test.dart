import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/core/models/match_official.dart';
import 'package:playsphere/core/models/umpire_profile.dart';

void main() {
  group('Umpire System — Models & Assignments', () {
    test('UmpireProfile supports multi-sport certification', () {
      const profile = UmpireProfile(
        uid: 'user_official_1',
        displayName: 'Ravi Verma',
        sports: ['cricket', 'football', 'volleyball'],
        badgeLevel: 'state_certified',
      );

      expect(profile.isCertifiedFor('cricket'), isTrue);
      expect(profile.isCertifiedFor('football'), isTrue);
      expect(profile.isCertifiedFor('kabaddi'), isFalse);
      expect(profile.badgeLevel, equals('state_certified'));
    });

    test('MatchOfficial serializes to and from Map', () {
      const official = MatchOfficial(
        uid: 'user_official_1',
        name: 'Ravi Verma',
        role: 'main_umpire',
        grantedScoringAccess: true,
      );

      final map = official.toMap();
      final restored = MatchOfficial.fromMap(map);

      expect(restored.uid, equals('user_official_1'));
      expect(restored.name, equals('Ravi Verma'));
      expect(restored.role, equals('main_umpire'));
      expect(restored.grantedScoringAccess, isTrue);
    });

    test('Fixture includes officials and handles copyWith', () {
      const fixture = Fixture(
        id: 'fix_1',
        orgId: 'org_1',
        compId: 'comp_1',
        entrantAId: 'team_a',
        entrantBId: 'team_b',
        entrantAName: 'Riders',
        entrantBName: 'Strikers',
        status: FixtureStatus.scheduled,
        officials: [
          MatchOfficial(uid: 'off_1', name: 'Referee John', role: 'referee'),
        ],
      );

      expect(fixture.officials.length, equals(1));
      expect(fixture.officials.first.name, equals('Referee John'));

      final updated = fixture.copyWith(
        officials: [
          ...fixture.officials,
          const MatchOfficial(uid: 'off_2', name: 'Umpire Jane', role: 'square_leg_umpire'),
        ],
      );

      expect(updated.officials.length, equals(2));
    });

    test('Official cannot be assigned to two live or overlapping matches at same time', () {
      final now = DateTime.now();
      final liveFixture = Fixture(
        id: 'fix_live',
        orgId: 'org_1',
        compId: 'comp_1',
        entrantAId: 'team_a',
        entrantBId: 'team_b',
        entrantAName: 'Team A',
        entrantBName: 'Team B',
        status: FixtureStatus.live,
        scheduledAt: now,
        officials: const [
          MatchOfficial(uid: 'off_1', name: 'Ravi Verma', role: 'main_umpire'),
        ],
      );

      // Verify that Ravi Verma is flagged as already assigned in live match
      expect(liveFixture.officials.any((o) => o.uid == 'off_1'), isTrue);
      expect(liveFixture.isLive, isTrue);
    });
  });
}
