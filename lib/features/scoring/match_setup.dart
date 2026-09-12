import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/fixture.dart';
import '../../core/models/match_player.dart';
import '../../core/permissions/capability.dart';
import '../../domain/scoring/scoring_plugin.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../core/providers.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/coin_flip.dart';
import 'registered_squad.dart';

/// Everything that has to happen between "the teams have arrived" and the
/// first ball: who is playing, and who won the toss.
///
/// Both are prerequisites rather than nice-to-haves. The scoring engines
/// refuse a delivery that names nobody, and cricket cannot know which innings
/// belongs to whom until the toss is recorded.

/// Picks the players for one side.
///
/// Members of the organization are offered first, because most of a squad is
/// already in the club. A guest can be added by name alone: a team turns up
/// one short and borrows someone who has never installed the app, and refusing
/// to start the match over that is how a scorer gives up and reaches for
/// paper.
class LineupEditor extends ConsumerStatefulWidget {
  const LineupEditor({super.key, required this.fixture});

  final Fixture fixture;

  @override
  ConsumerState<LineupEditor> createState() => _LineupEditorState();
}

class _LineupEditorState extends ConsumerState<LineupEditor> {
  /// The two team sheets being edited.
  ///
  /// Empty until [_seed] has run, which is why [_seeded] exists as its own
  /// flag: "this side has nobody on it" and "we have not worked out who is on
  /// this side yet" are different states, and conflating them would let a
  /// scorer save an empty sheet over a registered squad in the frame before
  /// the registration arrived.
  final List<MatchPlayer> _a = [];
  final List<MatchPlayer> _b = [];
  final Set<int> _seeded = {};

  /// Sides where the scorer has asked to see the rest of the club.
  ///
  /// Off by default, and that is the whole point of this screen's rework. The
  /// club's wider membership is the substitute path — a registered player did
  /// not turn up and somebody else is filling in — not the starting point.
  final Set<int> _showClubMembers = {};

  bool _busy = false;
  int _tab = 0;

  List<MatchPlayer> get _current => _tab == 0 ? _a : _b;

  /// Which sides this user is allowed to pick.
  ///
  /// In an ordinary competition the hosting club's organizers run both teams,
  /// which is right — one person is setting up a house match. An inter-club
  /// challenge is the opposite situation: two clubs that do not answer to
  /// each other, and the visiting club must be able to name its own players
  /// without handing the host the power to pick them. `firestore.rules`
  /// enforces the same split, so this is the honest shape of the screen
  /// rather than a courtesy.
  Set<int> _editableSides(WidgetRef ref) {
    final f = widget.fixture;
    final sides = <int>{};

    // Authority in the club that owns the fixture runs the whole match.
    if (ref
        .watch(myCapabilitiesProvider(f.orgId))
        .contains(Capability.manageCompetitions)) {
      sides.addAll({0, 1});
    }

    // Authority in either contesting club runs that club's own side.
    if (f.participantOrgIds != null) {
      if (ref
          .watch(myCapabilitiesProvider(f.entrantAId))
          .contains(Capability.manageCompetitions)) {
        sides.add(0);
      }
      if (ref
          .watch(myCapabilitiesProvider(f.entrantBId))
          .contains(Capability.manageCompetitions)) {
        sides.add(1);
      }
    }

    return sides;
  }

  /// Whose member list to offer for a side.
  ///
  /// For a challenge match the two squads come from two different clubs, and
  /// offering the host's members for both is how the visiting club ends up
  /// with a team sheet full of strangers. For everything else both sides are
  /// drawn from the club running the competition, as before.
  String _memberOrgFor(int side) {
    final f = widget.fixture;
    if (f.participantOrgIds == null) return f.orgId;
    return side == 0 ? f.entrantAId : f.entrantBId;
  }

  bool _lockedFor(int side) =>
      side == 0 ? widget.fixture.squadLockedA : widget.fixture.squadLockedB;

