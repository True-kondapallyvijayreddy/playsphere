import '../match_flow.dart';
import '../player_stats.dart';
import '../scoring_plugin.dart';

/// Volleyball, with per-player attribution of every rally.
///
/// Rally scoring means every rally produces a point for somebody, so the
/// interesting question is never the score — it is *how* the point was won.
/// A kill, a block, an ace and an opponent error all look identical on the
/// scoreboard and mean entirely different things about the players involved.
/// The spec asks for kills, blocks, aces and digs, none of which survive an
/// engine that only counts set scores.
///
/// Set structure, all configurable:
///
///  * **Sets to 25, win by two, no cap.** Unlike badminton there is no ceiling
///    — 33-31 is a legal set and an engine with a hard cap would end it wrongly.
///  * **The deciding set is to 15**, still win by two. Playing it to 25 is the
///    error that decides the match that matters most incorrectly.
class VolleyballPlugin extends ScoringPlugin with SquadRotation, TeamTimeouts {
  const VolleyballPlugin();

  /// Volleyball counts substitutions and timeouts **per set**, and its match
  /// has no running clock at all. So it takes the shared rotation machinery
  /// for the legality checks and the bench, and declines the minutes column:
  /// a number nobody at the venue could check is worse than no number.
  @override
  bool get tracksPlayingTime => false;

  /// Rally count stands in for a clock. Nothing here is measured in minutes;
  /// this exists so "has the match started" has an answer, which is what
  /// decides whether the starting six can still be declared.
  @override
  int rotationClock(Map<String, dynamic> state) {
    var played = 0;
    for (final set in copyList(state['completedSets'])) {
      played += ((set['a'] as num?) ?? 0).toInt();
      played += ((set['b'] as num?) ?? 0).toInt();
    }
    return played +
        ((state['currentA'] as num?) ?? 0).toInt() +
        ((state['currentB'] as num?) ?? 0).toInt();
  }

  /// Derived from the score, so there is nothing to write.
  @override
  Map<String, dynamic> withRotationClock(
    Map<String, dynamic> state,
    int value,
  ) =>
      state;

  static const pluginKey = 'volleyball';

  @override
  String get key => pluginKey;

  @override
  String get displayName => 'Volleyball';

  static const _kills = 'kills';
  static const _blocks = 'blocks';
  static const _aces = 'aces';
  static const _digs = 'digs';
  static const _assists = 'assists';
  static const _attackErrors = 'attackErrors';
  static const _serviceErrors = 'serviceErrors';

  int _setsToWin(ScoringContext ctx) => ctx.intConfig('setsToWin', 3);
  int _setPoints(ScoringContext ctx) => ctx.intConfig('pointsPerSet', 25);
  int _decidingSetPoints(ScoringContext ctx) =>
      ctx.intConfig('decidingSetPoints', 15);
  int _winBy(ScoringContext ctx) => ctx.intConfig('winBy', 2);

  /// The score at which teams change ends in the deciding set.
  ///
  /// This is a law of the game, not decoration: the deciding set is short and
  /// half of it is played into whatever wind, sun or glare the venue has, so
  /// the switch at 8 is what keeps it fair. A scorer who is not prompted will
  /// forget it, and the teams will play the whole set from one end.
  int _switchEndsAt(ScoringContext ctx) =>
      ctx.intConfig('switchEndsInDecidingAt', 8);

  @override
  Map<String, dynamic> initialState(ScoringContext ctx) => {
        'currentA': 0,
        'currentB': 0,
        'setsA': 0,
        'setsB': 0,
        'completedSets': <Map<String, dynamic>>[],
        'endsSwapped': false,
        'complete': false,
        'winner': null,
        PlayerTally.stateKey: <String, dynamic>{},
        ...rotationInitialState(ctx),
        ...timeoutInitialState(ctx),
        ..._liberoInitialState,
      };

