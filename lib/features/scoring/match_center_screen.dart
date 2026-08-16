import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/models/enums.dart';
import '../../core/models/fixture.dart';
import '../../core/models/match_official.dart';
import '../../core/models/umpire_profile.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui_kit.dart';
import 'match_setup.dart';

/// The hub a match opens into, whatever it came from.
///
/// `docs/Heart_of_the_playsphere.md` §4 and §30. A match created by a season,
/// a tournament, a challenge or two people on a court all arrive here, and
/// from here it is prepared and started. The point of the screen is that it
/// is the *same* screen in every case — the source is written on it as a
/// label, not as a different layout.
///
/// ## Why this sits between the fixture list and the scoring screen
///
/// Before this existed, tapping a match went straight to either the scorer's
/// keypad or the spectator's scoreboard, decided by whether you held the pen.
/// Neither is where an organizer needs to be an hour before a match: one is a
/// scoring surface for a game that has not started, the other is a scoreboard
/// showing nothing. Assigning an umpire had no home at all outside the
/// tournament-wide officials panel, which is the wrong altitude for "who is
/// standing in this one match".
class MatchCenterScreen extends ConsumerWidget {
  const MatchCenterScreen({
    super.key,
    required this.orgId,
    required this.compId,
    required this.fixtureId,
  });

  final String orgId;
  final String compId;
  final String fixtureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = FixtureRef(orgId, compId, fixtureId);
    final fixtureAsync = ref.watch(fixtureProvider(key));
    final uid = ref.watch(currentUidProvider);
    final canManage = ref
        .watch(myCapabilitiesProvider(orgId))
        .contains(Capability.manageCompetitions);

    return AppScaffold(
      orgId: orgId,
      title: 'Match Center',
      body: AsyncView(
        value: fixtureAsync,
        builder: (fixture) {
          if (fixture == null) {
            return const EmptyState(
              icon: Icons.search_off,
              title: 'This match is not available',
              message: 'It may have been removed, or belong to a private club.',
            );
          }

          final competition =
              ref.watch(competitionProvider(CompRef(orgId, compId))).valueOrNull;
          final canScore = uid != null &&
              fixture.canBeScoredBy(uid, isOrgManager: canManage);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _Header(fixture: fixture, competitionName: competition?.name),
              const SizedBox(height: 12),
              _OfficialsCard(
                fixture: fixture,
                canManage: canManage,
              ),
              const SizedBox(height: 12),
              _ConfigurationCard(fixture: fixture),
              const SizedBox(height: 20),
              _StartAction(
                fixture: fixture,
                canScore: canScore,
                canManage: canManage,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Sport, competition, the two sides, when and where, and what state it is in.
class _Header extends StatelessWidget {
  const _Header({required this.fixture, required this.competitionName});

  final Fixture fixture;
  final String? competitionName;

  @override
  Widget build(BuildContext context) {
    final sportId = fixture.sportId;
    final when = fixture.scheduledAt;

    return PsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (sportId != null) ...[
                SportBadge(sportId: sportId, size: 34),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (sportId != null)
                      Text(
                        SportCatalog.byId(sportId).name.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: Ps.primary,
                        ),
                      ),
                    if (competitionName != null)
                      Text(
                        competitionName!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: Ps.ink,
                        ),
                      ),
                  ],
                ),
              ),
              // §12's source, shown rather than merely stored. It is the one
              // thing on this screen that says why the match exists.
              _SourceChip(source: fixture.resolvedSource),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  fixture.entrantAName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Ps.ink,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'VS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Ps.faint,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  fixture.entrantBName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Ps.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (when != null)
            _MetaRow(
              icon: Icons.event,
              text: DateFormat('d MMM yyyy • h:mm a').format(when),
            ),
          if (fixture.venue case final venue? when venue.trim().isNotEmpty)
            _MetaRow(icon: Icons.place_outlined, text: venue),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Ps.border),
          const SizedBox(height: 12),
          _StatusLine(fixture: fixture),
        ],
      ),
    );
  }
}