  /// Fills a side's sheet the first time we know enough to do it.
  ///
  /// Order of preference, and it is the order that fixes the reported bug:
  ///
  ///  1. What is already saved on the fixture. A sheet somebody has edited is
  ///     never silently rewritten.
  ///  2. The side's REGISTERED squad. A team that entered this competition
  ///     named its players when it entered; match day is not a second
  ///     selection meeting, and presenting one is what let a member of
  ///     another team end up on this team's sheet.
  ///  3. Nothing, for a side with no registration to honour — an individual
  ///     event, an ad-hoc entrant, a knockout slot still awaiting a qualifier.
  /// [squad] is null while the registration is still being read, or when
  /// reading it failed. A saved sheet is seeded either way — it is already on
  /// the fixture and needs nothing else — but an empty side waits rather than
  /// seeding from nothing, because seeding empty would mark the side done and
  /// the registration would never be applied when it did arrive.
  void _seed(int side, RegisteredSquad? squad) {
    if (_seeded.contains(side)) return;

    final saved = side == 0 ? widget.fixture.lineupA : widget.fixture.lineupB;
    final target = side == 0 ? _a : _b;

    if (saved.isNotEmpty) {
      _seeded.add(side);
      target.addAll(saved);
      return;
    }

    if (squad == null) return;
    _seeded.add(side);
    if (squad.isRegistered) target.addAll(squad.players);
  }

  void _toggleMember(String uid, String name) {
    setState(() {
      final list = _current;
      final existing = list.indexWhere((p) => p.id == uid);
      if (existing >= 0) {
        list.removeAt(existing);
      } else {
        // Bug #7: A player cannot play for both sides. If present in the
        // opposite team list, remove them first.
        final otherList = _tab == 0 ? _b : _a;
        otherList.removeWhere((p) => p.id == uid);
        list.add(MatchPlayer(id: uid, name: name, uid: uid));
      }
    });
  }

