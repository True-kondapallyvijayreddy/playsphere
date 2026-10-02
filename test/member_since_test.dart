import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/organization.dart';
import 'package:playsphere/shared/member_since.dart';

void main() {
  final now = DateTime(2026, 9, 14, 12);

  group('tenure', () {
    test('same day', () {
      expect(clubTenure(DateTime(2026, 9, 14, 8), now: now), 'Joined today');
    });

    test('days under a month', () {
      expect(clubTenure(DateTime(2026, 9, 13, 20), now: now), '1 day');
      expect(clubTenure(DateTime(2026, 8, 20), now: now), '25 days');
    });

    test('calendar months, not 30-day blocks', () {
      expect(clubTenure(DateTime(2026, 8, 15), now: now), '30 days');
      expect(clubTenure(DateTime(2026, 8, 14), now: now), '1 mo');
      expect(clubTenure(DateTime(2026, 1, 31), now: DateTime(2026, 3, 2)),
          '1 mo');
    });

    test('years and months', () {
      expect(clubTenure(DateTime(2025, 9, 14), now: now), '1 yr');
      expect(clubTenure(DateTime(2024, 3, 1), now: now), '2 yrs 6 mos');
      expect(clubTenure(DateTime(2025, 8, 1), now: now), '1 yr 1 mo');
    });

    test('a clock running slightly ahead on the server is today', () {
      expect(clubTenure(DateTime(2026, 9, 14, 12, 1), now: now), 'Joined today');
    });

    test('label', () {
      expect(memberSinceLabel(DateTime(2024, 3, 1), now: now),
          'Member since Mar 2024 · 2 yrs 6 mos');
    });
  });

  group('memberSince', () {
    Membership row({
      MembershipStatus status = MembershipStatus.active,
      DateTime? joinedAt,
      DateTime? decidedAt,
    }) =>
        Membership(
          uid: 'u',
          orgId: 'o',
          role: MembershipRole.member,
          status: status,
          displayName: 'P',
          joinedAt: joinedAt,
          decidedAt: decidedAt,
        );

    test('an approved member counts from approval, not application', () {
      final m = row(
        joinedAt: DateTime(2026, 1, 1),
        decidedAt: DateTime(2026, 1, 15),
      );
      expect(m.memberSince, DateTime(2026, 1, 15));
    });

    test('a direct joiner counts from joining', () {
      expect(row(joinedAt: DateTime(2026, 1, 1)).memberSince,
          DateTime(2026, 1, 1));
    });

    test('a pending applicant is not a member yet', () {
      expect(
        row(status: MembershipStatus.pending, joinedAt: DateTime(2026, 1, 1))
            .memberSince,
        isNull,
      );
    });
  });
}