/// The single line that answers "where is this match up to".
///
/// Reads both axes — [Fixture.status] and [Fixture.readiness] — and states
/// whichever is the more informative. A match that is live says live; one
/// that has not started says how ready it is.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.fixture});

  final Fixture fixture;

  @override
  Widget build(BuildContext context) {
    final (label, color) = _describe(fixture);
    return Row(
      children: [
        const Text(
          'STATUS',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: Ps.faint,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  static (String, Color) _describe(Fixture fixture) {
    // A stale-live match is not live. Same derivation the spectator
    // scoreboard uses — a scorer who closed the app on Tuesday must not leave
    // the Match Center claiming a game is under way.
    final now = DateTime.now();
    if (fixture.isLiveAt(now)) return ('LIVE', Ps.live);
    if (fixture.isStaleLiveAt(now)) return ('PAUSED', const Color(0xFFF59E0B));

    if (fixture.status.isResulted) {
      return switch (fixture.resultState) {
        MatchResultState.awaitingApproval => (
            'AWAITING APPROVAL',
            const Color(0xFFF59E0B),
          ),
        _ => ('FINALIZED', Ps.primary),
      };
    }
    if (fixture.status != FixtureStatus.scheduled) {
      return (fixture.status.label.toUpperCase(), Ps.muted);
    }
    return switch (fixture.readiness) {
      MatchReadiness.ready => ('READY', Ps.primary),
      MatchReadiness.officialsAssigned => ('OFFICIALS ASSIGNED', Ps.muted),
      MatchReadiness.scheduled => ('UPCOMING', Ps.muted),
    };
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.source});

  final MatchSource source;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Ps.canvas,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Ps.border),
      ),
      child: Text(
        source.label,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: Ps.muted,
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 15, color: Ps.faint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, color: Ps.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// §5 and §6 — who is officiating, and who holds the pen.
class _OfficialsCard extends ConsumerWidget {
  const _OfficialsCard({required this.fixture, required this.canManage});

  final Fixture fixture;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final officials = fixture.officials;

    return PsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Officials',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Ps.ink,
            ),
          ),
          const SizedBox(height: 12),
          if (officials.isEmpty)
            const Text(
              'Nobody assigned yet.',
              style: TextStyle(fontSize: 13, color: Ps.muted),
            )
          else
            for (final official in officials)
              _OfficialRow(
                official: official,
                canManage: canManage,
                onRemove: () => _remove(context, ref, official),
              ),
          if (canManage) ...[
            const SizedBox(height: 12),
            PsSecondaryButton(
              label: officials.isEmpty ? 'Assign Umpire' : 'Assign another',
              icon: Icons.person_add_alt,
              onPressed: () => _assign(context, ref),
            ),
          ],
          const SizedBox(height: 16),
          const Divider(height: 1, color: Ps.border),
          const SizedBox(height: 12),
          const Text(
            'Scorer',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Ps.ink,
            ),
          ),
          const SizedBox(height: 8),
          if (fixture.scorerUids.isEmpty)
            const Text(
              'No scorer assigned. An organizer can still score without being '
              'assigned.',
              style: TextStyle(fontSize: 12.5, color: Ps.muted, height: 1.4),
            )
          else
            for (final scorerUid in fixture.scorerUids)
              _ScorerRow(
                uid: scorerUid,
                canManage: canManage,
                onRemove: () => _removeScorer(context, ref, scorerUid),
              ),
          if (canManage) ...[
            const SizedBox(height: 10),
            PsSecondaryButton(
              label: fixture.scorerUids.isEmpty
                  ? 'Assign Scorer'
                  : 'Assign another scorer',
              icon: Icons.edit_note,
              onPressed: () => _assignScorer(context, ref),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _assign(BuildContext context, WidgetRef ref) async {
    final sportId = fixture.sportId;
    if (sportId == null) {
      showError(context, 'This match has no sport recorded, so officials '
          'cannot be matched to it.');
      return;
    }
    final picked = await showModalBottomSheet<UmpireProfile>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AssignOfficialSheet(sportId: sportId),
    );
    if (picked == null || !context.mounted) return;

    try {
      await ref.read(umpireRepositoryProvider).assignOfficialToFixture(
            orgId: fixture.orgId,
            compId: fixture.compId,
            fixtureId: fixture.id,
            official: MatchOfficial(uid: picked.uid, name: picked.displayName),
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${picked.displayName} assigned.')),
        );
      }
    } catch (e) {
      // Surfaced rather than swallowed: the repository refuses an official
      // already standing in a live or overlapping match, and that refusal is
      // the whole reason the check exists.
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _assignScorer(BuildContext context, WidgetRef ref) async {
    final members =
        ref.read(orgMembersProvider(fixture.orgId)).valueOrNull ?? const [];
    final eligible = members
        .where((m) => m.isActive && !fixture.scorerUids.contains(m.uid))
        .toList();

    if (eligible.isEmpty) {
      showError(
        context,
        'Everyone in this club already holds the pen for this match.',
      );
      return;
    }

    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AssignScorerSheet(
        names: {for (final m in eligible) m.uid: m.displayName},
      ),
    );
    if (picked == null || !context.mounted) return;

    try {
      await ref.read(umpireRepositoryProvider).assignScorer(
            orgId: fixture.orgId,
            compId: fixture.compId,
            fixtureId: fixture.id,
            scorerUid: picked,
          );
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _removeScorer(
    BuildContext context,
    WidgetRef ref,
    String scorerUid,
  ) async {
    try {
      await ref.read(umpireRepositoryProvider).removeScorer(
            orgId: fixture.orgId,
            compId: fixture.compId,
            fixtureId: fixture.id,
            scorerUid: scorerUid,
          );
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    MatchOfficial official,
  ) async {
    try {
      await ref.read(umpireRepositoryProvider).removeOfficialFromFixture(
            orgId: fixture.orgId,
            compId: fixture.compId,
            fixtureId: fixture.id,
            officialUid: official.uid,
          );
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}

class _OfficialRow extends StatelessWidget {
  const _OfficialRow({
    required this.official,
    required this.canManage,
    required this.onRemove,
  });

  final MatchOfficial official;
  final bool canManage;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.check_circle, size: 18, color: Ps.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  official.name,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Ps.ink,
                  ),
                ),
                Text(
                  _roleLabel(official.role),
                  style: const TextStyle(fontSize: 11.5, color: Ps.muted),
                ),
              ],
            ),
          ),
          if (canManage)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Remove ${official.name}',
              onPressed: onRemove,
            ),
        ],
      ),
    );
  }

  /// `main_umpire` -> `Main umpire`.
  static String _roleLabel(String role) {
    final spaced = role.replaceAll('_', ' ');
    if (spaced.isEmpty) return 'Official';
    return spaced[0].toUpperCase() + spaced.substring(1);
  }
}