  // --- Libero -----------------------------------------------------------
  //
  // A libero is not an ordinary substitute, and modelling it as one would
  // get the rule wrong: a libero swap does not count against
  // `SquadRotation`'s substitution allowance, does not trip its "no return"
  // rule, and is reciprocal — the same libero goes back out the moment the
  // player they replaced rotates back to that spot, potentially many times
  // a set. `SquadRotation.subsUsedKey`/`subbedOffKey` book-keeping is built
  // for a permanent, capped change and is wrong on all three counts here, so
  // this is a second, independent on/off toggle that shares nothing with it
  // — a libero swap never touches `onCourtKey` through the shared mixin's
  // own substitution path, only through the two actions below.
  static const _liberoIdKey = 'liberoId'; // {'a': id?, 'b': id?}
  static const _liberoOnKey = 'liberoOn'; // {'a': bool, 'b': bool}
  static const _liberoReplacingKey = 'liberoReplacing'; // {'a': id?, 'b': id?}

  static const Map<String, dynamic> _liberoInitialState = {
    _liberoIdKey: {'a': null, 'b': null},
    _liberoOnKey: {'a': false, 'b': false},
    _liberoReplacingKey: {'a': null, 'b': null},
  };

  String? liberoIdFor(Map<String, dynamic> state, Side side) =>
      (state[_liberoIdKey] as Map?)?[side.wire] as String?;

  bool liberoIsOn(Map<String, dynamic> state, Side side) =>
      (state[_liberoOnKey] as Map?)?[side.wire] == true;

  ScoringResult _applySetLibero(
    Map<String, dynamic> state,
    ScoreAction action,
    ScoringContext ctx,
  ) {
    if (action.side == Side.neutral) {
      return const ScoringResult.rejected('Which side is this libero for?');
    }
    // A libero designated mid-set would retroactively make earlier digs and
    // kills legal or not depending on who was "really" on court — simplest
    // and clearest to require this settled before the set it applies to.
    if (liberoIsOn(state, action.side)) {
      return const ScoringResult.rejected(
        'Swap the current libero off before naming a new one.',
      );
    }
    final id = action.payload['playerId'] as String?;
    if (id == null) {
      return const ScoringResult.rejected('Who is the libero?');
    }
    final squad = ctx.lineupFor(action.side).map((p) => p.id).toSet();
    if (!squad.contains(id)) {
      return ScoringResult.rejected(
          '${ctx.playerName(id)} is not in this squad.');
    }
    return ScoringResult.ok(mutate(state, (s) {
      final ids = Map<String, dynamic>.from(s[_liberoIdKey] as Map? ?? {});
      ids[action.side.wire] = id;
      s[_liberoIdKey] = ids;
    }));
  }

  ScoringResult _applyLiberoSwap(
    Map<String, dynamic> state,
    ScoreAction action,
    ScoringContext ctx,
  ) {
    if (action.side == Side.neutral) {
      return const ScoringResult.rejected('Which side is swapping?');
    }
    final side = action.side;
    final libero = liberoIdFor(state, side);
    if (libero == null) {
      return const ScoringResult.rejected(
        'Name this side\'s libero first.',
      );
    }
    final court = Map<String, dynamic>.from(
        state[SquadRotation.onCourtKey] as Map? ?? {});
    final onCourtIds = List<String>.from(court[side.wire] as List? ?? const []);
    final onMap = Map<String, dynamic>.from(state[_liberoOnKey] as Map? ?? {});
    final replacingMap =
        Map<String, dynamic>.from(state[_liberoReplacingKey] as Map? ?? {});

    if (liberoIsOn(state, side)) {
      // Swap back out: restore whoever the libero replaced.
      final replaced = replacingMap[side.wire] as String?;
      if (replaced == null) {
        return const ScoringResult.rejected(
          'No record of who the libero replaced.',
        );
      }
      final idx = onCourtIds.indexOf(libero);
      if (idx == -1) {
        return const ScoringResult.rejected(
          'The libero is not currently on court.',
        );
      }
      onCourtIds[idx] = replaced;
      onMap[side.wire] = false;
      replacingMap[side.wire] = null;
    } else {
      final forId = action.payload['forId'] as String?;
      if (forId == null) {
        return const ScoringResult.rejected(
          'Which player is the libero coming on for?',
        );
      }
      if (!onCourtIds.contains(forId)) {
        return ScoringResult.rejected(
          '${ctx.playerName(forId)} is not on court.',
        );
      }
      if (forId == libero) {
        return const ScoringResult.rejected(
          'The libero cannot replace themselves.',
        );
      }
      final idx = onCourtIds.indexOf(forId);
      onCourtIds[idx] = libero;
      onMap[side.wire] = true;
      replacingMap[side.wire] = forId;
    }

    court[side.wire] = onCourtIds;
    return ScoringResult.ok(mutate(state, (s) {
      s[SquadRotation.onCourtKey] = court;
      s[_liberoOnKey] = onMap;
      s[_liberoReplacingKey] = replacingMap;
    }));
  }

