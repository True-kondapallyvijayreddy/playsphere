import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/competition.dart';
import '../../core/models/enums.dart';
import '../../core/models/fixture.dart';
import '../../core/models/organization.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../shared/app_scaffold.dart';
import '../scoring/widgets/live_score_card.dart';

/// One entrant's page inside a competition — what tapping a name on a match,
/// a schedule row or a standings table now leads to.
///
/// ## Why a team gets a different page from a player
///
/// PlaySphere has no persistent "Team" entity — a team entrant is a name and
/// a roster scoped to one competition (`Entrant.memberUids`), not something
/// with a history of its own across seasons; a quick-match "Team A" is not
/// even backed by an `Entrant` document at all (see the not-found branch
/// below). A player, by contrast, already has a real career page —
/// identity, every sport, match history — that this screen is not going to
/// build a second, thinner copy of.
///
/// So the split is: an individual redirects straight to that existing career
/// page; a team gets "this team, in this competition" — its roster (each of
/// whom does have a career, one tap further) and how it has done here. A
/// cross-tournament team identity with its own multi-season history is a
/// bigger, separate piece of work than this.
class EntrantDetailScreen extends ConsumerWidget {
  const EntrantDetailScreen({
    super.key,
    required this.orgId,
    required this.compId,
    required this.entrantId,
  });

  final String orgId;
  final String compId;
  final String entrantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = CompRef(orgId, compId);
    final entrantsAsync = ref.watch(entrantsProvider(key));
    final entrants = entrantsAsync.valueOrNull ?? const <Entrant>[];
    final entrant = entrants.where((e) => e.id == entrantId).firstOrNull;

    if (entrantsAsync.hasError) {
      return AppScaffold(
        orgId: orgId,
        title: 'Entrant',
        body: AsyncErrorStrip(value: entrantsAsync, what: 'this entrant'),
      );
    }

    // Single-match/quick-match/challenge fixtures name their two sides with
    // literal ids ('side_a'/'side_b', or an org id) rather than a real
    // `Entrant` document — see the quick-match path in
    // `CompetitionRepository`. Landing here for one of those is a genuine
    // "there is no profile for this", not a bug to paper over.
    if (entrant == null) {
      return AppScaffold(
        orgId: orgId,
        title: 'Entrant',
        body: entrantsAsync.isLoading
            ? const Center(child: CircularProgressIndicator())
            : const EmptyState(
                icon: Icons.person_off_outlined,
                title: 'No profile for this entrant',
                message: 'This side was named directly on the match rather '
                    'than entered into a draw, so there is nothing more to '
                    'show.',
              ),
      );
    }

    // An individual already has a career page — identity, every sport they
    // play, match history, head to head — one tap away from every screen
    // that leads here, so this hands off rather than building a second one.
    if (entrant.uid != null) {
      final uid = entrant.uid!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.pushReplacement(Routes.profile(uid));
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return _TeamEntrantView(orgId: orgId, compId: compId, entrant: entrant);
  }
}

/// Roster and this-competition record for a team entrant.
class _TeamEntrantView extends ConsumerWidget {
  const _TeamEntrantView({
    required this.orgId,
    required this.compId,
    required this.entrant,
  });

  final String orgId;
  final String compId;
  final Entrant entrant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final key = CompRef(orgId, compId);
    final members =
        ref.watch(orgMembersProvider(orgId)).valueOrNull ?? const <Membership>[];
    final fixtures = (ref.watch(fixturesProvider(key)).valueOrNull ??
            const <Fixture>[])
        .where(
          (f) => f.entrantAId == entrant.id || f.entrantBId == entrant.id,
        )
        .toList()
      ..sort((a, b) => a.round != b.round
          ? a.round.compareTo(b.round)
          : a.matchIndex.compareTo(b.matchIndex));
    final myUid = ref.watch(currentUidProvider);
    final canManage = ref
        .watch(myCapabilitiesProvider(orgId))
        .contains(Capability.manageCompetitions);
    final competition = ref.watch(competitionProvider(key)).valueOrNull;

    // Groups+knockout has a table per group and no single one is "the"
    // table — find whichever group actually has this entrant. Everything
    // else has at most one table.
    Standing? standing;
    String? groupLabel;
    if (competition?.format == CompetitionFormat.groupThenKnockout) {
      final groups =
          ref.watch(groupStandingsProvider(key)).valueOrNull ?? const {};
      for (final e in groups.entries) {
        final row = e.value.where((s) => s.entrantId == entrant.id).firstOrNull;
        if (row != null) {
          standing = row;
          groupLabel = e.key;
          break;
        }
      }
    } else {
      final table = ref.watch(standingsProvider(key)).valueOrNull ?? const [];
      standing = table.where((s) => s.entrantId == entrant.id).firstOrNull;
    }

    return AppScaffold(
      orgId: orgId,
      title: entrant.displayName,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ContentBounds(
            maxWidth: 720,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                if (standing != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  groupLabel == null
                                      ? 'This competition'
                                      : 'Group $groupLabel',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${standing.won}W – ${standing.lost}L'
                                  '${standing.drawn > 0 ? ' – ${standing.drawn}D' : ''}'
                                  ' · ${standing.points} pts',
                                  style: theme.textTheme.titleMedium,
                                ),
                              ],
                            ),
                          ),
                          if (standing.rank > 0)
                            Text(
                              '#${standing.rank}',
                              style: theme.textTheme.headlineSmall,
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Text('Roster', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                if (entrant.memberUids.isEmpty)
                  Text(
                    'No roster recorded for this entrant.',
                    style: theme.textTheme.bodySmall,
                  )
                else
                  for (final uid in entrant.memberUids)
                    _RosterTile(uid: uid, members: members),
                const SizedBox(height: 24),
                Text(
                  'Matches in this competition',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (fixtures.isEmpty)
                  Text('No matches yet.', style: theme.textTheme.bodySmall)
                else
                  for (final f in fixtures)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: LiveScoreCard(
                        fixture: f,
                        dense: true,
                        onTap: () {
                          final canScore = myUid != null &&
                              f.canBeScoredBy(myUid, isOrgManager: canManage);
                          context.push(
                            canScore
                                ? Routes.scoring(orgId, compId, f.id)
                                : Routes.watch(orgId, compId, f.id),
                          );
                        },
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RosterTile extends StatelessWidget {
  const _RosterTile({required this.uid, required this.members});

  final String uid;
  final List<Membership> members;

  @override
  Widget build(BuildContext context) {
    final member = members.where((m) => m.uid == uid).firstOrNull;
    final name = member?.displayName ?? 'Member';

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          backgroundImage:
              member?.photoUrl != null ? NetworkImage(member!.photoUrl!) : null,
          child: member?.photoUrl == null
              ? Text(name.characters.first.toUpperCase())
              : null,
        ),
        title: Text(name),
        trailing: const Icon(Icons.chevron_right),
        // Every member already has a career page — this is the other route
        // that leads to it, alongside a direct individual-entrant tap.
        onTap: () => context.push(Routes.profile(uid)),
      ),
    );
  }
}
