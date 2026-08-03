import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/competition.dart';
import '../../core/models/enums.dart';
import '../../core/models/fixture.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../core/models/draw_slot.dart';
import '../../domain/standings/standings_calculator.dart';
import '../../domain/standings/tiebreak.dart';
import '../../shared/app_scaffold.dart';
import 'widgets/draw_setup_sheet.dart';
import 'widgets/squad_call_card.dart';
import '../scoring/widgets/live_score_card.dart';
import '../scoring/widgets/share_match_button.dart';

/// The event's control room: entries, the draw, and every fixture.
///
/// The organizer's path through a competition is linear — open entries,
/// approve people, close entries, make the draw, play — so the screen shows
/// exactly one primary action at a time rather than a wall of buttons where
/// most are invalid.
class CompetitionDetailScreen extends ConsumerWidget {
  const CompetitionDetailScreen({
    super.key,
    required this.orgId,
    required this.compId,
  });

  final String orgId;
  final String compId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = CompRef(orgId, compId);
    final compAsync = ref.watch(competitionProvider(key));
    final caps = ref.watch(myCapabilitiesProvider(orgId));
    final canManage = caps.contains(Capability.manageCompetitions);

    return AppScaffold(
      orgId: orgId,
      title: 'Event',
      body: AsyncView(
        value: compAsync,
        builder: (comp) {
          if (comp == null) {
            return const EmptyState(
              icon: Icons.search_off,
              title: 'This event no longer exists',
            );
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              ContentBounds(
                maxWidth: 960,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(competition: comp),
                    const SizedBox(height: 16),
                    if (canManage) _OrganizerActions(competition: comp),
                    if (canManage) _QualifierCard(competition: comp),
                    const SizedBox(height: 16),
                    _Entries(competition: comp, canManage: canManage),
                    const SizedBox(height: 24),
                    _StandingsTable(competition: comp),
                    // A challenge is one fixture and two independently-owned
                    // squads, so the squad call belongs next to the match
                    // rather than inside the competition-level entry list.
                    if (comp.isInterClub) _InterClubSquads(competition: comp),
                    _Fixtures(competition: comp, canManage: canManage),
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

class _Header extends StatelessWidget {
  const _Header({required this.competition});
  final Competition competition;

  @override
  Widget build(BuildContext context) {
    final c = competition;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.name, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(c.sportName)),
                Chip(label: Text(c.category.label)),
                Chip(label: Text(c.format.label)),
                Chip(label: Text(c.status.label)),
              ],
            ),
            if (c.venue != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.place_outlined, size: 16),
                  const SizedBox(width: 6),
                  Text(c.venue!),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One primary action, chosen by where the competition is in its lifecycle.
class _OrganizerActions extends ConsumerWidget {
  const _OrganizerActions({required this.competition});
  final Competition competition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = competition;
    final repo = ref.read(competitionRepositoryProvider);
    final entrants =
        ref.watch(entrantsProvider(CompRef(c.orgId, c.id))).valueOrNull ??
            const [];

    Future<void> run(Future<void> Function() action) async {
      try {
        await action();
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    final (label, description, onPressed) = switch (c.status) {
      CompetitionStatus.draft => (
          'Open entries',
          'Players in this organization will be able to enter.',
          () => run(() => repo.setStatus(
                orgId: c.orgId,
                compId: c.id,
                status: CompetitionStatus.registrationOpen,
              )),
        ),
      CompetitionStatus.registrationOpen => (
          'Close entries',
          'Freezes the field so you can make the draw. Approve everyone you '
              'want in first.',
          () => run(() async {
                final count = await repo.lockFieldAndCreateEntrants(
                  orgId: c.orgId,
                  compId: c.id,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$count entrants confirmed.')),
                  );
                }
              }),
        ),
      CompetitionStatus.registrationClosed => (
          'Set up and generate the draw',
          'Choose groups, courts and match length, then create every fixture '
              'for a ${c.format.label.toLowerCase()}.',
          () => run(() async {
                // The organizer's choices are collected BEFORE generating,
                // because the draw's shape and its timetable are both fixed
                // the moment the fixtures are written — regenerating
                // afterwards is only possible while nothing has been scored.
                final choices = await DrawSetupSheet.show(
                  context,
                  competition: c,
                  entrantCount: entrants.where((e) => !e.withdrawn).length,
                );
                if (choices == null) return;

                final configured = c.withDrawSetup(
                  drawConfig: choices.draw,
                  scheduleConfig: choices.schedule,
                );
                // Persisted first, so the draw can be explained — and
                // reproduced identically — after the fact.
                await repo.updateCompetition(configured);

                final uid = ref.read(currentUidProvider);
                final made = await repo.generateDraw(
                  competition: configured,
                  entrants: entrants,
                  defaultScorerUids: uid == null ? const [] : [uid],
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${made.written} matches created'
                        '${choices.schedule.hasCourts ? ' and scheduled across '
                            '${choices.schedule.courts.length} courts' : ''}.',
                      ),
                    ),
                  );
                }
              }),
        ),
      CompetitionStatus.scheduled => (
          'Start the event',
          'Marks the competition as in progress.',
          () => run(() => repo.setStatus(
                orgId: c.orgId,
                compId: c.id,
                status: CompetitionStatus.inProgress,
              )),
        ),
      CompetitionStatus.inProgress => (
          'Finish the event',
          'Closes the competition. Results become final.',
          () => run(() => repo.setStatus(
                orgId: c.orgId,
                compId: c.id,
                status: CompetitionStatus.completed,
              )),
        ),
      _ => ('', '', null),
    };

    if (onPressed == null) return const SizedBox.shrink();

    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(description),
            const SizedBox(height: 12),
            FilledButton(onPressed: onPressed, child: Text(label)),
          ],
        ),
      ),
    );
  }
}