  /// Whether the set being played is the decider.
  bool isDecidingSet(Map<String, dynamic> state, ScoringContext ctx) {
    final toWin = _setsToWin(ctx);
    final setsA = (state['setsA'] as num?)?.toInt() ?? 0;
    final setsB = (state['setsB'] as num?)?.toInt() ?? 0;
    return setsA == toWin - 1 && setsB == toWin - 1;
  }

  /// The target for the set being played. The deciding set is shorter.
  int targetForCurrentSet(Map<String, dynamic> state, ScoringContext ctx) =>
      isDecidingSet(state, ctx) ? _decidingSetPoints(ctx) : _setPoints(ctx);

  /// True once a side reaches the switch score in the deciding set and the
  /// change of ends has not yet been recorded.
  ///
  /// Derived rather than stored so it cannot disagree with the score, and
  /// exposed so the pad can prompt rather than relying on the scorer to
  /// remember mid-rally.
  bool shouldSwitchEnds(Map<String, dynamic> state, ScoringContext ctx) {
    if (!isDecidingSet(state, ctx)) return false;
    if (state['endsSwapped'] == true) return false;
    final at = _switchEndsAt(ctx);
    if (at <= 0) return false;
    final a = (state['currentA'] as num?)?.toInt() ?? 0;
    final b = (state['currentB'] as num?)?.toInt() ?? 0;
    return a >= at || b >= at;
  }

