import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/result_labels.dart';
import '../../../core/models/fixture.dart';
import '../../../domain/schedule/schedule_view_model.dart';
import '../../../shared/ui_kit.dart';
import 'schedule_export.dart';

/// One organizer action offered on a match row.
///
/// Passed in rather than built here because the actions belong to the screen
/// that owns the event — moving a match opens a sheet that needs the sibling
/// fixtures, assigning a scorer opens a dialog that needs the membership
/// list — and none of that is the schedule's business. The board's only
/// contribution is deciding they go in an overflow menu instead of three
/// icon buttons, which is what they were.
class ScheduleAction {
  const ScheduleAction({
    required this.icon,
    required this.label,
    required this.onSelected,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onSelected;
  final Color? color;
}

/// Which slice of the schedule is on screen.
enum ScheduleLens {
  all('All'),
  mine('Ours'),
  live('Live'),
  upcoming('Upcoming'),
  results('Results');

  const ScheduleLens(this.label);
  final String label;
}

/// The match schedule, built to be read rather than scrolled.
///
/// ## The problem this replaces
///
/// The event screen rendered every fixture as a full [LiveScoreCard] in one
/// flat column. A sixteen-team round robin is ninety-six matches; at ~96pt a
/// card that is nine thousand points of scrolling, on a phone, to find the
/// two matches you are actually in. Organizers were scrolling past four
/// groups of standings first. The complaint was not that the information was
/// missing — it was that finding anything cost forty flicks.
///
/// ## What makes it short
///
/// **Sections collapse.** One group at a time, shut by default once the draw
/// is big enough that the whole thing cannot fit ([_collapseThreshold]). The
/// section header carries the counts, so a collapsed group still answers
/// "how many, and how many of ours".
///
/// **Rows are one line, not a card.** ~56pt against ~96pt, and the score, the
/// time and the court all still fit because they are laid out in columns
/// rather than stacked.
///
/// **"Ours" is a filter and a colour.** [mineEntrantIds] washes a row green
/// and gives it a green edge, and the "Ours" chip reduces ninety-six matches
/// to the six that concern you. This is the actual answer to the complaint;
/// everything else is making the remaining ninety cheap to skim.
///
/// **Your next match is lifted out.** A player opening this wants one fact,
/// and it is pinned above the fold instead of being somewhere in Group C.
///
/// **It prints.** A schedule taped to a noticeboard is still how a school
/// meet is run, so the same model renders to a PDF with the same green wash.
class ScheduleBoard extends StatefulWidget {
  const ScheduleBoard({
    super.key,
    required this.fixtures,
    this.mineEntrantIds = const {},
    this.title = 'Matches',
    this.notice,
    this.onTapFixture,
    this.actionsBuilder,
    this.pdfTitle,
    this.pdfSubtitle = '',
    this.pdfNote,
    this.showDownload = true,
    this.sectionOf,
    this.byDay = false,
  });

  final List<Fixture> fixtures;

  /// Entrant ids belonging to the reader's club, team or account.
  /// See [MyEntrants.resolve].
  final Set<String> mineEntrantIds;

  final String title;

  /// A line under the heading — the draft-schedule caveat, typically.
  final Widget? notice;

  final void Function(Fixture)? onTapFixture;
  final List<ScheduleAction> Function(Fixture)? actionsBuilder;

  /// Falls back to [title] when the caller has nothing better; an event's own
  /// name is much better and every caller has one.
  final String? pdfTitle;
  final String pdfSubtitle;
  final String? pdfNote;
  final bool showDownload;

  /// How rows are bucketed into collapsible sections. Defaults to the draw's
  /// own groups, which is right for ONE event; a season spanning eight draws
  /// passes the event's name instead, because four different sports each
  /// having a "Group A" is not four rows of the same section.
  final String Function(Fixture)? sectionOf;

  /// Buckets by calendar day rather than by [sectionOf]. What a spectator
  /// following a two-day meet wants: "Saturday", then "Sunday".
  final bool byDay;

  /// Above this many matches, sections start collapsed. Four groups of six
  /// still fit on a page and a shut drawer would be pure friction; ninety-six
  /// do not.
  static const int _collapseThreshold = 24;

  @override
  State<ScheduleBoard> createState() => _ScheduleBoardState();
}

class _ScheduleBoardState extends State<ScheduleBoard> {
  ScheduleLens _lens = ScheduleLens.all;

  /// Tracked as the exception, per section title. Which way round that runs
  /// depends on the size of the draw — see [_startsCollapsed].
  final Set<String> _toggled = {};

  /// Sections the reader has asked to see in full, past [_pageSize].
  final Set<String> _revealed = {};

  static const int _pageSize = 25;

  /// Sections only start shut on the unfiltered board. Choosing "Ours" or
  /// "Live" IS the reader narrowing the list; making them then open four
  /// drawers to see the six matches they asked for would undo the filter.
  bool get _startsCollapsed =>
      _lens == ScheduleLens.all &&
      widget.fixtures.length > ScheduleBoard._collapseThreshold;

  bool _isOpen(String section, {required bool hasMine}) {
    if (_toggled.contains(section)) return _startsCollapsed;
    // A section containing your own matches opens even in a large draw. It is
    // the one you came for, and hiding it behind a tap in a list of eight
    // shut drawers is the same problem in a smaller box.
    return !_startsCollapsed || hasMine;
  }

  bool _matches(Fixture f, ScheduleLens lens, DateTime now) => switch (lens) {
        ScheduleLens.all => true,
        ScheduleLens.mine => _isMine(f),
        // Activity-aware rather than the raw status field, exactly as
        // `MyMatchesScreen` and `LiveScoreCard` are: a match abandoned by its
        // scorer on Tuesday is not live on Friday.
        ScheduleLens.live => f.isLiveAt(now),
        ScheduleLens.upcoming => !f.status.isResulted && !f.isLiveAt(now),
        ScheduleLens.results => f.status.isResulted,
      };

  String _sectionKey(Fixture f) {
    if (widget.byDay) {
      return ScheduleFormat.hasTime(f)
          ? DateFormat('EEEE d MMMM').format(f.scheduledAt!)
          : 'Not yet scheduled';
    }
    return (widget.sectionOf ?? ScheduleFormat.section)(f);
  }

  bool _isMine(Fixture f) =>
      widget.mineEntrantIds.contains(f.entrantAId) ||
      widget.mineEntrantIds.contains(f.entrantBId);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final all = widget.fixtures;
    final hasAnyMine = all.any(_isMine);

    final shown = [
      for (final f in all)
        if (_matches(f, _lens, now)) f,
    ];

    // Grouped the way the standings above already are — one section per
    // group, knockout last. `ScheduleFormat` owns that ordering so the
    // printed copy cannot disagree with the screen.
    final sections = <String, List<Fixture>>{};
    for (final f in shown) {
      sections.putIfAbsent(_sectionKey(f), () => []).add(f);
    }
    final sectionKeys = sections.keys.toList()
      ..sort((a, b) {
        const tails = {'Knockout', 'Not yet scheduled'};
        if (tails.contains(a) != tails.contains(b)) {
          return tails.contains(a) ? 1 : -1;
        }
        if (widget.byDay) {
          final fa = sections[a]!.first.scheduledAt;
          final fb = sections[b]!.first.scheduledAt;
          if (fa != null && fb != null) return fa.compareTo(fb);
        }
        return a.compareTo(b);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(widget.title, style: theme.textTheme.titleMedium),
            ),
            if (widget.showDownload && all.isNotEmpty)
              ScheduleDownloadButton(
                fixtures: all,
                title: widget.pdfTitle ?? widget.title,
                subtitle: widget.pdfSubtitle,
                note: widget.pdfNote,
                mineEntrantIds: widget.mineEntrantIds,
                byDay: widget.byDay,
                sectionOf: widget.sectionOf,
                label: 'Download',
              ),
          ],
        ),
        if (widget.notice != null) ...[
          const SizedBox(height: 4),
          widget.notice!,
        ],
        const SizedBox(height: 8),
        _SummaryLine(
          total: all.length,
          mine: all.where(_isMine).length,
          played: all.where((f) => f.status.isResulted).length,
        ),
        const SizedBox(height: 10),
        _LensChips(
          selected: _lens,
          countFor: (lens) => all.where((f) => _matches(f, lens, now)).length,
          hasMine: hasAnyMine,
          onSelected: (l) => setState(() => _lens = l),
        ),
        const SizedBox(height: 12),

        // The one fact a player opens this screen for, lifted above every
        // group so it is never behind a scroll.
        if (hasAnyMine && _lens != ScheduleLens.mine)
          _NextUpCard(
            fixture: _nextMine(now),
            onTap: widget.onTapFixture,
          ),

        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                _lens == ScheduleLens.mine
                    ? 'None of your teams are in this draw yet.'
                    : 'Nothing under ${_lens.label}.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          )
        else
          for (final key in sectionKeys)
            _Section(
              title: key,
              fixtures: sections[key]!,
              open: _isOpen(key, hasMine: sections[key]!.any(_isMine)),
              onToggle: () => setState(() {
                if (!_toggled.remove(key)) _toggled.add(key);
              }),
              revealAll: _revealed.contains(key),
              onRevealAll: () => setState(() => _revealed.add(key)),
              pageSize: _pageSize,
              isMine: _isMine,
              onTapFixture: widget.onTapFixture,
              actionsBuilder: widget.actionsBuilder,
              sortByTime: widget.byDay,
            ),
      ],
    );
  }

  /// The reader's soonest unplayed match, or their last played one when the
  /// draw is over — never null while [_isMine] matches anything.
  Fixture? _nextMine(DateTime now) {
    final mine = widget.fixtures.where(_isMine).toList();
    if (mine.isEmpty) return null;
    final live = mine.where((f) => f.isLiveAt(now)).toList();
    if (live.isNotEmpty) return live.first;
    final ahead = mine
        .where((f) => !f.status.isResulted)
        .toList()
      ..sort(ScheduleFormat.byTime);
    return ahead.isNotEmpty ? ahead.first : null;
  }

}

