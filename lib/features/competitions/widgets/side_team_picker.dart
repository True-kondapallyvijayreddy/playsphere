import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/fixture.dart';
import '../../../core/models/match_player.dart';
import '../../../core/models/organization.dart';
import '../../../core/models/team.dart';
import '../../../core/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../domain/scoring/scoring_registry.dart';
import '../../../shared/app_scaffold.dart';
import '../../../shared/identity.dart';

/// One club choosing which of its teams is playing this match.
///
/// ## The gap this closes
///
/// A challenge produced a fixture between two CLUBS, and each club filled its
/// side with a list of names. That was the only place left in the product
/// where a side was not a team — everywhere else the participation rule holds
/// that a team is what enters, and a team has a page, a roster and a record
/// across seasons. Here the eleven names went onto the fixture and nowhere
/// else, so the match never appeared on any team's record, and the team a
/// club had just assembled off an availability call had nothing to be used
/// for.
///
/// ## The order it happens in
///
/// Challenge first, team second. A club is being asked which eleven are
/// playing a match that does not exist yet if the team is demanded on the
/// challenge form — and the club being challenged never sees that form at
/// all, so it would have no place to name its own. So: send the challenge,
/// agree a date, and *then* both clubs name a side, independently, whenever
/// they are ready.
///
/// ## Why nothing here is final
///
/// The team is a pointer. Its roster lives on the team document, so adding a
/// player to the team adds them to this match; and a club may swap the whole
/// team for another one — the B team travelling instead of the A team is an
/// ordinary Saturday. Both stop at the moment that club locks its squad,
/// which is the existing statement of "we have finished picking" and is
/// deliberately the only thing that freezes a side.
class SideTeamPicker extends ConsumerStatefulWidget {
  const SideTeamPicker({
    super.key,
    required this.fixture,
    required this.orgId,
    required this.side,
  });

  final Fixture fixture;

  /// The club naming its team — always the caller's own side.
  final String orgId;
  final String side;

  static Future<void> show(
    BuildContext context, {
    required Fixture fixture,
    required String orgId,
    required String side,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) =>
            SideTeamPicker(fixture: fixture, orgId: orgId, side: side),
      );

  @override
  ConsumerState<SideTeamPicker> createState() => _SideTeamPickerState();
}

class _SideTeamPickerState extends ConsumerState<SideTeamPicker> {
  String? _busyTeamId;

  /// The team's roster as match players, resolved against the club's member
  /// list.
  ///
  /// Uids and not names. A player written in by name is a stranger who
  /// happens to share it and nothing accrues to them — the same distinction
  /// `QuickMatchScreen` exists to protect. Passing the accounts is what makes
  /// the match land on the right careers.
  ///
  /// A member who has left the club is dropped rather than carried as a bare
  /// uid: they are on the team document's roster but they are not this club's
  /// player any more, and putting them on the sheet would name somebody the
  /// club can no longer field.
  List<MatchPlayer> _lineupFor(Team team, List<Membership> members) {
    final byUid = {for (final m in members) m.uid: m};
    return [
      for (final uid in team.memberUids)
        if (byUid[uid] != null)
          MatchPlayer(id: uid, name: byUid[uid]!.displayName, uid: uid),
    ];
  }

  Future<void> _choose(Team? team, List<Membership> members) async {
    setState(() => _busyTeamId = team?.id ?? '');
    try {
      await ref.read(competitionRepositoryProvider).setSideTeam(
            fixture: widget.fixture,
            forOrgId: widget.orgId,
            team: team,
            lineup: team == null ? const [] : _lineupFor(team, members),
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            team == null
                ? 'Team cleared. Pick players individually, or name another '
                    'team.'
                : '${team.name} is your side for this match.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyTeamId = null);
      showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fixture = widget.fixture;
    // `sport` and not `sportId`: the latter is null on fixtures written
    // before it existed, and the accessor carries the plugin-key fallback.
    // Every challenge fixture writes it, so this is exact for the case that
    // brought the picker here.
    final sportId = fixture.sport;
    final sport = SportCatalog.byId(sportId);
    final named = fixture.teamIdForSide(widget.side);

    final membersAsync = ref.watch(orgMembersProvider(widget.orgId));
    final members = (membersAsync.valueOrNull ?? const <Membership>[])
        .where((m) => m.isActive)
        .toList();

    // The club's own teams only. A club naming a side may field any squad it
    // has raised, and may not field somebody else's — which is also what
    // `firestore.rules` enforces on the write, so offering a wider list here
    // would just produce a permission error at the tap.
    final teams = [
      for (final t in ref.watch(clubTeamsProvider(widget.orgId)).valueOrNull ??
          const <Team>[])
        if (t.sportId == sportId && t.isSelectable) t,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text('Which team is playing?', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            '${sport.icon} Your side of ${fixture.displayNameA()} v '
            '${fixture.displayNameB()}. You can change this until you lock '
            'your squad.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),

          if (teams.isEmpty)
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'This club has no ${sport.name.toLowerCase()} team yet. '
                  'Build one from whoever answered your availability call — '
                  'the new-team screen can filter to the people who said '
                  'they are in.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            )
          else
            for (final t in teams)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: PsAvatar(
                  name: t.name,
                  photoUrl: t.photoUrl,
                  seed: t.id,
                  size: 36,
                ),
                title: Text(t.name),
                subtitle: Text(
                  '${t.memberUids.length} in the squad'
                  '${t.id == named ? ' · playing this match' : ''}',
                ),
                trailing: _busyTeamId == t.id
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : t.id == named
                        ? const Icon(Icons.check_circle)
                        : const Icon(Icons.chevron_right),
                // One at a time: two side-naming writes racing each other
                // would leave the line-up and the pointer disagreeing.
                enabled: _busyTeamId == null && t.id != named,
                onTap: () => _choose(t, members),
              ),

          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              context.push(Routes.createTeam(widget.orgId));
            },
            icon: const Icon(Icons.group_add_outlined),
            label: const Text('Build a team from who said they are in'),
          ),

          if (named != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed:
                  _busyTeamId == null ? () => _choose(null, members) : null,
              child: const Text('Play without naming a team'),
            ),
          ],
        ],
      ),
    );
  }
}
