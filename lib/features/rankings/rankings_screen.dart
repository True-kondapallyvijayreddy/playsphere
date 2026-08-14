import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/club_standing.dart';
import '../../core/models/ranking_entry.dart';
import '../../core/providers.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui_kit.dart';

/// Which ladder the screen is showing.
///
/// Player and Club have data, from two different sources and necessarily so.
/// `rankingEntries` is written per *player* by `onTournamentCompleted`; a club
/// is not a competitor in a tournament draw, so its ladder is built instead
/// from inter-club fixtures — the one shape where a club plays as itself, with
/// an identity stable across every event (`functions/clubs.js`).
///
/// Team is still a known gap, and specifically: nothing in the product gives a
/// team an identity that survives a tournament. Entrant ids are scoped to one
/// competition, and no entry flow writes a team entrant tied to a club or a
/// sub-group. A team ladder needs that first — it is a registration feature,
/// not a ranking one. The tab says so rather than showing an empty table that
/// looks broken.
enum _Ladder {
  player('Player Rankings'),
  team('Team Rankings'),
  club('Club Rankings');

  const _Ladder(this.label);
  final String label;
}

/// How far back the ladder counts.
///
/// A real filter over `awardedAt`, not a decorative dropdown. "All time" is
/// still bounded by the rolling 52-week window every entry carries in
/// `expiresAt` — nothing on this list is older than a year by construction —
/// so it means "everything currently counting", which is what the ranking is.
enum _Window {
  all('All Time', null),
  year('Last 12 months', 365),
  quarter('Last 3 months', 90),
  month('Last 30 days', 30);

  const _Window(this.label, this.days);
  final String label;
  final int? days;
}

/// The ranking list — what people have won, over a rolling year.
///
/// Distinct from a rating, and the distinction matters. Glicko says how good
/// somebody is right now; this says what they have achieved and is what every
/// selection meeting in the world actually runs on. It is also the mechanism
/// that makes a district tournament worth entering: win one and your position
/// on this list moves that night, visibly, where a Telegram message vanishes.
class RankingsScreen extends ConsumerStatefulWidget {
  const RankingsScreen({super.key, this.orgId});

  /// Present when reached from inside a club, so the shell can show its
  /// navigation. The list itself spans every club — a ranking confined to one
  /// club is a club ladder, not a ranking.
  final String? orgId;

  @override
  ConsumerState<RankingsScreen> createState() => _RankingsScreenState();
}

class _RankingsScreenState extends ConsumerState<RankingsScreen> {
  late String _sportId = SportCatalog.all.first.id;
  _Ladder _ladder = _Ladder.player;
  _Window _window = _Window.all;

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LadderTabs(
          selected: _ladder,
          onSelected: (l) => setState(() => _ladder = l),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: _Dropdown<String>(
                  value: _sportId,
                  items: [
                    for (final sport in SportCatalog.all)
                      DropdownMenuItem(
                        value: sport.id,
                        child: Text(sport.name),
                      ),
                  ],
                  onChanged: (v) => setState(() => _sportId = v ?? _sportId),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Dropdown<_Window>(
                  value: _window,
                  items: [
                    for (final w in _Window.values)
                      DropdownMenuItem(value: w, child: Text(w.label)),
                  ],
                  onChanged: (v) => setState(() => _window = v ?? _window),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (_ladder) {
            _Ladder.player => _PlayerLadder(sportId: _sportId, window: _window),
            _Ladder.team => const _NotYetLadder(
                title: 'Team rankings are not published yet',
                message: 'A team has to keep the same identity from one '
                    'tournament to the next before it can hold a position. '
                    'Teams are named per event today, so there is nothing '
                    'stable to rank — club rankings work because a club '
                    'plays as itself.',
              ),
            _Ladder.club => _ClubLadder(sportId: _sportId, window: _window),
          },
        ),
      ],
    );

