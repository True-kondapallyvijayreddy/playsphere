import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/domain/gov/age_group.dart';
import 'package:playsphere/domain/rating/glicko2.dart';
import 'package:playsphere/domain/scout/talent_board.dart';
import 'package:playsphere/domain/scout/talent_trend.dart';

/// Talent *discovery* — ranking players by how much they have improved,
/// rather than by how good they currently are (§6 of the product vision).
///
/// ## This file is a contract with `functions/talent.js`
///
/// The boards are built server-side, because no client is allowed to read
/// across a district's profiles. That means the scoring formula exists twice:
/// once in `lib/domain/scout/talent_trend.dart` and once in JavaScript. The
/// "cross-implementation contract" group below fixes the exact numbers both
/// must produce. `functions/talent.js` carries the same table in a comment;
/// if either side is changed alone, this file fails.
void main() {
  final now = DateTime.utc(2026, 8, 9);

  DateTime daysAgo(int d) => now.subtract(Duration(days: d));

  RatingTrail trailOf(List<(int, double)> daysAgoAndRating) => RatingTrail([
        for (final (d, r) in daysAgoAndRating)
          RatingSnapshot(rating: r, at: daysAgo(d)),
      ]);

  const settled = Rating(rating: 1600, deviation: 60);
  const unsettled = Rating(rating: 1600, deviation: 200);

  group('RatingTrail.deltaOver', () {
    test('an empty trail says nothing rather than zero-with-confidence', () {
      final d = RatingTrail.empty.deltaOver(RisingSignal.window, now: now);
      expect(d.span, TrendSpan.absent);
      expect(d.matches, 0);
      expect(d.points, 0);
    });

    test('anchors on the last reading BEFORE the window, not the first '
        'inside it', () {
      // 1500 sits outside the 90-day window and is the correct baseline.
      // Anchoring on 1540 instead — the first reading inside — would report
      // +60 and silently discard the first match of the window.
      final trail = trailOf([
        (120, 1500),
        (80, 1540),
        (40, 1570),
        (10, 1600),
      ]);
      final d = trail.deltaOver(RisingSignal.window, now: now);
      expect(d.points, 100);
      expect(d.matches, 3);
      expect(d.span, TrendSpan.full);
    });

    test('a trail that starts inside the window is reported as truncated', () {
      final trail = trailOf([(50, 1500), (20, 1560), (5, 1580)]);
      final d = trail.deltaOver(RisingSignal.window, now: now);
      expect(d.span, TrendSpan.truncated);
      expect(d.points, 80);
      // The baseline reading is itself inside the window, so it must not also
      // be counted as one of the matches that moved the rating away from it.
      expect(d.matches, 2);
    });

    test('a decline is a negative delta, not a floor at zero', () {
      final trail = trailOf([(100, 1700), (30, 1600), (5, 1550)]);
      expect(trail.deltaOver(RisingSignal.window, now: now).points, -150);
    });

    test('an unsorted trail is ordered on decode', () {
      final trail = RatingTrail.fromList([
        {'r': 1600, 't': daysAgo(5).toIso8601String()},
        {'r': 1500, 't': daysAgo(100).toIso8601String()},
        {'r': 1550, 't': daysAgo(40).toIso8601String()},
      ]);
      expect(trail.snapshots.map((s) => s.rating), [1500, 1550, 1600]);
      expect(trail.deltaOver(RisingSignal.window, now: now).points, 100);
    });

    test('a malformed entry costs one data point, never the whole trail', () {
      final trail = RatingTrail.fromList([
        {'r': 1500, 't': daysAgo(100).toIso8601String()},
        {'r': 'not a number', 't': daysAgo(50).toIso8601String()},
        'garbage',
        {'r': 1600},
        {'r': 1600, 't': daysAgo(5).toIso8601String()},
      ]);
      expect(trail.snapshots.length, 2);
      expect(trail.deltaOver(RisingSignal.window, now: now).points, 100);
    });
  });

  group('RisingSignal eligibility', () {
    test('two matches is below the floor even on a huge climb', () {
      // Exactly the single-upset spike the gate exists to keep off a board:
      // 200 points from two results would otherwise top every district.
      final trail = trailOf([(100, 1400), (20, 1500), (5, 1600)]);
      final s = RisingSignal.from(trail: trail, rating: settled, now: now);
      expect(s.delta.matches, 2);
      expect(s.eligible, isFalse);
    });

    test('three matches clears the floor', () {
      final trail = trailOf([(100, 1400), (50, 1450), (20, 1500), (5, 1540)]);
      final s = RisingSignal.from(trail: trail, rating: settled, now: now);
      expect(s.delta.matches, 3);
      expect(s.eligible, isTrue);
    });

    test('a player going backwards is never eligible, however many '
        'matches', () {
      final trail =
          trailOf([(100, 1700), (60, 1650), (40, 1600), (20, 1560), (5, 1500)]);
      final s = RisingSignal.from(trail: trail, rating: settled, now: now);
      expect(s.delta.matches, 4);
      expect(s.score, lessThan(0));
      expect(s.eligible, isFalse);
    });

    test('a high deviation is flagged provisional, not excluded', () {
      final trail = trailOf([(100, 1400), (50, 1450), (20, 1500), (5, 1540)]);
      final s = RisingSignal.from(trail: trail, rating: unsettled, now: now);
      expect(s.eligible, isTrue,
          reason: 'uncertainty is disclosed to the scout, not hidden from '
              'them by dropping the row');
      expect(s.provisional, isTrue);
    });
  });

  group('RisingSignal shrinkage', () {
    test('shrinkage costs a heavy sample little and a thin sample a lot', () {
      // Same +120 climb, different evidence behind it.
      final thin = trailOf([(100, 1480), (30, 1520), (20, 1560), (5, 1600)]);
      final heavy = trailOf([
        (100, 1480),
        for (var i = 0; i < 11; i++) (80 - i * 7, 1480 + (i + 1) * 10.0),
        (2, 1600),
      ]);

      final thinSignal = RisingSignal.from(trail: thin, rating: settled, now: now);
      final heavySignal =
          RisingSignal.from(trail: heavy, rating: settled, now: now);

      expect(thinSignal.delta.points, 120);
      expect(heavySignal.delta.points, 120);
      expect(heavySignal.score, greaterThan(thinSignal.score));
      expect(heavySignal.confidence, greaterThan(0.79));
      expect(thinSignal.confidence, closeTo(0.5, 1e-9));
    });

    test('an unknown climber outranks a known one on the same delta', () {
      // The premise of the whole feature: score depends on the change, never
      // on the level. A 1200-rated player and a 1900-rated player who both
      // gained 90 points over the same four matches must tie exactly.
      final trail = trailOf([(100, 0), (60, 30), (30, 60), (5, 90)]);
      final unknown = RisingSignal.from(
          trail: trail, rating: const Rating(rating: 1200, deviation: 70), now: now);
      final established = RisingSignal.from(
          trail: trail, rating: const Rating(rating: 1900, deviation: 70), now: now);
      expect(unknown.score, established.score);
    });
  });

  group('TeamFormSignal', () {
    test('a quietly dominant club with no trend still scores', () {
      // The vision's village team: 27 of 32, and it was always that good.
      final s = TeamFormSignal.from(
        matchesInWindow: 12,
        winsInWindow: 10,
        lifetimeMatches: 32,
        lifetimeWins: 27,
      );
      expect(s.eligible, isTrue);
      expect(s.momentum, lessThan(0.01),
          reason: 'no upward trend — it was already winning');
      expect(s.score, greaterThan(0.5),
          reason: 'dominance alone must be enough to be found');
    });

    test('a club that has turned a corner scores on momentum', () {
      final s = TeamFormSignal.from(
        matchesInWindow: 8,
        winsInWindow: 6,
        lifetimeMatches: 40,
        lifetimeWins: 10,
      );
      expect(s.momentum, closeTo(0.75 - 0.25, 1e-9));
      expect(s.score, greaterThan(0.5));
    });

    test('a brand-new club ranks on record, never on manufactured '
        'momentum', () {
      // Every match is inside the window, so there is no history to improve
      // on. Falling back to a zero lifetime rate would hand this club a
      // momentum of +1.0 and put it above every established club in India.
      final s = TeamFormSignal.from(
        matchesInWindow: 5,
        winsInWindow: 4,
        lifetimeMatches: 5,
        lifetimeWins: 4,
      );
      expect(s.momentum, 0);
      expect(s.score, closeTo((5 / 7) * 0.8, 1e-9));
    });

    test('a declining club scores below a steady one', () {
      final declining = TeamFormSignal.from(
        matchesInWindow: 6,
        winsInWindow: 1,
        lifetimeMatches: 30,
        lifetimeWins: 24,
      );
      final steady = TeamFormSignal.from(
        matchesInWindow: 6,
        winsInWindow: 3,
        lifetimeMatches: 30,
        lifetimeWins: 15,
      );
      expect(declining.score, lessThan(steady.score));
      expect(declining.momentum, lessThan(0));
    });

    test('two matches is below the floor', () {
      final s = TeamFormSignal.from(
        matchesInWindow: 2,
        winsInWindow: 2,
        lifetimeMatches: 2,
        lifetimeWins: 2,
      );
      expect(s.eligible, isFalse);
    });
  });

  group('TalentBoardKey', () {
    test('round-trips through a document id', () {
      const key = TalentBoardKey(
        sportId: 'kabaddi',
        state: 'telangana',
        district: 'nalgonda',
        ageGroup: AgeGroup.u17,
        audience: BoardAudience.scout,
      );
      expect(key.docId, 'kabaddi__telangana__nalgonda__u17__scout');
      final parsed = TalentBoardKey.parse(key.docId)!;
      expect(parsed.sportId, 'kabaddi');
      expect(parsed.district, 'nalgonda');
      expect(parsed.ageGroup, AgeGroup.u17);
      expect(parsed.audience, BoardAudience.scout);
    });

    test('a national all-ages public board', () {
      const key =
          TalentBoardKey(sportId: 'athletics', audience: BoardAudience.public);
      expect(key.docId, 'athletics___any___any___any__public');
      expect(TalentBoardKey.parse(key.docId)!.scopeLabel, 'All India · All ages');
    });

    test('an unknown audience decodes to the STRICTER one', () {
      // A board written by a newer function than this client understands must
      // never be shown to a wider audience than it was built for.
      final parsed = TalentBoardKey.parse('cricket___any___any___any__future');
      expect(parsed!.audience, BoardAudience.scout);
    });

    test('a district without a state is rejected as incoherent', () {
      expect(TalentBoardKey.parse('cricket___any__nalgonda___any__public'),
          isNull);
    });

    test('a malformed id is rejected rather than half-parsed', () {
      expect(TalentBoardKey.parse('cricket__telangana'), isNull);
      expect(TalentBoardKey.parse('cricket___any___any__u99__public'), isNull);
    });

    test('place names slug consistently so one district is one board', () {
      expect(TalentBoardKey.slug('Nalgonda'), 'nalgonda');
      expect(TalentBoardKey.slug('  nalgonda '), 'nalgonda');
      expect(TalentBoardKey.slug('Rangareddy / Vikarabad'),
          'rangareddy-vikarabad');
      expect(TalentBoardKey.slug(''), kBoardAny);
      expect(TalentBoardKey.slug(null), kBoardAny);
      expect(TalentBoardKey.slug('!!!'), kBoardAny,
          reason: 'a name that slugs to nothing must not produce an empty '
              'id segment, which would break the parser');
    });

    test('scope labels read as a human wrote them', () {
      const state = TalentBoardKey(
        sportId: 'cricket',
        state: 'andhra-pradesh',
        audience: BoardAudience.public,
      );
      expect(state.scopeLabel, 'Andhra Pradesh · All ages');
    });
  });

  group('TalentBoard document', () {
    test('round-trips players and teams', () {
      const key = TalentBoardKey(
        sportId: 'cricket',
        state: 'telangana',
        audience: BoardAudience.public,
      );
      const board = TalentBoard(
        key: key,
        windowDays: 90,
        playerPoolSize: 41,
        teamPoolSize: 6,
        players: [
          RisingPlayerEntry(
            uid: 'u1',
            displayName: 'Asha',
            rank: 1,
            score: 62.5,
            ratingDelta: 100,
            matchesInWindow: 5,
            ageGroupLabel: 'U-17',
            provisional: true,
          ),
        ],
        teams: [
          RisingTeamEntry(
            orgId: 'o1',
            orgName: 'Falcons',
            rank: 1,
            score: 0.9,
            matchesInWindow: 8,
            winsInWindow: 7,
            recentWinRate: 0.875,
            momentum: 0.2,
            tournamentWins: 2,
          ),
        ],
      );

      final decoded = TalentBoard.fromMap(
        board.toMap().cast<String, dynamic>(),
        key.docId,
      )!;
      expect(decoded.players.single.displayName, 'Asha');
      expect(decoded.players.single.provisional, isTrue);
      expect(decoded.teams.single.tournamentWins, 2);
      expect(decoded.playerPoolSize, 41);
      expect(decoded.key.audience, BoardAudience.public);
    });

    test('a row missing its subject is dropped, not rendered blank', () {
      final decoded = TalentBoard.fromMap(
        {
          'players': [
            {'displayName': 'Ghost', 'rank': 1},
            {'uid': 'u2', 'displayName': 'Real', 'rank': 2},
          ],
          'teams': const [],
        },
        'cricket___any___any___any__public',
      )!;
      expect(decoded.players.map((p) => p.displayName), ['Real']);
    });

    test('rows are ordered by rank regardless of stored array order', () {
      final decoded = TalentBoard.fromMap(
        {
          'players': [
            {'uid': 'b', 'rank': 2},
            {'uid': 'a', 'rank': 1},
          ],
        },
        'cricket___any___any___any__public',
      )!;
      expect(decoded.players.map((p) => p.uid), ['a', 'b']);
    });

    test('a board id that cannot be parsed yields no board at all', () {
      expect(TalentBoard.fromMap(const {}, 'nonsense'), isNull);
    });
  });

  group('cross-implementation contract with functions/talent.js', () {
    // These exact numbers are reproduced in a comment in functions/talent.js.
    // Changing the formula on either side without the other fails here.
    test('player scores', () {
      final cases = <(String, List<(int, double)>, double)>[
        // (label, trail, expected score)
        ('4 matches, +120', [(100, 1480), (60, 1520), (30, 1560), (5, 1600)], 60.0),
        ('3 matches, +60', [(100, 1500), (60, 1520), (30, 1540), (5, 1560)], 30.0),
        ('6 matches, +90', [
          (100, 1500),
          (70, 1515),
          (60, 1530),
          (40, 1545),
          (30, 1560),
          (20, 1575),
          (5, 1590),
        ], 60.0),
      ];
      for (final (label, raw, expected) in cases) {
        final s = RisingSignal.from(
          trail: trailOf(raw),
          rating: settled,
          now: now,
        );
        expect(s.score, closeTo(expected, 1e-9), reason: label);
      }
    });

    test('team scores', () {
      expect(
        TeamFormSignal.from(
          matchesInWindow: 8,
          winsInWindow: 6,
          lifetimeMatches: 40,
          lifetimeWins: 10,
        ).score,
        closeTo(0.8 * (0.75 + 0.5), 1e-9),
      );
      expect(
        TeamFormSignal.from(
          matchesInWindow: 12,
          winsInWindow: 10,
          lifetimeMatches: 32,
          lifetimeWins: 27,
        ).score,
        closeTo((12 / 14) * (10 / 12 + (10 / 12 - 27 / 32)), 1e-9),
      );
    });

    test('the trail bound agrees with the server constant', () {
      // functions/index.js TRAIL_LENGTH must equal this. If you change one,
      // change both — a server that keeps fewer snapshots than the client
      // expects silently shortens every measurable window.
      expect(RatingTrail.maxLength, 24);
    });
  });
}
