import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firebase/firestore_refs.dart';
import '../core/models/sport_rule.dart';

/// Manages official rules and regulations for all sports (ICC, FIFA, FIBA, PKL, BWF, FIDE).
class SportRuleRepository {
  const SportRuleRepository({FirebaseFirestore? firestore}) : _db = firestore;

  final FirebaseFirestore? _db;

  /// Fetches or streams rules filtered by sport and search query.
  Stream<List<SportRule>> watchRules({
    String? sportId,
    String? searchQuery,
  }) {
    Stream<List<SportRule>> rawStream;
    try {
      if (_db == null) {
        rawStream = Stream.value(_seedRules);
      } else {
        rawStream = Refs.sportRules.snapshots().map((snap) {
          final list = snap.docs
              .map((d) => SportRule.fromDoc(d.data(), d.id))
              .toList();
          return list.isEmpty ? _seedRules : list;
        });
      }
    } catch (_) {
      rawStream = Stream.value(_seedRules);
    }

    return rawStream.map((list) {
      var filtered = list;
      if (sportId != null && sportId.isNotEmpty && sportId != 'all') {
        filtered = filtered.where((r) => r.sportId == sportId).toList();
      }

      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final q = searchQuery.trim().toLowerCase();
        filtered = filtered.where((r) {
          return r.title.toLowerCase().contains(q) ||
              r.description.toLowerCase().contains(q) ||
              r.officialSource.toLowerCase().contains(q) ||
              r.category.toLowerCase().contains(q) ||
              r.keywords.any((k) => k.toLowerCase().contains(q));
        }).toList();
      }

      return filtered;
    });
  }

  /// Official pre-populated rules knowledgebase seed (ICC, FIFA, FIBA, PKL, BWF, FIDE, ITF, ITTF, FIH).
  static const List<SportRule> _seedRules = [
    // CRICKET (ICC Laws)
    SportRule(
      id: 'cricket_no_ball',
      sportId: 'cricket',
      category: 'Bowling / Illegal Deliveries',
      title: 'No Ball & Free Hit Rule',
      officialSource: 'ICC Law 21.5 & Clause 21.19',
      description:
          'A No Ball is called if the bowler oversteps the popping crease. The batting side is awarded 1 run penalty, and the next delivery MUST be a Free Hit where the batsman can only be dismissed via Run Out, Obstructing the Field, or Hit the Ball Twice.',
      keywords: ['no ball', 'free hit', 'overstep', 'crease', 'bowling', 'penalty'],
    ),
    SportRule(
      id: 'cricket_wide',
      sportId: 'cricket',
      category: 'Bowling / Illegal Deliveries',
      title: 'Wide Ball Rule',
      officialSource: 'ICC Law 22.1',
      description:
          'If the bowler delivers the ball out of reach of the striker where they cannot hit it with a normal cricket stroke, it is judged a Wide. 1 extra run is awarded and the delivery must be re-bowled.',
      keywords: ['wide', 'extras', 'out of reach', 'bowling'],
    ),
    SportRule(
      id: 'cricket_lbw',
      sportId: 'cricket',
      category: 'Dismissals',
      title: 'Leg Before Wicket (LBW)',
      officialSource: 'ICC Law 36',
      description:
          'A batsman is out LBW if the ball pitches in line or outside off-stump, hits the striker in line with the stumps without hitting the bat first, and would have gone on to hit the wickets.',
      keywords: ['lbw', 'leg before wicket', 'dismissal', 'out', 'pitching'],
    ),
    SportRule(
      id: 'cricket_maiden',
      sportId: 'cricket',
      category: 'Bowling',
      title: 'Maiden Over',
      officialSource: 'ICC Law 19.3',
      description:
          'An over in which no runs are scored off the bat and no wides/no-balls are bowled is credited to the bowler as a Maiden Over.',
      keywords: ['maiden', 'over', 'zero runs', 'bowler'],
    ),

    // FOOTBALL (FIFA Laws of the Game)
    SportRule(
      id: 'football_offside',
      sportId: 'football',
      category: 'Offside Law',
      title: 'Offside Rule',
      officialSource: 'FIFA Law 11',
      description:
          'A player is in an offside position if any part of their head, body or feet is nearer to the opponents’ goal line than both the ball and the second-last opponent when the ball is played to them.',
      keywords: ['offside', 'fifa law 11', 'attacker', 'defender', 'pass'],
    ),
    SportRule(
      id: 'football_handball',
      sportId: 'football',
      category: 'Fouls & Misconduct',
      title: 'Handball Offence',
      officialSource: 'FIFA Law 12.1',
      description:
          'It is an offence if a player touches the ball with their hand/arm when it has made their body unnaturally bigger, or if they score directly with their hand/arm.',
      keywords: ['handball', 'foul', 'arm', 'penalty', 'fifa law 12'],
    ),

    // KABADDI (AKFI & Pro Kabaddi Rules)
    SportRule(
      id: 'kabaddi_do_or_die',
      sportId: 'kabaddi',
      category: 'Raiding Rules',
      title: 'Do-or-Die Raid',
      officialSource: 'AKFI / PKL Clause 8.2',
      description:
          'After two consecutive empty raids by a team, the third raid becomes a "Do-or-Die Raid". The raider MUST score a point (touch or bonus) or else the raider is declared OUT and the opponent gains 1 point.',
      keywords: ['do or die', 'raid', 'empty raid', 'pkl', 'akfi'],
    ),
    SportRule(
      id: 'kabaddi_super_tackle',
      sportId: 'kabaddi',
      category: 'Defending Rules',
      title: 'Super Tackle (2 Points)',
      officialSource: 'AKFI / PKL Clause 9.1',
      description:
          'When a defending team has 3 or fewer players remaining on the court and successfully tackles the raider, it is a Super Tackle awarding 2 points instead of 1.',
      keywords: ['super tackle', 'defenders', '3 players', 'bonus point'],
    ),

    // BASKETBALL (FIBA Rules)
    SportRule(
      id: 'basketball_24_second',
      sportId: 'basketball',
      category: 'Shot Clock',
      title: '24-Second Shot Clock Rule',
      officialSource: 'FIBA Rule 29',
      description:
          'Whenever a player gains control of a live ball on the court, their team must attempt a field goal attempt within 24 seconds. The ball must leave the hands before time expires and touch the ring.',
      keywords: ['shot clock', '24 seconds', 'fiba', 'possession', 'rim'],
    ),

    // BADMINTON (BWF Rules)
    SportRule(
      id: 'badminton_scoring',
      sportId: 'badminton',
      category: 'Scoring System',
      title: 'Rally Point System (Best of 3 Sets to 21)',
      officialSource: 'BWF Law 7',
      description:
          'A match consists of the best of 3 games of 21 points. Whichever side wins a rally adds a point to its score. At 20-all, the side which gains a 2 point lead first wins that game (up to max 30 points).',
      keywords: ['badminton', 'bwf law 7', '21 points', 'deuce', 'rally point'],
    ),

    // CHESS (FIDE Laws of Chess)
    SportRule(
      id: 'chess_en_passant',
      sportId: 'chess',
      category: 'Special Moves',
      title: 'En Passant Pawn Capture',
      officialSource: 'FIDE Article 3.7.3',
      description:
          'A pawn attacking a square passed by an enemy pawn that has advanced two squares from its starting position on the immediately previous turn may capture the enemy pawn "in passing" as if it had only moved one square.',
      keywords: ['en passant', 'pawn', 'fide', 'special capture', 'chess'],
    ),
  ];
}
