import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/models/arena_match.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/arena/arena_game.dart';
import '../../domain/arena/arena_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/identity.dart';
import '../../shared/section_header.dart';
import '../../shared/ui_kit.dart';
import 'arena_providers.dart';
import 'widgets/arena_game_emblem.dart';

/// The Arena: board games between members.
///
/// Deliberately separate from everything else in the app, and it says so at
/// the top. A club's cricket record and a member's Glicko come from matches
/// played on a ground with people watching; a chess game on two phones does
/// not, and quietly mixing the two would make both less trustworthy. Nothing
/// that happens here leaves here.
class ArenaHomeScreen extends ConsumerWidget {
  const ArenaHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(arenaInboxProvider);
    final loading = ref.watch(myArenaMatchesProvider).isLoading;

    return AppScaffold(
      title: 'Arena',
      subtitle: 'Board games, just for the fun of it',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          const _ArenaNote(),
          const _LadderLink(),
          if (inbox.invitations.isNotEmpty) ...[
            const SectionHeader(icon: Icons.mark_chat_unread_outlined, title: 'Waiting for you'),
            for (final match in inbox.invitations)
              _MatchCard(match: match, tone: _CardTone.invitation),
          ],
          if (inbox.yourMove.isNotEmpty) ...[
            const SectionHeader(icon: Icons.touch_app_outlined, title: 'Your move'),
            for (final match in inbox.yourMove)
              _MatchCard(match: match, tone: _CardTone.yourMove),
          ],
          const SectionHeader(icon: Icons.grid_view_rounded, title: 'Pick a game'),
          const _GameGrid(),
          if (inbox.theirMove.isNotEmpty) ...[
            const SectionHeader(icon: Icons.hourglass_bottom_outlined, title: 'Their move'),
            for (final match in inbox.theirMove)
              _MatchCard(match: match, tone: _CardTone.waiting),
          ],
          if (inbox.sent.isNotEmpty) ...[
            const SectionHeader(icon: Icons.send_outlined, title: 'Challenges you sent'),
            for (final match in inbox.sent)
              _MatchCard(match: match, tone: _CardTone.waiting),
          ],
          if (inbox.finished.isNotEmpty) ...[
            const SectionHeader(icon: Icons.history, title: 'Finished'),
            for (final match in inbox.finished.take(15))
              _MatchCard(match: match, tone: _CardTone.finished),
          ],
          if (loading && inbox.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: PsListSkeleton(),
            ),
        ],
      ),
    );
  }
}

