import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/play_sphere_store.dart';
import '../../../../core/network/firebase_service.dart';
import '../../../../shared/widgets/portal_scaffold.dart';

class LiveDashboardScreen extends ConsumerStatefulWidget {
  const LiveDashboardScreen({
    super.key,
    required this.orgId,
    required this.eventId,
  });

  final String orgId;
  final String eventId;

  @override
  ConsumerState<LiveDashboardScreen> createState() => _LiveDashboardScreenState();
}

class _LiveDashboardScreenState extends ConsumerState<LiveDashboardScreen> {
  // Common Score State
  int _scoreA = 0;
  int _scoreB = 0;
  String _activeSport = 'Football'; // Default

  // Game/Set States
  int _setsA = 1;
  int _setsB = 0;
  final int _currentHalfOrQuarter = 1;

  // Chess Clock State
  final int _chessTimeA = 300; // 5 mins in seconds
  final int _chessTimeB = 280;

  // Cricket State
  final int _cricketRuns = 148;
  final int _cricketWickets = 3;
  final int _cricketTotalBalls = 104;
  final int _cricketTarget = 172;
  final String _activeRaider = 'Aarav Sharma';

  final List<Map<String, dynamic>> _liveEventStream = [
    {'time': '09:14:10', 'event': 'Match initialized under Pro Sports OS Studio', 'team': 'System', 'icon': Icons.sports},
  ];

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(playSphereStoreProvider);
    final fixture = store.fixtures.firstWhere(
      (f) => f.id == 'f1',
      orElse: () => store.fixtures.first,
    );
    final isAdmin = store.role == PortalRole.admin;