  @override
  ScoringResult apply(
    Map<String, dynamic> state,
    ScoreAction action,
    ScoringContext ctx,
  ) {
    if (state['complete'] == true && action.type != 'reopen') {
      return const ScoringResult.rejected(
        'This match is already finished. Reopen it to make a correction.',
      );
    }

    // The ordinary substitution control (`SquadRotation._applySubstitution`,
    // reached below via `applyRotationAction`) knows nothing about a libero:
    // it validates purely against `onCourtKey`, which a libero swap edits
    // directly. Left unguarded, two real bugs follow from that — both found
    // by tracing what happens when the two mixins touch the same court slot:
    //
    //   * subbing OUT the on-court libero through the ordinary control would
    //     silently spend a substitution credit and add the libero to the
    //     no-return list, neither of which a libero swap is allowed to do
    //     under the actual rules of the sport;
    //   * subbing IN the player a libero is currently standing in for — who
    //     reads as "on the bench" to the ordinary control, because the
    //     libero occupies their slot in `onCourtKey` — would put that player
    //     on court a SECOND time the moment the libero is later swapped back
    //     off, since the swap-off restores them into the libero's slot too.
    //
    // Both are rejected here, before either action reaches the shared
    // mixin, rather than taught to `SquadRotation` itself: the libero is a
    // volleyball-only concept, and `SquadRotation` is shared by every sport
    // that substitutes. See test/volleyball_libero_test.dart.
    if (action.type == 'substitution' && action.side != Side.neutral) {
      final side = action.side;
      if (liberoIsOn(state, side)) {
        final off = action.payload['playerOffId'] as String?;
        final on = action.payload['playerOnId'] as String?;
        final libero = liberoIdFor(state, side);
        final standingInFor =
            (state[_liberoReplacingKey] as Map?)?[side.wire] as String?;
        if (off != null && off == libero) {
          return const ScoringResult.rejected(
            'That is the libero on court — swap them off with the libero '
            'control, not an ordinary substitution.',
          );
        }
        if (on != null && on == standingInFor) {
          return ScoringResult.rejected(
            '${ctx.playerName(on)} is off court only because the libero is '
            'standing in for them. Swap the libero off first.',
          );
        }
      }
    }

    final shared = applyRotationAction(state, action, ctx) ??
        applyTimeoutAction(state, action, ctx);
    if (shared != null) return shared;

    switch (action.type) {
      case 'set_libero':
        return _applySetLibero(state, action, ctx);
      case 'libero_swap':
        return _applyLiberoSwap(state, action, ctx);
      case 'point':
        if (action.side == Side.neutral) {
          return const ScoringResult.rejected('A point needs a side.');
        }
        // How the point was won. Only `opponent_error` has no player of its
        // own — everything else belongs to somebody.
        final how = action.payload['how'] as String? ?? 'attack';
        final player = action.payload['playerId'] as String?;
        final assist = action.payload['assistId'] as String?;

        if (how != 'opponent_error' && player == null) {
          return ScoringResult.rejected('Who won the point with the $how?');
        }

        final key = action.side == Side.a ? 'currentA' : 'currentB';
        var next = mutate(state, (s) {
          s[key] = ((s[key] as num?)?.toInt() ?? 0) + 1;
        });

        if (player != null) {
          next = PlayerTally.add(
            next,
            player,
            switch (how) {
              'block' => _blocks,
              'ace' => _aces,
              _ => _kills,
            },
            1,
          );
          // A setter's assist only exists on a kill.
          if (how == 'attack' && assist != null && assist != player) {
            next = PlayerTally.add(next, assist, _assists, 1);
          }
        }

        // An opponent error is also somebody's error, when named.
        final erroredBy = action.payload['errorById'] as String?;
        if (how == 'opponent_error' && erroredBy != null) {
          final kind = action.payload['errorType'] as String? ?? 'attack';
          next = PlayerTally.add(
            next,
            erroredBy,
            kind == 'service' ? _serviceErrors : _attackErrors,
            1,
          );
        }

        return ScoringResult.ok(_settleSet(next, ctx));

      case 'dig':
        final player = action.payload['playerId'] as String?;
        if (player == null) {
          return const ScoringResult.rejected('Who dug it up?');
        }
        // A dig does not score; it is recorded because it is one of the few
        // defensive contributions volleyball measures.
        return ScoringResult.ok(PlayerTally.add(state, player, _digs, 1));

      case 'correct':
        if (action.side == Side.neutral) {
          return const ScoringResult.rejected('Correction needs a side.');
        }
        final key = action.side == Side.a ? 'currentA' : 'currentB';
        final current = (state[key] as num?)?.toInt() ?? 0;
        if (current == 0) {
          return const ScoringResult.rejected(
            'Cannot go below zero in the current set.',
          );
        }
        return ScoringResult.ok(mutate(state, (s) => s[key] = current - 1));

      case 'switch_ends':
        // Recorded as its own event so the log shows the change of ends
        // happened and at what score, which is what an official asks for
        // when a deciding set is queried afterwards.
        if (!isDecidingSet(state, ctx)) {
          return const ScoringResult.rejected(
            'Ends only change mid-set in the deciding set.',
          );
        }
        return ScoringResult.ok(mutate(state, (s) {
          s['endsSwapped'] = true;
        }));

      case 'reopen':
        return ScoringResult.ok(mutate(state, (s) {
          s['complete'] = false;
          s['winner'] = null;
        }));

      default:
        return ScoringResult.rejected('Unknown action "${action.type}".');
    }
  }

  Map<String, dynamic> _settleSet(
    Map<String, dynamic> state,
    ScoringContext ctx,
  ) {
    final target = targetForCurrentSet(state, ctx);
    final winBy = _winBy(ctx);
    final toWin = _setsToWin(ctx);

    final a = (state['currentA'] as num?)?.toInt() ?? 0;
    final b = (state['currentB'] as num?)?.toInt() ?? 0;
    final high = a > b ? a : b;
    final margin = (a - b).abs();

    // No hard cap: 33-31 is a legal volleyball set, and a ceiling would end
    // it at the wrong moment.
    if (high < target || margin < winBy) return state;

    final aWon = a > b;
    final completed = copyList(state['completedSets'])..add({'a': a, 'b': b});
    final setsA = ((state['setsA'] as num?)?.toInt() ?? 0) + (aWon ? 1 : 0);
    final setsB = ((state['setsB'] as num?)?.toInt() ?? 0) + (aWon ? 0 : 1);
    final matchOver = setsA >= toWin || setsB >= toWin;

    return mutate(state, (s) {
      s['completedSets'] = completed;
      s['setsA'] = setsA;
      s['setsB'] = setsB;
      s['currentA'] = 0;
      s['currentB'] = 0;
      // Teams change ends between sets anyway, so the mid-set flag resets
      // with the set it belonged to.
      s['endsSwapped'] = false;
      // A new set refills both allowances. Carrying a spent set's timeouts
      // into the next one is how a side is told it has none left in a set it
      // has not yet called one in.
      s[TeamTimeouts.usedKey] = {'a': 0, 'b': 0};
      s[SquadRotation.subsUsedKey] = {'a': 0, 'b': 0};
      s[SquadRotation.subbedOffKey] = <String>[];
      // Libero state (who is designated, whether they are currently on
      // court, who they are standing in for) is deliberately left alone
      // here. `onCourtKey` is not reset between sets by this method either
      // — resetting only the libero half of "who is on court" would leave
      // the two disagreeing about it.
      if (matchOver) {
        s['complete'] = true;
        s['winner'] = setsA > setsB ? 'a' : 'b';
      }
    });
  }

