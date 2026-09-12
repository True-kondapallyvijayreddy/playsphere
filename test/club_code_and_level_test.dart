import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/organization.dart';
import 'package:playsphere/core/providers.dart';
import 'package:playsphere/domain/rating/glicko2.dart';
import 'package:playsphere/domain/rating/overall_glicko.dart';
import 'package:playsphere/features/profile/widgets/level_board.dart';
import 'package:playsphere/shared/club_id_chip.dart';

/// Two things this covers, and why they belong in one file: they are the two
/// halves of "the profile is about the person, the club list is about the
/// clubs". The level board is what the account panel shows instead of a club
/// list; the code chip is what the club list shows instead of a document id.
void main() {
  const club = Organization(
    id: 'org_tcs',
    name: 'TCS Sports',
    orgType: OrgType.corporate,
    visibility: OrgVisibility.public,
    ownerUid: 'uid_owner',
    inviteCode: 'TCS482',
    memberCount: 31,
  );

  Membership membership(MembershipStatus status) => Membership(
        uid: 'uid_me',
        orgId: club.id,
        role: MembershipRole.member,
        status: status,
        displayName: 'Ravi Kumar',
        joinedAt: DateTime(2025, 1, 1),
      );

  Future<void> pumpChip(
    WidgetTester tester, {
    required List<Membership> memberships,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myMembershipsProvider.overrideWith((ref) => Stream.value(memberships)),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Center(child: ClubIdChip(org: club, compact: true)),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('the code beside a club name', () {
    testWidgets('a member sees the invite code, not the document id',
        (tester) async {
      await pumpChip(tester, memberships: [membership(MembershipStatus.active)]);

      expect(find.text('TCS482'), findsOneWidget);
      expect(find.text(club.clubCodeLabel), findsNothing);
    });

    testWidgets('somebody who has not joined sees the club id', (tester) async {
      await pumpChip(tester, memberships: const []);

      expect(find.text(club.clubCodeLabel), findsOneWidget);
      expect(find.text('TCS482'), findsNothing);
    });

    testWidgets('waiting for approval is not membership', (tester) async {
      // A pending applicant has not been handed the club's door, so they must
      // not be handed the key that opens it for other people either.
      await pumpChip(
        tester,
        memberships: [membership(MembershipStatus.pending)],
      );

      expect(find.text('TCS482'), findsNothing);
    });

    testWidgets('tapping the code opens the QR, big enough to scan',
        (tester) async {
      await pumpChip(tester, memberships: [membership(MembershipStatus.active)]);

      await tester.tap(find.text('TCS482'));
      await tester.pumpAndSettle();

      expect(find.text('Invite code'), findsOneWidget);
      expect(find.text('TCS Sports'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Copy link'), findsOneWidget);
    });
  });

  group('PlayerLevel', () {
    OverallGlicko at(double rating, {double evidence = 1}) => OverallGlicko(
          overall: rating,
          evidenceWeight: evidence,
          effectiveMatches: 40,
          components: const [
            OverallGlickoComponent(
              sportId: 'cricket',
              rating: 1700,
              confidence: 1,
              recency: 1,
              rankFactor: 1,
              matches: 40,
            ),
          ],
        );

    test('the level is the tier the rest of the app already speaks', () {
      // If these ever disagree, a player is Level 4 on their own panel and
      // "Strong" on the roster beside their name — one ladder, two names.
      for (final rating in [1100.0, 1300.0, 1500.0, 1700.0, 1900.0, 2100.0]) {
        expect(
          PlayerLevel.of(at(rating)).name,
          Rating(rating: rating).tier,
          reason: 'rating $rating',
        );
      }
    });

    test('the bar measures position inside the band, not on the whole scale',
        () {
      // 1700 is halfway through Strong (1600–1800), not 70% of the way up the
      // ladder — a bar that filled by absolute rating would sit near-full for
      // a mid-table player and never visibly move.
      final level = PlayerLevel.of(at(1700));
      expect(level.name, 'Strong');
      expect(level.number, 4);
      expect(level.progress, closeTo(0.5, 0.001));
      expect(level.pointsToNext, 100);
      expect(level.nextLabel, '100 to District');
    });

    test('one point into a band reads as the bottom of it', () {
      final level = PlayerLevel.of(at(1601));
      expect(level.name, 'Strong');
      expect(level.progress, closeTo(0.005, 0.001));
    });

    test('the top band has no next rung to promise', () {
      final level = PlayerLevel.of(at(2350));
      expect(level.number, 7);
      expect(level.name, 'Elite');
      expect(level.pointsToNext, isNull);
      expect(level.progress, 1);
      expect(level.nextLabel, 'Top level reached');
    });

    test('a rating past the top of the ladder does not overflow the bar', () {
      final level = PlayerLevel.of(at(2600));
      expect(level.number, 7);
      expect(level.progress, 1);
    });

    test('nobody rated yet starts on the ladder rather than off it', () {
      expect(PlayerLevel.of(null).number, 1);
      expect(PlayerLevel.of(null).progress, 0);
      expect(
        PlayerLevel.of(null).caption(null),
        'Play a rated match and your level starts climbing.',
      );
    });

    test('a settling rating says so instead of stating a level flatly', () {
      final level = PlayerLevel.of(at(1700, evidence: 0.3));
      expect(level.provisional, isTrue);
      expect(level.caption(at(1700, evidence: 0.3)), contains('Still settling'));
    });
  });
}