/// One person holding the pen.
///
/// Resolves the name from the club's member list rather than storing it on
/// the fixture: `scorerUids` is a list of uids by design, and denormalizing a
/// name beside each would go stale the first time somebody changed how they
/// are listed.
class _ScorerRow extends ConsumerWidget {
  const _ScorerRow({
    required this.uid,
    required this.canManage,
    required this.onRemove,
  });

  final String uid;
  final bool canManage;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider(uid)).valueOrNull;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Icon(Icons.edit_note, size: 18, color: Ps.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              // Falls back to a neutral label rather than the raw uid: a
              // member whose profile this viewer cannot read is still a
              // scorer, and showing a document id helps nobody.
              profile?.displayName ?? 'Scorer',
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Ps.ink,
              ),
            ),
          ),
          if (canManage)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Remove scorer',
              onPressed: onRemove,
            ),
        ],
      ),
    );
  }
}

/// Picks a club member to hand the pen to — §6.
class _AssignScorerSheet extends StatefulWidget {
  const _AssignScorerSheet({required this.names});

  /// uid -> display name, already filtered to people who do not hold it yet.
  final Map<String, String> names;

  @override
  State<_AssignScorerSheet> createState() => _AssignScorerSheetState();
}

class _AssignScorerSheetState extends State<_AssignScorerSheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final entries = widget.names.entries
        .where((e) => query.isEmpty || e.value.toLowerCase().contains(query))
        .toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            const Text(
              'Assign Scorer',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Ps.ink,
              ),
            ),
            const SizedBox(height: 4),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Anyone in the club can score — an official, a team scorer, '
                'or a captain.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Ps.muted),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: PsSearchField(
                hint: 'Search members',
                controller: _search,
                onChanged: (_) => setState(() {}),
              ),
            ),
            Flexible(
              child: entries.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Nobody matches that.',
                        style: TextStyle(fontSize: 13, color: Ps.muted),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: entries.length,
                      itemBuilder: (context, i) => ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Ps.canvas,
                          child:
                              Icon(Icons.person, size: 18, color: Ps.muted),
                        ),
                        title: Text(entries[i].value),
                        onTap: () => Navigator.pop(context, entries[i].key),
                      ),
                    ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// §4's Match Configuration block — the rules this match will actually be
/// played under.
///
/// Read from `fixture.scoringConfig`, which the draw froze at creation, not
/// from the sport's current preset. A competition whose rules were edited
/// after the draw was generated must still show each match the rules it was
/// made with.
class _ConfigurationCard extends StatelessWidget {
  const _ConfigurationCard({required this.fixture});

