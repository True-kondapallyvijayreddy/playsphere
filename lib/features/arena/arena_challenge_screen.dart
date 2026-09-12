import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../data/org_repository.dart' show PlayerLookup;
import '../../domain/arena/arena_game.dart';
import '../../domain/arena/arena_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/identity.dart';
import '../../shared/section_header.dart';
import '../../shared/ui_kit.dart';
import 'arena_providers.dart';

/// Pick a variant, pick an opponent, send it.
///
/// The opponent list is drawn from the clubs the player is actually in, which
/// is the only directory the app has that is both useful and safe to show — a
/// global list of every member would be a people-search, and the app does not
/// have one for good reason. A player code covers the rest: somebody met at a
/// tournament reads out `PSOS-4K7M2` and gets challenged without either of
/// them joining anything.
class ArenaChallengeScreen extends ConsumerStatefulWidget {
  const ArenaChallengeScreen({super.key, required this.gameId});

  final String gameId;

  @override
  ConsumerState<ArenaChallengeScreen> createState() =>
      _ArenaChallengeScreenState();
}

class _ArenaChallengeScreenState extends ConsumerState<ArenaChallengeScreen> {
  String? _variantId;
  String _query = '';
  bool _busy = false;
  PlayerLookup? _found;
  String? _lookupError;

  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = ArenaGames.byId(widget.gameId);
    if (game == null) {
      return const AppScaffold(
        title: 'Arena',
        body: Center(child: Text('That game is not available.')),
      );
    }

    final variant = game.variant(_variantId);
    final everyone = ref.watch(arenaOpponentsProvider);
    final query = _query.toLowerCase();
    final matches = query.isEmpty
        ? everyone
        : everyone
            .where((o) =>
                o.displayName.toLowerCase().contains(query) ||
                o.where.toLowerCase().contains(query))
            .toList();

