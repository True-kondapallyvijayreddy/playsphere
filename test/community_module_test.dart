import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/announcement.dart';
import 'package:playsphere/core/models/challenge.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/looking_for_post.dart';
import 'package:playsphere/core/models/sub_group.dart';

void main() {
  group('Module A — Clubs & Communities Domain Models & Logic', () {
    test('OrgType supports village and individual entity types', () {
      expect(OrgType.fromWire('village'), equals(OrgType.village));
      expect(OrgType.fromWire('individual'), equals(OrgType.individual));
      expect(OrgType.village.label, contains('Village'));
      expect(OrgType.individual.label, contains('Individual'));
    });

    test('SubGroup models age and gender sub-teams', () {
      const subGroup = SubGroup(
        id: 'sub_1',
        orgId: 'org_1',
        name: 'Under-17 Boys Cricket',
        sportId: 'cricket',
        ageGroup: 'U-17',
        gender: 'male',
        memberUids: ['user_1', 'user_2'],
      );

      final map = subGroup.toCreate();
      expect(map['orgId'], equals('org_1'));
      expect(map['name'], equals('Under-17 Boys Cricket'));
      expect((map['memberUids'] as List).length, equals(2));
    });

    test('Announcement represents pinned club feed notices', () {
      const notice = Announcement(
        id: 'ann_1',
        orgId: 'org_1',
        authorUid: 'user_admin',
        authorName: 'President Rao',
        title: 'Sunday Mandal Tournament',
        content: 'Grounds open at 7 AM. All teams must report by 6:30 AM.',
        isPinned: true,
      );

      final map = notice.toCreate();
      expect(map['title'], equals('Sunday Mandal Tournament'));
      expect(map['isPinned'], isTrue);
    });

    test('Challenge represents cross-club challenges', () {
      final challenge = Challenge(
        id: 'chal_1',
        fromOrgId: 'village_a',
        toOrgId: 'village_b',
        fromOrgName: 'Kondapally XI',
        toOrgName: 'Warangal Tigers',
        sportId: 'cricket',
        status: 'pending',
        proposedSlots: [DateTime.now()],
      );

      expect(challenge.isPending, isTrue);
      expect(challenge.fromOrgName, equals('Kondapally XI'));
      expect(challenge.toOrgName, equals('Warangal Tigers'));
    });

    test('LookingForPost models CricHeroes community requirements', () {
      const post = LookingForPost(
        id: 'post_1',
        authorUid: 'user_1',
        authorName: 'Vijay',
        type: 'umpire',
        sportId: 'cricket',
        description: 'Need certified umpire for Sunday final',
        district: 'Hyderabad',
        mandal: 'Gachibowli',
      );

      final map = post.toCreate();
      expect(map['type'], equals('umpire'));
      expect(map['district'], equals('Hyderabad'));
      expect(map['mandal'], equals('Gachibowli'));
    });
  });
}
