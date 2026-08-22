import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/domain/tournament/house_roster.dart';

void main() {
  group('HouseRoster.plan', () {
    test('a clean list saves with nothing to migrate', () {
      final plan = HouseRoster.plan(
        drafts: HouseRoster.draftsFrom(const ['Red House', 'Blue House']),
        current: const ['Red House', 'Blue House'],
      );

      expect(plan.isValid, isTrue);
      expect(plan.names, ['Red House', 'Blue House']);
      expect(plan.renames, isEmpty);
      expect(plan.removed, isEmpty);
      expect(plan.touchesEntries, isFalse);
    });

    test('renaming a house carries its registrations, not deletes them', () {
      final drafts = HouseRoster.draftsFrom(const ['Red Hosue', 'Blue House']);
      drafts.first.name = 'Red House';

      final plan = HouseRoster.plan(
        drafts: drafts,
        current: const ['Red Hosue', 'Blue House'],
      );

      expect(plan.isValid, isTrue);
      expect(plan.names, ['Red House', 'Blue House']);
      // The whole point: the old name is a rename, NOT a removal, so the
      // students who entered under the typo move with it.
      expect(plan.renames, {'Red Hosue': 'Red House'});
      expect(plan.removed, isEmpty);
    });

    test('a house that is dropped is reported as removed', () {
      final drafts = HouseRoster.draftsFrom(
        const ['Red House', 'Blue House', 'Green House'],
      )..removeWhere((d) => d.originalName == 'Green House');

      final plan = HouseRoster.plan(
        drafts: drafts,
        current: const ['Red House', 'Blue House', 'Green House'],
      );

      expect(plan.removed, ['Green House']);
      expect(plan.renames, isEmpty);
      expect(plan.touchesEntries, isTrue);
    });

    test('a rename and a removal in the same save stay separate', () {
      final drafts = HouseRoster.draftsFrom(
        const ['ECE — 1st Year', 'CSE — 1st Year', 'EEE — 1st Year'],
      );
      drafts[0].name = 'ECE — 2nd Year';
      drafts.removeWhere((d) => d.originalName == 'EEE — 1st Year');

      final plan = HouseRoster.plan(
        drafts: drafts,
        current: const ['ECE — 1st Year', 'CSE — 1st Year', 'EEE — 1st Year'],
      );

      expect(plan.renames, {'ECE — 1st Year': 'ECE — 2nd Year'});
      expect(plan.removed, ['EEE — 1st Year']);
    });

    test('duplicate names are refused — a student picks a house by reading it',
        () {
      final drafts = HouseRoster.draftsFrom(const ['Red House', 'Blue House']);
      drafts[1].name = 'red house';

      final plan = HouseRoster.plan(
        drafts: drafts,
        current: const ['Red House', 'Blue House'],
      );

      expect(plan.isValid, isFalse);
      expect(plan.error, contains('red house'));
    });

    test('a half-typed blank row is dropped, not treated as an error', () {
      final drafts = HouseRoster.draftsFrom(const ['Red House', 'Blue House'])
        ..add(HouseDraft.fresh('   '));

      final plan = HouseRoster.plan(
        drafts: drafts,
        current: const ['Red House', 'Blue House'],
      );

      expect(plan.isValid, isTrue);
      expect(plan.names, ['Red House', 'Blue House']);
    });

    test('fewer than two houses cannot make a draw', () {
      final plan = HouseRoster.plan(
        drafts: HouseRoster.draftsFrom(const ['Red House']),
        current: const ['Red House'],
      );

      expect(plan.isValid, isFalse);
      expect(plan.error, contains('at least 2'));
    });

    test('names are trimmed before they reach the competition', () {
      final drafts = [
        HouseDraft.fresh('  ECE — 3rd Year  '),
        HouseDraft.fresh('CSE — 4th Year'),
      ];

      final plan = HouseRoster.plan(drafts: drafts, current: const []);

      expect(plan.names, ['ECE — 3rd Year', 'CSE — 4th Year']);
    });

    test('a new row replacing a deleted one does not inherit its members', () {
      final drafts = HouseRoster.draftsFrom(const ['Red House', 'Blue House'])
        ..removeAt(0)
        ..insert(0, HouseDraft.fresh('Red House'));

      final plan = HouseRoster.plan(
        drafts: drafts,
        current: const ['Red House', 'Blue House'],
      );

      // Same name, but the organizer deleted and retyped rather than edited.
      // Nothing is renamed and nothing is removed — the name survives, so the
      // registrations pointing at it are still valid.
      expect(plan.names, ['Red House', 'Blue House']);
      expect(plan.renames, isEmpty);
      expect(plan.removed, isEmpty);
    });
  });

  group('HouseTemplates', () {
    test('departments cross with years the way a college meet splits', () {
      expect(
        HouseTemplates.departmentYears(
          departments: ['ECE', 'CSE'],
          years: [3, 4],
        ),
        ['ECE — 3rd Year', 'ECE — 4th Year', 'CSE — 3rd Year', 'CSE — 4th Year'],
      );
    });

    test('blank departments are skipped rather than producing "— 1st Year"', () {
      expect(
        HouseTemplates.departmentYears(
          departments: ['ECE', '  ', ''],
          years: [1],
        ),
        ['ECE — 1st Year'],
      );
    });

    test('sections letter through the alphabet', () {
      expect(
        HouseTemplates.sections(grade: 'Class 8', count: 3),
        ['Class 8-A', 'Class 8-B', 'Class 8-C'],
      );
    });

    test('an empty grade still produces usable names', () {
      expect(HouseTemplates.sections(grade: '  ', count: 2),
          ['Class-A', 'Class-B']);
    });

    test('ordinals are right where English is irregular', () {
      expect(
        [1, 2, 3, 4, 11, 12, 13, 21, 22, 23].map(HouseTemplates.ordinal).toList(),
        ['1st', '2nd', '3rd', '4th', '11th', '12th', '13th', '21st', '22nd', '23rd'],
      );
    });
  });
}