    final orgId = widget.orgId;
    if (orgId == null) {
      return Scaffold(
        backgroundColor: Ps.canvas,
        appBar: AppBar(
          backgroundColor: Ps.surface,
          foregroundColor: Ps.ink,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: const IconThemeData(color: Ps.ink),
          title: const Text(
            'Leaderboard',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Ps.ink,
            ),
          ),
        ),
        body: body,
      );
    }
    return AppScaffold(orgId: orgId, title: 'Leaderboard', body: body);
  }
}

/// The player ladder proper — the one tab with a data source behind it.
class _PlayerLadder extends ConsumerWidget {
  const _PlayerLadder({required this.sportId, required this.window});

  final String sportId;
  final _Window window;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(rankingProvider(sportId));
    final uid = ref.watch(currentUidProvider);

    return AsyncView(
      value: async,
      builder: (allRows) {
        final rows = _applyWindow(allRows, window);
        if (rows.isEmpty) {
          return EmptyState(
            icon: Icons.leaderboard_outlined,
            title: 'No rankings yet',
            message: window == _Window.all
                ? 'Points are awarded when a tournament is closed. Finish one '
                    'and it appears here.'
                : 'Nothing was won in this period. Try a longer one.',
          );
        }

        // Their own row, wherever it sits. Pinned below the table so someone
        // ranked 240th does not have to scroll to find out that they are.
        final mine = uid == null
            ? null
            : rows.where((r) => r.uid == uid).firstOrNull;

        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  ContentBounds(
                    maxWidth: 760,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
                          child: Text(
                            'Points from the last 52 weeks. A result drops off '
                            'a year after it was won, so a ranking has to be '
                            'defended rather than banked.',
                            style: TextStyle(fontSize: 12, color: Ps.muted),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: PsCard(
                            padding: EdgeInsets.zero,
                            child: Column(
                              children: [
                                const _LadderHeaderRow(),
                                for (var i = 0; i < rows.length; i++)
                                  _RankingRowTile(
                                    row: rows[i],
                                    isMe: rows[i].uid == uid,
                                    isLast: i == rows.length - 1,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (mine != null) _YourRankBar(row: mine),
          ],
        );
      },
    );
  }

  /// Re-ranks within the chosen period rather than filtering the existing
  /// list. Dropping rows from a finished ranking would leave the numbers
  /// intact — 1, 4, 9 — which reads as a broken list rather than as a
  /// three-month ladder.
  static List<RankingRow> _applyWindow(List<RankingRow> rows, _Window window) {
    final days = window.days;
    if (days == null) return rows;
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final kept = <RankingEntry>[
      for (final row in rows)
        for (final entry in row.entries)
          if (entry.awardedAt != null && entry.awardedAt!.isAfter(cutoff))
            entry,
    ];
    return buildRanking(kept);
  }
}

class _LadderTabs extends StatelessWidget {
  const _LadderTabs({required this.selected, required this.onSelected});

  final _Ladder selected;
  final ValueChanged<_Ladder> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Ps.surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          for (final ladder in _Ladder.values)
            Expanded(
              child: InkWell(
                onTap: () => onSelected(ladder),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: ladder == selected ? Ps.primary : Ps.border,
                        width: ladder == selected ? 2 : 1,
                      ),
                    ),
                  ),
                  child: Text(
                    ladder.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: ladder == selected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: ladder == selected ? Ps.primary : Ps.muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The column headings above the table.
///
/// "Points" and "Results", not the mockup's "Runs" and "Matches". Runs are a
/// cricket statistic and this screen serves fifteen sports — a chess player's
/// ranking has no runs in it, and a column heading that is wrong for most of
/// the catalogue is worse than one that is plain.
class _LadderHeaderRow extends StatelessWidget {
  const _LadderHeaderRow();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
      color: Ps.faint,
      letterSpacing: 0.6,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Ps.border)),
      ),
      child: const Row(
        children: [
          SizedBox(width: 30, child: Text('RANK', style: style)),
          SizedBox(width: 8),
          Expanded(child: Text('PLAYER', style: style)),
          SizedBox(
            width: 62,
            child: Text('POINTS', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(
            width: 62,
            child: Text('RESULTS', style: style, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

class _RankingRowTile extends StatelessWidget {
  const _RankingRowTile({
    required this.row,
    required this.isMe,
    required this.isLast,
  });

  final RankingRow row;
  final bool isMe;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        // A tint rather than a border, so their own row reads as highlighted
        // instead of as a section boundary.
        color: isMe ? Ps.primary.withValues(alpha: 0.06) : null,
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: Ps.border)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              '${row.rank}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                // The top three carry the accent. Beyond that a coloured
                // number stops meaning anything.
                color: row.rank <= 3 ? Ps.primary : Ps.muted,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _Avatar(name: row.displayName),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              row.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Ps.ink,
              ),
            ),
          ),
          SizedBox(
            width: 62,
            child: Text(
              psGrouped(row.points),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Ps.ink,
              ),
            ),
          ),
          SizedBox(
            width: 62,
            child: Text(
              '${row.eventsCounted}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13.5, color: Ps.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// The pinned "your rank" strip at the foot of the ladder.
class _YourRankBar extends StatelessWidget {
  const _YourRankBar({required this.row});

  final RankingRow row;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: const BoxDecoration(
        color: Ps.surface,
        border: Border(top: BorderSide(color: Ps.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Text(
                '${row.rank}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Ps.primary,
                ),
              ),
            ),
            _Avatar(name: row.displayName),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your Rank',
                    style: TextStyle(fontSize: 11, color: Ps.muted),
                  ),
                  Text(
                    row.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Ps.ink,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${psGrouped(row.points)} pts',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Ps.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An initial in a tinted circle.
///
/// Not a network image. Ranking entries carry a display name and no photo —
/// `RankingEntry` has no `photoUrl` — and fetching one profile picture per
/// visible row would put a hundred image requests behind a table that scrolls.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Ps.canvas,
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Ps.muted,
        ),
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      items: items,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 13.5, color: Ps.ink),
      icon: const Icon(Icons.keyboard_arrow_down, size: 20, color: Ps.muted),
      decoration: InputDecoration(
        filled: true,
        fillColor: Ps.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        // Same reasoning as PsSearchField: every state is pinned so the
        // app-wide green input theme cannot reappear on focus alone.
        border: _outline(Ps.border),
        enabledBorder: _outline(Ps.border),
        focusedBorder: _outline(Ps.primary),
        disabledBorder: _outline(Ps.border),
      ),
    );
  }

  static OutlineInputBorder _outline(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(Ps.radiusSm),
        borderSide: BorderSide(color: color),
      );
}

/// A tab whose data source does not exist yet, saying so.
class _NotYetLadder extends StatelessWidget {
  const _NotYetLadder({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.leaderboard_outlined, size: 40, color: Ps.faint),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Ps.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Ps.muted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

/// The club ladder, from inter-club results.
///
/// Deliberately a different computation from [_PlayerLadder] rather than the
/// same one grouped differently. A club does not enter a draw — its players
/// do — so summing its members' ranking points would rank the club with the
/// most members rather than the club that beats other clubs. What a club
/// ladder should answer is "who beats whom", and the only records of that are
/// inter-club fixtures, where both entrant ids ARE the two clubs.
///
/// The rollup is nightly (`functions/clubs.js`), so this reads one document
/// per sport rather than running a cross-club scan no client is permitted to
/// do — see that file for why a client-side count would show every visitor a
/// different ladder.
class _ClubLadder extends ConsumerWidget {
  const _ClubLadder({required this.sportId, required this.window});

  final String sportId;
  final _Window window;

  /// Maps the screen's window onto the keys the rollup publishes.
  /// Mirrors `WINDOWS` in `functions/clubs.js`.
  String get _windowKey => switch (window) {
        _Window.all => 'all',
        _Window.year => 'd365',
        _Window.quarter => 'd90',
        _Window.month => 'd30',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(clubStandingsProvider(sportId));

    return AsyncView(
      value: async,
      onRetry: () => ref.invalidate(clubStandingsProvider(sportId)),
      builder: (standings) {
        final rows = standings.ranked(_windowKey);
        if (rows.isEmpty) {
          return EmptyState(
            icon: Icons.shield_outlined,
            title: 'No club results yet',
            message: window == _Window.all
                ? 'Clubs appear here once they play each other. Challenge '
                    'another club, or host an inter-club match, and the '
                    'result counts overnight.'
                : 'No club played another in this period. Try a longer one.',
          );
        }

        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            ContentBounds(
              maxWidth: 760,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Text(
                      'Three points for a win, one for a draw, from matches '
                      'against other clubs. A club that only plays its own '
                      'members does not appear.'
                      '${standings.computedAt == null ? '' : ' Updated nightly.'}',
                      style: const TextStyle(fontSize: 12, color: Ps.muted),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: PsCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          const _ClubLadderHeaderRow(),
                          for (var i = 0; i < rows.length; i++)
                            _ClubRowTile(
                              rank: i + 1,
                              club: rows[i],
                              tally: rows[i].tallyFor(_windowKey),
                              isLast: i == rows.length - 1,
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ClubLadderHeaderRow extends StatelessWidget {
  const _ClubLadderHeaderRow();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
      color: Ps.faint,
      letterSpacing: 0.6,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Ps.border)),
      ),
      child: const Row(
        children: [
          SizedBox(width: 30, child: Text('RANK', style: style)),
          SizedBox(width: 8),
          Expanded(child: Text('CLUB', style: style)),
          SizedBox(
            width: 62,
            child: Text('POINTS', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(
            width: 62,
            child: Text('W-D-L', style: style, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

class _ClubRowTile extends StatelessWidget {
  const _ClubRowTile({
    required this.rank,
    required this.club,
    required this.tally,
    required this.isLast,
  });

  final int rank;
  final ClubStanding club;
  final ClubTally tally;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: Ps.border)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              '$rank',
              style: TextStyle(
                fontSize: 13,
                fontWeight: rank <= 3 ? FontWeight.w800 : FontWeight.w600,
                color: rank <= 3 ? Ps.ink : Ps.muted,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                _ClubCrest(name: club.name, logoUrl: club.logoUrl),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        club.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Ps.ink,
                        ),
                      ),
                      Text(
                        // Blank below three matches rather than "100%", for the
                        // same reason the tournament board withholds it: one
                        // win is not a record.
                        tally.winRate == null
                            ? '${tally.played} played'
                            : '${tally.played} played · '
                                '${(tally.winRate! * 100).round()}% won',
                        style: const TextStyle(fontSize: 11, color: Ps.faint),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 62,
            child: Text(
              psGrouped(tally.points),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Ps.ink,
              ),
            ),
          ),
          SizedBox(
            width: 62,
            child: Text(
              '${tally.won}-${tally.drawn}-${tally.lost}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12, color: Ps.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// A club's logo, or its initials when it has none.
class _ClubCrest extends StatelessWidget {
  const _ClubCrest({required this.name, this.logoUrl});

  final String name;
  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    if (logoUrl != null && logoUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          logoUrl!,
          width: 26,
          height: 26,
          fit: BoxFit.cover,
          // A broken logo must not take the ladder row down with it.
          errorBuilder: (_, __, ___) => _InitialsCrest(name: name),
        ),
      );
    }
    return _InitialsCrest(name: name);
  }
}

class _InitialsCrest extends StatelessWidget {
  const _InitialsCrest({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty
        ? '?'
        : name
            .trim()
            .split(RegExp(r'\s+'))
            .take(2)
            .map((w) => w[0].toUpperCase())
            .join();
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Ps.canvas,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Ps.border),
      ),
      child: Text(
        initials,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: Ps.muted,
        ),
      ),
    );
  }
}