/// "96 matches · 12 yours · 40 played".
class _SummaryLine extends StatelessWidget {
  const _SummaryLine({
    required this.total,
    required this.mine,
    required this.played,
  });

  final int total;
  final int mine;
  final int played;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodySmall;
    // One wrapping [Text] rather than a [Row] of three. The row could not
    // wrap, so "96 matches · 12 yours · 40 played" overflowed the right edge
    // of a 360pt phone the moment any of the numbers reached three digits.
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$total ${total == 1 ? 'match' : 'matches'}',
            style: base?.copyWith(color: Ps.muted),
          ),
          if (mine > 0) ...[
            TextSpan(text: '  ·  ', style: base?.copyWith(color: Ps.faint)),
            TextSpan(
              text: '$mine yours',
              style: base?.copyWith(
                color: Ps.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (played > 0) ...[
            TextSpan(text: '  ·  ', style: base?.copyWith(color: Ps.faint)),
            TextSpan(
              text: '$played played',
              style: base?.copyWith(color: Ps.muted),
            ),
          ],
        ],
      ),
    );
  }
}

/// The filter row. Horizontally scrollable because five chips with counts do
/// not fit a 360pt phone, and a [Wrap] here pushed the first group off screen.
class _LensChips extends StatelessWidget {
  const _LensChips({
    required this.selected,
    required this.countFor,
    required this.hasMine,
    required this.onSelected,
  });

