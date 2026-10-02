import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/draw_config.dart';
import 'package:playsphere/core/models/venue.dart';
import 'package:playsphere/core/models/venue_plan.dart';
import 'package:playsphere/domain/draw/season_capacity.dart';

/// "Season hours are ignored by the planner."
///
/// A season set to run 08:00–20:00 had its capacity worked out against the
/// ground's own 06:00–22:00, so the planner costed sixteen-hour days and
/// reported room for matches no scheduler would ever place.
void main() {
  Venue ground() => const Venue(
        id: 'v1',
        orgId: 'o1',
        name: 'PS Test Ground',
        openHour: 6,
        closeHour: 22,
        courts: [Court(id: 'c1', name: 'Court 1')],
      );

  group('the season window bounds an unplanned ground', () {
    test('a 12-hour season day is not costed as the ground\'s 16', () {
      final wide = SeasonCapacity.lineFor(
        venue: ground(),
        plan: VenuePlan(venueId: 'v1'),
        seasonStart: DateTime(2026, 9, 19),
        dayCount: 1,
        defaultMatchMinutes: 60,
        defaultTurnaroundMinutes: 0,
      );
      // 06:00–22:00 at an hour a match.
      expect(wide.computedPerCourtPerDay, 16);

      final bounded = SeasonCapacity.lineFor(
        venue: ground(),
        plan: VenuePlan(venueId: 'v1'),
        seasonStart: DateTime(2026, 9, 19),
        dayCount: 1,
        defaultMatchMinutes: 60,
        defaultTurnaroundMinutes: 0,
        dayStartHour: 8,
        dayEndHour: 20,
      );
      // 08:00–20:00 is twelve hours, and twelve matches — which is what the
      // scheduler will actually place.
      expect(bounded.computedPerCourtPerDay, 12);
    });

    test('sessions typed into the planner are not clipped', () {
      // An evening session that runs past the season's nominal close is a
      // decision an organizer made on purpose.
      final plan = VenuePlan(
        venueId: 'v1',
        sessions: const [
          DaySession(startMinute: 18 * 60, endMinute: 22 * 60, label: 'Evening'),
        ],
      );
      final line = SeasonCapacity.lineFor(
        venue: ground(),
        plan: plan,
        seasonStart: DateTime(2026, 9, 19),
        dayCount: 1,
        defaultMatchMinutes: 60,
        defaultTurnaroundMinutes: 0,
        dayStartHour: 8,
        dayEndHour: 20,
      );
      expect(line.computedPerCourtPerDay, 4);
    });

    test('a ground open outside the season hours entirely offers nothing', () {
      final morningOnly = const Venue(
        id: 'v2',
        orgId: 'o1',
        name: 'Morning Hall',
        openHour: 5,
        closeHour: 8,
        courts: [Court(id: 'c1', name: 'Court 1')],
      );
      final line = SeasonCapacity.lineFor(
        venue: morningOnly,
        plan: VenuePlan(venueId: 'v2'),
        seasonStart: DateTime(2026, 9, 19),
        dayCount: 1,
        defaultMatchMinutes: 60,
        defaultTurnaroundMinutes: 0,
        dayStartHour: 18,
        dayEndHour: 20,
      );
      expect(line.computedPerCourtPerDay, 0);
      expect(line.totalMatchSlots, 0);
    });
  });

  group('which hours the season plays between', () {
    test('the widest window its events ask for', () {
      final hours = SeasonCapacity.hoursOf(const [
        ScheduleConfig(dayStartHour: 9, dayEndHour: 18),
        ScheduleConfig(dayStartHour: 8, dayEndHour: 17),
        ScheduleConfig(dayStartHour: 10, dayEndHour: 20),
      ]);
      expect(hours?.startHour, 8);
      expect(hours?.endHour, 20);
    });

    test('no events narrows nothing', () {
      expect(SeasonCapacity.hoursOf(const []), isNull);
    });
  });
}
