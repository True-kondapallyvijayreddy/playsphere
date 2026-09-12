import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../domain/career/club_record.dart';
import '../../../domain/scoring/scoring_registry.dart';
import '../../../shared/ui_kit.dart';

/// The three numbers a club is judged on, plus the two that stop them being
/// read wrongly.
///
/// Won/lost/drawn come only from matches where the club itself was a named
/// side — see [ClubSportRecord]'s doc. Where a club has played plenty and
/// none of it was club-vs-club, showing "0 Won" next to "40 Matches" would
/// read as forty defeats, so the record collapses to what is actually known
/// and [ClubRecordNote] says why underneath.
class ClubRecordStats extends StatelessWidget {
  const ClubRecordStats({
    super.key,
    required this.matches,
    required this.won,
    required this.lost,
    required this.drawn,
    required this.winRate,
    this.onMatchesTap,
  });

  ClubRecordStats.of(ClubRecord record, {super.key, this.onMatchesTap})
      : matches = record.matches,
        won = record.won,
        lost = record.lost,
        drawn = record.drawn,
        winRate = record.winRate;

  ClubRecordStats.ofSport(ClubSportRecord record, {super.key, this.onMatchesTap})
      : matches = record.matches,
        won = record.won,
        lost = record.lost,
        drawn = record.drawn,
        winRate = record.winRate;

  final int matches;
  final int won;
  final int lost;
  final int drawn;
  final double? winRate;
  final VoidCallback? onMatchesTap;

  bool get _hasRecord => won + lost + drawn > 0;

  @override
  Widget build(BuildContext context) {
    return PsStatRow(
      stats: [
        PsStat(
          value: psGrouped(matches),
          label: matches == 1 ? 'Match' : 'Matches',
          onTap: onMatchesTap,
        ),
        if (_hasRecord) ...[
          PsStat(value: psGrouped(won), label: 'Won'),
          PsStat(value: psGrouped(lost), label: 'Lost'),
          if (drawn > 0) PsStat(value: psGrouped(drawn), label: 'Drawn'),
          if (winRate != null)
            PsStat(
              value: '${(winRate! * 100).round()}%',
              label: 'Win rate',
            ),
        ],
      ],
    );
  }
}

/// The sentence under a record that says which matches it is a record OF.
///
/// Nothing at all when every match the club played was club-vs-club, because
/// then the record covers all of them and there is nothing to qualify.
class ClubRecordNote extends StatelessWidget {
  const ClubRecordNote({
    super.key,
    required this.decided,
    required this.internal,
  });

  ClubRecordNote.of(ClubRecord record, {super.key})
      : decided = record.decided,
        internal = record.internal;

  ClubRecordNote.ofSport(ClubSportRecord record, {super.key})
      : decided = record.decided,
        internal = record.internal;

  /// Matches with a club-level result on them.
  final int decided;

  /// Matches the club played that were its own sides against each other, or
  /// events it hosted for other people.
  final int internal;

  @override
  Widget build(BuildContext context) {
    if (internal == 0) return const SizedBox.shrink();

    final text = decided == 0
        ? 'Every match so far has been played inside the club — its own '
            'teams, or an event it hosted. A win/loss record starts the '
            'first time the club plays another club.'
        : 'Won, lost and drawn cover the ${psGrouped(decided)} '
            '${decided == 1 ? 'match' : 'matches'} played against another '
            'club. The other ${psGrouped(internal)} were played inside the '
            'club, where there is no side to credit.';

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: Ps.muted, height: 1.4),
      ),
    );
  }
}

/// A win/loss/draw bar — the club's record read at a glance rather than
/// counted off three numbers.
///
/// Renders nothing where nothing has been decided, rather than a full-width
/// grey bar that looks like a result the club has not got.
class ClubFormBar extends StatelessWidget {
  const ClubFormBar({
    super.key,
    required this.won,
    required this.lost,
    required this.drawn,
  });

  final int won;
  final int lost;
  final int drawn;

