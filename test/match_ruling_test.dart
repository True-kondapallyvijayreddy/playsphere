import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/domain/scoring/scoring_plugin.dart';
import 'package:playsphere/features/scoring/widgets/pad_chrome.dart';
import 'package:playsphere/features/scoring/widgets/win_celebration.dart';

/// "Match did not play normally" — the half of it that was never wired.
///
/// Every option in that sheet wrote a ruling onto the fixture and stopped.
/// Nothing downstream knew: the pad kept its controls, the next tap recomputed
/// `status` from a projection that has never heard of a walkover and quietly
/// wrote the match back to `live`, a restart left `resultType: abandoned`
/// behind so the replayed match awarded nobody anything, and there was no way
/// at all to take a ruling back off once it was on.
///
/// These pin the model half of that — the part every other layer reads.
void main() {
  Fixture fixture({
    FixtureStatus status = FixtureStatus.live,
    MatchResultType type = MatchResultType.normal,
    int lastSeq = 12,
    String? note,
  }) =>
      Fixture(
        id: 'f1',
        orgId: 'o1',
        compId: 'c1',
        entrantAId: 'a',
        entrantBId: 'b',
        entrantAName: 'Hyderabad Strikers',
        entrantBName: 'Secunderabad Blues',
        status: status,
        resultType: type,
        resultNote: note,
        lastSeq: lastSeq,
      );

  group('what counts as a ruling', () {
    test('the three statuses the engine can never produce are rulings', () {
      // The engine only ever writes `live` and `completed`. Everything else on
      // the enum is somebody's decision, and this is the test that says so —
      // it is the precondition on locking the pad, and on the one security
      // rule that can take a ruling off.
      expect(FixtureStatus.walkover.isDecision, isTrue);
      expect(FixtureStatus.abandoned.isDecision, isTrue);
      expect(FixtureStatus.disputed.isDecision, isTrue);

      expect(FixtureStatus.live.isDecision, isFalse);
      expect(FixtureStatus.scheduled.isDecision, isFalse);
      expect(FixtureStatus.completed.isDecision, isFalse);
    });

    test('a retirement is a ruling even though its status is completed', () {
      // The case the status alone cannot see, and the reason `endedByDecision`
      // consults both fields. A retirement and a straight-games win are both
      // `completed` with a winner; only `resultType` tells them apart, and
      // only the retirement must lock the pad.
      final retired = fixture(
        status: FixtureStatus.completed,
        type: MatchResultType.retired,
      );
      expect(retired.endedByDecision, isTrue);

      final played = fixture(status: FixtureStatus.completed);
      expect(played.endedByDecision, isFalse);
      expect(played.status.acceptsScoring, isFalse,
          reason: 'a played-out match is frozen too — by a different rule');
    });

    test('a live match in progress is not a ruling', () {
      expect(fixture().endedByDecision, isFalse);
    });
  });

  group('what a withdrawal goes back to', () {
    test('a match with events resumes as live', () {
      final abandoned = fixture(
        status: FixtureStatus.abandoned,
        type: MatchResultType.abandoned,
        lastSeq: 40,
      );
      expect(abandoned.statusWithoutDecision, FixtureStatus.live);
    });

    test('a match awarded before a ball was bowled goes back to scheduled', () {
      // A walkover is the common case: awarded from Match Center, on a fixture
      // that never started. Resuming it as `live` would put a match nobody has
      // begun on every live-now list in the app.
      final walkover = fixture(
        status: FixtureStatus.walkover,
        type: MatchResultType.walkover,
        lastSeq: 0,
      );
      expect(walkover.statusWithoutDecision, FixtureStatus.scheduled);
    });
  });

  group('the ruling comes off cleanly', () {
    test('copyWith can clear the note, not only replace it', () {
      // `?? this.resultNote` cannot say "there is no longer a reason on file",
      // so without this a withdrawn abandonment kept explaining itself with
      // "rain stopped play" under a match that went on to be played out.
      final ruled = fixture(
        status: FixtureStatus.abandoned,
        type: MatchResultType.abandoned,
        note: 'Rain — covers on at 15:10',
      );

      final withdrawn = ruled.copyWith(
        status: FixtureStatus.live,
        resultType: MatchResultType.normal,
        clearResultNote: true,
      );

      expect(withdrawn.resultNote, isNull);
      expect(withdrawn.endedByDecision, isFalse);
      expect(withdrawn.status.acceptsScoring, isTrue);
    });

    test('an untouched note survives an ordinary copy', () {
      final ruled = fixture(
        status: FixtureStatus.abandoned,
        type: MatchResultType.abandoned,
        note: 'Rain',
      );
      expect(ruled.copyWith(lastSeq: 41).resultNote, 'Rain');
    });
  });

  group('what a ruling does to the tables', () {
    test('an abandonment awards nothing and rates nobody', () {
      const t = MatchResultType.abandoned;
      expect(t.countsForStandings, isFalse);
      expect(t.countsForRating, isFalse);
    });

    test('a walkover awards the points but moves no rating', () {
      const t = MatchResultType.walkover;
      expect(t.countsForStandings, isTrue);
      expect(t.countsForRating, isFalse);
    });

    test('a retirement is a real result on every axis', () {
      const t = MatchResultType.retired;
      expect(t.countsForStandings, isTrue);
      expect(t.countsForRating, isTrue);
      expect(t.countsForCareerStats, isTrue);
    });

    test('a withdrawn abandonment stops excluding the match', () {
      // The restart bug, stated as the model sees it. `restartMatch` cleared
      // the winner and the completion time and left `resultType` alone, so the
      // replayed match was scored to a proper finish and then awarded nobody
      // anything, with nothing on any screen to say why.
      final replayed = fixture(
        status: FixtureStatus.abandoned,
        type: MatchResultType.abandoned,
      ).copyWith(
        status: FixtureStatus.completed,
        resultType: MatchResultType.normal,
        winnerEntrantId: 'a',
      );
      expect(replayed.countsForStandings, isTrue);
    });
  });

  group('a long label takes the room it needs', () {
    test('digits stay one column', () {
      // The keypad shape is the point for cricket: 0-6 in equal tiles is a
      // layout a thumb learns in one match, and widening "4" would break it.
      for (final label in ['0', '4', '6', 'W', 'NB']) {
        expect(padColumnSpan(label), 1, reason: label);
      }
    });

    test('a phrase gets more columns rather than smaller type', () {
      // The bug: these were forced into one column and the tile shrank 17pt
      // type to about 7pt to make them fit — on a pad held at arm's length in
      // daylight, which is the same as not drawing them.
      expect(padColumnSpan('Wicket'), greaterThan(1));
      expect(padColumnSpan('Technical point'), greaterThan(2));
      expect(
        padColumnSpan('Technical point (defence)'),
        greaterThanOrEqualTo(padColumnSpan('Technical point')),
      );
    });

    test('the span never shrinks as the label grows', () {
      var previous = 0;
      for (final label in ['4', 'Wide', 'Wicket', 'Caught behind', 'Run out at the non-strikers end']) {
        final span = padColumnSpan(label);
        expect(span, greaterThanOrEqualTo(previous), reason: label);
        previous = span;
      }
    });
  });

  group('the pad button stays inside the pad', () {
    testWidgets('a long label wraps instead of running off the screen',
        (tester) async {
      // A `Wrap` lays its children out with UNBOUNDED width, so before the
      // cap this button grew past the edge of the phone and Flutter clipped it
      // with an overflow stripe — a truncated word on the one screen where
      // reading the wrong button is a wrong scoreline.
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ControlDeck(
              groups: [
                ScoreControlGroup(
                  title: 'Wicket',
                  controls: [
                    ScoreControl(
                      action: 'wicket',
                      label: 'Run out at the non-striker’s end',
                    ),
                  ],
                ),
              ],
              enabled: true,
              showShortcuts: false,
              onControl: _ignore,
            ),
          ),
        ),
      );

      // No overflow was reported, and the button is inside the viewport.
      expect(tester.takeException(), isNull);
      final box = tester.getRect(find.byType(PadButton));
      expect(box.width, lessThanOrEqualTo(360));
      expect(box.right, lessThanOrEqualTo(360));
    });
  });

  group('the five seconds after the last point', () {
    testWidgets('names the winner and takes itself away', (tester) async {
      // The moment the app exists for, and the one moment that had no design
      // on it at all: the engine flipped `complete`, the controls swapped for
      // a Reopen, and that was the entire announcement a scorer got.
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          ctx = c;
          return const Scaffold(body: SizedBox());
        }),
      ));

      unawaited(showWinCelebration(
        ctx,
        title: 'Hyderabad Strikers won',
        subtitle: '21-19, 21-15',
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Hyderabad Strikers won'), findsOneWidget);
      expect(find.text('Congratulations!'), findsOneWidget);
      expect(find.text('21-19, 21-15'), findsOneWidget);

      // Still there at four seconds — a scorer looking at the court has to be
      // able to look back and still find it.
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('Hyderabad Strikers won'), findsOneWidget);

      // Gone on its own by five, with nothing to dismiss. The scorer's hands
      // are busy and the next thing they need is the scorecard.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Hyderabad Strikers won'), findsNothing);
    });

    testWidgets('says what kind of ending it was when it was not a normal one',
        (tester) async {
      // A walkover decides a quarter-final and a retirement sends a player
      // through. Announcing them without saying which would state the wrong
      // thing in the loudest way the app has.
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: WinCelebration(
            title: 'Secunderabad Blues won',
            kicker: 'Walkover',
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('WALKOVER'), findsOneWidget);
      expect(find.text('Secunderabad Blues won'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });
  });
}

void _ignore(ScoreControl _) {}
