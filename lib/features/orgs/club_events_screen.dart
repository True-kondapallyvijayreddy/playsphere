import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/result_labels.dart';
import '../../core/layout/responsive.dart';
import '../../core/models/competition.dart';
import '../../core/models/fixture.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/club_events.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/section_header.dart' show friendlyDate;
import '../../shared/ui_kit.dart';
import '../competitions/widgets/event_card.dart';
import '../home/event_feed.dart';

/// Everything a club has ever run, sorted into the four shapes it runs and
/// filterable down to the stage each one is at.
///
/// ## Why the club's own page could not stay one flat list
///
/// A club that has been going a year has a season, eleven Sunday matches, two
/// tournaments and a handful of challenges, and the home screen showed all of
/// them as one undifferentiated column of cards ordered by date. Finding "the
/// tournament whose entries are still open" meant reading the whole thing, and
/// an owner looking for a draft they had not finished had no way to ask for
/// drafts. Both are one tap here.
///
/// The four kinds are [ClubEventKind]; they are the same four an organizer
/// chose between when creating the thing, which is what makes the sorting
/// predictable rather than a taxonomy invented for this screen.
class ClubEventsScreen extends ConsumerStatefulWidget {
  const ClubEventsScreen({super.key, required this.orgId, this.initialKind});

  final String orgId;

  /// Which tab to open on. Set when the caller already knows what the user is
  /// looking for — the "Challenges" counter on the club header opens the
  /// challenges tab rather than dropping them at "Seasons" to find it.
  final ClubEventKind? initialKind;

  @override
  ConsumerState<ClubEventsScreen> createState() => _ClubEventsScreenState();
}

class _ClubEventsScreenState extends ConsumerState<ClubEventsScreen> {
  late ClubEventKind _kind = widget.initialKind ?? ClubEventKind.season;
  ClubEventStage _stage = ClubEventStage.all;