  final Fixture fixture;

  @override
  Widget build(BuildContext context) {
    final config = fixture.scoringConfig;
    final entries = config.entries
        .where((e) => e.value != null && '${e.value}'.isNotEmpty)
        .take(6)
        .toList();

    return PsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Match Configuration',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Ps.ink,
            ),
          ),
          const SizedBox(height: 10),
          if (entries.isEmpty)
            const Text(
              'This match uses the sport\'s standard rules.',
              style: TextStyle(fontSize: 13, color: Ps.muted),
            )
          else
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        psHumanizeCounter(entry.key),
                        style: const TextStyle(fontSize: 13, color: Ps.muted),
                      ),
                    ),
                    Text(
                      '${entry.value}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Ps.ink,
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

/// The button §30 ends on, and what it becomes once the match is under way.
class _StartAction extends ConsumerWidget {
  const _StartAction({
    required this.fixture,
    required this.canScore,
    required this.canManage,
  });

  final Fixture fixture;
  final bool canScore;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watchPath = Routes.watch(fixture.orgId, fixture.compId, fixture.id);

    if (fixture.status.isResulted) {
      return PsPrimaryButton(
        label: 'View result',
        onPressed: () => context.push(
          Routes.matchResult(fixture.orgId, fixture.compId, fixture.id),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canScore)
          PsPrimaryButton(
            label: fixture.isLiveAt(DateTime.now())
                ? 'Continue scoring'
                : 'Start Match',
            onPressed: () => _handleStartMatch(context, ref),
          )
        else
          PsSecondaryButton(
            label: 'Watch this match',
            icon: Icons.visibility_outlined,
            onPressed: () => context.push(watchPath),
          ),
        // §7's READY, and deliberately only an organizer's signal rather than
        // a gate — see `UmpireRepository.setMatchReadiness`. A club playing on
        // a Sunday has nobody to press it and must never be blocked by that.
        if (canManage &&
            fixture.status == FixtureStatus.scheduled &&
            fixture.readiness != MatchReadiness.ready) ...[
          const SizedBox(height: 10),
          PsSecondaryButton(
            label: 'Mark ready to play',
            icon: Icons.check_circle_outline,
            onPressed: () => ref.read(umpireRepositoryProvider).setMatchReadiness(
                  orgId: fixture.orgId,
                  compId: fixture.compId,
                  fixtureId: fixture.id,
                  readiness: MatchReadiness.ready,
                ),
          ),
        ],
        if (canManage &&
            fixture.status == FixtureStatus.scheduled &&
            !fixture.isDraft) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.flag_outlined, size: 18),
            label: const Text('Award Walkover / Forfeit'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
              side: BorderSide(
                color: Theme.of(context).colorScheme.error.withValues(alpha: 0.5),
              ),
            ),
            onPressed: () => _showWalkoverDialog(context, ref),
          ),
        ],
      ],
    );
  }

  Future<void> _handleStartMatch(BuildContext context, WidgetRef ref) async {
    final scoringPath =
        Routes.scoring(fixture.orgId, fixture.compId, fixture.id);

    // If the match is already live or has recorded actions, go straight to scoring
    if (fixture.lastSeq > 0 ||
        (fixture.tossWonByEntrantId != null &&
            fixture.tossWonByEntrantId!.isNotEmpty)) {
      context.push(scoringPath);
      return;
    }

    // Intercept with dedicated Pre-Match Toss Flow (CricHeroes / IPL standard)
    final tossDone = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TossDialog(fixture: fixture),
    );

    if (tossDone == true && context.mounted) {
      context.push(scoringPath);
    }
  }

  Future<void> _showWalkoverDialog(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<
        ({String? winnerId, String note, bool isAbandoned})>(
      context: context,
      builder: (ctx) => _WalkoverDialog(fixture: fixture),
    );
    if (result == null || !context.mounted) return;

    try {
      if (result.isAbandoned) {
        await ref.read(scoringServiceProvider).setFixtureOutcome(
              fixture: fixture,
              status: FixtureStatus.abandoned,
              resultType: MatchResultType.abandoned,
              note: result.note,
            );
      } else {
        await ref.read(scoringServiceProvider).setFixtureOutcome(
              fixture: fixture,
              status: FixtureStatus.walkover,
              resultType: MatchResultType.walkover,
              winnerEntrantId: result.winnerId,
              note: result.note,
            );
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.isAbandoned
                  ? 'Match marked as abandoned.'
                  : 'Walkover awarded. Standings & bracket updated!',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}

/// Dialog letting organizers resolve a no-show / forfeit cleanly on match day.
class _WalkoverDialog extends StatefulWidget {
  const _WalkoverDialog({required this.fixture});
  final Fixture fixture;

  @override
  State<_WalkoverDialog> createState() => _WalkoverDialogState();
}

class _WalkoverDialogState extends State<_WalkoverDialog> {
  String? _selectedWinnerId;
  bool _isAbandoned = false;
  final _noteController = TextEditingController(text: 'Opponent no-show');

  @override
  void initState() {
    super.initState();
    _selectedWinnerId = widget.fixture.entrantAId;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.fixture;
    return AlertDialog(
      title: const Text('Award Walkover / Forfeit'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select the winning side if an opponent was absent, or mark as abandoned:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            RadioListTile<String?>(
              title: Text('Win: ${f.entrantAName}'),
              subtitle: Text('Opponent ${f.entrantBName} did not show'),
              value: f.entrantAId,
              groupValue: _isAbandoned ? null : _selectedWinnerId,
              onChanged: (val) => setState(() {
                _isAbandoned = false;
                _selectedWinnerId = val;
              }),
            ),
            RadioListTile<String?>(
              title: Text('Win: ${f.entrantBName}'),
              subtitle: Text('Opponent ${f.entrantAName} did not show'),
              value: f.entrantBId,
              groupValue: _isAbandoned ? null : _selectedWinnerId,
              onChanged: (val) => setState(() {
                _isAbandoned = false;
                _selectedWinnerId = val;
              }),
            ),
            RadioListTile<bool>(
              title: const Text('Abandoned / No Contest'),
              subtitle: const Text('Both sides absent or match called off'),
              value: true,
              groupValue: _isAbandoned,
              onChanged: (val) => setState(() {
                _isAbandoned = true;
                _selectedWinnerId = null;
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: 'Reason / Notes',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            (
              winnerId: _selectedWinnerId,
              note: _noteController.text.trim(),
              isAbandoned: _isAbandoned,
            ),
          ),
          child: const Text('Confirm Result'),
        ),
      ],
    );
  }
}

/// §5's official picker: search, then a list showing what each one has done.
class _AssignOfficialSheet extends ConsumerStatefulWidget {
  const _AssignOfficialSheet({required this.sportId});

  final String sportId;

  @override
  ConsumerState<_AssignOfficialSheet> createState() =>
      _AssignOfficialSheetState();
}

class _AssignOfficialSheetState extends ConsumerState<_AssignOfficialSheet> {
  final _search = TextEditingController();
  late Future<List<UmpireProfile>> _officials;

  @override
  void initState() {
    super.initState();
    // Fetched once and filtered in memory. The registry for one sport is a
    // short list, and re-querying Firestore on every keystroke would cost a
    // read per character typed.
    _officials = ref
        .read(umpireRepositoryProvider)
        .fetchUmpiresForSport(widget.sportId);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            const Text(
              'Assign Umpire',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Ps.ink,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: PsSearchField(
                hint: 'Search officials',
                controller: _search,
                onChanged: (_) => setState(() {}),
              ),
            ),
            Flexible(
              child: FutureBuilder<List<UmpireProfile>>(
                future: _officials,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final all = snapshot.data ?? const <UmpireProfile>[];
                  final shown = query.isEmpty
                      ? all
                      : all
                          .where((u) =>
                              u.displayName.toLowerCase().contains(query))
                          .toList();

                  if (shown.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'No officials registered for this sport yet. Umpires '
                        'register themselves in the umpire registry.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Ps.muted),
                      ),
                    );
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: shown.length,
                    itemBuilder: (context, i) {
                      final umpire = shown[i];
                      return ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Ps.canvas,
                          child: Icon(
                            Icons.sports,
                            size: 18,
                            color: Ps.muted,
                          ),
                        ),
                        title: Text(umpire.displayName),
                        // Exactly what §5's mockup shows: the badge and the
                        // count are how an organizer chooses between three
                        // names they may not know personally.
                        subtitle: Text(
                          '${_badge(umpire.badgeLevel)} · '
                          '${psGrouped(umpire.matchesOfficiated)} matches',
                          style: const TextStyle(fontSize: 12),
                        ),
                        onTap: () => Navigator.pop(context, umpire),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  static String _badge(String level) {
    if (level.isEmpty) return 'Official';
    return level[0].toUpperCase() + level.substring(1);
  }
}
