import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/enums.dart';
import '../../../core/models/fixture.dart';
import '../../../core/models/organization.dart';
import '../../../core/models/tournament.dart';
import '../../../core/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../domain/schedule/match_phase.dart';
import '../../../domain/tournament/season_access.dart';
import '../../../domain/tournament/season_sports.dart';
import '../../../domain/tournament/tournament_overview.dart';
import '../../../shared/app_scaffold.dart';
import '../../../shared/ui_kit.dart';
import '../../competitions/widgets/schedule_board.dart';
import '../../scoring/open_match.dart';

/// One sport of a season, as its own tournament: how far through, who is in
/// charge, who is umpiring, its events and tables, what is next and what just
/// finished. See [SeasonSport] for why the season page is built from these.
///
/// Collapsed, it is still a complete one-line answer — sport, stage, played of
/// total, anything on now or late — so a season of six sports reads as six
/// lines before anybody opens one.
class SeasonSportPanel extends StatefulWidget {
  const SeasonSportPanel({
    super.key,
    required this.orgId,
    required this.tournamentId,
    required this.sport,
    required this.access,
    required this.eventTile,
    this.initiallyExpanded = true,
  });

  final String orgId;
  final String tournamentId;
  final SeasonSport sport;

  /// Who is reading. Decides whether the panel carries the staffing — who is
  /// in charge, who is umpiring, what is unstaffed — or only the sport.
  final SeasonAccess access;

  /// Draws one event row. Passed in because the season screen owns the event
  /// tile — its points table, its edit dialog — and a second copy of that here
  /// would be two event rows that drift.
  final Widget Function(EventSummary) eventTile;

  final bool initiallyExpanded;

  @override
  State<SeasonSportPanel> createState() => _SeasonSportPanelState();
}

class _SeasonSportPanelState extends State<SeasonSportPanel> {
  late bool _open = widget.initiallyExpanded;

  @override
  void didUpdateWidget(SeasonSportPanel old) {
    super.didUpdateWidget(old);
    // Focusing one sport from the chips above opens it; the reader's own
    // toggle is otherwise left alone as results stream in.
    if (widget.initiallyExpanded && !old.initiallyExpanded) _open = true;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.sport;
    final visual = SportVisual.of(s.sportId);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: Ps.surface,
          borderRadius: BorderRadius.circular(Ps.radius),
          border: Border.all(
            color: s.tally.inProgress > 0
                ? Ps.live.withValues(alpha: 0.5)
                : Ps.border,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _open = !_open),
              child: Container(
                color: visual.color.withValues(alpha: 0.06),
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                child: Row(
                  children: [
                    SportBadge(sportId: s.sportId, size: 40),
                    const SizedBox(width: 12),
                    Expanded(child: _Headline(sport: s)),
                    Icon(
                      _open ? Icons.expand_less : Icons.expand_more,
                      color: Ps.muted,
                    ),
                  ],
                ),
              ),
            ),
            if (_open)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TallyBar(tally: s.tally, color: visual.color),
                    const SizedBox(height: 14),
                    // Read top to bottom the way anyone asks about a sport:
                    // who is winning, what is on, what is next, what just
                    // happened. The same order for every role, so an
                    // organizer and a parent describing the page to each
                    // other are describing the same page.
                    _Leaderboard(orgId: widget.orgId, sport: s),
                    if (s.onNow.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _Matches(
                        title: 'On now',
                        fixtures: s.onNow,
                        canManage: widget.access.canManage,
                      ),
                    ],
                    if (s.upNext.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _Matches(
                        title: 'Up next',
                        fixtures: s.upNext,
                        canManage: widget.access.canManage,
                      ),
                    ],
                    if (s.latestResults.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _Matches(
                        title: 'Latest results',
                        fixtures: s.latestResults,
                        canManage: widget.access.canManage,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        icon:
                            const Icon(Icons.calendar_month_outlined, size: 18),
                        label: Text(
                          s.tally.total == 0
                              ? '${s.sportName} schedule'
                              : 'Full ${s.sportName.toLowerCase()} schedule '
                                  '(${s.tally.total})',
                        ),
                        onPressed: () => context.push(
                          Routes.tournamentSchedule(
                            widget.orgId,
                            widget.tournamentId,
                            sportId: s.sportId,
                          ),
                        ),
                      ),
                    ),
                    _People(
                      orgId: widget.orgId,
                      tournamentId: widget.tournamentId,
                      sport: s,
                      access: widget.access,
                    ),
                    const SizedBox(height: 14),
                    _Heading('Events', trailing: '${s.events.length}'),
                    for (final e in s.events) widget.eventTile(e),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Badminton · Running" over "12 of 30 played · 2 on now · 3 late".
class _Headline extends StatelessWidget {
  const _Headline({required this.sport});