  @override
  Widget build(BuildContext context) {
    final competitions = ref.watch(competitionsProvider(widget.orgId));
    final canCreate = ref
        .watch(myCapabilitiesProvider(widget.orgId))
        .contains(Capability.manageCompetitions);

    return AppScaffold(
      orgId: widget.orgId,
      title: 'Events',
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () =>
                  context.push(Routes.createCompetition(widget.orgId)),
              icon: const Icon(Icons.add),
              label: const Text('New event'),
            )
          : null,
      body: AsyncView(
        value: competitions,
        onRetry: () => ref.invalidate(competitionsProvider(widget.orgId)),
        builder: (all) {
          final index = ClubEventIndex.of(all);
          // A stage that exists under one kind need not exist under the next.
          // Falling back rather than showing an empty list under a chip the
          // user did not choose keeps the screen honest as they move across
          // the tabs.
          final stages = index.stagesPresent(_kind);
          final stage = stages.contains(_stage) ? _stage : ClubEventStage.all;
          final rows = index.events(_kind, stage: stage);

          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              const SizedBox(height: 8),
              _KindTabs(
                index: index,
                selected: _kind,
                onSelected: (k) => setState(() {
                  _kind = k;
                  _stage = ClubEventStage.all;
                }),
              ),
              if (stages.length > 1) ...[
                const SizedBox(height: 10),
                PsFilterChips(
                  labels: [
                    for (final s in stages)
                      '${s.label}'
                          '${s == ClubEventStage.all ? '' : ' '
                              '(${index.count(_kind, stage: s)})'}',
                  ],
                  selected: stages.indexOf(stage),
                  onSelected: (i) => setState(() => _stage = stages[i]),
                ),
              ],
              const SizedBox(height: 14),
              ContentBounds(
                maxWidth: 900,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (rows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 32),
                        child: EmptyState(
                          icon: _kind.icon,
                          title: stage == ClubEventStage.all
                              ? 'No ${_kind.label.toLowerCase()} yet'
                              : 'Nothing ${stage.label.toLowerCase()}',
                          message: stage == ClubEventStage.all
                              ? _kind.empty
                              : 'No ${_kind.label.toLowerCase()} are '
                                  '${stage.label.toLowerCase()} right now.',
                        ),
                      )
                    else if (_kind.groupsBySeason)
                      for (final item in groupEventFeed(rows))
                        switch (item) {
                          EventFeedSingle(:final competition) =>
                            ClubEventTile(competition: competition),
                          EventFeedSeason(
                            :final tournamentId,
                            :final competitions
                          ) =>
                            SeasonCard(
                              orgId: widget.orgId,
                              tournamentId: tournamentId,
                              competitions: competitions,
                              showOrg: false,
                            ),
                        }
                    else
                      for (final c in rows) ClubEventTile(competition: c),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The four kind tabs, each carrying how many the club has.
///
/// Counts on the tab rather than a bare label: the number is the reason to
/// tap or not tap, and a club that has never issued a challenge should be
/// able to see that without opening the tab to find out.
class _KindTabs extends StatelessWidget {
  const _KindTabs({
    required this.index,
    required this.selected,
    required this.onSelected,
  });

  final ClubEventIndex index;
  final ClubEventKind selected;
  final ValueChanged<ClubEventKind> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 74,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: Ps.gutter,
        itemCount: ClubEventKind.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final kind = ClubEventKind.values[i];
          final isSelected = kind == selected;
          final count = index.count(kind);
          return Semantics(
            selected: isSelected,
            button: true,
            label: '${kind.label}, $count',
            excludeSemantics: true,
            child: InkWell(
              onTap: () => onSelected(kind),
              borderRadius: BorderRadius.circular(Ps.radiusSm),
              child: Container(
                width: 104,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? Ps.primary : Ps.surface,
                  borderRadius: BorderRadius.circular(Ps.radiusSm),
                  border: Border.all(
                    color: isSelected ? Ps.primary : Ps.border,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(
                      kind.icon,
                      size: 18,
                      color: isSelected ? Colors.white : Ps.muted,
                    ),
                    Text(
                      psGrouped(count),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? Colors.white : Ps.ink,
                      ),
                    ),
                    Text(
                      kind.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? Colors.white.withValues(alpha: 0.9)
                            : Ps.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One event in a club's own list.
///
/// Where the event is a single match — a Sunday game, a challenge leg — this
/// carries the result and opens the scorecard rather than the competition
/// document above it. That competition is an implementation detail: it was
/// created to hold one fixture (see `CompetitionRepository.createQuickMatch`
/// and `CommunityRepository.acceptChallenge`), and sending somebody to a
/// bracket page with one match in it to find out the score is a tap and a
/// page nobody wanted.
class ClubEventTile extends ConsumerWidget {
  const ClubEventTile({super.key, required this.competition});

  final Competition competition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = competition;
    final fixture = _resultFixture(ref, c);
    final status = c.displayStatus();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: SportBadge(sportId: c.sportId, size: 40),
        title: Text(
          fixture == null
              ? c.name
              : '${fixture.displayNameA()} v ${fixture.displayNameB()}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          [
            c.sportName,
            if (fixture != null && fixture.summary.isNotEmpty)
              localizedSummary(context, fixture.summary)
            else
              c.category.label,
            if (fixture == null) '${c.entrantCount} entered',
            if (c.startDate != null) friendlyDate(c.startDate!),
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        trailing: EventStatusChip(status: status),
        onTap: () => fixture == null
            ? context.push(Routes.competition(c.orgId, c.id))
            : context.push(Routes.watch(c.orgId, c.id, fixture.id)),
      ),
    );
  }

  /// The one finished fixture this event is, when it is one.
  ///
  /// Read from the club's own already-open fixture listener rather than a
  /// query per row — `orgFixturesProvider` is watched by the stats section on
  /// the club's home screen anyway, so on the common path this costs nothing.
  /// Null for anything with a draw behind it, and null while the listener is
  /// still loading, which degrades to the ordinary competition tap.
  Fixture? _resultFixture(WidgetRef ref, Competition c) {
    if (c.fixtureCount != 1) return null;
    final fixtures = ref.watch(orgFixturesProvider(c.orgId)).valueOrNull;
    if (fixtures == null) return null;
    for (final f in fixtures) {
      if (f.compId == c.id) return f;
    }
    return null;
  }
}
