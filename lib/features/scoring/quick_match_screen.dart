import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/competition.dart';
import '../../core/models/match_player.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../data/org_repository.dart' show PlayerLookup;
import '../../data/rating_service.dart';
import '../../domain/rating/glicko2.dart';
import '../../domain/scoring/rule_config.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../domain/team/team_balancer.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/identity.dart';
import '../../shared/ui_kit.dart';

/// Start a match and score it, now.
///
/// The product could describe a season and a draw and a waitlist, and could
/// not describe two friends on a court or a club's own Sunday game — the two
/// things that actually happen most often. Every match had to arrive through
/// create event → open entries → register → close entries → generate draw,
/// which is six screens and a wait, on a ground, before the first ball.
///
/// This screen is the whole of that path collapsed into one: pick a sport and
/// its arrangement, name the two sides, tap start, score. What it creates is
/// not a lesser kind of match — it is a real fixture with a real event log, so
/// it feeds the same scorecard, the same ratings, the same career profile and
/// the same club gallery as a tournament final does.
///
/// Three things it must get right, all of which the first version did not:
///
///  1. **How many a side.** A sport does not have one squad size. Badminton is
///     one or two; cricket is eleven, or eight with a tennis ball, or six in a
///     school yard. Guessing "one" made a cricket match unscorable — the
///     engine rejects the first delivery because the same person cannot be on
///     strike and at the other end.
///  2. **The rules themselves.** Overs, balls per over, points per game, who
///     serves how often. A preset covers the common cases; the numbers behind
///     it have to be editable for the ones it does not.
///  3. **Who the players actually are.** A player added by name is a stranger
///     with that name — nothing accrues to them. Added by their PSOS code they
///     are themselves, from any club, and the match lands on their career.
class QuickMatchScreen extends ConsumerStatefulWidget {
  const QuickMatchScreen({
    super.key,
    required this.orgId,
    this.initialName,
    this.initialSportId,
    this.initialVenue,
    this.initialPlayerUids = const [],
  });

  final String orgId;

  /// Prefilled when an organizer arrived here from the event screen having
  /// chosen the Single Match format — they already typed a name, a sport and
  /// a venue there, and asking again would be the ceremony this path removes.
  final String? initialName;
  final String? initialSportId;
  final String? initialVenue;

  /// Members who already said they are coming, from a match availability call.
  ///
  /// This is the join between "who is free on Sunday" and the team sheet, and
  /// it is why the availability call is worth having: the fourteen names an
  /// organizer collected are dealt into two sides without anybody retyping
  /// one. Uids rather than names, so the match lands on real careers — see
  /// [MatchPlayer.uid].
  final List<String> initialPlayerUids;

  @override
  ConsumerState<QuickMatchScreen> createState() => _QuickMatchScreenState();
}

class _QuickMatchScreenState extends ConsumerState<QuickMatchScreen> {
  SportSpec _sport = SportCatalog.byId('badminton');
  late SideFormat _side = _sport.defaultSideFormat;
  RulePreset? _preset;

  /// The rule values as they will be written onto the fixture: the preset,
  /// with the arrangement's implications and the scorer's own edits on top.
  Map<String, dynamic> _config = {};

  final _sideAName = TextEditingController();
  final _sideBName = TextEditingController();
  final _venue = TextEditingController();

  final List<MatchPlayer> _a = [];
  final List<MatchPlayer> _b = [];

  /// Which side the next tap on a member adds them to.
  int _target = 0;

  bool _busy = false;
  double? _balancePercent;
  String? _givenName;

