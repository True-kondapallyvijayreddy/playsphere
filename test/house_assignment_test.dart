import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/organization.dart';
import 'package:playsphere/data/competition_repository.dart';
import 'package:playsphere/domain/tournament/house_roster.dart';

Membership _member(String uid, MemberGrouping g) => Membership(
      uid: uid,
      orgId: 'org',
      role: MembershipRole.member,
      status: MembershipStatus.active,
      displayName: uid,
      grouping: g,
    );

Registration _reg(
  String uid, {
  RegistrationStatus status = RegistrationStatus.confirmed,
  String? houseName,
}) =>
    Registration(
      uid: uid,
      displayName: uid,
      status: status,
      houseName: houseName,
    );

void main() {
  group('HouseAssigner', () {
    const collegeHouses = [
      'ECE — 3rd Year',
      'ECE — 4th Year',
      'CSE — 4th Year',
      'EEE — 1st Year',
    ];

    test('department and year resolve to the exact house', () {
      expect(
        HouseAssigner.assign(
          const MemberGrouping(department: 'ECE', year: 3),
          collegeHouses,
        ),
        'ECE — 3rd Year',
      );
    });

    test('the same department in another year is a different house', () {
      expect(
        HouseAssigner.assign(
          const MemberGrouping(department: 'ECE', year: 4),
          collegeHouses,
        ),
        'ECE — 4th Year',
      );
    });

    test('a student whose exact group is not in the draw is left unplaced', () {
      // CSE 3rd Year is a real student, but this event did not field that
      // group. Guessing "CSE — 4th Year" would put them in the wrong squad.
      expect(
        HouseAssigner.assign(
          const MemberGrouping(department: 'CSE', year: 3),
          collegeHouses,
        ),
        isNull,
      );
    });

    test('the narrower group wins when both would match', () {
      expect(
        HouseAssigner.assign(
          const MemberGrouping(department: 'ECE', year: 3),
          const ['3rd Year', 'ECE — 3rd Year'],
        ),
        'ECE — 3rd Year',
      );
    });

    test('a year-group event places by year alone', () {
      expect(
        HouseAssigner.assign(
          const MemberGrouping(department: 'ECE', year: 3),
          const ['1st Year', '2nd Year', '3rd Year', '4th Year'],
        ),
        '3rd Year',
      );
    });

    test('a school house event places by house', () {
      expect(
        HouseAssigner.assign(
          const MemberGrouping(house: 'Red House', grade: 'Class 8'),
          HouseTemplates.schoolColours,
        ),
        'Red House',
      );
    });

    test('class and section place into a section event', () {
      expect(
        HouseAssigner.assign(
          const MemberGrouping(grade: 'Class 8', section: 'B'),
          const ['Class 8-A', 'Class 8-B', 'Class 8-C'],
        ),
        'Class 8-B',
      );
    });

    test('case and stray spacing do not stop a match', () {
      expect(
        HouseAssigner.assign(
          const MemberGrouping(department: 'ece', year: 3),
          const ['  ECE —  3rd   Year '],
        ),
        '  ECE —  3rd   Year ',
      );
    });

    test('a member with nothing recorded is never guessed at', () {
      expect(
        HouseAssigner.assign(MemberGrouping.empty, collegeHouses),
        isNull,
      );
    });
  });

  group('previewHousePlacement', () {
    const houses = ['ECE — 3rd Year', 'CSE — 4th Year'];

    test('places members and reports everyone it could not', () {
      final preview = CompetitionRepository.previewHousePlacement(
        registrations: [
          _reg('placeable'),
          _reg('no_grouping'),
          _reg('outsider'),
          _reg('hand_placed', houseName: 'CSE — 4th Year'),
        ],
        members: [
          _member('placeable', const MemberGrouping(department: 'ECE', year: 3)),
          _member('no_grouping', MemberGrouping.empty),
          _member('hand_placed', const MemberGrouping(department: 'ECE', year: 3)),
        ],
        houses: houses,
      );

      expect(preview.placements, {'placeable': 'ECE — 3rd Year'});
      expect(preview.unplaced, ['no_grouping']);
      expect(preview.outsiders, ['outsider']);
      // Already in a house on the list — a bulk action does not overrule a
      // decision somebody already made, even a "wrong" one.
      expect(preview.alreadyPlaced, ['hand_placed']);
      expect(preview.total, 4);
    });

    test('an entrant from another club is never placed by our roster', () {
      final preview = CompetitionRepository.previewHousePlacement(
        registrations: [_reg('guest')],
        members: const [],
        houses: houses,
      );

      expect(preview.placements, isEmpty);
      expect(preview.outsiders, ['guest']);
      expect(preview.hasWork, isFalse);
    });

    test('unconfirmed entries are not placed', () {
      final preview = CompetitionRepository.previewHousePlacement(
        registrations: [
          _reg('waiting', status: RegistrationStatus.waitlisted),
          _reg('pending', status: RegistrationStatus.pending),
        ],
        members: [
          _member('waiting', const MemberGrouping(department: 'ECE', year: 3)),
          _member('pending', const MemberGrouping(department: 'ECE', year: 3)),
        ],
        houses: houses,
      );

      expect(preview.placements, isEmpty);
      expect(preview.total, 0);
    });

    test('a stale house that is no longer on the list is re-placed', () {
      // The organizer renamed or removed the house this student sat in. They
      // are not "already placed" — they are pointing at nothing.
      final preview = CompetitionRepository.previewHousePlacement(
        registrations: [_reg('student', houseName: 'Old House')],
        members: [
          _member('student', const MemberGrouping(department: 'ECE', year: 3)),
        ],
        houses: houses,
      );

      expect(preview.placements, {'student': 'ECE — 3rd Year'});
      expect(preview.alreadyPlaced, isEmpty);
    });
  });

  group('MemberGrouping', () {
    test('a blank field in an update leaves the existing value alone', () {
      const existing = MemberGrouping(house: 'Red House', department: 'ECE');
      final updated = existing.copyWith(year: 3);

      expect(updated.house, 'Red House');
      expect(updated.department, 'ECE');
      expect(updated.year, 3);
    });

    test('summary reads as a roster line', () {
      expect(
        const MemberGrouping(
          department: 'ECE',
          year: 3,
          house: 'Red House',
        ).summary,
        'ECE · 3rd Year · Red House',
      );
    });

    test('round-trips through Firestore shape', () {
      const g = MemberGrouping(
        house: 'Red House',
        department: 'ECE',
        year: 3,
        grade: 'Class 8',
        section: 'A',
      );
      final back = MemberGrouping.fromMap(
        g.toMap().map((k, v) => MapEntry(k, v as dynamic)),
      );

      expect(back.house, 'Red House');
      expect(back.department, 'ECE');
      expect(back.year, 3);
      expect(back.grade, 'Class 8');
      expect(back.section, 'A');
    });
  });
}
