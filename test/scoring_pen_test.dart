import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/errors/app_exception.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/data/scoring_service.dart';
import 'package:playsphere/domain/scoring/scoring_plugin.dart';
import 'package:playsphere/domain/scoring/scoring_registry.dart';

/// Exclusive scoring control — "the pen" — and the restart that keeps the
/// score it replaces.
///
/// ## What was actually broken
///
/// `scorerUids` says who MAY score a match. Nothing said who IS scoring, so
/// two eligible people — an umpire and the club admin, or one person on a
/// phone and a tablet — each had a live pad. Both wrote authoritative events
/// into the same sequence numbers, the document-id-is-the-sequence guard let
/// exactly one of each pair survive, and the loser's tap vanished. What the
/// scorer sees is the score moving backwards under their thumb, and no amount
/// of retrying fixes it, because neither write was wrong.
void main() {
  Fixture fixtureWith({
    String? activeScorerUid,
    String? activeScorerDeviceId,
    FixtureStatus status = FixtureStatus.live,
    int lastSeq = 4,
  }) =>
      Fixture(
        id: 'fix',
        orgId: 'org',
        compId: 'comp',
        entrantAId: 'a',
        entrantBId: 'b',
        entrantAName: 'Anand',
        entrantBName: 'Bhavani',
        status: status,
        scoringPluginKey: 'simple_points',
        scorerUids: const ['umpire', 'admin'],
        activeScorerUid: activeScorerUid,
        activeScorerDeviceId: activeScorerDeviceId,
        lastSeq: lastSeq,
        lineupA: const [MatchPlayer(id: 'p1', name: 'Anand')],
        lineupB: const [MatchPlayer(id: 'p2', name: 'Bhavani')],
      );

  group('who may score right now', () {
    test('an unheld pen leaves the old role-based gate in charge', () {
      final f = fixtureWith();
      expect(f.penIsHeld, isFalse);
      expect(
        f.mayScoreNow(uid: 'admin', deviceId: 'dev-1', eligible: true),
        isTrue,
      );
      // Every fixture written before the pen existed has no holder, so this
      // is also the "nothing changes for old matches" case.
      expect(
        f.mayScoreNow(uid: 'stranger', deviceId: 'dev-1', eligible: false),
        isFalse,
      );
    });

    test('a held pen locks out everyone else, the owner included', () {
      final f = fixtureWith(activeScorerUid: 'umpire');
      // 'admin' is on scorerUids AND eligible by role. Before the pen, that
      // was enough — and that is precisely how two live pads happened.
      expect(
        f.mayScoreNow(uid: 'admin', deviceId: 'dev-2', eligible: true),
        isFalse,
      );
      expect(
        f.mayScoreNow(uid: 'umpire', deviceId: 'dev-1', eligible: true),
        isTrue,
      );
    });

    test('an unclaimed device does not lock the holder out', () {
      // The organizer grants the pen before the match; the umpire walks out
      // of signal before their pad ever claims a device. They must still be
      // able to score the whole match.
      final f = fixtureWith(activeScorerUid: 'umpire');
      expect(f.penIsLiveOn('umpire', 'any-device'), isTrue);
      expect(
        f.mayScoreNow(uid: 'umpire', deviceId: 'any-device', eligible: false),
        isTrue,
      );
    });

    test('a claimed device excludes the same person on a second screen', () {
      final f = fixtureWith(
        activeScorerUid: 'umpire',
        activeScorerDeviceId: 'phone',
      );
      expect(f.penIsLiveOn('umpire', 'phone'), isTrue);
      expect(f.penIsLiveOn('umpire', 'tablet'), isFalse);
      expect(
        f.mayScoreNow(uid: 'umpire', deviceId: 'tablet', eligible: true),
        isFalse,
      );
    });

    test('a finished match is nobody\'s to score, pen or no pen', () {
      final f = fixtureWith(
        activeScorerUid: 'umpire',
        status: FixtureStatus.completed,
      );
      expect(
        f.mayScoreNow(uid: 'umpire', deviceId: 'phone', eligible: true),
        isFalse,
      );
    });
  });

  group('the service refuses a write from the wrong hands', () {
    // The rule enforces this too. This exists because of WHERE the rule's
    // answer arrives: a scoring write is deliberately not awaited, so a
    // rejection comes back seconds later — after the local cache applied the
    // action and the pad drew it. The scorer sees the point land and then
    // jump off the board. Refusing locally makes it instant and specific.
    test('a second scorer is rejected before anything is queued', () {
      final service = ScoringService();
      final f = fixtureWith(activeScorerUid: 'umpire');
      expect(
        () => service.submit(
          fixture: f,
          action: const ScoreAction(type: 'point', side: Side.a),
          context: f.scoringContext(),
          byUid: 'admin',
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('the holder is not rejected', () async {
      final service = ScoringService();
      final f = fixtureWith(activeScorerUid: 'umpire');
      // Not awaited to completion — the write path needs Firestore. All this
      // asserts is that it got PAST the pen check, which is the guard under
      // test; a plugin rejection would surface as ValidationException too, so
      // the assertion is deliberately only about the pen message.
      try {
        // `submit` is synchronous now — see its doc comment. Nothing to await.
        service.submit(
          fixture: f,
          action: const ScoreAction(type: 'point', side: Side.a),
          context: f.scoringContext(),
          byUid: 'umpire',
        );
      } catch (e) {
        expect(e.toString(), isNot(contains('scoring control')));
      }
    });
  });

  group('restart keeps the score it replaces', () {
    final plugin = ScoringRegistry.resolve('simple_points');
    final ctx = fixtureWith().scoringContext();

    ScoreAction point(Side side) => ScoreAction(type: 'point', side: side);

    test('a restart resets the projection', () {
      final rebuilt = plugin.rebuild([
        LoggedAction(seq: 1, action: point(Side.a)),
        LoggedAction(seq: 2, action: point(Side.a)),
        LoggedAction(seq: 3, action: point(Side.b)),
        const LoggedAction(
          seq: 4,
          action: ScoreAction(type: ScoringPlugin.restartActionType),
        ),
        LoggedAction(seq: 5, action: point(Side.b)),
      ], ctx);

      expect(rebuilt['a'], 0);
      expect(rebuilt['b'], 1);
    });

    test('undoing the restart brings the old score back exactly', () {
      // The whole reason a restart is a marker and not a wipe: this is the
      // organizer who tapped it by mistake on a forty-minute-old match.
      final log = <LoggedAction>[
        LoggedAction(seq: 1, action: point(Side.a)),
        LoggedAction(seq: 2, action: point(Side.a)),
        LoggedAction(seq: 3, action: point(Side.b)),
        const LoggedAction(
          seq: 4,
          action: ScoreAction(type: ScoringPlugin.restartActionType),
        ),
        const LoggedAction(
          seq: 5,
          action: ScoreAction(
            type: ScoringPlugin.undoActionType,
            payload: {'reversesSeq': 4},
          ),
        ),
      ];

      final rebuilt = plugin.rebuild(log, ctx);
      expect(rebuilt['a'], 2);
      expect(rebuilt['b'], 1);
    });

    test('points scored after a withdrawn restart still count', () {
      final rebuilt = plugin.rebuild([
        LoggedAction(seq: 1, action: point(Side.a)),
        const LoggedAction(
          seq: 2,
          action: ScoreAction(type: ScoringPlugin.restartActionType),
        ),
        LoggedAction(seq: 3, action: point(Side.b)),
        const LoggedAction(
          seq: 4,
          action: ScoreAction(
            type: ScoringPlugin.undoActionType,
            payload: {'reversesSeq': 2},
          ),
        ),
      ], ctx);

      expect(rebuilt['a'], 1);
      expect(rebuilt['b'], 1);
    });
  });
}