  @override
  void initState() {
    super.initState();
    _givenName = widget.initialName;
    _venue.text = widget.initialVenue ?? '';
    final given = widget.initialSportId;
    if (given != null && given.isNotEmpty) {
      _applySport(SportCatalog.byId(given));
      return;
    }
    _applySport(_sport);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final preferred = _defaultSport();
      if (preferred != null && preferred.id != _sport.id) {
        setState(() => _applySport(preferred));
      }
    });
  }

  @override
  void dispose() {
    _sideAName.dispose();
    _sideBName.dispose();
    _venue.dispose();
    super.dispose();
  }

  /// One attempt at dealing the confirmed roster onto the two sides.
  ///
  /// Deferred rather than done in `initState` because the names come from
  /// `orgMembersProvider`, which is a stream that has not delivered on the
  /// first frame. Guarded so it happens once: the member list rebuilds
  /// whenever anybody's profile changes, and re-seeding on every rebuild would
  /// undo an organizer's own edits underneath them.
  bool _seeded = false;

  void _seedFromRsvp() {
    if (_seeded) return;
    final wanted = widget.initialPlayerUids;
    if (wanted.isEmpty) return;
    final members =
        ref.read(orgMembersProvider(widget.orgId)).valueOrNull ?? const [];
    if (members.isEmpty) return;
    _seeded = true;

    final byUid = {for (final m in members) m.uid: m.displayName};
    // Alternated rather than filled in order, so a pool that arrives sorted by
    // name does not put the whole first half of the alphabet on one side.
    // Auto-balance is one tap away and is the real answer, but the starting
    // split should not be visibly silly.
    var toA = true;
    for (final uid in wanted) {
      final name = byUid[uid];
      if (name == null) continue;
      final target = toA ? _a : _b;
      if (target.length >= _side.max) {
        // The arrangement cannot seat everybody who said yes. Not an error
        // here — the organizer was offered a mini-tournament on the card and
        // chose this, so the surplus simply does not make the team sheet.
        final other = toA ? _b : _a;
        if (other.length >= _side.max) break;
        other.add(MatchPlayer(id: uid, name: name, uid: uid));
      } else {
        target.add(MatchPlayer(id: uid, name: name, uid: uid));
      }
      toA = !toA;
    }
    if (mounted) setState(() {});
  }

  /// A sensible starting sport — the club's own most recent event.
  SportSpec? _defaultSport() {
    final comps =
        ref.read(competitionsProvider(widget.orgId)).valueOrNull ?? const [];
    if (comps.isEmpty) return null;
    return SportCatalog.byId(comps.first.sportId);
  }

  void _applySport(SportSpec sport) {
    _sport = sport;
    _side = sport.defaultSideFormat;
    _preset = RulePresets.defaultFor(sport.id);
    _rebuildConfig();
    _trimToSide();
  }

  /// Preset → arrangement → nothing else. The scorer's own edits are dropped
  /// here on purpose: they were edits to a *different* ruleset, and silently
  /// carrying "20 overs" onto a badminton match is worse than losing it.
  void _rebuildConfig() {
    _config = {
      ...?_preset?.values,
      ..._sport.configOverrides,
      ..._side.configOverrides,
    };
    _balancePercent = null;
  }

  /// Drops anyone who no longer fits the chosen arrangement, newest first, so
  /// switching from doubles to singles does not silently keep three players.
  void _trimToSide() {
    if (_a.length > _side.max) _a.removeRange(_side.max, _a.length);
    if (_b.length > _side.max) _b.removeRange(_side.max, _b.length);
  }

  // --- Picking who plays ---------------------------------------------------

  List<MatchPlayer> get _targetList => _target == 0 ? _a : _b;

  int? _sideOf(String id) {
    if (_a.any((p) => p.id == id)) return 0;
    if (_b.any((p) => p.id == id)) return 1;
    return null;
  }

  /// Adds to the targeted side, or reports why it could not.
  ///
  /// Returns false when the side is full. The caller shows the reason —
  /// silently ignoring the tap is what made the first version feel broken.
  bool _add(MatchPlayer player) {
    final list = _targetList;
    if (list.length >= _side.max) return false;
    setState(() {
      list.add(player);
      _balancePercent = null;
    });
    return true;
  }

  void _toggleMember(String uid, String name) {
    final side = _sideOf(uid);
    if (side != null) {
      setState(() {
        (side == 0 ? _a : _b).removeWhere((p) => p.id == uid);
        _balancePercent = null;
      });
      return;
    }
    if (!_add(MatchPlayer(id: uid, name: name, uid: uid))) _sideFullMessage();
  }

  void _sideFullMessage() {
    final which = _target == 0 ? _nameA : _nameB;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '$which already has ${_side.max} '
            '${_side.max == 1 ? 'player' : 'players'} — the most '
            '${_side.name.toLowerCase()} allows.',
          ),
        ),
      );
  }

  /// Adds a player by their PSOS code.
  ///
  /// The reason this exists rather than only a member list: a side is often
  /// short and borrows somebody from another club. Added by name they are a
  /// guest — a stranger who happens to share a name — and nothing they do
  /// counts. Added by code they are themselves, and the match lands on their
  /// own career record.
  Future<void> _addByCode() async {
    final result = await showDialog<PlayerLookup>(
      context: context,
      builder: (_) => const _FindPlayerDialog(),
    );
    if (result == null || !mounted) return;

    if (_sideOf(result.uid) != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${result.displayName} is already playing.')),
      );
      return;
    }
    if (!_add(MatchPlayer(
      id: result.uid,
      name: result.displayName,
      uid: result.uid,
    ))) {
      _sideFullMessage();
    }
  }

  Future<void> _addGuest() async {
    if (_targetList.length >= _side.max) {
      _sideFullMessage();
      return;
    }
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add a guest player'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name',
            helperText: 'Somebody with no account. They appear on the '
                'scorecard but build no career record — if they have a PSOS '
                'code, use Add by code instead.',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    final trimmedName = name.trim();
    final isDuplicate = [..._a, ..._b].any(
      (p) => p.name.trim().toLowerCase() == trimmedName.toLowerCase(),
    );
    if (isDuplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Player "$trimmedName" is already in the roster.')),
      );
      return;
    }
    _add(MatchPlayer(
      id: 'guest_${DateTime.now().microsecondsSinceEpoch}',
      name: trimmedName,
    ));
  }

  /// Redeals everyone already picked into two sides of even strength.
  ///
  /// CLAUDE.md §8.3's AI team shuffle, which was a fully tested engine with
  /// nothing calling it. It runs over the players already chosen rather than
  /// over the whole club, because "these fourteen turned up" is the real
  /// input on a Sunday morning.
  Future<void> _autoBalance() async {
    final pool = [..._a, ..._b];
    if (pool.length < 4) return;

    setState(() => _busy = true);
    try {
      const ratings = RatingService();
      final players = <BalancerPlayer>[];
      for (final p in pool) {
        players.add(
          BalancerPlayer(
            id: p.id,
            // A guest has no account and so no rating. The Glicko-2 default —
            // 1500 at maximum deviation — is the honest answer for an unknown
            // player: exactly what a registered player who has never played
            // would carry.
            rating: p.uid == null
                ? const Rating()
                : await ratings.getRating(p.uid!, _sport.id),
          ),
        );
      }

      final result = const TeamBalancer().shuffle(
        players: players,
        teamCount: 2,
        seed: DateTime.now().millisecondsSinceEpoch,
      );

      final byId = {for (final p in pool) p.id: p};
      if (!mounted) return;
      setState(() {
        _a
          ..clear()
          ..addAll(result.teams[0].players.map((p) => byId[p.id]!));
        _b
          ..clear()
          ..addAll(result.teams[1].players.map((p) => byId[p.id]!));
        _balancePercent = result.balancePercent;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // --- Starting it ---------------------------------------------------------

  String get _nameA => _sideAName.text.trim().isNotEmpty
      ? _sideAName.text.trim()
      : _autoName(_a, 'Side A');

  String get _nameB => _sideBName.text.trim().isNotEmpty
      ? _sideBName.text.trim()
      : _autoName(_b, 'Side B');

  /// In a singles match the side IS the player, so naming it anything else
  /// makes the scoreboard read about two teams that do not exist. In doubles
  /// it is both names, which is what a draw sheet says.
  String _autoName(List<MatchPlayer> side, String fallback) {
    if (side.isEmpty) return fallback;
    if (side.length == 1) return side.first.name;
    if (side.length == 2 && _side.max == 2) {
      return '${side[0].name} / ${side[1].name}';
    }
    return fallback;
  }

  /// Why the match cannot start yet, or null when it can.
  ///
  /// Phrased as the shortfall rather than as a rule, because a scorer reading
  /// "needs at least 2 a side" can act on it and "invalid line-up" cannot.
  String? get _blocker {
    if (_a.length < _side.min || _b.length < _side.min) {
      final n = _side.min;
      return 'Each side needs at least $n ${n == 1 ? 'player' : 'players'} '
          'for ${_side.name.toLowerCase()}.';
    }
    return null;
  }

  bool get _ready => _blocker == null && !_busy;

  Future<void> _start() async {
    final uid = ref.read(currentUidProvider);
    if (uid == null || !_ready) return;

    setState(() => _busy = true);
    try {
      final ids =
          await ref.read(competitionRepositoryProvider).createQuickMatch(
                orgId: widget.orgId,
                name: _givenName?.trim().isNotEmpty == true
                    ? _givenName!.trim()
                    : '$_nameA v $_nameB',
                sport: _sport,
                category: CompetitionCategory.presets().first,
                sideAName: _nameA,
                sideBName: _nameB,
                lineupA: List.of(_a),
                lineupB: List.of(_b),
                createdByUid: uid,
                venue: _venue.text.trim().isEmpty ? null : _venue.text.trim(),
                // The edited ruleset, not the sport's default. This is what
                // makes "8 overs, no free hit" a real match rather than a
                // T20 scored wrong.
                scoringConfig: Map<String, dynamic>.from(_config),
              );

      if (!mounted) return;
      context.pushReplacement(
        Routes.scoring(widget.orgId, ids.compId, ids.fixtureId),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Match started. Score away.')),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(orgMembersProvider(widget.orgId));
    final members = (membersAsync.valueOrNull ?? const [])
        .where((m) => m.isActive)
        .toList();
    // Post-frame: seeding calls setState, and the members stream can deliver
    // during this very build.
    if (!_seeded && members.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _seedFromRsvp();
      });
    }
    final theme = Theme.of(context);
    final presets = RulePresets.forSport(_sport.id);
    final isTeamSport = _side.max > 2;

    return AppScaffold(
      orgId: widget.orgId,
      title: 'Quick match',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ContentBounds(
            maxWidth: 720,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'A match between people in this club. No registration, no '
                  'draw — playable the moment you tap start, and it counts '
                  'towards everyone\'s record exactly like any other match.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),

                DropdownButtonFormField<String>(
                  value: _sport.id,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Sport'),
                  items: [
                    for (final s in SportCatalog.all)
                      DropdownMenuItem(
                        value: s.id,
                        child: Text('${s.icon}  ${s.name}'),
                      ),
                  ],
                  onChanged: (id) {
                    if (id == null) return;
                    setState(() => _applySport(SportCatalog.byId(id)));
                  },
                ),
                const SizedBox(height: 16),

                if (_sport.id == 'cricket') ...[
                  DropdownButtonFormField<String>(
                    value: _config['ballType'] as String? ?? 'Tennis',
                    decoration: const InputDecoration(
                      labelText: 'Ball type',
                      helperText: 'Select the ball used for this match',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Tennis', child: Text('🎾 Tennis Ball')),
                      DropdownMenuItem(value: 'Leather', child: Text('🏏 Leather Ball')),
                      DropdownMenuItem(value: 'Soft Tennis', child: Text('🥎 Soft Tennis Ball')),
                      DropdownMenuItem(value: 'Heavy Tennis', child: Text('🎾 Heavy Tennis Ball')),
                      DropdownMenuItem(value: 'Cork', child: Text('🔴 Cork Ball')),
                      DropdownMenuItem(value: 'Tape Ball', child: Text('⚪ Tape Ball')),
                    ],
                    onChanged: (val) {
                      if (val == null) return;
                      setState(() {
                        _config = {..._config, 'ballType': val};
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                ],

                // --- How many a side ----------------------------------------
                //
                // Singles or doubles; eleven, eight or six. This is the choice
                // that decides everything below it, so it comes first.
                if (_sport.sideFormats.length > 1) ...[
                  const PsSectionHeader(title: 'Match Type'),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final f in _sport.sideFormats)
                        ChoiceChip(
                          label: Text(f.name),
                          selected: _side.id == f.id,
                          onSelected: (_) => setState(() {
                            _side = f;
                            _rebuildConfig();
                            _trimToSide();
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // --- The two sides ------------------------------------------
                //
                // Participants before rules, following the sample flow's
                // order. It is also the better order on its own merits: who is
                // playing is decided at the ground and is what people arrive
                // knowing, where the ruleset is usually left at its preset.
                const PsSectionHeader(title: 'Participants'),
                Row(
                  children: [
                    Expanded(
                      child: _SideCard(
                        title: _side.max == 1 ? 'Player 1' : 'Side A',
                        subtitle: '${_a.length} / ${_side.max}',
                        players: _a,
                        selected: _target == 0,
                        onSelect: () => setState(() => _target = 0),
                        onRemove: (p) => setState(() {
                          _a.remove(p);
                          _balancePercent = null;
                        }),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SideCard(
                        title: _side.max == 1 ? 'Player 2' : 'Side B',
                        subtitle: '${_b.length} / ${_side.max}',
                        players: _b,
                        selected: _target == 1,
                        onSelect: () => setState(() => _target = 1),
                        onRemove: (p) => setState(() {
                          _b.remove(p);
                          _balancePercent = null;
                        }),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if (isTeamSport) ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _a.length + _b.length >= 4 && !_busy
                              ? _autoBalance
                              : null,
                          icon: const Icon(Icons.balance),
                          label: const Text('Auto-balance'),
                        ),
                      ),
                      if (_balancePercent != null) ...[
                        const SizedBox(width: 12),
                        Text(
                          '${_balancePercent!.toStringAsFixed(0)}% balanced',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Splits whoever is picked into two sides of even strength '
                    'using each player\'s rating in this sport. You can still '
                    'move anyone afterwards.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _sideAName,
                          textCapitalization: TextCapitalization.words,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Side A name',
                            hintText: 'e.g. Blues',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _sideBName,
                          textCapitalization: TextCapitalization.words,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Side B name',
                            hintText: 'e.g. Reds',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],

                // --- Who is here --------------------------------------------
                Text(
                  'Adding to ${_target == 0 ? _nameA : _nameB}',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _addByCode,
                        icon: const Icon(Icons.badge_outlined),
                        label: const Text('Add by code'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _addGuest,
                        icon: const Icon(Icons.person_add_alt),
                        label: const Text('Add a guest'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AsyncErrorStrip(value: membersAsync, what: 'the member list'),
                if (membersAsync.isLoading && members.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        for (final m in members)
                          ListTile(
                            dense: true,
                            leading: Icon(
                              _sideOf(m.uid) != null
                                  ? Icons.check_circle
                                  : Icons.person_outline,
                              color: _sideOf(m.uid) != null
                                  ? theme.colorScheme.primary
                                  : null,
                            ),
                            title: Text(m.displayName),
                            subtitle: switch (_sideOf(m.uid)) {
                              0 => Text(_nameA),
                              1 => Text(_nameB),
                              _ => null,
                            },
                            onTap: () => _toggleMember(m.uid, m.displayName),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),

                const PsSectionHeader(title: 'Venue & Time'),
                TextField(
                  controller: _venue,
                  decoration: const InputDecoration(
                    labelText: 'Where (optional)',
                    hintText: 'e.g. Main court',
                  ),
                ),
                const SizedBox(height: 20),

                // --- The ruleset --------------------------------------------
                //
                // Moved below the sides and the venue. It is the section most
                // matches never touch — the sport's preset is usually right —
                // so it sits after the two that every match does.
                if (presets.isNotEmpty || _config.isNotEmpty) ...[
                  const PsSectionHeader(title: 'Match Rules'),
                  _RulesetCard(
                    sportId: _sport.id,
                    presets: presets,
                    preset: _preset,
                    config: _config,
                    onPreset: (p) => setState(() {
                      _preset = p;
                      _rebuildConfig();
                    }),
                    onChanged: (key, value) => setState(() {
                      _config = {..._config, key: value};
                    }),
                  ),
                ],
                const SizedBox(height: 24),

                FilledButton.icon(
                  onPressed: _ready ? _start : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  icon: const Icon(Icons.sports_score),
                  label: Text(_busy ? 'Starting…' : 'Start match & score'),
                ),
                const SizedBox(height: 8),
                Text(
                  _blocker ??
                      'You will be the scorer. The match goes live '
                          'immediately and anyone in the club can watch it.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _blocker == null ? null : theme.colorScheme.error,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The ruleset: a named preset, and every number behind it, editable.
///
/// Collapsed by default. Most matches are played under the preset and the
/// scorer should not have to scroll past nine fields to reach the team sheet;
/// the one match in ten that is eight overs with no free hit needs them all
/// within one tap.
class _RulesetCard extends StatelessWidget {
  const _RulesetCard({
    required this.sportId,
    required this.presets,
    required this.preset,
    required this.config,
    required this.onPreset,
    required this.onChanged,
  });

  final String sportId;
  final List<RulePreset> presets;
  final RulePreset? preset;
  final Map<String, dynamic> config;
  final void Function(RulePreset?) onPreset;
  final void Function(String key, Object value) onChanged;

  /// Whether anything has been changed away from the named preset. Worth
  /// saying out loud: a scorecard read months later has to be attributable to
  /// a ruleset, and "T20, amended" is a different claim from "T20".
  bool get _amended {
    final base = preset?.values;
    if (base == null) return false;
    for (final entry in config.entries) {
      if (base.containsKey(entry.key) && base[entry.key] != entry.value) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keys = RuleFields.orderedKeys(sportId, config);

    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.rule),
        title: Text(preset?.name ?? 'Rules'),
        subtitle: Text(
          _amended
              ? 'Edited — tap to review'
              : (preset?.description.isNotEmpty == true
                  ? preset!.description
                  : 'Tap to change overs, points and timings'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (presets.length > 1) ...[
            DropdownButtonFormField<String>(
              value: preset?.id,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Preset'),
              items: [
                for (final p in presets)
                  DropdownMenuItem(value: p.id, child: Text(p.name)),
              ],
              onChanged: (id) => onPreset(RulePresets.byId(id)),
            ),
            if (preset?.source.isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text(
                'Source: ${preset!.source}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
          ],
          for (final key in keys)
            _RuleFieldRow(
              label: RuleFields.labelFor(key),
              value: config[key],
              onChanged: (v) => onChanged(key, v),
            ),
        ],
      ),
    );
  }
}

/// One rule value, rendered from its own type.
///
/// Typed rather than enumerated so a key added to a preset becomes editable
/// in the same commit, with no screen to update — which is the difference
/// between "rules are configuration" and "rules are configuration a developer
/// can change".
class _RuleFieldRow extends StatelessWidget {
  const _RuleFieldRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final Object? value;
  final void Function(Object) onChanged;

  @override
  Widget build(BuildContext context) {
    final v = value;

    if (v is bool) {
      return SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: v,
        onChanged: onChanged,
      );
    }

    if (v is num) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          initialValue: '$v',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: InputDecoration(labelText: label, isDense: true),
          // Parsed on every keystroke, and a half-typed value is simply not
          // committed. Committing on submit instead would lose the edit of
          // anyone who taps straight from the field to Start.
          onChanged: (text) {
            final parsed = v is int ? int.tryParse(text) : double.tryParse(text);
            if (parsed != null) onChanged(parsed);
          },
        ),
      );
    }

    if (v is String) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          initialValue: v,
          decoration: InputDecoration(labelText: label, isDense: true),
          onChanged: onChanged,
        ),
      );
    }

    // Lists and maps — powerplay windows, tiebreak chains. Shown so the
    // scorer knows the value exists and what it is, but not editable here: a
    // free-text list is a way to write a config the engine cannot read.
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Text('$v', style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

/// Find a player by their PSOS code.
class _FindPlayerDialog extends ConsumerStatefulWidget {
  const _FindPlayerDialog();

  @override
  ConsumerState<_FindPlayerDialog> createState() => _FindPlayerDialogState();
}

class _FindPlayerDialogState extends ConsumerState<_FindPlayerDialog> {
  final _controller = TextEditingController();
  PlayerLookup? _found;
  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final typed = _controller.text.trim();
    if (typed.isEmpty) return;

    setState(() {
      _searching = true;
      _error = null;
      _found = null;
    });
    try {
      final result =
          await ref.read(userRepositoryProvider).findByPlayerCode(typed);
      if (!mounted) return;
      setState(() {
        _found = result;
        // One message for "no such code" and for "you typed it wrong",
        // deliberately: distinguishing them would confirm which codes exist.
        _error = result == null ? 'No player with that code.' : null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not look that up.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = ref.watch(currentUserProvider).valueOrNull;

    return AlertDialog(
      title: const Text('Add by player code'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Every player has a code on their profile. Adding somebody by '
              'code attaches their real account, so what they do in this '
              'match counts towards their career — including a player from '
              'another club.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Player code',
                hintText: 'PSOS-4K7M2',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _searching ? null : _search,
                ),
              ),
              onSubmitted: (_) => _search(),
            ),
            if (me?.playerCode != null) ...[
              const SizedBox(height: 8),
              Text(
                'Yours is ${me!.playerCode}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (_searching) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            if (_found case final found?) ...[
              const SizedBox(height: 12),
              Card(
                color: theme.colorScheme.primaryContainer,
                child: ListTile(
                  leading: PsAvatar(
                    name: found.displayName,
                    photoUrl: found.photoUrl,
                    seed: found.uid,
                  ),
                  title: Text(found.displayName),
                  subtitle: Text(found.code),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _found == null
              ? null
              : () => Navigator.pop(context, _found),
          child: const Text('Add to side'),
        ),
      ],
    );
  }
}

/// One side's current squad, and the tap target that makes it the side the
/// member list is adding to.
class _SideCard extends StatelessWidget {
  const _SideCard({
    required this.title,
    required this.subtitle,
    required this.players,
    required this.selected,
    required this.onSelect,
    required this.onRemove,
  });

  final String title;
  final String subtitle;
  final List<MatchPlayer> players;
  final bool selected;
  final VoidCallback onSelect;
  final void Function(MatchPlayer) onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(16),
      child: Card(
        color: selected ? theme.colorScheme.primaryContainer : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(subtitle, style: theme.textTheme.bodyMedium),
                ],
              ),
              const SizedBox(height: 8),
              if (players.isEmpty)
                Text('Nobody yet', style: theme.textTheme.bodySmall)
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final p in players)
                      InputChip(
                        label: Text(p.name),
                        avatar: p.isGuest
                            ? const Icon(Icons.person_outline, size: 16)
                            : null,
                        onDeleted: () => onRemove(p),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