  final SeasonSport sport;

  @override
  Widget build(BuildContext context) {
    final s = sport;
    final t = s.tally;
    final (label, color) = switch (s.stage) {
      SportStage.notDrawn => ('Not drawn yet', Ps.faint),
      SportStage.notStarted => ('Not started', Ps.muted),
      SportStage.running => ('In progress', Ps.primary),
      SportStage.needsRuling => ('Needs a ruling', Ps.live),
      SportStage.complete => ('Complete', Ps.primary),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              s.sportName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Ps.ink,
              ),
            ),
            if (t.inProgress > 0)
              const PsLivePill()
            else
              _Tag(label: label, color: color),
          ],
        ),
        const SizedBox(height: 2),
        Text.rich(
          TextSpan(
            style: const TextStyle(fontSize: 12, color: Ps.muted),
            children: [
              TextSpan(
                text: '${s.events.length} '
                    '${s.events.length == 1 ? 'event' : 'events'}',
              ),
              if (t.total > 0)
                TextSpan(text: '  ·  ${t.played}/${t.total} played'),
              if (t.inProgress > 0)
                TextSpan(
                  text: '  ·  ${t.inProgress} on now',
                  style: const TextStyle(
                    color: Ps.live,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (t.overdue > 0)
                TextSpan(
                  text: '  ·  ${t.overdue} late',
                  style: const TextStyle(
                    color: MatchRow.lateColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (s.stage == SportStage.complete && s.champions.isNotEmpty)
                TextSpan(
                  text: s.champions.length == 1
                      ? '  ·  Won by ${s.champions.first}'
                      : '  ·  ${s.champions.length} champions crowned',
                ),
            ],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

extension on SeasonSport {
  List<String> get champions => [
        for (final e in events)
          if (e.champion != null) e.champion!,
      ];
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      );
}

/// The bar and the four numbers under it.
class _TallyBar extends StatelessWidget {
  const _TallyBar({required this.tally, required this.color});

  final MatchTally tally;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = tally;
    if (t.total == 0) {
      return const Text(
        'No matches yet — they appear once this sport is drawn and scheduled.',
        style: TextStyle(fontSize: 12.5, color: Ps.muted),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: t.progress,
            minHeight: 6,
            color: color,
            backgroundColor: Ps.border,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 18,
          runSpacing: 8,
          children: [
            _Figure(value: t.played, label: 'Played'),
            _Figure(
              value: t.inProgress,
              label: 'On now',
              color: t.inProgress > 0 ? Ps.live : null,
            ),
            _Figure(value: t.ahead, label: 'To play'),
            if (t.overdue > 0)
              _Figure(
                value: t.overdue,
                label: 'Late',
                color: MatchRow.lateColor,
              ),
            if (t.halted > 0)
              _Figure(
                value: t.halted,
                label: 'Stopped',
                color: MatchRow.lateColor,
              ),
            _Figure(value: t.total, label: 'Total'),
          ],
        ),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label, this.color});

  final int value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color ?? Ps.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(label, style: const TextStyle(fontSize: 11, color: Ps.muted)),
        ],
      );
}

class _Heading extends StatelessWidget {
  const _Heading(this.title, {this.trailing, this.action});

  final String title;
  final String? trailing;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: Ps.muted,
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 6),
              Text(
                trailing!,
                style: const TextStyle(fontSize: 11, color: Ps.faint),
              ),
            ],
            const Spacer(),
            if (action != null) action!,
          ],
        ),
      );
}

/// In charge, and umpiring.
class _People extends ConsumerWidget {
  const _People({
    required this.orgId,
    required this.tournamentId,
    required this.sport,
    required this.access,
  });

  final String orgId;
  final String tournamentId;
  final SeasonSport sport;
  final SeasonAccess access;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = sport;
    final canManage = access.canManage;
    final panel = s.umpires.where((u) => u.onPanel).length;