  @override
  Widget build(BuildContext context) {
    final total = won + lost + drawn;
    if (total == 0) return const SizedBox.shrink();

    return Semantics(
      label: '$won won, $lost lost, $drawn drawn',
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          height: 6,
          child: Row(
            children: [
              if (won > 0) Expanded(flex: won, child: const ColoredBox(color: Ps.primary)),
              if (drawn > 0)
                Expanded(flex: drawn, child: const ColoredBox(color: Ps.faint)),
              if (lost > 0)
                Expanded(flex: lost, child: const ColoredBox(color: Ps.live)),
            ],
          ),
        ),
      ),
    );
  }
}

/// One sport's line in a club's record: the badge, the played/won/lost line,
/// the form bar, and a chevron into that sport's detail.
class ClubSportRecordRow extends StatelessWidget {
  const ClubSportRecordRow({
    super.key,
    required this.orgId,
    required this.record,
    this.dense = false,
  });

  final String orgId;
  final ClubSportRecord record;

  /// The home-screen variant: no stat chips, tighter padding. The full
  /// analytics screen shows the same row with its figures.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final sport = SportCatalog.byId(record.sportId);
    final top = record.topPlayers(1);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: PsCard(
        padding: EdgeInsets.all(dense ? 12 : 14),
        onTap: () => context.push(Routes.clubSportStats(orgId, record.sportId)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SportBadge(sportId: record.sportId, size: dense ? 34 : 38),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sport.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Ps.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _line(record),
                        style: const TextStyle(fontSize: 12, color: Ps.muted),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 20, color: Ps.faint),
              ],
            ),
            if (record.decided > 0) ...[
              const SizedBox(height: 10),
              ClubFormBar(
                won: record.won,
                lost: record.lost,
                drawn: record.drawn,
              ),
            ],
            if (top.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.star_outline, size: 14, color: Ps.faint),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _topLine(record, top.first),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Ps.muted),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _line(ClubSportRecord r) {
    final played = '${psGrouped(r.matches)} '
        '${r.matches == 1 ? 'match' : 'matches'}';
    if (r.decided == 0) return played;
    return '$played · ${r.won}W ${r.lost}L'
        '${r.drawn > 0 ? ' ${r.drawn}D' : ''}';
  }

  static String _topLine(ClubSportRecord r, ClubPlayerLine p) {
    final key = r.headlineStats.isEmpty ? null : r.headlineStats.first;
    if (key == null) {
      return '${p.name} · ${p.matches} '
          '${p.matches == 1 ? 'appearance' : 'appearances'}';
    }
    return '${p.name} · ${psFormatStat(p[key])} ${psHumanizeCounter(key)}';
  }
}

/// The club's leading players in one sport, as a ranked board.
///
/// Ranked on the sport's own headline stat — runs in cricket, goals in
/// football — because a "top players" list ordered by something the sport
/// does not care about is worse than none. A sport that declares no headline
/// stat ranks on appearances instead, and the column heading says so.
///
/// This is the club-scoped counterpart to `LeaderboardScreen`, which ranks
/// one stat across the whole platform. Both exist because they answer
/// different questions: that one says "who is the best in the country at
/// this", and a club's page needs "who is the best HERE" — the name a
/// prospective member will actually be playing alongside on Sunday.
class ClubTopPlayers extends StatelessWidget {
  const ClubTopPlayers({
    super.key,
    required this.record,
    this.limit = 5,
    this.title = 'Top players',
  });

  final ClubSportRecord record;
  final int limit;
  final String title;

  @override
  Widget build(BuildContext context) {
    final players = record.topPlayers(limit);
    if (players.isEmpty) return const SizedBox.shrink();

    final keys = record.headlineStats.take(2).toList();

    return PsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Ps.ink,
                  ),
                ),
              ),
              for (final key in keys)
                SizedBox(
                  width: 58,
                  child: Text(
                    psHumanizeCounter(key),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Ps.faint),
                  ),
                ),
              if (keys.isEmpty)
                const SizedBox(
                  width: 58,
                  child: Text(
                    'Played',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 11, color: Ps.faint),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < players.length; i++)
            _PlayerRow(rank: i + 1, player: players[i], keys: keys),
        ],
      ),
    );
  }
}

/// The club's most-decorated players — player-of-the-match awards, which is
/// the one honour a player can take out of a match their side lost.
///
/// Separate from [ClubTopPlayers] on purpose: a top-scorer board rewards
/// volume and rewards the same two people every season, while awards reward
/// the best performance on a given day and surface a different set of names.
/// A club whose board shows both is describing a squad rather than a pair of
/// stars.
class ClubMvpBoard extends StatelessWidget {
  const ClubMvpBoard({super.key, required this.record, this.limit = 5});

