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
import 'package:playsphere/domain/scoring/scoring_registry.dart';
import 'package:playsphere/features/scoring/scoring_screen.dart';

/// Guards the ENDING of a match, on the pad.
///
/// The pad used to announce a result exactly once — a bottom sheet, on the one
/// frame the engine flipped to complete — and then draw nothing at all. Two
/// consequences, both of which put a match in front of a scorer that they
/// could not finish:
///
///  * A scorer who was watching the court, or who backed out and came back,
///    or whose phone restarted, saw a pad with every button gone and no
///    statement anywhere on it that the match had ended.
///  * When the fixture and its own projection disagreed — a protest reopens a
///    finished fixture without touching `scoreState`, and a refused completing
///    write leaves the same split — the engine offered no scoring controls
///    (it is finished) and the finish bar drew nothing (it only draws while a
///    match is unfinished). The result could not be recorded from anywhere,
///    and the match stayed Live for every spectator, permanently.
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

  /// The toss is recorded so the pad renders rather than the pre-match gate —
  /// see the same note in `scoring_undo_test.dart`.
  Fixture fixtureWith({
    required int lastSeq,
    FixtureStatus? status,
    Map<String, dynamic>? scoreState,
  }) =>
      Fixture(
        id: fixtureId,
        tossWonByEntrantId: 'a',
        tossDecision: 'serve',
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
        scoreState: scoreState ?? const {},
        lineupA: const [MatchPlayer(id: 'p1', name: 'Anand')],
        lineupB: const [MatchPlayer(id: 'p2', name: 'Bhavani')],
      );

  /// A real projection of a match Anand has won, produced by the real engine
  /// rather than hand-written — a literal would pin this test to the shape of
  /// badminton's state instead of to the behaviour under test.
  Map<String, dynamic> decidedState() {
    final blank = fixtureWith(lastSeq: 0);
    final ctx = blank.scoringContext();
    final plugin = ScoringRegistry.resolve(blank.scoringPluginKey);
    var state = plugin.initialState(ctx);
    for (var i = 0; i < 200; i++) {
      if (plugin.outcome(state, ctx).isComplete) return state;
      final result = plugin.apply(
        state,
        const ScoreAction(type: 'rally', side: Side.a),
        ctx,
      );
      if (!result.isAccepted) break;
      state = result.state;
    }
    expect(plugin.outcome(state, ctx).isComplete, isTrue,
        reason: 'the engine never decided the match');
    return state;
  }

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

  testWidgets(
      'a decided match the fixture still calls live offers Finish on the pad',
      (tester) async {
    final service = _FakeScoringService();
    await tester.pumpWidget(
      harness(
        // Exactly the state a upheld protest leaves behind: the engine has
        // decided, the fixture says live.
        fixtureWith(lastSeq: 42, scoreState: decidedState()),
        service,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Match over — not recorded yet'), findsOneWidget);
    expect(find.text('Finish match'), findsWidgets);

    // `FilledButton.icon` builds a private subclass, so the press has to be
    // aimed at the public supertype — see the same note in
    // `scoring_undo_test.dart`.
    final finishButton = find
        .ancestor(
          of: find.text('Finish match'),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        )
        .first;
    await tester.ensureVisible(finishButton);
    await tester.pumpAndSettle();
    await tester.tap(finishButton);
    await tester.pumpAndSettle();
    // Confirmed, because an undo does not take a result back.
    expect(find.text('Finish this match?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Finish match').last);
    await tester.pumpAndSettle();

    expect(service.finalizeCalls, 1);
  });

  testWidgets('a recorded result stays stated on the pad, with no Finish',
      (tester) async {
    final service = _FakeScoringService();
    await tester.pumpWidget(
      harness(
        fixtureWith(
          lastSeq: 42,
          status: FixtureStatus.completed,
          scoreState: decidedState(),
        ),
        service,
      ),
    );
    await tester.pumpAndSettle();

    // The winner is named, permanently, not for four seconds.
    expect(find.text('Anand won'), findsWidgets);
    expect(find.text('Match over — not recorded yet'), findsNothing);
    expect(find.text('Finish match'), findsNothing);
    expect(service.finalizeCalls, 0);
  });

  testWidgets('a match still being played is not offered a Finish',
      (tester) async {
    final service = _FakeScoringService();
    await tester.pumpWidget(harness(fixtureWith(lastSeq: 3), service));
    await tester.pumpAndSettle();

    expect(find.text('Match over — not recorded yet'), findsNothing);
    expect(find.text('Finish match'), findsNothing);
  });
}

/// Stands in for the real service so the pad can be driven without Firestore.
class _FakeScoringService extends ScoringService {
  int finalizeCalls = 0;

  @override
  Future<void> reconcileQueue() async {}

  @override
  Fixture finalizeMatch({
    required Fixture fixture,
    required ScoringContext context,
    required String byUid,
  }) {
    finalizeCalls++;
    return fixture.copyWith(status: FixtureStatus.completed);
  }
}