    // A spectator is told who to go to for this sport, when somebody has been
    // named, and nothing else: no empty "In charge" heading, no umpire list.
    if (!access.seesStaffing && !access.seesUmpires) {
      if (s.leads.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Heading('In charge'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final l in s.leads)
                  _PersonChip(icon: Icons.shield_outlined, label: l.name),
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Heading(
            'In charge',
            action: canManage
                ? _SmallAction(
                    label: s.leads.isEmpty ? 'Assign' : 'Change',
                    onTap: () => showSportLeadsDialog(
                      context,
                      ref,
                      orgId: orgId,
                      tournamentId: tournamentId,
                      sportId: s.sportId,
                      sportName: s.sportName,
                      current: s.leads,
                    ),
                  )
                : null,
          ),
          if (s.leads.isEmpty)
            Text(
              canManage
                  ? 'Nobody named for ${s.sportName.toLowerCase()} yet. Name '
                      'the admin people should go to on the day.'
                  : "Run by the club's organizers.",
              style: const TextStyle(fontSize: 12.5, color: Ps.muted),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final l in s.leads)
                  _PersonChip(icon: Icons.shield_outlined, label: l.name),
              ],
            ),
          const SizedBox(height: 12),
          _Heading(
            'Umpires',
            trailing: s.umpires.isEmpty
                ? null
                : '${s.umpires.length}'
                    '${panel > 0 && panel != s.umpires.length ? ' · $panel on the panel' : ''}',
            action: canManage
                ? _SmallAction(
                    label: 'Umpire panel',
                    onTap: () => context.push(
                      Routes.tournamentOfficials(orgId, tournamentId),
                    ),
                  )
                : null,
          ),
          if (s.umpires.isEmpty)
            const Text(
              'No umpires on the panel or named on a match yet.',
              style: TextStyle(fontSize: 12.5, color: Ps.muted),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final u in s.umpires.take(8))
                  _PersonChip(
                    icon: Icons.sports_outlined,
                    label: u.matches == 0
                        ? u.name
                        : '${u.name} · ${u.matches} '
                            '${u.matches == 1 ? 'match' : 'matches'}',
                  ),
                if (s.umpires.length > 8)
                  _PersonChip(label: '+${s.umpires.length - 8} more'),
              ],
            ),
          // The number the panel exists to drive to zero, shown only to the
          // people who can do something about it.
          if (canManage && s.aheadWithoutUmpire > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 16, color: MatchRow.lateColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${s.aheadWithoutUmpire} of ${s.tally.ahead} matches still '
                    'to play have no umpire.',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: MatchRow.lateColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SmallAction extends StatelessWidget {
  const _SmallAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 28),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label, style: const TextStyle(fontSize: 12.5)),
      );
}

class _PersonChip extends StatelessWidget {
  const _PersonChip({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: Ps.canvas,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Ps.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: Ps.muted),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Ps.ink),
              ),
            ),
          ],
        ),
      );
}

/// The sport's standings, as simple tables: one per group (or one per league
/// event), # · team or player · P · W · L · Pts, with the places that go
/// through marked. A sport made only of knockouts has no table, so it gets a
/// wins board instead — the same people, ranked by titles and wins.
class _Leaderboard extends StatelessWidget {
  const _Leaderboard({required this.orgId, required this.sport});

  final String orgId;
  final SeasonSport sport;

  @override
  Widget build(BuildContext context) {
    final s = sport;
    final tables = [
      for (final t in s.tables)
        if (t.rows.isNotEmpty) t,
    ];

    if (tables.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Heading('Leaderboard'),
          for (final t in tables)
            _PointsTable(
              table: t,
              onOpenEvent: () =>
                  context.push(Routes.competition(orgId, t.eventId)),
            ),
        ],
      );
    }

    if (s.leaders.isNotEmpty) {
      final teams = s.events.any(
        (e) => e.competition.entrantType == EntrantType.team,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Heading('Leaderboard', trailing: 'by wins'),
          _TableFrame(
            header: _TableRow.header(
              name: teams ? 'Team' : 'Player',
              columns: const ['P', 'W', 'L'],
            ),
            rows: [
              for (var i = 0; i < s.leaders.length; i++)
                _TableRow(
                  rank: i + 1,
                  name: s.leaders[i].displayName,
                  columns: [
                    '${s.leaders[i].played}',
                    '${s.leaders[i].won}',
                    '${s.leaders[i].lost}',
                  ],
                  highlight: i == 0 && s.leaders[i].won > 0,
                  note: s.leaders[i].titles > 0
                      ? '${s.leaders[i].titles}× champion'
                      : null,
                ),
            ],
          ),
        ],
      );
    }

    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading('Leaderboard'),
        Text(
          'The table fills in as results come in.',
          style: TextStyle(fontSize: 12.5, color: Ps.muted),
        ),
      ],
    );
  }
}