  Future<void> _addGuest() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a guest player'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name',
            helperText: 'They will appear on the scorecard. Career stats '
                'start once they join PlaySphere.',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    setState(() {
      _current.add(MatchPlayer(
        // Distinct from any uid, and stable for the life of the match.
        id: 'guest_${DateTime.now().microsecondsSinceEpoch}',
        name: name.trim(),
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.fixture;
    final editable = _editableSides(ref);

    // Land on a side this user may actually pick, so a visiting club's admin
    // does not open the screen looking at the opposition's team sheet.
    if (editable.isNotEmpty && !editable.contains(_tab)) {
      _tab = editable.first;
    }

    final squadsAsync = ref.watch(
      registeredSquadsProvider(FixtureRef(f.orgId, f.compId, f.id)),
    );
    final squads = squadsAsync.valueOrNull;
    _seed(0, squads?.a);
    _seed(1, squads?.b);
    final squad = squads?.forSide(_tab);

    final membersAsync = ref.watch(orgMembersProvider(_memberOrgFor(_tab)));
    final members = membersAsync.valueOrNull ?? const [];
    final active = members.where((m) => m.isActive).toList();
    final selectedIds = _current.map((p) => p.id).toSet();
    final locked = _lockedFor(_tab);
    final canEditThisSide = editable.contains(_tab) && !locked;

    // The registered squad is what this side entered with. Everyone else in
    // the club is offered separately and only on request — see
    // [_showClubMembers].
    final registered = squad != null && squad.isRegistered;
    final registeredIds = registered
        ? squad.players.map((p) => p.id).toSet()
        : const <String>{};
    final others =
        active.where((m) => !registeredIds.contains(m.uid)).toList();
    final showingOthers = !registered || _showClubMembers.contains(_tab);

    return AlertDialog(
      title: Text(registered ? 'Confirm the team sheet' : 'Who is playing?'),
      content: SizedBox(
        width: 460,
        height: 460,
        child: Column(
          children: [
            SegmentedButton<int>(
              segments: [
                ButtonSegment(
                  value: 0,
                  label: Text('${f.entrantAName} (${_a.length})'),
                  icon: f.squadLockedA ? const Icon(Icons.lock, size: 14) : null,
                ),
                ButtonSegment(
                  value: 1,
                  label: Text('${f.entrantBName} (${_b.length})'),
                  icon: f.squadLockedB ? const Icon(Icons.lock, size: 14) : null,
                ),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
            const SizedBox(height: 8),
            if (!editable.contains(_tab))
              const _SquadNotice(
                icon: Icons.visibility_outlined,
                message: 'This is the other club\'s squad. They pick it, '
                    'you can see it.',
              )
            else if (locked)
              const _SquadNotice(
                icon: Icons.lock_outline,
                message: 'This squad is locked. Reopen it to make changes.',
              )
            else if (registered)
              _SquadNotice(
                icon: Icons.verified_outlined,
                message: 'These are the players registered for '
                    '${squad.entrantName}. Untick anyone who has not turned '
                    'up — nothing else needs changing.',
              ),
            // Without this, a rejected member read leaves an empty checklist
            // and the scorer concludes the club has no players.
            AsyncErrorStrip(value: membersAsync, what: 'the member list'),
            AsyncErrorStrip(
              value: squadsAsync,
              what: 'the registered squad',
            ),
            Expanded(
              child: ListView(
                children: [
                  // The registered squad, first and ticked. A registered team
                  // that named nobody falls straight through to the club list
                  // below rather than showing an empty section.
                  if (registered && squad.players.isNotEmpty) ...[
                    for (final p in squad.players)
                      CheckboxListTile(
                        dense: true,
                        value: selectedIds.contains(p.id),
                        onChanged: canEditThisSide
                            ? (_) => _toggleMember(p.id, p.name)
                            : null,
                        title: Text(p.name),
                      ),
                    const Divider(height: 20),
                  ],
                  // Everyone else in the club, behind a deliberate tap.
                  //
                  // Not hidden to be tidy: this is the list a mis-tap adds a
                  // player from another team out of, which is exactly what
                  // was reported. Reaching it should be a decision, and the
                  // decision should be labelled with what it means.
                  if (registered && !showingOthers)
                    TextButton.icon(
                      onPressed: canEditThisSide
                          ? () => setState(() => _showClubMembers.add(_tab))
                          : null,
                      icon: const Icon(Icons.person_search_outlined),
                      label: const Text('Add a substitute from the club'),
                    ),
                  if (showingOthers) ...[
                    if (registered)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Text(
                          'Not registered for ${squad.entrantName}. Only add '
                          'them if they are genuinely playing for this side '
                          'today.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ),
                    for (final m in others)
                      CheckboxListTile(
                        dense: true,
                        value: selectedIds.contains(m.uid),
                        onChanged: canEditThisSide
                            ? (_) => _toggleMember(m.uid, m.displayName)
                            : null,
                        title: Text(m.displayName),
                      ),
                  ],
                  // Guests already added to this side.
                  for (final g in _current.where((p) => p.isGuest))
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.person_outline),
                      title: Text(g.name),
                      subtitle: const Text('Guest'),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: canEditThisSide
                            ? () => setState(
                                () => _current.removeWhere((p) => p.id == g.id))
                            : null,
                      ),
                    ),
                  TextButton.icon(
                    onPressed: canEditThisSide ? _addGuest : null,
                    icon: const Icon(Icons.person_add_alt),
                    label: const Text('Add a guest player'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        // Reopening a squad this club locked. Only offered to the club that
        // locked it — the segment is not editable otherwise.
        if (locked && editable.contains(_tab))
          TextButton(
            onPressed: _busy ? null : () => _save(unlockOnly: true),
            child: const Text('Reopen squad'),
          ),
        // "Lock final squad" from the flow: one club telling the other it has
        // finished picking. Only meaningful in an inter-club match, where
        // there is another club to tell.
        if (!locked && canEditThisSide && f.participantOrgIds != null)
          TextButton(
            onPressed: _busy || _current.isEmpty
                ? null
                : () => _save(lock: true),
            child: const Text('Save & lock'),
          ),
        FilledButton(
          onPressed: _busy || !canEditThisSide || !_hasEnoughPlayers()
              ? null
              : () => _save(),
          child: Text(_busy ? 'Saving…' : _saveLabel()),
        ),
      ],
    );
  }

  /// An internal match needs both sides before it can be scored; a club
  /// picking only its own side is done when its own side is picked.
  bool _hasEnoughPlayers() {
    if (_restrictedToOneSide) return _current.isNotEmpty;
    return _a.isNotEmpty && _b.isNotEmpty;
  }

  bool get _restrictedToOneSide =>
      widget.fixture.participantOrgIds != null &&
      _editableSides(ref).length == 1;

  String _saveLabel() => _restrictedToOneSide ? 'Save our squad' : 'Save line-ups';

  Future<void> _save({bool lock = false, bool unlockOnly = false}) async {
    final f = widget.fixture;
    setState(() => _busy = true);
    try {
      final repo = ref.read(competitionRepositoryProvider);

      if (_restrictedToOneSide || lock || unlockOnly) {
        // One club, one side. Which club this user is acting for is decided
        // by the side they are on, not by anything they can type.
        final orgId = _memberOrgFor(_tab);
        await repo.setSideLineup(
          fixture: f,
          forOrgId: orgId,
          lineup: unlockOnly
              ? (_tab == 0 ? f.lineupA : f.lineupB)
              : _current,
          lock: unlockOnly ? false : (lock ? true : null),
        );
      } else {
        await repo.setLineups(
          fixture: f,
          lineupA: _a,
          lineupB: _b,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }
}


/// A short explanation of why this squad is not editable right now.
class _SquadNotice extends StatelessWidget {
  const _SquadNotice({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// The toss.
///
/// Every match starts with one and the app previously just assumed side A went
/// first. Recording it decides which innings belongs to whom, and is written
/// into the fixture's frozen scoring config so the match reads the same way
/// forever.
///
/// Built around the throw rather than around a form. It used to be an
/// [AlertDialog] of radio buttons and chips with the coin hidden behind a
/// small button in the corner, which put the one moment of the match everybody
/// actually gathers round somewhere you had to go looking for it. Now the coin
/// is the screen: heads and tails are named on it before it is thrown, the
/// throw decides, and only then does it ask what the winner took.
///
/// A toss taken at the ground stays first-class — [TossCoin.settleOn] turns
/// the coin to the face a scorer picks by hand, without animating a throw the
/// app did not make.
class TossDialog extends ConsumerStatefulWidget {
  const TossDialog({super.key, required this.fixture});

  final Fixture fixture;

  @override
  ConsumerState<TossDialog> createState() => _TossDialogState();
}

class _TossDialogState extends ConsumerState<TossDialog> {
  final _coin = GlobalKey<TossCoinState>();

  String? _winnerId;
  late final List<TossChoice> _choices =
      TossOptions.forSport(widget.fixture.sport);
  late String _decision = _choices.first.id;
  bool _busy = false;
  bool _flipping = false;

  /// Whether the coin decided it, or a scorer did. Only a thrown result is
  /// offered a re-throw; one entered by hand is a record of something that
  /// already happened off-screen and re-throwing it would be a fiction.
  bool _thrown = false;

  /// Chess has no toss; it has a drawing of lots for colour. Saying "toss"
  /// there would be the same error in the wording that the Bat/Field buttons
  /// once were in the body.
  bool get _isChess => widget.fixture.sport == 'chess';

  String get _noun => _isChess ? 'draw' : 'toss';

  String _nameOf(String entrantId) => entrantId == widget.fixture.entrantAId
      ? widget.fixture.entrantAName
      : widget.fixture.entrantBName;

  void _pickByHand(String entrantId) {
    setState(() {
      _winnerId = entrantId;
      _thrown = false;
    });
    _coin.currentState?.settleOn(entrantId == widget.fixture.entrantAId);
  }

  void _throw() {
    setState(() {
      _winnerId = null;
      _flipping = true;
    });
    _coin.currentState?.flip();
  }

  Future<void> _record() async {
    final f = widget.fixture;
    setState(() => _busy = true);
    try {
      await ref.read(competitionRepositoryProvider).recordToss(
            fixture: f,
            wonByEntrantId: _winnerId!,
            decision: _decision,
            startingSide: _startingSide(f),
            // Only cricket's toss decides who bats, and only cricket's engine
            // reads `battingFirst`. Writing it for a badminton match would put
            // a meaningless key into a frozen ruleset.
            decidesBatting: TossOptions.decidesBatting(f.sport),
            scoringConfig: f.scoringConfig,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.fixture;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final sport = SportCatalog.byId(f.sport);
    final decided = _winnerId != null;

    return Dialog.fullscreen(
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.space): () {
            if (!_flipping && !_busy) _throw();
          },
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: cs.surface,
            appBar: AppBar(
              leading: IconButton(
                tooltip: 'Cancel',
                icon: const Icon(Icons.close),
                // `false` is Cancel, and both callers keep their gate on it.
                onPressed:
                    _busy || _flipping ? null : () => Navigator.pop(context, false),
              ),
              title: Text(_isChess ? 'Colours' : 'Toss'),
              centerTitle: false,
            ),
            body: SafeArea(
              // Centred when the throw fits, scrolling when the choices push it
              // past the screen. A fixed list left the coin stranded at the top of
              // a tall phone with the button a long way beneath it.
              child: LayoutBuilder(
                builder: (context, box) => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: box.maxHeight - 28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                  Text(
                    '${sport.name} · ${f.entrantAName} v ${f.entrantBName}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  // Said before the coin is thrown, never after it.
                  Row(
                    children: [
                      Expanded(
                        child: _FaceCard(
                          face: 'HEADS',
                          name: f.entrantAName,
                          won: _winnerId == f.entrantAId,
                          onTap: _flipping || _busy
                              ? null
                              : () => _pickByHand(f.entrantAId),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _FaceCard(
                          face: 'TAILS',
                          name: f.entrantBName,
                          won: _winnerId == f.entrantBId,
                          onTap: _flipping || _busy
                              ? null
                              : () => _pickByHand(f.entrantBId),
                        ),
                      ),
                    ],
                  ),
                  // The coin is the button. Tapping the thing you are about to
                  // throw is the obvious gesture, and hunting for a control at
                  // the bottom of the screen is not — the bar below stays for
                  // discoverability and for anyone who reaches for it first.
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _flipping || _busy ? null : _throw,
                    child: TossCoin(
                      key: _coin,
                      headsLabel: f.entrantAName,
                      tailsLabel: f.entrantBName,
                      onLanded: (heads) => setState(() {
                        _flipping = false;
                        _thrown = true;
                        _winnerId = heads ? f.entrantAId : f.entrantBId;
                      }),
                    ),
                  ),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      switch ((_flipping, _winnerId)) {
                        (true, _) => 'In the air…',
                        (_, null) =>
                          'Tap the coin to throw it, or tap the side that won '
                              'it at the ground.',
                        (_, final w?) => '${_nameOf(w)} won the $_noun',
                      },
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: decided ? FontWeight.w700 : FontWeight.w500,
                        color: decided ? cs.primary : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (decided) ...[
                    const SizedBox(height: 24),
                    Text(
                      _isChess
                          ? 'And ${_nameOf(_winnerId!)} took'
                          : 'And ${_nameOf(_winnerId!)} chose to',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    // Full-width tiles rather than the chips this used to use: the
                    // choice is what decides who bats, serves or raids first, and
                    // it was the smallest thing on the screen.
                    for (final c in _choices)
                      _ChoiceTile(
                        label: c.label,
                        selected: _decision == c.id,
                        onTap: _busy ? null : () => setState(() => _decision = c.id),
                      ),
                    const SizedBox(height: 12),
                    // Spells the consequence back before it is saved. "Bat" and
                    // "field" produce opposite starters and a scorer who tapped the
                    // wrong tile has no other way to notice.
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: cs.secondaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.play_arrow_rounded,
                              size: 20, color: cs.onSecondaryContainer),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _startsLabel(f),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: cs.onSecondaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                      ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            bottomNavigationBar: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!decided)
                      FilledButton.icon(
                        onPressed: _flipping ? null : _throw,
                        icon: const Icon(Icons.monetization_on_outlined),
                        label: Text(_flipping ? 'Flipping…' : 'Flip the coin'),
                      )
                    else
                      FilledButton.icon(
                        onPressed: _busy ? null : _record,
                        icon: const Icon(Icons.check),
                        label: Text(_busy ? 'Saving…' : 'Record $_noun & Start'),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          // Kept, and kept quiet. A club playing an evening
                          // friendly that genuinely did not toss must not be
                          // locked out of scoring it.
                          onPressed: _busy || _flipping
                              ? null
                              : () => Navigator.pop(context, true),
                          child: Text('Skip $_noun'),
                        ),
                        if (_thrown && !_busy)
                          TextButton.icon(
                            onPressed: _flipping ? null : _throw,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Throw again'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Which side actually starts, given who won and what they took.
  ///
  /// One rule for every sport: a choice that gives you the first turn means
  /// you start, and one that does not hands it to the other side. Choosing
  /// ends concedes the serve; fielding concedes the bat.
  String _startingSide(Fixture f) {
    final winnerIsA = _winnerId == f.entrantAId;
    final choice = TossOptions.resolve(f.sport, _decision);
    if (choice.givesFirstTurn) return winnerIsA ? 'a' : 'b';
    return winnerIsA ? 'b' : 'a';
  }

  /// Spells the consequence back before it is saved, in the sport's own words.
  String _startsLabel(Fixture f) {
    final startsA = _startingSide(f) == 'a';
    final who = startsA ? f.entrantAName : f.entrantBName;
    final verb = switch (f.sport) {
      'cricket' => 'bats first',
      'chess' => 'plays White',
      'kabaddi' => 'raids first',
      'kho_kho' => 'chases first',
      'football' || 'hockey' => 'starts',
      _ => 'serves first',
    };
    return '$who $verb';
  }
}

/// One side of the coin, with the name riding on it.
class _FaceCard extends StatelessWidget {
  const _FaceCard({
    required this.face,
    required this.name,
    required this.won,
    required this.onTap,
  });

  final String face;
  final String name;
  final bool won;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: won ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: won ? cs.primary : cs.outlineVariant,
            width: won ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              face,
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
                color: won ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: won ? cs.onPrimaryContainer : cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the winner took — one full-width tile per option.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? cs.primary : cs.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: selected ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color:
                        selected ? cs.onPrimaryContainer : cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The toss, once it has been taken: stated, not re-offered.
///
/// A recorded toss is settled history — it has already decided who bats,
/// serves, raids or chases, and the opening state of the match was built from
/// it. So from that moment it stops being a question anywhere in the app and
/// becomes one line at the top of the pad. Re-opening [TossDialog] on a match
/// in progress could only ever overwrite the decision the innings was built
/// on, which is why nothing offers it any more.
///
/// Sport-agnostic on purpose: the choice is named from the same catalogue the
/// dialog offered it from, so "Bat", "Raid first", "First possession" and
/// "Play White" all read correctly without this widget knowing a single
/// sport's rules.
class TossResultStrip extends StatelessWidget {
  const TossResultStrip({super.key, required this.fixture});

  final Fixture fixture;

  @override
  Widget build(BuildContext context) {
    final won = fixture.tossWonByEntrantId;
    if (won == null || won.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final name =
        won == fixture.entrantAId ? fixture.entrantAName : fixture.entrantBName;
    final choice = TossOptions.resolve(fixture.sport, fixture.tossDecision);
    // Chess draws lots for colour rather than tossing; calling it a toss here
    // would be the same error the dialog's own title avoids.
    final verb = fixture.sport == 'chess' ? 'won the draw' : 'won the toss';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.monetization_on_outlined, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$name $verb \u00b7 ${choice.label}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
/// Asks which player fills a role — the incoming batter, the next bowler, or
/// the opening trio.
///
/// Returned as a payload so the caller can merge it into the ScoreAction the
/// plugin asked for.
class PlayerPicker extends StatefulWidget {
  const PlayerPicker({
    super.key,
    required this.title,
    required this.roles,
    required this.candidatesFor,
    this.optionalRoles = const {},
    this.multiRoles = const {},
    this.exclusiveRoleGroups = const [],
    this.values = const [],
    this.choices = const [],
    this.texts = const [],
  });

  /// Short free text collected alongside the rest — a chess move in algebraic
  /// notation, a dart checkout, a stroke code. Deliberately not a notes field:
  /// see [TextPrompt].
  final List<TextPrompt> texts;

  /// Fixed-answer questions — "why is the match ending?" — asked after the
  /// people and the numbers. See [ChoicePrompt].
  final List<ChoicePrompt> choices;

  /// Numbers to collect alongside the people — a time, a distance, a wind
  /// reading. Rendered after the roles, because "who" comes before "how
  /// fast".
  final List<ValuePrompt> values;

  final String title;

  /// payload key -> label, in the order they should be chosen.
  final Map<String, String> roles;

  /// Which players may fill a given role.
  final List<MatchPlayer> Function(String roleKey) candidatesFor;

  /// Roles the scorer may leave blank.
  ///
  /// An assist is the case that matters: plenty of goals have none, and a
  /// picker that will not close without one teaches the scorer to name
  /// whoever is nearest, which is worse than recording nothing. Anything not
  /// listed here is required, because the engine will reject the event
  /// without it.
  final Set<String> optionalRoles;

  /// Roles that name SEVERAL people and are written as a list.
  ///
  /// A kabaddi tackle is the case: three defenders get hold of the raider and
  /// the engine splits the points between all of them, so a single dropdown
  /// would hand a super-tackle to one player and falsify the rest.
  final Set<String> multiRoles;

  /// Groups of roles that must each name a DIFFERENT person.
  ///
  /// The cricket case is the one that got reported: a scorer could pick the
  /// same player as striker and non-striker, and only found out after tapping
  /// through the whole dialog, when the engine rejected the delivery. The
  /// answer to "who is at the other end" can never be "the person already on
  /// strike", so offering them was never right — the fix is to stop offering,
  /// not to explain the refusal better.
  ///
  /// The caller derives these from the prompts drawing on the same pool, so
  /// this generalises past cricket without knowing any sport: a footballer
  /// cannot assist their own goal, and a kho-kho attacker cannot tag himself.
  /// A prompt drawn from the OPPOSING side is in a different group and stays
  /// unfiltered — the bowler is on the other team and has nothing to do with
  /// who is batting.
  final List<Set<String>> exclusiveRoleGroups;

  @override
  State<PlayerPicker> createState() => _PlayerPickerState();
}

class _PlayerPickerState extends State<PlayerPicker> {
  final Map<String, String> _chosen = {};
  final Map<String, Set<String>> _chosenMany = {};

  /// The answer picked for each [ChoicePrompt], by payload key.
  final Map<String, String> _picked = {};

  bool _filled(String key) => widget.multiRoles.contains(key)
      ? (_chosenMany[key]?.isNotEmpty ?? false)
      : (_chosen[key]?.isNotEmpty ?? false);

  /// The candidates for [key], minus anyone already named in a role that must
  /// be a different person.
  ///
  /// Recomputed on every build rather than cached, because it depends on what
  /// the scorer has picked so far: choosing a striker has to remove that
  /// player from the non-striker list on the same frame.
  List<MatchPlayer> _available(String key) {
    final taken = <String>{};
    for (final group in widget.exclusiveRoleGroups) {
      if (!group.contains(key)) continue;
      for (final other in group) {
        if (other == key) continue;
        final one = _chosen[other];
        if (one != null && one.isNotEmpty) taken.add(one);
        final many = _chosenMany[other];
        if (many != null) taken.addAll(many);
      }
    }
    final pool = widget.candidatesFor(key);
    if (taken.isEmpty) return pool;
    return [
      for (final p in pool)
        if (!taken.contains(p.id)) p,
    ];
  }

  /// Drops a selection that a LATER pick has just made illegal.
  ///
  /// Without this, picking A as striker and then A as non-striker is blocked,
  /// but picking A as non-striker first and then A as striker would leave A
  /// sitting in both — the second dropdown's filter only runs against what was
  /// chosen before it. Clearing the clash keeps the dialog in a state the
  /// engine would accept, whatever order the scorer answers in.
  void _clearClashes(String justSet) {
    final id = _chosen[justSet];
    if (id == null || id.isEmpty) return;
    for (final group in widget.exclusiveRoleGroups) {
      if (!group.contains(justSet)) continue;
      for (final other in group) {
        if (other == justSet) continue;
        if (_chosen[other] == id) _chosen.remove(other);
        _chosenMany[other]?.remove(id);
      }
    }
  }

  /// Raw text per value field, kept as typed rather than as a parsed number.
  ///
  /// A half-typed "10." is not a double and must not be discarded on the
  /// keystroke that produced it — parsing on submit rather than on change is
  /// what lets somebody type a time without the field fighting them.
  final Map<String, String> _typed = {};

  /// Raw text per free-text field, trimmed only when it is read.
  ///
  /// Kept separate from [_typed] because these are not numbers and must never
  /// be parsed: in algebraic notation `b4` is a pawn move and `B4` is not a
  /// move at all, so the string a scorer typed is the whole of the answer.
  final Map<String, String> _entered = {};

  String? _textOf(TextPrompt t) {
    final text = _entered[t.key]?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  double? _valueOf(ValuePrompt v) {
    final text = _typed[v.key]?.trim() ?? '';
    if (text.isEmpty) return null;
    final parsed = double.tryParse(text);
    if (parsed == null) return null;
    if (v.min != null && parsed < v.min!) return null;
    if (v.max != null && parsed > v.max!) return null;
    return parsed;
  }

  bool get _complete =>
      widget.roles.keys.every(
        (key) => widget.optionalRoles.contains(key) || _filled(key),
      ) &&
      widget.values.every((v) => v.optional || _valueOf(v) != null) &&
      widget.texts.every((t) => t.optional || _textOf(t) != null) &&
      // A required choice with nothing picked is the case this whole prompt
      // exists for: a retirement with no reason is exactly what the engine
      // refuses, so the dialog must not offer to send one.
      widget.choices.every((c) => c.optional || _picked[c.key] != null);

  /// Fills a role that has exactly one candidate, so the scorer is not asked
  /// a question with one answer.
  ///
  /// Real on a ground: a five-a-side with one keeper, or a kho-kho batch down
  /// to its last defender. Tapping through a dropdown of one during play is
  /// the kind of friction that gets an app put down.
  @override
  void initState() {
    super.initState();
    for (final key in widget.roles.keys) {
      if (widget.multiRoles.contains(key)) continue;
      final only = _available(key);
      if (only.length == 1) _chosen[key] = only.first.id;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in widget.roles.entries)
              if (widget.multiRoles.contains(entry.key))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.value,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final p in _available(entry.key))
                            FilterChip(
                              label: Text(p.name),
                              selected:
                                  _chosenMany[entry.key]?.contains(p.id) ??
                                      false,
                              onSelected: (on) => setState(() {
                                final set = _chosenMany.putIfAbsent(
                                  entry.key,
                                  () => <String>{},
                                );
                                if (on) {
                                  set.add(p.id);
                                } else {
                                  set.remove(p.id);
                                }
                              }),
                            ),
                        ],
                      ),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: DropdownButtonFormField<String>(
                    value: _chosen[entry.key],
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: entry.value,
                      helperText: widget.optionalRoles.contains(entry.key)
                          ? 'Optional'
                          : null,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      if (widget.optionalRoles.contains(entry.key))
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Nobody'),
                        ),
                      for (final p in _available(entry.key))
                        DropdownMenuItem(value: p.id, child: Text(p.name)),
                    ],
                    onChanged: (v) => setState(() {
                      _chosen[entry.key] = v ?? '';
                      _clearClashes(entry.key);
                    }),
                  ),
                ),
            for (final v in widget.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: TextFormField(
                  autofocus: widget.roles.isEmpty,
                  keyboardType: TextInputType.numberWithOptions(
                    decimal: !v.isInteger,
                    // A wind reading can be negative; a time cannot. The
                    // keyboard offers a minus sign only where one is legal.
                    signed: (v.min ?? 0) < 0,
                  ),
                  decoration: InputDecoration(
                    labelText: v.label,
                    suffixText: v.unit,
                    helperText: v.optional ? 'Optional' : null,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (text) => setState(() => _typed[v.key] = text),
                ),
              ),
            for (final t in widget.texts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: TextFormField(
                  // Focused when it is the only question, which is the chess
                  // case: the scorer taps Add move and types straight into it.
                  autofocus: widget.roles.isEmpty && widget.values.isEmpty,
                  maxLength: t.maxLength,
                  // Off unless the prompt asks for it, because the case that
                  // forced this field is one where case is MEANING and an
                  // autocapitalising keyboard would corrupt every entry.
                  textCapitalization: t.autoCapitalize
                      ? TextCapitalization.sentences
                      : TextCapitalization.none,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: t.label,
                    hintText: t.hint,
                    helperText: t.optional ? 'Optional' : null,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (text) => setState(() => _entered[t.key] = text),
                ),
              ),
            for (final c in widget.choices)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: DropdownButtonFormField<String>(
                  value: _picked[c.key],
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: c.label,
                    helperText: c.optional ? 'Optional' : null,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final o in c.options)
                      DropdownMenuItem(value: o.value, child: Text(o.label)),
                  ],
                  onChanged: (v) => setState(() {
                    if (v == null) {
                      _picked.remove(c.key);
                    } else {
                      _picked[c.key] = v;
                    }
                  }),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          // Every REQUIRED role must be filled: a half-named delivery is
          // exactly the state the engine refuses.
          onPressed: _complete
              ? () => Navigator.pop(context, <String, dynamic>{
                    // Blank optional roles are dropped rather than sent as
                    // empty strings — an engine checking `payload['assistId']
                    // != null` would otherwise credit an assist to nobody.
                    for (final e in _chosen.entries)
                      if (e.value.isNotEmpty) e.key: e.value,
                    for (final e in _chosenMany.entries)
                      if (e.value.isNotEmpty) e.key: e.value.toList(),
                    // Integers go over the wire as ints: a lane is lane 4,
                    // not lane 4.0, and the engine reads `is num` either way
                    // but the stored event should say what it means.
                    for (final v in widget.values)
                      if (_valueOf(v) case final n?)
                        v.key: v.isInteger ? n.round() : n,
                    // Sent as typed. A blank optional field is dropped rather
                    // than sent as an empty string, for the same reason a
                    // blank optional role is.
                    for (final t in widget.texts)
                      if (_textOf(t) case final s?) t.key: s,
                    for (final e in _picked.entries) e.key: e.value,
                  })
              : null,
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