    return AppScaffold(
      title: game.name,
      subtitle: 'Challenge someone',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (game.variants.length > 1) ...[
            const SectionHeader(
              icon: Icons.tune,
              title: 'Board',
            ),
            _VariantPicker(
              game: game,
              selected: variant,
              onPick: (v) => setState(() => _variantId = v.id),
            ),
          ],
          SectionHeader(
            icon: Icons.person_search_outlined,
            title: 'Who are you playing?',
            subtitle: everyone.isEmpty
                ? 'Anyone in your clubs, or by player code'
                : '${everyone.length} '
                    '${everyone.length == 1 ? 'person' : 'people'} '
                    'across your clubs, or anyone by player code',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search by name or club',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          _CodeLookup(
            controller: _codeController,
            found: _found,
            error: _lookupError,
            busy: _busy,
            onLookup: _lookup,
            onChallenge: (uid) => _challenge(game, variant, uid),
          ),
          if (everyone.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'You are not in a club yet, so there is nobody to list here. '
                'A player code still works — ask them for theirs.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Ps.muted),
              ),
            )
          else if (matches.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Nobody in your clubs matches "$_query". If they are not in '
                'one of your clubs, their player code will still reach them.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Ps.muted),
              ),
            )
          else ...[
            const SectionHeader(
              icon: Icons.groups_outlined,
              title: 'In your clubs',
            ),
            // Not capped. A capped list is a list that quietly cannot do what
            // the screen says it does — see `arenaOpponentsProvider`.
            for (final person in matches)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: _PersonRow(
                  name: person.displayName,
                  photoUrl: person.photoUrl,
                  uid: person.uid,
                  subtitle: person.where,
                  busy: _busy,
                  onTap: () => _challenge(
                    game,
                    variant,
                    person.uid,
                    orgId: person.orgId,
                    orgName: person.clubNames.isEmpty
                        ? null
                        : person.clubNames.first,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _lookup() async {
    final typed = _codeController.text.trim();
    if (typed.isEmpty) return;
    setState(() {
      _busy = true;
      _lookupError = null;
      _found = null;
    });
    try {
      final result =
          await ref.read(userRepositoryProvider).findByPlayerCode(typed);
      final me = ref.read(currentUidProvider);
      setState(() {
        if (result == null) {
          _lookupError = 'No player with that code.';
        } else if (result.uid == me) {
          _lookupError = 'That is your own code.';
        } else {
          _found = result;
        }
      });
    } on AppException catch (e) {
      setState(() => _lookupError = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _challenge(
    ArenaGame game,
    GameVariant variant,
    String opponentUid, {
    String? orgId,
    String? orgName,
  }) async {
    if (_busy) return;
    final me = ref.read(currentUserProvider).valueOrNull;
    if (me == null) return;

    setState(() => _busy = true);
    try {
      final opponent =
          await ref.read(userRepositoryProvider).fetch(opponentUid);
      if (opponent == null) {
        throw const NotFoundException('That player could not be found.');
      }
      final matchId = await ref.read(arenaRepositoryProvider).challenge(
            game: game,
            variant: variant,
            from: me,
            to: opponent,
            orgId: orgId,
            orgName: orgName,
          );
      if (!mounted) return;
      // Straight to the board: it shows "waiting for them to accept", which
      // is more useful than a snackbar and is where they will come back to.
      context.pushReplacement(Routes.arenaBoard(matchId));
    } on AppException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _VariantPicker extends StatelessWidget {
  const _VariantPicker({
    required this.game,
    required this.selected,
    required this.onPick,
  });

  final ArenaGame game;
  final GameVariant selected;
  final ValueChanged<GameVariant> onPick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        children: [
          for (final variant in game.variants)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(Ps.radiusSm),
                onTap: () => onPick(variant),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Ps.surface,
                    borderRadius: BorderRadius.circular(Ps.radiusSm),
                    border: Border.all(
                      color: variant.id == selected.id
                          ? Ps.primary
                          : Ps.border,
                      width: variant.id == selected.id ? 1.6 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        variant.id == selected.id
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 18,
                        color: variant.id == selected.id
                            ? Ps.primary
                            : Ps.faint,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              variant.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                            if (variant.note != null)
                              Text(
                                variant.note!,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Ps.muted,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CodeLookup extends StatelessWidget {
  const _CodeLookup({
    required this.controller,
    required this.found,
    required this.error,
    required this.busy,
    required this.onLookup,
    required this.onChallenge,
  });

  final TextEditingController controller;
  final PlayerLookup? found;
  final String? error;
  final bool busy;
  final VoidCallback onLookup;
  final ValueChanged<String> onChallenge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    hintText: 'PSOS-XXXXX',
                    prefixIcon: Icon(Icons.badge_outlined),
                    isDense: true,
                  ),
                  onSubmitted: (_) => onLookup(),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: busy ? null : onLookup,
                child: const Text('Find'),
              ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                error!,
                style: const TextStyle(fontSize: 12, color: Ps.live),
              ),
            ),
          if (found != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _PersonRow(
                name: found!.displayName,
                photoUrl: found!.photoUrl,
                uid: found!.uid,
                subtitle: found!.code,
                busy: busy,
                onTap: () => onChallenge(found!.uid),
              ),
            ),
        ],
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.name,
    required this.photoUrl,
    required this.uid,
    required this.subtitle,
    required this.busy,
    required this.onTap,
  });

  final String name;
  final String? photoUrl;
  final String uid;
  final String subtitle;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Ps.surface,
      borderRadius: BorderRadius.circular(Ps.radiusSm),
      child: InkWell(
        borderRadius: BorderRadius.circular(Ps.radiusSm),
        onTap: busy ? null : onTap,
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Ps.radiusSm),
            border: Border.all(color: Ps.border),
          ),
          child: Row(
            children: [
              PsAvatar(name: name, photoUrl: photoUrl, seed: uid, size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                          fontSize: 11.5, color: Ps.muted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.sports_esports_outlined,
                  size: 18, color: Ps.primary),
            ],
          ),
        ),
      ),
    );
  }
}