/// One group's table.
class _PointsTable extends StatelessWidget {
  const _PointsTable({required this.table, required this.onOpenEvent});

  final SportTable table;
  final VoidCallback onOpenEvent;

  @override
  Widget build(BuildContext context) {
    final t = table;
    // A draws column only where somebody has drawn: most racquet sports
    // cannot, and an empty "D" column is noise on a phone.
    final draws = t.rows.any((r) => r.drawn > 0);
    final columns = ['P', 'W', if (draws) 'D', 'L', 'Pts'];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _TableFrame(
        title: InkWell(
          onTap: onOpenEvent,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Ps.ink,
                    ),
                  ),
                ),
                Text(
                  t.isComplete ? 'Final' : '${t.played}/${t.total} played',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: t.isComplete ? Ps.primary : Ps.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
        header: _TableRow.header(
          name: t.isTeams ? 'Team' : 'Player',
          columns: columns,
        ),
        rows: [
          for (var i = 0; i < t.rows.length; i++)
            _TableRow(
              rank: i + 1,
              name: t.rows[i].displayName,
              columns: [
                '${t.rows[i].played}',
                '${t.rows[i].won}',
                if (draws) '${t.rows[i].drawn}',
                '${t.rows[i].lost}',
                '${t.rows[i].points}',
              ],
              highlight: i < t.qualifiers,
            ),
        ],
        footer: t.qualifiers > 0
            ? 'Top ${t.qualifiers} go through to the knockout'
            : null,
      ),
    );
  }
}

class _TableFrame extends StatelessWidget {
  const _TableFrame({
    required this.header,
    required this.rows,
    this.title,
    this.footer,
  });

  final Widget? title;
  final Widget header;
  final List<Widget> rows;
  final String? footer;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Ps.canvas,
          borderRadius: BorderRadius.circular(Ps.radiusSm),
          border: Border.all(color: Ps.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) title!,
            header,
            for (final r in rows) r,
            if (footer != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Ps.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      footer!,
                      style: const TextStyle(fontSize: 11, color: Ps.muted),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
}

/// # · name · figures, in fixed-width columns so the numbers line up down
/// the table on any width.
class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.rank,
    required this.name,
    required this.columns,
    this.highlight = false,
    this.note,
  }) : isHeader = false;

  const _TableRow.header({required this.name, required this.columns})
      : rank = 0,
        highlight = false,
        note = null,
        isHeader = true;

  final int rank;
  final String name;
  final List<String> columns;
  final bool highlight;
  final String? note;
  final bool isHeader;

  static const double _numberWidth = 32;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontSize: isHeader ? 10.5 : 12.5,
      fontWeight: isHeader
          ? FontWeight.w700
          : highlight
              ? FontWeight.w700
              : FontWeight.w500,
      color: isHeader ? Ps.muted : Ps.ink,
      letterSpacing: isHeader ? 0.4 : null,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Container(
      decoration: BoxDecoration(
        color: highlight ? Ps.primary.withValues(alpha: 0.08) : null,
        border: const Border(top: BorderSide(color: Ps.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(isHeader ? '#' : '$rank', style: base),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isHeader ? name.toUpperCase() : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: base,
                ),
                if (note != null)
                  Text(
                    note!,
                    style: const TextStyle(fontSize: 10.5, color: Ps.primary),
                  ),
              ],
            ),
          ),
          for (var i = 0; i < columns.length; i++)
            SizedBox(
              width: _numberWidth,
              child: Text(
                columns[i],
                textAlign: TextAlign.right,
                style: i == columns.length - 1 && !isHeader
                    ? base.copyWith(fontWeight: FontWeight.w800)
                    : base,
              ),
            ),
        ],
      ),
    );
  }
}

/// A few matches, through the one fixture row the app has.
class _Matches extends ConsumerWidget {
  const _Matches({
    required this.title,
    required this.fixtures,
    required this.canManage,
  });

  final String title;
  final List<Fixture> fixtures;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(title),
        for (final f in fixtures)
          MatchRow(
            fixture: f,
            onTap: () => openMatch(
              context,
              fixture: f,
              myUid: ref.read(currentUidProvider),
              canManage: canManage,
            ),
          ),
      ],
    );
  }
}