class _ArenaNote extends StatelessWidget {
  const _ArenaNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Ps.surface,
        borderRadius: BorderRadius.circular(Ps.radius),
        border: Border.all(color: Ps.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.psychology_outlined, size: 20, color: Ps.primary),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: const TextSpan(
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: Ps.muted,
                ),
                children: [
                  TextSpan(
                    text: 'Nothing here is rated. ',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Ps.ink,
                    ),
                  ),
                  TextSpan(
                    text: 'Arena games do not touch your Glicko, your career '
                        'record or your club standings — an unwatched board '
                        'is too easy to cheat for a result here to mean '
                        'anything about how you play. Every move is kept so '
                        'you can walk back through the game afterwards.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The way through to the ladder.
///
/// Given its own row rather than an app-bar action because it is a
/// destination people go looking for, and because the row has space to say
/// what the ladder is NOT — which an icon does not.
class _LadderLink extends ConsumerWidget {
  const _LadderLink();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(myArenaStatsProvider).valueOrNull;
    final record = mine?.overall;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      child: Material(
        color: Ps.surface,
        borderRadius: BorderRadius.circular(Ps.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(Ps.radius),
          onTap: () => context.push(Routes.arenaLadder),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Ps.radius),
              border: Border.all(color: Ps.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.emoji_events_outlined,
                    size: 20, color: Ps.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Arena ladder',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        record == null || record.isEmpty
                            ? 'Wins and losses in here only'
                            : '${record.played} played · ${record.summary}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Ps.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Ps.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The six games, as tiles.
///
/// Laid out as explicit rows rather than a `GridView.count`, and the reason is
/// mobile. A grid needs a `childAspectRatio` — one fixed height for every tile
/// — and on a 360dp phone the two-line taglines plus a system font scaled up
/// for accessibility overflowed it, which Flutter renders as the yellow-and-
/// black stripes across the bottom of the card. Rows of `Expanded` tiles
/// inside an `IntrinsicHeight` size to their own content instead: every tile
/// in a row matches the tallest one, and the row grows if the text does.
class _GameGrid extends StatelessWidget {
  const _GameGrid();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Two across on a phone. Three tiles on a 360dp screen leaves each
          // about 105dp wide, which is narrower than the word "Connect Four".
          final columns = constraints.maxWidth < 520
              ? 2
              : constraints.maxWidth < 900
                  ? 3
                  : 4;

          final rows = <Widget>[];
          for (var start = 0;
              start < ArenaGames.all.length;
              start += columns) {
            final slice =
                ArenaGames.all.skip(start).take(columns).toList();
            rows.add(
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < columns; i++) ...[
                      // A short final row is padded with blanks so its tiles
                      // keep the width of the ones above rather than
                      // stretching across the screen.
                      Expanded(
                        child: i < slice.length
                            ? _GameTile(game: slice[i])
                            : const SizedBox.shrink(),
                      ),
                      if (i != columns - 1) const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            );
          }

          return Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                rows[i],
                if (i != rows.length - 1) const SizedBox(height: 8),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _GameTile extends StatelessWidget {
  const _GameTile({required this.game});

  final ArenaGame game;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Ps.surface,
      borderRadius: BorderRadius.circular(Ps.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(Ps.radius),
        onTap: () => context.push(Routes.arenaChallenge(game.id)),
        child: Container(
          padding: const EdgeInsets.fromLTRB(11, 11, 11, 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Ps.radius),
            border: Border.all(color: Ps.border),
          ),
          // Content-sized, with no Spacer: a Spacer needs a bounded height,
          // which is exactly what this layout deliberately no longer has.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ArenaGameEmblem(game: game),
                  const SizedBox(width: 6),
                  // Expanded rather than a Spacer plus a naturally-sized
                  // Text: with the system font scaled up for accessibility,
                  // "25 min" grows past what is left beside the emblem on a
                  // 320dp phone, and an unconstrained Text in a Row has no
                  // way to give ground. This one ellipsises instead.
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        game.duration,
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Ps.faint,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Text(
                game.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14.5,
                  color: Ps.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                game.tagline,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.25,
                  color: Ps.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _CardTone { invitation, yourMove, waiting, finished }

class _MatchCard extends ConsumerStatefulWidget {
  const _MatchCard({required this.match, required this.tone});

  final ArenaMatch match;
  final _CardTone tone;

  @override
  ConsumerState<_MatchCard> createState() => _MatchCardState();
}

class _MatchCardState extends ConsumerState<_MatchCard> {
  bool _busy = false;

  ArenaMatch get match => widget.match;
  _CardTone get tone => widget.tone;

  /// Accepts and goes straight to the board.
  ///
  /// The board is where the game IS, and an accepted challenge with nothing
  /// on screen afterwards leaves somebody looking at a list wondering whether
  /// it worked. The push happens after the write returns, so a refusal —
  /// already answered, withdrawn a second ago — surfaces here rather than on
  /// a board that then has nothing to show.
  Future<void> _accept() async {
    final uid = ref.read(currentUidProvider);
    if (uid == null || _busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(arenaRepositoryProvider).accept(match.id, uid);
      if (mounted) context.push(Routes.arenaBoard(match.id));
    } on AppException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline() async {
    final uid = ref.read(currentUidProvider);
    if (uid == null || _busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(arenaRepositoryProvider).withdraw(match.id, uid);
    } on AppException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUidProvider);
    final other = uid == null ? null : match.opponentOf(uid);
    final game = match.game;

    final (badge, colour) = switch (tone) {
      // Not rendered for an invitation — that card carries buttons instead —
      // but kept so the switch stays total over the tones.
      _CardTone.invitation => ('Accept?', Ps.primary),
      _CardTone.yourMove => ('Your move', Ps.primary),
      _CardTone.waiting => (
          match.status == ArenaStatus.pending ? 'Sent' : 'Waiting',
          Ps.muted,
        ),
      _CardTone.finished => (_resultLabel(uid), Ps.muted),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        color: Ps.surface,
        borderRadius: BorderRadius.circular(Ps.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(Ps.radius),
          onTap: () => context.push(Routes.arenaBoard(match.id)),
          child: Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Ps.radius),
              border: Border.all(
                color: tone == _CardTone.yourMove ||
                        tone == _CardTone.invitation
                    ? Ps.primary.withValues(alpha: 0.45)
                    : Ps.border,
              ),
            ),
            child: Row(
              children: [
                PsAvatar(
                  name: match.nameOf(other),
                  photoUrl: match.photos[other],
                  seed: other,
                  size: 36,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        match.nameOf(other),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        [
                          game?.name ?? match.gameId,
                          if (match.moves.isNotEmpty)
                            '${match.moves.length} moves',
                          if (match.orgName != null) match.orgName!,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Ps.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (tone == _CardTone.invitation)
                  // Answered from the list. Tapping the card still opens the
                  // board for a look first, which is the right move when the
                  // question is "who is this and what are they proposing".
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: _busy ? null : _decline,
                        style: TextButton.styleFrom(
                          foregroundColor: Ps.muted,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: const Text('Decline'),
                      ),
                      const SizedBox(width: 4),
                      FilledButton(
                        onPressed: _busy ? null : _accept,
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                        child: const Text('Play'),
                      ),
                    ],
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: colour.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: colour,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _resultLabel(String? uid) {
    final result = match.result;
    if (result == null) return 'Over';
    if (result.isDraw) return 'Drawn';
    return result.winnerUid == uid ? 'Won' : 'Lost';
  }
}