  final ScheduleLens selected;
  final int Function(ScheduleLens) countFor;
  final bool hasMine;
  final ValueChanged<ScheduleLens> onSelected;

  @override
  Widget build(BuildContext context) {
    final lenses = [
      for (final l in ScheduleLens.values)
        // "Ours" with nothing behind it is a dead chip; it is hidden rather
        // than shown empty, so a spectator with no team is not offered it.
        if (l != ScheduleLens.mine || hasMine) l,
    ];

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: lenses.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final l = lenses[i];
          final n = countFor(l);
          final isMine = l == ScheduleLens.mine;
          return FilterChip(
            label: Text('${l.label} ($n)'),
            selected: selected == l,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            selectedColor: isMine ? Ps.primary.withValues(alpha: 0.16) : null,
            labelStyle: isMine
                ? const TextStyle(
                    color: Ps.primary, fontWeight: FontWeight.w700)
                : null,
            onSelected: (_) => onSelected(l),
          );
        },
      ),
    );
  }
}

/// One collapsible block of matches — a group, or the knockout stage.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.fixtures,
    required this.open,
    required this.onToggle,
    required this.revealAll,
    required this.onRevealAll,
    required this.pageSize,
    required this.isMine,
    required this.onTapFixture,
    required this.actionsBuilder,
    this.sortByTime = false,
  });

  final String title;
  final List<Fixture> fixtures;
  final bool open;
  final VoidCallback onToggle;
  final bool revealAll;
  final VoidCallback onRevealAll;
  final int pageSize;
  final bool Function(Fixture) isMine;
  final void Function(Fixture)? onTapFixture;
  final List<ScheduleAction> Function(Fixture)? actionsBuilder;

  /// A day's programme reads in kick-off order; one group's reads in draw
  /// order, because round 2 follows round 1 whatever time it was given.
  final bool sortByTime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mineCount = fixtures.where(isMine).length;
    final sorted = [...fixtures]
      ..sort(sortByTime ? ScheduleFormat.byTime : ScheduleFormat.byRound);
    final visible =
        revealAll ? sorted : sorted.take(pageSize).toList(growable: false);
    final hidden = sorted.length - visible.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Icon(
                  open ? Icons.expand_more : Icons.chevron_right,
                  size: 20,
                  color: Ps.muted,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (mineCount > 0)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Ps.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$mineCount ours',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Ps.primary,
                      ),
                    ),
                  ),
                Text(
                  '${fixtures.length}',
                  style: theme.textTheme.bodySmall?.copyWith(color: Ps.muted),
                ),
              ],
            ),
          ),
        ),
        if (open) ...[
          for (final entry in _byRound(visible).entries) ...[
            // A day's programme is already in time order and its rows come
            // from several different draws, so "R1" over a mixed list would
            // be a heading that means nothing. Groups keep theirs.
            if (!sortByTime)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 0, 6),
                child: Text(
                  entry.key,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Ps.faint,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            for (final f in entry.value)
              MatchRow(
                fixture: f,
                mine: isMine(f),
                onTap: onTapFixture == null ? null : () => onTapFixture!(f),
                actions: actionsBuilder?.call(f) ?? const [],
              ),
          ],
          if (hidden > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onRevealAll,
                child: Text('Show $hidden more'),
              ),
            ),
        ],
        const SizedBox(height: 4),
      ],
    );
  }

  /// Rounds keep their draw order, which is why this is a [LinkedHashMap] by
  /// insertion over an already-sorted list rather than a sort on the labels —
  /// "R10" sorts before "R2" as text.
  Map<String, List<Fixture>> _byRound(List<Fixture> sorted) {
    if (sortByTime) return {'': sorted};
    final out = <String, List<Fixture>>{};
    for (final f in sorted) {
      out.putIfAbsent(ScheduleFormat.round(f), () => []).add(f);
    }
    return out;
  }
}

