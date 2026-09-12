import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/organization.dart';
import 'package:playsphere/core/permissions/capability.dart';
import 'package:playsphere/core/providers.dart';
import 'package:playsphere/shared/app_scaffold.dart';
import 'package:playsphere/shared/club_switcher.dart';

/// One club, everywhere, at all times.
///
/// The chip shipped twice before it was right. First it read the SCREEN's
/// club on a club-owned page and the standing selection everywhere else, so
/// it changed as you walked around and no two pages agreed. Then it read the
/// selection only — steady, but now a create form reached through club B's
/// pages was creating for B while the bar said A, which is the same
/// contradiction wearing different clothes.
///
/// What holds now is one rule: **the club you are reading is the club you are
/// in.** Opening one of your own clubs adopts it, so the chip, the
/// dashboard's buttons and every form that writes something all name the same
/// club — and a club you do NOT belong to is browsing, and moves nothing.
///
/// See `CurrentClubController` and `actingOrgIdProvider`.
void main() {
  const orgA = 'org_school';
  const orgB = 'org_academy';

  const school = Organization(
    id: orgA,
    name: 'Nizampet High School',
    orgType: OrgType.school,
    visibility: OrgVisibility.public,
    ownerUid: 'uid_me',
    inviteCode: 'ABC234',
  );

  const academy = Organization(
    id: orgB,
    name: 'Kompally Sports Academy',
    orgType: OrgType.academy,
    visibility: OrgVisibility.unlisted,
    ownerUid: 'uid_other',
    inviteCode: 'XYZ789',
  );

  Membership membership(String orgId) => Membership(
        uid: 'uid_me',
        orgId: orgId,
        role: MembershipRole.member,
        status: MembershipStatus.active,
        displayName: 'Ravi Kumar',
        joinedAt: DateTime(2025, 1, 1),
      );

  /// A club-owned screen — one that passes `orgId` to [AppScaffold] — for a
  /// club that is NOT the selection.
  Widget harness({required String screenOrgId}) {
    final router = GoRouter(
      initialLocation: '/org/$screenOrgId',
      routes: [
        GoRoute(
          path: '/org/:orgId',
          builder: (_, state) => AppScaffold(
            orgId: state.pathParameters['orgId'],
            title: 'Club',
            body: Center(child: Text('AT ${state.uri.path}')),
          ),
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue('uid_me'),
        // Most recently joined first, which is what the selection falls back
        // to: the school is the club this person is acting as.
        myMembershipsProvider.overrideWith(
          (ref) => Stream.value([membership(orgA), membership(orgB)]),
        ),
        organizationProvider.overrideWith(
          (ref, id) => Stream.value(
            switch (id) {
              orgA => school,
              orgB => academy,
              // A club this person has no membership in, for the browsing
              // case — it must not become their club just by being opened.
              _ => const Organization(
                  id: 'org_stranger',
                  name: 'Somebody Elses Club',
                  orgType: OrgType.cityClub,
                  visibility: OrgVisibility.public,
                  ownerUid: 'uid_stranger',
                  inviteCode: 'QQQ111',
                ),
            },
          ),
        ),
        myCapabilitiesProvider.overrideWith(
          (ref, id) => PermissionMatrix.capabilitiesOf(MembershipRole.member),
        ),
        incomingChallengesProvider.overrideWith(
          (ref, id) => const AsyncValue.data([]),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> pump(WidgetTester tester, Widget widget) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(widget);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('opening your own club adopts it, so the bar and body agree',
      (tester) async {
    // The selection starts on the school — most recently joined, the
    // fallback when nothing has been chosen. The screen is the academy's.
    await pump(tester, harness(screenOrgId: orgB));

    // Reading the academy IS being in the academy. Anything started from here
    // — an event, a season, a quick match — is created for the club the bar
    // names, because there is now only one club to name.
    expect(
      find.descendant(
        of: find.byType(ClubChip),
        matching: find.text('Kompally Sports Academy'),
      ),
      findsOneWidget,
    );
    expect(find.text('Nizampet High School'), findsNothing);
  });

  testWidgets('a club you do not belong to moves nothing', (tester) async {
    // Browsing a public club page is not joining it. The selection stays put,
    // which is also what stops a shared link from quietly reassigning
    // somebody to a club they have never been a member of.
    await pump(tester, harness(screenOrgId: 'org_stranger'));

    expect(
      find.descendant(
        of: find.byType(ClubChip),
        matching: find.text('Nizampet High School'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('switching from a club screen moves the app and the screen',
      (tester) async {
    await pump(tester, harness(screenOrgId: orgA));

    await tester.tap(
      find.descendant(
        of: find.byType(ClubChip),
        matching: find.text('Nizampet High School'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kompally Sports Academy').last);
    await tester.pumpAndSettle();

    // The selection moved, and because the screen underneath belonged to a
    // club, it moved with it — leaving the bar and the body naming two
    // different clubs is the confusion this whole chip exists to end.
    expect(
      find.descendant(
        of: find.byType(ClubChip),
        matching: find.text('Kompally Sports Academy'),
      ),
      findsOneWidget,
    );
    expect(find.text('AT /org/$orgB'), findsOneWidget);
  });
}
