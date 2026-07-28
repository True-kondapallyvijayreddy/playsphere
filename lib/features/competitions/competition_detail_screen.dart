import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/competition.dart';
import '../../core/models/enums.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../shared/app_scaffold.dart';
import '../scoring/widgets/live_score_card.dart';

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
                    const SizedBox(height: 16),
                    _Entries(competition: comp, canManage: canManage),
                    const SizedBox(height: 24),
                    _Fixtures(competition: comp),
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
          'Generate the draw',
          'Creates every fixture for a ${c.format.label.toLowerCase()}.',
          () => run(() async {
                final uid = ref.read(currentUidProvider);
                final made = await repo.generateDraw(
                  competition: c,
                  entrants: entrants,
                  defaultScorerUids: uid == null ? const [] : [uid],
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$made matches created.')),
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
    final regs = ref.watch(registrationsProvider(key)).valueOrNull ?? const [];
    final me = ref.watch(currentUserProvider).valueOrNull;
    final myReg = me == null
        ? null
        : regs.where((r) => r.uid == me.uid).firstOrNull;

    Future<void> enter() async {
      if (me == null) return;
      try {
        await ref
            .read(competitionRepositoryProvider)
            .register(competition: c, user: me);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Entry submitted.')),
          );
        }
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

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
                  Chip(label: Text(myReg.status.label))
                else if (c.registrationIsOpen && me != null)
                  FilledButton.tonal(
                    onPressed:
                        eligibility?.isEligible == true ? enter : null,
                    child: const Text('Enter'),
                  ),
              ],
            ),
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
            if (regs.isEmpty)
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
                  subtitle: Text(r.status.label),
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

class _Fixtures extends ConsumerWidget {
  const _Fixtures({required this.competition});
  final Competition competition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = competition;
    final key = CompRef(c.orgId, c.id);
    final fixtures = ref.watch(fixturesProvider(key)).valueOrNull ?? const [];
    final myUid = ref.watch(currentUidProvider);

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
            child: LiveScoreCard(
              fixture: f,
              dense: true,
              onTap: () {
                final canScore =
                    myUid != null && f.canBeScoredBy(myUid);
                context.go(
                  canScore
                      ? Routes.scoring(c.orgId, c.id, f.id)
                      : Routes.watch(c.orgId, c.id, f.id),
                );
              },
            ),
          ),
      ],
    );
  }
}