/// One match, on one line.
///
/// Public because the same row is what a season's schedule page and the
/// public spectator page want; there is no second way to draw a fixture in a
/// list worth maintaining.
class MatchRow extends StatelessWidget {
  const MatchRow({
    super.key,
    required this.fixture,
    this.mine = false,
    this.onTap,
    this.actions = const [],
  });

  final Fixture fixture;
  final bool mine;
  final VoidCallback? onTap;
  final List<ScheduleAction> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = fixture;
    final now = DateTime.now();
    final isLive = f.isLiveAt(now);
    final hasTime = ScheduleFormat.hasTime(f);
    final court = ScheduleFormat.court(f);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: mine ? Ps.primary.withValues(alpha: 0.07) : Ps.surface,
        borderRadius: BorderRadius.circular(Ps.radiusSm),
        border: Border.all(
          color: mine ? Ps.primary.withValues(alpha: 0.45) : Ps.border,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      // A [Stack] rather than a [Row] with an [IntrinsicHeight] around it.
      // The green edge has to run the full height of a row whose height is
      // set by its own text, and IntrinsicHeight answers that by asking a
      // Row full of Expanded children for its intrinsic width — which it
      // cannot give, and which laid the row out against a nonsense width and
      // overflowed it by 99,772 pixels. A positioned bar needs no intrinsic
      // pass at all, and costs one less layout of every row in the list.
      child: Stack(
        children: [
          if (mine)
            const Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 4,
              // Wide enough to find by eye down a long list, which a tint
              // alone is not on a sunlit phone.
              child: ColoredBox(color: Ps.primary),
            ),
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.fromLTRB(mine ? 14 : 10, 8, 4, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 50,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          hasTime
                              ? ScheduleFormat.when(f, withDate: false)
                              : 'TBC',
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: hasTime ? Ps.ink : Ps.faint,
                          ),
                        ),
                        if (hasTime)
                          Text(
                            _dayLabel(f),
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style:
                                const TextStyle(fontSize: 10, color: Ps.muted),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${f.displayNameA()}  v  ${f.displayNameB()}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight:
                                mine ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                        if (court.isNotEmpty)
                          Text(
                            court,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontSize: 11, color: Ps.muted),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  _Status(fixture: f, isLive: isLive),
                  if (actions.isNotEmpty)
                    PopupMenuButton<ScheduleAction>(
                      // One overflow button rather than three icon buttons:
                      // on a 360pt phone those three took a third of the row
                      // and pushed both team names into an ellipsis.
                      icon: const Icon(Icons.more_vert, size: 18),
                      tooltip: 'Match options',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32),
                      onSelected: (a) => a.onSelected(),
                      itemBuilder: (context) => [
                        for (final a in actions)
                          PopupMenuItem(
                            value: a,
                            child: Row(
                              children: [
                                Icon(a.icon, size: 18, color: a.color),
                                const SizedBox(width: 10),
                                // A menu opened from a row near the right
                                // edge of a phone is narrower than "Start
                                // this match early" is wide.
                                Flexible(
                                  child: Text(
                                    a.label,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _dayLabel(Fixture f) {
    final at = f.scheduledAt!;
    final today = DateTime.now();
    final isToday = at.year == today.year &&
        at.month == today.month &&
        at.day == today.day;
    return isToday ? 'Today' : ScheduleFormat.when(f).split(' · ').first;
  }
}

/// The right-hand column: a live dot, a score, or nothing.
class _Status extends StatelessWidget {
  const _Status({required this.fixture, required this.isLive});

  final Fixture fixture;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    if (isLive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Ps.live,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'LIVE',
          style: TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      );
    }

    final summary = fixture.summary;
    if (summary.isEmpty) return const SizedBox.shrink();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 84),
      child: Text(
        localizedSummary(context, summary),
        textAlign: TextAlign.right,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Ps.ink,
        ),
      ),
    );
  }
}

/// "Your next match", pinned above the groups.
class _NextUpCard extends StatelessWidget {
  const _NextUpCard({required this.fixture, this.onTap});

  final Fixture? fixture;
  final void Function(Fixture)? onTap;

  @override
  Widget build(BuildContext context) {
    final f = fixture;
    if (f == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final court = ScheduleFormat.court(f);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Ps.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Ps.radiusSm),
        border: Border.all(color: Ps.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.event_available_outlined,
              size: 20, color: Ps.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  f.isLiveAt(DateTime.now())
                      ? 'Your match is on now'
                      : 'Your next match',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Ps.primary,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${f.displayNameA()}  v  ${f.displayNameB()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  [
                    ScheduleFormat.when(f),
                    if (court.isNotEmpty) court,
                    ScheduleFormat.round(f),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Ps.muted),
                ),
              ],
            ),
          ),
          if (onTap != null)
            IconButton(
              icon: const Icon(Icons.arrow_forward, size: 18),
              tooltip: 'Open this match',
              onPressed: () => onTap!(f),
            ),
        ],
      ),
    );
  }
}
