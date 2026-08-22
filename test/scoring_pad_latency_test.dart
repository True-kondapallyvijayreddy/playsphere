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

/// Pins the two properties that make the pad usable on a ground: a tap lands
/// NOW, and a burst of taps does not fight itself.
///
/// ## The bugs these are here for
///
/// The pad rendered straight from the fixture's Firestore listener and threw
/// away the projection `submit` returned. Two things followed, and scorers
/// reported both as one symptom ("the buttons are slow and the score jumps"):
///
///  1. **Latency.** The score did not move when the scorer tapped. It moved
///     when the local Firestore write echoed back through the snapshot
///     stream — after an awaited `SharedPreferences` write whose cost grew
///     with the length of the match, and with every control disabled behind
///     `_busy` for the duration.
///  2. **Collisions.** The second tap of a burst was handed the same stale
///     fixture as the first, so both computed `lastSeq + 1` from the same
///     `lastSeq`. The event document id IS the sequence number, so one of
///     them lost, was rolled back, and the score visibly snapped backwards.
///
/// The fixture stream in this harness is a `Stream.value` — it emits ONCE and
/// never again. That is the whole point: everything asserted below has to
/// come from the pad's own projection, because there is no second snapshot
/// coming. A regression that reintroduces the round trip cannot pass.
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

  /// Singles, and with the toss already recorded.
  ///
  /// Singles matters: the pad fills the rally winner in without asking, so a
  /// point is one tap with no picker in the way — which is the path these
  /// tests are about. Doubles opens a modal first, and a modal is a decision,
  /// not latency.
  Fixture liveFixture() => const Fixture(
        id: fixtureId,
        tossWonByEntrantId: 'a',
        tossDecision: 'serve',
        orgId: orgId,
        compId: compId,
        entrantAId: 'a',
        entrantBId: 'b',
        entrantAName: 'Anand',
        entrantBName: 'Bhavani',
        status: FixtureStatus.live,
        scoringPluginKey: 'badminton',
        sportId: 'badminton',
        scorerUids: [scorerUid],
        lastSeq: 0,
        lineupA: [MatchPlayer(id: 'p1', name: 'Anand')],
        lineupB: [MatchPlayer(id: 'p2', name: 'Bhavani')],
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
        pendingScoreEventsProvider.overrideWith((ref) => Stream.value(0)),
        organizationProvider.overrideWith((ref, id) => Stream.value(organization)),
        myCapabilitiesProvider.overrideWith(
          (ref, id) => PermissionMatrix.capabilitiesOf(MembershipRole.owner),
        ),
        competitionProvider.overrideWith((ref, key) => Stream.value(competition)),
        // Emits once. Nothing the pad shows after the first frame can have
        // come from here.
        fixtureProvider.overrideWith((ref, key) => Stream.value(fixture)),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Finder undoButton() => find.ancestor(
        of: find.text('Undo last'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );

  /// Whether the pad believes anything has been scored yet.
  ///
  /// Used as the probe instead of reading a number off the scoreboard so the
  /// assertion does not depend on how a badminton score is laid out — undo is
  /// enabled exactly when `lastSeq > 0`, which is the projection state under
  /// test.
  bool undoEnabled(WidgetTester tester) =>
      tester.widget<ButtonStyleButton>(undoButton().first).onPressed != null;

  /// Taps the half of the duel pad that awards a rally to Anand.
  ///
  /// The rally sports render a `DuelPad`, whose two targets are `InkWell`s
  /// filling half the screen each rather than buttons, and whose labels are
  /// upper-cased for legibility at arm's length — hence 'ANAND'.
  Future<void> scoreForA(WidgetTester tester) async {
    final control = find
        .ancestor(
          of: find.text('ANAND'),
          matching: find.byType(InkWell),
        )
        .first;
    await tester.tap(control);
  }

  testWidgets('a tap shows on the pad in the same frame, with no snapshot back',
      (tester) async {
    final service = _RecordingScoringService();
    await tester.pumpWidget(harness(liveFixture(), service));
    await tester.pumpAndSettle();

    expect(undoEnabled(tester), isFalse, reason: 'nothing scored yet');

    await scoreForA(tester);
    // ONE pump. Not `pumpAndSettle`, which would hide a repaint that only
    // happens after a future resolves — the exact defect this pins.
    await tester.pump();

    expect(service.calls, hasLength(1));
    expect(
      undoEnabled(tester),
      isTrue,
      reason: 'the pad must render its own projection, not wait for Firestore',
    );
  });

  testWidgets('a burst of taps takes consecutive sequence numbers',
      (tester) async {
    final service = _RecordingScoringService();
    await tester.pumpWidget(harness(liveFixture(), service));
    await tester.pumpAndSettle();

    // Four rallies as fast as the pad will take them, with only a frame
    // between — which is faster than any snapshot could come back even on
    // good signal, and is what a badminton rally actually looks like.
    for (var i = 0; i < 4; i++) {
      await scoreForA(tester);
      await tester.pump();
    }

    expect(service.calls, hasLength(4),
        reason: 'no tap may be swallowed by a busy flag');
    expect(
      service.calls.map((c) => c.lastSeq).toList(),
      [0, 1, 2, 3],
      reason: 'each tap must fold onto the previous one, not onto the stale '
          'fixture from the listener — two taps claiming the same sequence '
          'number is what made the score jump backwards',
    );
  });
}

/// Records what the pad asked for and answers with the real projection.
///
/// Deliberately runs the genuine plugin rather than returning a canned
/// fixture: the point of the burst test is that the pad accumulates a real
/// score across taps, and a fake that just incremented `lastSeq` would pass
/// while the actual arithmetic was being thrown away.
class _RecordingScoringService extends ScoringService {
  final List<Fixture> calls = <Fixture>[];

  @override
  Future<void> reconcileQueue() async {}

  @override
  Fixture submit({
    required Fixture fixture,
    required ScoreAction action,
    required ScoringContext context,
    required String byUid,
  }) {
    calls.add(fixture);
    final plugin = ScoringRegistry.resolve(fixture.scoringPluginKey);
    final result = plugin.apply(fixture.scoreState, action, context);
    return fixture.copyWith(
      scoreState: result.state,
      lastSeq: fixture.lastSeq + 1,
      summary: plugin.summary(result.state, context),
    );
  }
}