  final ClubSportRecord record;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final leaders = record.mvpLeaders(limit);
    if (leaders.isEmpty) return const SizedBox.shrink();

    return PsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.military_tech_outlined,
                  size: 17, color: Color(0xFFD97706)),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Player of the match',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Ps.ink,
                  ),
                ),
              ),
              Text(
                '${psGrouped(record.mvps)} awarded',
                style: const TextStyle(fontSize: 11, color: Ps.faint),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < leaders.length; i++)
            _AwardRow(rank: i + 1, player: leaders[i]),
        ],
      ),
    );
  }
}

/// The rank marker down the left of a board: a coloured disc for the top
/// three, a plain number after that.
///
/// Medals stop at three because that is what a podium is. Colouring the whole
/// list makes every position look like a placing and the fourth-best player
/// look like they won something.
class _RankPip extends StatelessWidget {
  const _RankPip({required this.rank});

  final int rank;

  static const _gold = Color(0xFFD97706);
  static const _silver = Color(0xFF94A3B8);
  static const _bronze = Color(0xFFB45309);

  @override
  Widget build(BuildContext context) {
    final color = switch (rank) {
      1 => _gold,
      2 => _silver,
      3 => _bronze,
      _ => null,
    };
    return SizedBox(
      width: 26,
      child: color == null
          ? Text(
              '$rank',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Ps.faint,
              ),
            )
          : Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
    );
  }
}

/// One player's name and sub-line, shared by both boards.
///
/// A guest — someone who turned up, played, and has never installed the app —
/// is on the board and is labelled as one rather than linked to a profile
/// that does not exist. Leaving them off would produce a top-scorer list with
/// the top scorer missing, which is the version of "correct" nobody at the
/// ground would accept.
class _PlayerIdentity extends StatelessWidget {
  const _PlayerIdentity({required this.player, required this.extra});

  final ClubPlayerLine player;
  final List<String> extra;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          player.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: Ps.ink,
          ),
        ),
        Text(
          [
            ...extra,
            if (!player.isRegistered) 'guest',
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11.5, color: Ps.muted),
        ),
      ],
    );
  }
}

/// Wraps a board row in a tap into the player's profile, where there is one.
class _ProfileLink extends StatelessWidget {
  const _ProfileLink({required this.uid, required this.child});

  final String? uid;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final id = uid;
    if (id == null) return child;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => context.push(Routes.profile(id)),
      child: child,
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.rank,
    required this.player,
    required this.keys,
  });

  final int rank;
  final ClubPlayerLine player;
  final List<String> keys;

  @override
  Widget build(BuildContext context) {
    return _ProfileLink(
      uid: player.uid,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            _RankPip(rank: rank),
            const SizedBox(width: 8),
            Expanded(
              child: _PlayerIdentity(
                player: player,
                extra: [
                  '${player.matches} '
                      '${player.matches == 1 ? 'match' : 'matches'}',
                  if (player.won > 0) '${player.won} won',
                  if (player.mvps > 0)
                    '${player.mvps} '
                        '${player.mvps == 1 ? 'award' : 'awards'}',
                ],
              ),
            ),
            for (final key in keys)
              SizedBox(
                width: 58,
                child: Text(
                  psFormatStat(player[key]),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Ps.ink,
                  ),
                ),
              ),
            if (keys.isEmpty)
              SizedBox(
                width: 58,
                child: Text(
                  psGrouped(player.matches),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Ps.ink,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AwardRow extends StatelessWidget {
  const _AwardRow({required this.rank, required this.player});

  final int rank;
  final ClubPlayerLine player;

  @override
  Widget build(BuildContext context) {
    return _ProfileLink(
      uid: player.uid,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            _RankPip(rank: rank),
            const SizedBox(width: 8),
            Expanded(
              child: _PlayerIdentity(
                player: player,
                extra: [
                  '${player.matches} '
                      '${player.matches == 1 ? 'match' : 'matches'}',
                ],
              ),
            ),
            SizedBox(
              width: 58,
              child: Text(
                psGrouped(player.mvps),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Ps.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