  static List<StatColumn> get columns => [
        const StatColumn(key: _kills, label: 'Kills', shortLabel: 'K'),
        const StatColumn(key: _blocks, label: 'Blocks', shortLabel: 'BLK'),
        const StatColumn(key: _aces, label: 'Aces', shortLabel: 'ACE'),
        const StatColumn(key: _digs, label: 'Digs', shortLabel: 'DIG'),
        const StatColumn(key: _assists, label: 'Assists', shortLabel: 'AST'),
        StatColumn(
          key: 'points',
          label: 'Points won',
          shortLabel: 'PTS',
          derive: (t) =>
              ((t[_kills] ?? 0) + (t[_blocks] ?? 0) + (t[_aces] ?? 0))
                  .toDouble(),
        ),
        const StatColumn(
          key: _attackErrors,
          label: 'Attack errors',
          shortLabel: 'AE',
        ),
        const StatColumn(
          key: _serviceErrors,
          label: 'Service errors',
          shortLabel: 'SE',
        ),
      ];

  @override
  BoxScore boxScore(
    Map<String, dynamic> state,
    ScoringContext ctx,
    Side side,
  ) =>
      PlayerTally.boxScore(
        state: state,
        ctx: ctx,
        side: side,
        columns: columns,
      );

  @override
  String headline(Map<String, dynamic> state, ScoringContext ctx) {
    if (state['complete'] == true) {
      return '${state['setsA'] ?? 0} - ${state['setsB'] ?? 0}';
    }
    return '${state['currentA'] ?? 0} - ${state['currentB'] ?? 0}';
  }

  @override
  String summary(Map<String, dynamic> state, ScoringContext ctx) {
    final sets = copyList(state['completedSets'])
        .map((s) => '${s['a']}-${s['b']}')
        .toList();
    final inPlay = state['complete'] != true
        ? '${state['currentA'] ?? 0}-${state['currentB'] ?? 0}*'
        : null;
    final parts = [...sets, if (inPlay != null) inPlay];
    return parts.isEmpty ? '0-0' : parts.join(', ');
  }

  @override
  String? statusLine(Map<String, dynamic> state, ScoringContext ctx) {
    if (state['complete'] == true) {
      return 'Final · sets ${state['setsA']}-${state['setsB']}';
    }
    final setNumber = copyList(state['completedSets']).length + 1;
    final target = targetForCurrentSet(state, ctx);
    final isDecider = target != _setPoints(ctx);
    return isDecider
        ? 'Deciding set · to $target'
        : 'Set $setNumber · to $target';
  }