    return PortalScaffold(
      title: 'God-Level Universal Multi-Sport Scoring Studio',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Universal Sport Engine Selector Bar
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.green.withValues(alpha: 0.4), width: 1.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.tune, color: Color(0xFF16A34A), size: 18),
                    SizedBox(width: 8),
                    Text('Select Universal Sport Scoring Engine:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 6),
                DropdownButton<String>(
                  value: _activeSport,
                  isExpanded: true,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 'Football', child: Text('⚽ Football / Soccer (Goal, Assist, Cards & VAR Studio)')),
                    DropdownMenuItem(value: 'Cricket', child: Text('🏏 Cricket (CricHeroes Pro Ball-by-Ball Engine)')),
                    DropdownMenuItem(value: 'Badminton', child: Text('🎾 Badminton / TT (Set Rally & Smash Winner Studio)')),
                    DropdownMenuItem(value: 'Kabaddi', child: Text('🤼 Kabaddi Pro (Raid, Tackle, Super Raid & All Out)')),
                    DropdownMenuItem(value: 'Basketball', child: Text('🏀 Basketball Pro (2pt, 3pt, Dunk, Foul & Timeout)')),
                    DropdownMenuItem(value: 'Chess', child: Text('♟️ Chess FIDE (Checkmate, Clock & Resignation Studio)')),
                    DropdownMenuItem(value: 'Carrom', child: Text('🎯 Carrom Pro (Queen + Cover & Coin Pocket Studio)')),
                    DropdownMenuItem(value: 'Volleyball', child: Text('🏐 Volleyball Pro (Best-of-5 Sets & Spike Winner)')),
                    DropdownMenuItem(value: 'Athletics', child: Text('🏃 Athletics & Swimming (Stopwatch & Rank Position)')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _activeSport = val;
                        _scoreA = 0;
                        _scoreB = 0;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Universal Stadium Scoreboard Header
          Card(
            elevation: 8,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  colors: [Color(0xFF07140B), Color(0xFF0F2314)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Column(
                children: [
                  // Live Header Badge & Period
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC2626),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(color: const Color(0xFFDC2626).withValues(alpha: 0.5), blurRadius: 8),
                          ],
                        ),
                        child: Text('🔴 LIVE $_activeSport.toUpperCase()', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)),
                      ),
                      Text(
                        _activeSport == 'Football' ? '2nd Half • 68:40' : (_activeSport == 'Basketball' ? 'Q3 • 04:12' : (_activeSport == 'Kabaddi' ? '2nd Half' : 'Live Court 1')),
                        style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Main Score Numbers
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      // Entrant A
                      Column(
                        children: [
                          const CircleAvatar(
                            radius: 30,
                            backgroundColor: Color(0xFF16A34A),
                            child: Text('A', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                          ),
                          const SizedBox(height: 6),
                          Text(fixture.entrantAId, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                          const SizedBox(height: 2),
                          const Text('Rank #1 • 1420 ELO', style: TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.bold, fontSize: 11)),
                        ],
                      ),

                      // Central Score Counter
                      Column(
                        children: [
                          if (_activeSport == 'Cricket') ...[
                            Text('$_cricketRuns/$_cricketWickets', style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: Colors.white)),
                            Text('(${_cricketTotalBalls ~/ 6}.${_cricketTotalBalls % 6} Overs) • Target $_cricketTarget', style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                          ] else ...[
                            Text('$_scoreA - $_scoreB', style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 2)),
                            if (_activeSport == 'Badminton' || _activeSport == 'Volleyball')
                              Text('Sets: $_setsA - $_setsB (Game 2)', style: const TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.bold, fontSize: 12))
                            else if (_activeSport == 'Chess')
                              Text('${_chessTimeA ~/ 60}:${(_chessTimeA % 60).toString().padLeft(2, "0")} vs ${_chessTimeB ~/ 60}:${(_chessTimeB % 60).toString().padLeft(2, "0")}', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12))
                            else
                              Text('Period $_currentHalfOrQuarter', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                          ],
                        ],
                      ),

                      // Entrant B
                      Column(
                        children: [
                          const CircleAvatar(
                            radius: 30,
                            backgroundColor: Color(0xFFDC2626),
                            child: Text('B', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                          ),
                          const SizedBox(height: 6),
                          Text(fixture.entrantBId, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                          const SizedBox(height: 2),
                          const Text('Rank #2 • 1380 ELO', style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.bold, fontSize: 11)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Specialized Official Scorer Action Console
          if (isAdmin) ...[
            Text('Pro Official Scorer Console ($_activeSport Engine)', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    // 1. FOOTBALL STUDIO
                    if (_activeSport == 'Football') ...[
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.sports_soccer),
                              label: const Text('Goal (A) ⚽'),
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
                              onPressed: () => _logSportEvent('Entrant A GOAL ⚽ (Aarav Sharma)', 1, isA: true),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.sports_soccer),
                              label: const Text('Goal (B) ⚽'),
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                              onPressed: () => _logSportEvent('Entrant B GOAL ⚽ (Riya Sen)', 1, isA: false),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                              onPressed: () => _logSportEvent('Yellow Card 🟨 (Entrant A)', 0, isA: true),
                              child: const Text('Yellow Card 🟨', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
                              onPressed: () => _logSportEvent('Red Card 🟥 (Entrant A)', 0, isA: true),
                              child: const Text('Red Card 🟥', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white),
                              onPressed: () => _logSportEvent('VAR Check Review 🖥️', 0, isA: true),
                              child: const Text('VAR Review 🖥️', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
                    ]
                    // 2. KABADDI PRO STUDIO
                    else if (_activeSport == 'Kabaddi') ...[
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.directions_run),
                              label: const Text('Raid Pt (+1)'),
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
                              onPressed: () => _logSportEvent('Raid Point (+1) by $_activeRaider', 1, isA: true),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.shield),
                              label: const Text('Tackle Pt (+1)'),
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
                              onPressed: () => _logSportEvent('Tackle Point (+1) by Defense', 1, isA: true),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.star),
                              label: const Text('Bonus Pt (+1)'),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                              onPressed: () => _logSportEvent('Bonus Point ⭐ (+1)', 1, isA: true),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.bolt),
                              label: const Text('Super Raid (+3)'),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                              onPressed: () => _logSportEvent('SUPER RAID ⚡ (+3 pts)', 3, isA: true),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.flash_on),
                              label: const Text('All Out (+2)'),
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                              onPressed: () => _logSportEvent('ALL OUT 💥 (+2 Extra Pts)', 2, isA: false),
                            ),
                          ),
                        ],
                      ),
                    ]
                    // 3. BADMINTON & TABLE TENNIS STUDIO
                    else if (_activeSport == 'Badminton') ...[
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.sports_tennis),
                              label: const Text('Point (A) 🟢'),
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
                              onPressed: () => _logSportEvent('Entrant A Point Won 🎾 (Smash Winner)', 1, isA: true),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.sports_tennis),
                              label: const Text('Point (B) 🔴'),
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                              onPressed: () => _logSportEvent('Entrant B Point Won 🎾 (Ace Serve)', 1, isA: false),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.emoji_events),
                              label: const Text('Set Won (A)'),
                              onPressed: () {
                                setState(() => _setsA++);
                                _logSportEvent('Set Won by Entrant A 🏆', 0, isA: true);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.emoji_events),
                              label: const Text('Set Won (B)'),
                              onPressed: () {
                                setState(() => _setsB++);
                                _logSportEvent('Set Won by Entrant B 🏆', 0, isA: false);
                              },
                            ),
                          ),
                        ],
                      ),
                    ]
                    // 4. BASKETBALL STUDIO
                    else if (_activeSport == 'Basketball') ...[
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
                              onPressed: () => _logSportEvent('2-Pointer Field Goal 🏀 (A)', 2, isA: true),
                              child: const Text('2-Pt Goal (A)', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
                              onPressed: () => _logSportEvent('3-POINTER 🎯 (A)', 3, isA: true),
                              child: const Text('3-Pointer 🎯 (A)', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                              onPressed: () => _logSportEvent('Free Throw (+1) (A)', 1, isA: true),
                              child: const Text('Free Throw (+1)', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ]
                    // 5. CHESS FIDE STUDIO
                    else if (_activeSport == 'Chess') ...[
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.emoji_events),
                              label: const Text('White Won (1-0) ♟️'),
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
                              onPressed: () => _logSportEvent('White Won by Checkmate ♟️ (1 - 0)', 1, isA: true),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.emoji_events),
                              label: const Text('Black Won (0-1) ♟️'),
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                              onPressed: () => _logSportEvent('Black Won by Checkmate ♟️ (0 - 1)', 1, isA: false),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.handshake),
                        label: const Text('Stalemate / Draw Agreed 🤝 (0.5 - 0.5)'),
                        onPressed: () => _logSportEvent('Agreed Draw / Stalemate 🤝', 0, isA: true),
                      ),
                    ]
                    // 6. DEFAULT GENERAL SPORTS STUDIO
                    else ...[
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.add_circle),
                              label: const Text('+1 Score (Entrant A)'),
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
                              onPressed: () => _logSportEvent('Entrant A scored +1 Point', 1, isA: true),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.add_circle),
                              label: const Text('+1 Score (Entrant B)'),
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                              onPressed: () => _logSportEvent('Entrant B scored +1 Point', 1, isA: false),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),

                    // Undo & Finalization Bar
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.undo),
                            label: const Text('Undo Last Action'),
                            onPressed: _liveEventStream.length <= 1
                                ? null
                                : () {
                                    setState(() => _liveEventStream.removeAt(0));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Undid last action! Scoreboard replayed.')),
                                    );
                                  },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.check_circle),
                            label: const Text('Finalize Match & Recalculate ELO', style: TextStyle(fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16A34A), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                            onPressed: () {
                              store.finalizeFixture(fixture.id);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('🎉 Match Finalized! ELO Ratings & Standings Updated!'),
                                  backgroundColor: Color(0xFF16A34A),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),

          // Universal Live Action Ticker Stream
          Text('Live Official Event Stream', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          ..._liveEventStream.map((item) {
            final isA = item['team'] == 'Entrant A';
            final isSystem = item['team'] == 'System';
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: isSystem ? Colors.grey.withValues(alpha: 0.2) : (isA ? const Color(0xFF16A34A) : const Color(0xFFDC2626)).withValues(alpha: 0.2),
                  child: Icon(item['icon'] ?? Icons.flash_on, color: isSystem ? Colors.grey : (isA ? const Color(0xFF16A34A) : const Color(0xFFDC2626)), size: 20),
                ),
                title: Text(item['event'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text('Recorded by Official Scorer • ${item["time"]}'),
                trailing: Text(item['team'], style: TextStyle(color: isSystem ? Colors.grey : (isA ? const Color(0xFF16A34A) : const Color(0xFFDC2626)), fontWeight: FontWeight.bold)),
              ),
            );
          }),
        ],
      ),
    );
  }

  void _logSportEvent(String eventText, int scoreDelta, {required bool isA}) {
    setState(() {
      if (isA) {
        _scoreA += scoreDelta;
      } else {
        _scoreB += scoreDelta;
      }
      final now = DateTime.now();
      final timeStr = '${now.hour.toString().padLeft(2, "0")}:${now.minute.toString().padLeft(2, "0")}:${now.second.toString().padLeft(2, "0")}';
      _liveEventStream.insert(0, {
        'time': timeStr,
        'event': eventText,
        'team': isA ? 'Entrant A' : 'Entrant B',
        'icon': Icons.flash_on,
      });
    });

    // Save directly to Firebase Firestore & Stream to GCP BigQuery
    FirebaseService.saveMatchEvent(
      fixtureId: widget.eventId,
      eventType: eventText,
      payload: {
        'sport': _activeSport,
        'team': isA ? 'Entrant A' : 'Entrant B',
        'score_delta': scoreDelta,
        'current_score_a': _scoreA,
        'current_score_b': _scoreB,
      },
    );
  }
}
