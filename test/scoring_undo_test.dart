import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/core/models/organization.dart';
import 'package:playsphere/core/permissions/capability.dart';
import 'package:playsphere/core/providers.dart';
import 'package:playsphere/data/scoring_service.dart';
import 'package:playsphere/domain/scoring/scoring_plugin.dart';
import 'package:playsphere/features/scoring/scoring_screen.dart';

/// Guards the UNDO control on the scoring pad.
///
/// CLAUDE.md §2.4 makes reversal the only legal correction, and §6 requires
/// undo to be *visible*. `ScoringService.undo()` was written and tested at the
/// domain level, but nothing in the UI ever called it — the pad shipped with no
/// way to withdraw a mis-tap. That is exactly the class of gap a pure-Dart test
/// suite cannot see, so it is pinned here.
void main() {
  const orgId = 'org_test';
  const compId = 'comp_test';
  const fixtureId = 'fix_test';
  const scorerUid = 'uid_scorer';

  const organization = Organization(
    id: orgId,
    name: 'Test Sports Club',
    orgType: OrgType.school,
    visibility: OrgVisibility.public,
    ownerUid: scorerUid,
    inviteCode: 'ABC234',
  );

  const competition = Competition(
    id: compId,
    orgId: orgId,
    name: 'Test Cup',
    sportId: 'badminton',
    sportName: 'Badminton',
    archetype: CompetitionArchetype.versus,
    entrantType: EntrantType.individual,
    format: CompetitionFormat.knockout,
    status: CompetitionStatus.inProgress,
    category: CompetitionCategory(label: 'Open'),
    scoringPluginKey: 'badminton',
  );

  Fixture fixtureWith({required int lastSeq, FixtureStatus? status}) => Fixture(
        id: fixtureId,
        orgId: orgId,
        compId: compId,
        entrantAId: 'a',
        entrantBId: 'b',
        entrantAName: 'Anand',
        entrantBName: 'Bhavani',
        status: status ?? FixtureStatus.live,
        scoringPluginKey: 'badminton',
        sportId: 'badminton',
        scorerUids: const [scorerUid],
        lastSeq: lastSeq,
        lineupA: const [MatchPlayer(id: 'p1', name: 'Anand')],
        lineupB: const [MatchPlayer(id: 'p2', name: 'Bhavani')],
      );

  Widget harness(Fixture fixture, ScoringService service) {
    final router = GoRouter(
      initialLocation: '/score',
      routes: [
        GoRoute(
          path: '/score',
          builder: (_, __) => const ScoringScreen(
            orgId: orgId,
            compId: compId,
            fixtureId: fixtureId,
          ),
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue(scorerUid),
        scoringServiceProvider.overrideWithValue(service),
        // The banner would otherwise reach through to SharedPreferences.
        pendingScoreEventsProvider.overrideWith((ref) => Stream.value(0)),
        organizationProvider.overrideWith((ref, id) => Stream.value(organization)),
        myCapabilitiesProvider.overrideWith(
          (ref, id) => PermissionMatrix.capabilitiesOf(MembershipRole.owner),
        ),
        competitionProvider.overrideWith((ref, key) => Stream.value(competition)),
        fixtureProvider.overrideWith((ref, key) => Stream.value(fixture)),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  /// `FilledButton.tonalIcon` builds a *private* `FilledButton` subclass, so
  /// `find.byType(FilledButton)` matches nothing — `byType` is exact. Match on
  /// the public supertype instead, or this passes only by accident of styling.
  Finder undoButton() => find.ancestor(
        of: find.text('Undo last'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );

  VoidCallback? undoPressed(WidgetTester tester) =>
      tester.widget<ButtonStyleButton>(undoButton().first).onPressed;

  testWidgets('the pad offers undo once there is something to withdraw',
      (tester) async {
    final service = _FakeScoringService();
    await tester.pumpWidget(harness(fixtureWith(lastSeq: 3), service));
    await tester.pumpAndSettle();

    expect(undoButton(), findsWidgets);
    expect(undoPressed(tester), isNotNull);
  });

  testWidgets('tapping undo withdraws through the service', (tester) async {
    final service = _FakeScoringService();
    await tester.pumpWidget(harness(fixtureWith(lastSeq: 3), service));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Undo last'));
    await tester.pumpAndSettle();

    expect(service.undoCalls, 1);
    // The scorer is told it happened — a silent undo on a ground is
    // indistinguishable from a dead button.
    expect(find.text('Last action withdrawn.'), findsOneWidget);
  });

  testWidgets('undo is unavailable before the first event', (tester) async {
    final service = _FakeScoringService();
    await tester.pumpWidget(harness(fixtureWith(lastSeq: 0), service));
    await tester.pumpAndSettle();

    expect(undoButton(), findsWidgets);
    expect(undoPressed(tester), isNull);
    expect(service.undoCalls, 0);
  });

  testWidgets('a completed match cannot be undone from the pad',
      (tester) async {
    final service = _FakeScoringService();
    await tester.pumpWidget(
      harness(
        fixtureWith(lastSeq: 9, status: FixtureStatus.completed),
        service,
      ),
    );
    await tester.pumpAndSettle();

    expect(undoPressed(tester), isNull);
  });
}

/// Stands in for the real service so the pad can be driven without Firestore
/// or SharedPreferences. Only the methods the screen reaches are overridden.
class _FakeScoringService extends ScoringService {
  int undoCalls = 0;

  @override
  Future<void> reconcileQueue() async {}

  @override
  Future<Fixture> undo({
    required Fixture fixture,
    required ScoringContext context,
    required String byUid,
    int? reversesSeq,
    String? note,
  }) async {
    undoCalls++;
    return fixture;
  }
}