/// Picks who is in charge of one sport, from the people who already run the
/// club's competitions. See [Tournament.sportLeads].
Future<void> showSportLeadsDialog(
  BuildContext context,
  WidgetRef ref, {
  required String orgId,
  required String tournamentId,
  required String sportId,
  required String sportName,
  required List<SportLead> current,
}) async {
  final chosen = await showDialog<List<SportLead>>(
    context: context,
    builder: (_) => _SportLeadsDialog(
      orgId: orgId,
      sportName: sportName,
      current: current,
    ),
  );
  if (chosen == null || !context.mounted) return;
  try {
    await ref.read(tournamentRepositoryProvider).setSportLeads(
          orgId: orgId,
          tournamentId: tournamentId,
          sportId: sportId,
          leads: chosen,
        );
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

class _SportLeadsDialog extends ConsumerStatefulWidget {
  const _SportLeadsDialog({
    required this.orgId,
    required this.sportName,
    required this.current,
  });

  final String orgId;
  final String sportName;
  final List<SportLead> current;

  @override
  ConsumerState<_SportLeadsDialog> createState() => _SportLeadsDialogState();
}

class _SportLeadsDialogState extends ConsumerState<_SportLeadsDialog> {
  late final Set<String> _picked = {for (final l in widget.current) l.uid};

  /// What Save writes. Built from the people on screen, never from the
  /// member list alone.
  ///
  /// It used to be "the eligible members who are ticked". That meant a Save
  /// pressed before the member list arrived, or after it failed, wrote an
  /// empty list and deleted every lead the sport had. The same happened to
  /// any lead no longer on the list (demoted, or left the club): they
  /// vanished without being unticked. So a current lead stays unless they
  /// are unticked, under the name they were saved with, and Save stays off
  /// until the member list has loaded.
  List<SportLead> _chosen(List<Membership> eligible) {
    final eligibleByUid = {for (final m in eligible) m.uid: m};
    return [
      for (final lead in widget.current)
        if (_picked.contains(lead.uid))
          SportLead(
            uid: lead.uid,
            name: eligibleByUid[lead.uid]?.displayName ?? lead.name,
          ),
      for (final m in eligible)
        if (_picked.contains(m.uid) &&
            !widget.current.any((l) => l.uid == m.uid))
          SportLead(uid: m.uid, name: m.displayName),
    ];
  }

  bool _unchanged(List<SportLead> chosen) =>
      chosen.length == widget.current.length &&
      chosen.every((c) => widget.current.any((l) => l.uid == c.uid));

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(orgMembersProvider(widget.orgId));
    final loaded = membersAsync.hasValue && !membersAsync.hasError;
    final eligible = [
      for (final m in membersAsync.valueOrNull ?? const <Membership>[])
        if (m.isActive && SportLead.eligible.contains(m.role)) m,
    ]..sort((a, b) {
        final byRank = b.role.rank.compareTo(a.role.rank);
        return byRank != 0 ? byRank : a.displayName.compareTo(b.displayName);
      });
    final eligibleUids = {for (final m in eligible) m.uid};
    // Leads who are no longer an owner, admin or event manager. Listed, so
    // removing them is a decision somebody makes and sees.
    final former = [
      for (final l in widget.current)
        if (loaded && !eligibleUids.contains(l.uid)) l,
    ];
    final chosen = _chosen(eligible);

    Widget tick({
      required String uid,
      required String name,
      required String subtitle,
    }) =>
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: _picked.contains(uid),
          title: Text(name),
          subtitle: Text(subtitle),
          onChanged: (on) => setState(() {
            if (on == true) {
              _picked.add(uid);
            } else {
              _picked.remove(uid);
            }
          }),
        );

    return AlertDialog(
      title: Text('In charge of ${widget.sportName}'),
      content: SizedBox(
        width: 420,
        child: AsyncView(
          value: membersAsync,
          builder: (_) => eligible.isEmpty && former.isEmpty
              ? const Text('This club has no owner, admin or event manager '
                  'to name.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Who people should go to for this sport on the day. '
                      'Chosen from the club\'s owners, admins and event '
                      'managers; it changes nobody\'s permissions.',
                      style: TextStyle(fontSize: 12.5, color: Ps.muted),
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final m in eligible)
                            tick(
                              uid: m.uid,
                              name: m.displayName,
                              subtitle: m.role.label,
                            ),
                          for (final l in former)
                            tick(
                              uid: l.uid,
                              name: l.name,
                              subtitle: 'No longer runs competitions — '
                                  'untick to remove',
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          // Off until the member list is in: without it Save cannot tell
          // "unticked" from "not loaded yet".
          onPressed: !loaded
              ? null
              : () => Navigator.pop(
                    context,
                    _unchanged(chosen) ? null : chosen,
                  ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