  @override
  MatchOutcome outcome(Map<String, dynamic> state, ScoringContext ctx) {
    if (state['complete'] != true) return MatchOutcome.inProgress;
    return MatchOutcome(
      isComplete: true,
      winnerSide: state['winner'] == null
          ? null
          : Side.fromWire(state['winner'] as String),
      scoreForA: (state['setsA'] as num?)?.toInt() ?? 0,
      scoreForB: (state['setsB'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  List<ScoreControlGroup> controls(
    Map<String, dynamic> state,
    ScoringContext ctx,
  ) {
    if (state['complete'] == true) {
      return const [
        ScoreControlGroup(title: 'Match finished', controls: [
          ScoreControl(
            action: 'reopen',
            label: 'Reopen to correct',
            style: ControlStyle.subtle,
            shortcut: 'r',
          ),
        ]),
      ];
    }

    // Surfaced the moment the deciding set reaches the switch score, because
    // a scorer mid-rally will not remember a law that fires once a season.
    final endsPrompt = shouldSwitchEnds(state, ctx)
        ? const ScoreControlGroup(
            title: 'Change ends',
            controls: [
              ScoreControl(
                action: 'switch_ends',
                label: 'Ends changed',
                style: ControlStyle.secondary,
                shortcut: 'e',
                tooltip: 'Teams change ends at this score in the final set',
              ),
            ],
          )
        : null;

    // A kill, a block and an ace are all somebody's — the engine asks "Who
    // won the point with the attack?" and refuses without an answer. An
    // opponent error is nobody's, which is why it is the one point button
    // below that carries no prompt.
    List<ScoreControl> forSide(Side side, String killKey) {
      final starters = startersControl(state, ctx, side);
      final sub = substitutionControl(state, ctx, side);
      final timeout = timeoutControl(state, ctx, side);
      final liberoId = liberoIdFor(state, side);
      final squadIds = ctx.lineupFor(side).map((p) => p.id).toList();

      final liberoControl = squadIds.isEmpty
          ? null
          : liberoId == null
              ? ScoreControl(
                  action: 'set_libero',
                  label: 'Name libero',
                  side: side,
                  style: ControlStyle.subtle,
                  prompts: const [
                    PlayerPrompt(key: 'playerId', label: 'Who is the libero?'),
                  ],
                )
              : liberoIsOn(state, side)
                  ? ScoreControl(
                      action: 'libero_swap',
                      label: 'Libero off (${ctx.playerName(liberoId)})',
                      side: side,
                      style: ControlStyle.subtle,
                    )
                  : ScoreControl(
                      action: 'libero_swap',
                      label: 'Libero on (${ctx.playerName(liberoId)})',
                      side: side,
                      style: ControlStyle.subtle,
                      prompts: [
                        PlayerPrompt(
                          key: 'forId',
                          label: 'Coming on for?',
                          only: List<String>.from(
                            (state[SquadRotation.onCourtKey]
                                    as Map?)?[side.wire] as List? ??
                                const [],
                          ),
                        ),
                      ],
                    );

      return [
        ScoreControl(
          action: 'point',
          label: 'Kill',
          side: side,
          style: ControlStyle.primary,
          payload: const {'how': 'attack'},
          shortcut: killKey,
          prompts: const [
            PlayerPrompt(key: 'playerId', label: 'Who hit it?'),
          ],
        ),
        ScoreControl(
          action: 'point',
          label: 'Block',
          side: side,
          payload: const {'how': 'block'},
          prompts: const [
            PlayerPrompt(key: 'playerId', label: 'Who blocked?'),
          ],
        ),
        ScoreControl(
          action: 'point',
          label: 'Ace',
          side: side,
          payload: const {'how': 'ace'},
          prompts: const [
            PlayerPrompt(key: 'playerId', label: 'Who served it?'),
          ],
        ),
        ScoreControl(
          action: 'point',
          label: 'Opp. error',
          side: side,
          style: ControlStyle.subtle,
          payload: const {'how': 'opponent_error'},
        ),
        ScoreControl(
          action: 'dig',
          label: 'Dig',
          side: side,
          prompts: const [
            PlayerPrompt(key: 'playerId', label: 'Who dug it up?'),
          ],
        ),
        ScoreControl(
          action: 'correct',
          label: '−1',
          side: side,
          style: ControlStyle.subtle,
        ),
        if (starters != null) starters,
        if (sub != null) sub,
        if (timeout != null) timeout,
        if (liberoControl != null) liberoControl,
      ];
    }

    return [
      if (endsPrompt != null) endsPrompt,
      ScoreControlGroup(
        title: ctx.entrantAName,
        controls: forSide(Side.a, 'a'),
      ),
      ScoreControlGroup(
        title: ctx.entrantBName,
        controls: forSide(Side.b, 'l'),
      ),
    ];
  }
}