class _Entries extends ConsumerWidget {
  const _Entries({required this.competition, required this.canManage});
  final Competition competition;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = competition;
    final key = CompRef(c.orgId, c.id);
    final regsAsync = ref.watch(registrationsProvider(key));
    final regs = regsAsync.valueOrNull ?? const [];
    final me = ref.watch(currentUserProvider).valueOrNull;
    // If the read failed, `myReg` is null for the wrong reason and the screen
    // would offer "Enter" to someone already entered — a duplicate the rules
    // then reject, which reads to the user as the button being broken.
    final myReg = me == null
        ? null
        : regs.where((r) => r.uid == me.uid).firstOrNull;

    Future<void> enter() async {
      if (me == null) return;
      try {
        // The repository decides the real outcome inside a transaction
        // against fresh counts, and returns it. Reporting *that* rather than
        // a generic "submitted" is the difference between a player knowing
        // they are playing on Sunday and a player assuming it.
        final outcome = await ref
            .read(competitionRepositoryProvider)
            .register(competition: c, user: me);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(switch (outcome) {
              RegistrationStatus.confirmed => 'You are in. See you there.',
              RegistrationStatus.waitlisted =>
                'Event is full — you are on the waitlist. '
                    'You move up automatically if someone drops out.',
              _ => 'Entry submitted. The organizer will confirm it.',
            })),
          );
        }
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    // What the button will actually do, said before it is pressed.
    final actionLabel = switch (c.outcomeOfRegisteringNow) {
      RegistrationStatus.confirmed => 'Register',
      RegistrationStatus.waitlisted => 'Join waitlist',
      _ => 'Apply',
    };

    final eligibility =
        me == null ? null : c.category.check(me, competitionStart: c.startDate);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Entries (${regs.length})',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (myReg != null)
                  Chip(
                    label: Text(
                      myReg.status == RegistrationStatus.waitlisted &&
                              myReg.waitlistPosition != null
                          ? 'Waitlist #${myReg.waitlistPosition}'
                          : myReg.status.label,
                    ),
                  )
                else if (c.registrationIsOpen && me != null)
                  FilledButton.tonal(
                    onPressed:
                        eligibility?.isEligible == true ? enter : null,
                    child: Text(actionLabel),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            _SlotsLine(competition: c),
            // Telling someone exactly why they cannot enter is the difference
            // between a fair rule and an unexplained refusal.
            if (myReg == null &&
                eligibility != null &&
                !eligibility.isEligible) ...[
              const SizedBox(height: 6),
              Text(
                eligibility.reason!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
              ),
            ],
            const SizedBox(height: 8),
            AsyncErrorStrip(value: regsAsync, what: 'the entry list'),
            if (regs.isEmpty && !regsAsync.hasError)
              Text('Nobody has entered yet.',
                  style: Theme.of(context).textTheme.bodySmall)
            else
              for (final r in regs)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundImage:
                        r.photoUrl != null ? NetworkImage(r.photoUrl!) : null,
                    child: r.photoUrl == null
                        ? Text(r.displayName.characters.first.toUpperCase())
                        : null,
                  ),
                  title: Text(r.displayName),
                  subtitle: Text(
                    [
                      if (r.status == RegistrationStatus.waitlisted &&
                          r.waitlistPosition != null)
                        'Waitlist #${r.waitlistPosition}'
                      else
                        r.status.label,
                      // Marked so the open registrants can see which slots
                      // were ever really available to them.
                      if (r.preselected) 'picked by organizer',
                    ].join(' · '),
                  ),
                  trailing: !canManage ||
                          r.status != RegistrationStatus.pending
                      ? null
                      : Wrap(
                          children: [
                            IconButton(
                              tooltip: 'Confirm',
                              icon: const Icon(Icons.check),
                              onPressed: () => _decide(
                                context,
                                ref,
                                c,
                                r.uid,
                                RegistrationStatus.confirmed,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Reject',
                              icon: const Icon(Icons.close),
                              onPressed: () => _decide(
                                context,
                                ref,
                                c,
                                r.uid,
                                RegistrationStatus.rejected,
                              ),
                            ),
                          ],
                        ),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref,
    Competition c,
    String uid,
    RegistrationStatus status,
  ) async {
    final me = ref.read(currentUidProvider);
    if (me == null) return;
    try {
      await ref.read(competitionRepositoryProvider).decideRegistration(
            orgId: c.orgId,
            compId: c.id,
            uid: uid,
            status: status,
            decidedByUid: me,
          );
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}

/// How the field stands, in one line.
///
/// A registration limit that is only enforced at the moment someone taps
/// Register is a limit nobody can plan around. Saying "4 of 13 slots left"
/// up front is what lets a member decide to register now rather than
/// discovering on Saturday night that they are third reserve.
class _SlotsLine extends StatelessWidget {
  const _SlotsLine({required this.competition});

  final Competition competition;

  @override
  Widget build(BuildContext context) {
    final c = competition;
    final theme = Theme.of(context);
    final parts = <String>[];

    final left = c.slotsRemaining;
    if (left == null) {
      parts.add('No limit on entries');
    } else if (left > 0) {
      parts.add('$left of ${c.openSlots} slots left');
    } else {
      parts.add('Field is full');
    }

    if (c.participationModel == ParticipationModel.hybrid &&
        c.preselectedSlots > 0) {
      parts.add('${c.preselectedSlots} picked by the organizer');
    }

    if (c.waitlistCount > 0) {
      parts.add('${c.waitlistCount} on the waitlist');
    } else if (c.waitlistEnabled && (left == null || left == 0)) {
      parts.add('waitlist open');
    }

    if (!c.isFree) parts.add('₹${c.entryFeeRupees} entry');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          parts.join(' · '),
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (c.rulesNote != null && c.rulesNote!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(c.rulesNote!, style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }
}

/// The league table.
///
/// Shown only for formats where a table means something. A knockout bracket
/// has no standings — presenting one implies a league that is not being
/// played, and an organizer reading it would draw the wrong conclusion.
/// Promotes finished group winners into the knockout bracket.
///
/// The step that used to be done on paper. The draw has always carried, on
/// every knockout fixture, the table position that will fill it — "winner of
/// Group B" — and nothing ever read those tags, so the quarter-finals of a
/// groups+knockout tournament said "To be decided" until the organizer
/// rewrote them by hand.
///
/// Shown only while there is something left to promote, so it disappears once
/// the bracket is full rather than sitting there as a permanent button.
class _QualifierCard extends ConsumerStatefulWidget {
  const _QualifierCard({required this.competition});
  final Competition competition;

  @override
  ConsumerState<_QualifierCard> createState() => _QualifierCardState();
}

class _QualifierCardState extends ConsumerState<_QualifierCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.competition;
    if (c.format != CompetitionFormat.groupThenKnockout) {
      return const SizedBox.shrink();
    }

    final fixtures =
        ref.watch(fixturesProvider(CompRef(c.orgId, c.id))).valueOrNull ??
            const <Fixture>[];

    // Knockout slots still waiting on a group they can name.
    final pending = fixtures.where((f) =>
        (f.qualifierA != null && f.entrantAId.isEmpty) ||
        (f.qualifierB != null && f.entrantBId.isEmpty));
    if (pending.isEmpty) return const SizedBox.shrink();

    const groupsDone = StandingsCalculator();
    final readyGroups = <String>{
      for (final f in fixtures)
        if (f.bracket == Bracket.group && f.groupId != null) f.groupId!,
    }.where((g) => groupsDone.isGroupComplete(g, fixtures)).toList()
      ..sort();

    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        color: theme.colorScheme.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Fill the knockout stage',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                readyGroups.isEmpty
                    ? 'No group has finished yet. A group only promotes once '
                        'every one of its matches has a result — half a group '
                        'has a leader, not a winner.'
                    : '${readyGroups.length} group'
                        '${readyGroups.length == 1 ? '' : 's'} finished '
                        '(${readyGroups.join(', ')}). '
                        '${pending.length} knockout '
                        '${pending.length == 1 ? 'match is' : 'matches are'} '
                        'still waiting on a name.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: _busy || readyGroups.isEmpty ? null : _resolve,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.account_tree_outlined),
                label: const Text('Update the bracket'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _resolve() async {
    setState(() => _busy = true);
    final c = widget.competition;
    try {
      final outcome = await ref.read(competitionRepositoryProvider)
          .resolveQualifiers(orgId: c.orgId, compId: c.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            outcome.slotsResolved == 0
                ? 'Nothing to promote yet — still waiting on '
                    '${outcome.groupsPending.join(', ')}.'
                : '${outcome.slotsResolved} knockout '
                    '${outcome.slotsResolved == 1 ? 'match' : 'matches'} '
                    'filled in.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// One group's table, with the qualifying places marked.
///
/// The line under the last qualifying position is the whole point: a group
/// table is read to answer one question — am I going through? — and a table
/// that does not answer it makes everyone ask the organizer instead.
class _GroupTable extends StatelessWidget {
  const _GroupTable({
    required this.groupId,
    required this.rows,
    required this.qualifiers,
  });

  final String groupId;
  final List<Standing> rows;
  final int qualifiers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Group $groupId', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (var i = 0; i < rows.length; i++) ...[
              Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      '${i + 1}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: i < qualifiers
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight:
                            i < qualifiers ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                  Expanded(child: Text(rows[i].displayName)),
                  Text('${rows[i].played}',
                      style: theme.textTheme.bodySmall),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${rows[i].points}',
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              if (i == qualifiers - 1 && i < rows.length - 1)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Divider(color: theme.colorScheme.primary),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          'qualify',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: theme.colorScheme.primary),
                        ),
                      ),
                      Expanded(
                        child: Divider(color: theme.colorScheme.primary),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StandingsTable extends ConsumerWidget {
  const _StandingsTable({required this.competition});
  final Competition competition;

  static const _tableFormats = {
    CompetitionFormat.roundRobin,
    CompetitionFormat.leagueTable,
    CompetitionFormat.swiss,
    CompetitionFormat.groupThenKnockout,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_tableFormats.contains(competition.format)) {
      return const SizedBox.shrink();
    }

    // A groups draw has several tables and no meaningful combined one: Group
    // A's players have never met Group B's, so their points do not compare.
    // Showing one merged table was not just untidy, it was wrong.
    if (competition.format == CompetitionFormat.groupThenKnockout) {
      final groupsAsync = ref.watch(
        groupStandingsProvider(CompRef(competition.orgId, competition.id)),
      );
      final tables = groupsAsync.valueOrNull ?? const <String, List<Standing>>{};
      if (tables.isEmpty) return const SizedBox.shrink();

      final ids = tables.keys.toList()..sort();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final id in ids)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _GroupTable(
                groupId: id,
                rows: tables[id]!,
                qualifiers: competition.drawConfig.qualifiersPerGroup,
              ),
            ),
        ],
      );
    }

    final tableAsync = ref.watch(
      standingsProvider(CompRef(competition.orgId, competition.id)),
    );

    // A table that failed to load must say so. Collapsing to `shrink()` on
    // error is what made a rejected fixtures read look like a competition
    // nobody had played yet.
    if (tableAsync.hasError) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Card(
          child: ListTile(
            leading: const Icon(Icons.error_outline),
            title: const Text('Table unavailable'),
            subtitle: Text(errorMessage(tableAsync.error!)),
          ),
        ),
      );
    }

    final table = tableAsync.valueOrNull ?? const <Standing>[];
    if (table.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final anyPlayed = table.any((r) => r.played > 0);

    // The order shown has to be the order actually applied. This used to be a
    // fixed sentence naming score difference, which misdescribed every cricket
    // league (net run rate) and every Swiss event (Buchholz).
    final chain = Tiebreak.parse(
      competition.tiebreakChain,
      competition.sportId,
    );
    final shownChain =
        chain.where((t) => t != Tiebreak.name).map((t) => t.label).toList();

    // Whichever separator the chain actually uses gets its own column, so an
    // organizer can show a disputing captain the number that decided the order.
    final showNrr = chain.contains(Tiebreak.netRunRate);
    final showBuchholz = chain.contains(Tiebreak.buchholz);

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Table', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            anyPlayed
                ? 'Points, then ${shownChain.join(', then ').toLowerCase()}.'
                : 'Updates automatically as results come in.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              // A table is genuinely wide content, so it scrolls inside its own
              // box rather than making the whole page scroll sideways on a
              // phone.
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 40,
                  dataRowMinHeight: 42,
                  dataRowMaxHeight: 48,
                  columnSpacing: 18,
                  columns: [
                    const DataColumn(label: Text('#')),
                    const DataColumn(label: Text('Entrant')),
                    const DataColumn(label: Text('P'), numeric: true),
                    const DataColumn(label: Text('W'), numeric: true),
                    const DataColumn(label: Text('D'), numeric: true),
                    const DataColumn(label: Text('L'), numeric: true),
                    const DataColumn(label: Text('+/−'), numeric: true),
                    if (showNrr)
                      const DataColumn(
                        label: Tooltip(
                          message: 'Net run rate',
                          child: Text('NRR'),
                        ),
                        numeric: true,
                      ),
                    if (showBuchholz)
                      const DataColumn(
                        label: Tooltip(
                          message: 'Buchholz — sum of opponents’ scores',
                          child: Text('BH'),
                        ),
                        numeric: true,
                      ),
                    const DataColumn(label: Text('Pts'), numeric: true),
                  ],
                  rows: [
                    for (final row in table)
                      DataRow(
                        cells: [
                          DataCell(Text('${row.rank}')),
                          DataCell(
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 180),
                              child: Text(
                                row.displayName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DataCell(Text('${row.played}')),
                          DataCell(Text('${row.won}')),
                          DataCell(Text('${row.drawn}')),
                          DataCell(Text('${row.lost}')),
                          DataCell(Text(
                            row.scoreDifference > 0
                                ? '+${row.scoreDifference}'
                                : '${row.scoreDifference}',
                          )),
                          if (showNrr)
                            DataCell(Text(
                              // Three decimals, because that is the precision
                              // qualification is argued at (CLAUDE.md §12.6).
                              row.netRunRate == null
                                  ? '—'
                                  : row.netRunRate!.toStringAsFixed(3),
                            )),
                          if (showBuchholz)
                            DataCell(Text('${row.buchholz}')),
                          DataCell(Text(
                            '${row.points}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          )),
                        ],
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

/// Picks who may score a match.
///
/// Without this the only person who could ever score was whoever pressed
/// "Generate the draw" — `assignScorers` existed in the repository with no
/// caller, so the judge/scorer role could be granted but never used, and the
/// "an event manager can add you as a scorer" empty state pointed at a screen
/// that did not exist.
class _AssignScorersDialog extends ConsumerStatefulWidget {
  const _AssignScorersDialog({required this.fixture});
  final Fixture fixture;

  @override
  ConsumerState<_AssignScorersDialog> createState() =>
      _AssignScorersDialogState();
}

class _AssignScorersDialogState extends ConsumerState<_AssignScorersDialog> {
  late final Set<String> _selected = {...widget.fixture.scorerUids};
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(orgMembersProvider(widget.fixture.orgId));
    final members = membersAsync.valueOrNull ?? const [];
    // Only roles that carry the scoring capability. Offering a plain member
    // would let an organizer assign someone the rules will then reject.
    final eligible = members
        .where((m) =>
            m.isActive &&
            PermissionMatrix.can(m.role, Capability.scoreMatches))
        .toList();

    return AlertDialog(
      title: const Text('Who can score this match?'),
      content: SizedBox(
        width: 400,
        // The "nobody holds the scoring role" sentence sends the organizer to
        // the Members screen to fix a problem that may not exist, so it is
        // only claimed when the member list genuinely loaded.
        child: membersAsync.hasError
            ? AsyncErrorStrip(value: membersAsync, what: 'the member list')
            : eligible.isEmpty
            ? const Text(
                'Nobody in this organization holds the scoring role yet. '
                'Give someone the Judge / Scorer role on the Members screen '
                'first.',
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final m in eligible)
                    CheckboxListTile(
                      value: _selected.contains(m.uid),
                      onChanged: (on) => setState(() {
                        if (on == true) {
                          _selected.add(m.uid);
                        } else {
                          _selected.remove(m.uid);
                        }
                      }),
                      title: Text(m.displayName),
                      subtitle: Text(m.role.label),
                      dense: true,
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy || eligible.isEmpty
              ? null
              : () async {
                  setState(() => _busy = true);
                  try {
                    await ref
                        .read(competitionRepositoryProvider)
                        .assignScorers(
                          orgId: widget.fixture.orgId,
                          compId: widget.fixture.compId,
                          fixtureId: widget.fixture.id,
                          scorerUids: _selected.toList(),
                        );
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    if (context.mounted) {
                      setState(() => _busy = false);
                      showError(context, e);
                    }
                  }
                },
          child: Text(_busy ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}

class _Fixtures extends ConsumerWidget {
  const _Fixtures({required this.competition, required this.canManage});
  final Competition competition;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = competition;
    final key = CompRef(c.orgId, c.id);
    final fixturesAsync = ref.watch(fixturesProvider(key));
    final fixtures = fixturesAsync.valueOrNull ?? const [];
    final myUid = ref.watch(currentUidProvider);

    // "No matches yet" is a claim about the draw. Only make it when the read
    // actually succeeded — otherwise an organizer is told to generate a draw
    // that already exists.
    if (fixturesAsync.hasError) {
      return AsyncErrorStrip(value: fixturesAsync, what: 'the match list');
    }

    if (fixtures.isEmpty) {
      return Text(
        'No matches yet — generate the draw once entries are closed.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Matches', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        for (final f in fixtures)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: LiveScoreCard(
                    fixture: f,
                    dense: true,
                    onTap: () {
                      final canScore = myUid != null && f.canBeScoredBy(myUid);
                      context.push(
                        canScore
                            ? Routes.scoring(c.orgId, c.id, f.id)
                            : Routes.watch(c.orgId, c.id, f.id),
                      );
                    },
                  ),
                ),
                // Only while there is something to watch. A link to a match
                // that has not started shows an empty scoreboard, which is a
                // worse thing to send someone than nothing.
                if (f.isLive || f.hasResult)
                  ShareMatchButton(fixture: f, compact: true),
                if (canManage)
                  IconButton(
                    tooltip: f.scorerUids.isEmpty
                        ? 'No scorer assigned'
                        : '${f.scorerUids.length} scorer(s) assigned',
                    icon: Icon(
                      f.scorerUids.isEmpty
                          ? Icons.person_off_outlined
                          : Icons.how_to_reg_outlined,
                      color: f.scorerUids.isEmpty
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => _AssignScorersDialog(fixture: f),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The squad call for a challenge match.
///
/// A challenge has exactly one fixture, so this finds it rather than making
/// the reader pick one from a list of one.
class _InterClubSquads extends ConsumerWidget {
  const _InterClubSquads({required this.competition});

  final Competition competition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fixtures = ref
            .watch(fixturesProvider(CompRef(competition.orgId, competition.id)))
            .valueOrNull ??
        const <Fixture>[];
    if (fixtures.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: SquadCallCard(
        competition: competition,
        fixture: fixtures.first,
      ),
    );
  }
}
