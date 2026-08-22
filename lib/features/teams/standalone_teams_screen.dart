import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/team.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui_kit.dart';

/// Teams that belong to no club — make one, find one, or join one by code.
///
/// ## Why this screen exists at all
///
/// `Team` has supported `TeamType.independent` since it was written, and
/// `firestore.rules` has always allowed a signed-in person to create one. No
/// screen ever did. Every route into team creation ran through
/// `CreateTeamScreen`, which takes an `orgId`, checks
/// `Capability.manageOrganization` and hard-codes `TeamType.permanent` — so
/// in practice a team required a club you were an admin of, which is the
/// exact constraint Rule 4 forbids and the model went out of its way to
/// avoid.
///
/// The case it locks out is the ordinary one: five players from five
/// different clubs entering a tournament as one side. None of them can raise
/// that squad inside any club they belong to, because it is not that club's
/// team.
class StandaloneTeamsScreen extends ConsumerStatefulWidget {
  const StandaloneTeamsScreen({super.key});

  @override
  ConsumerState<StandaloneTeamsScreen> createState() =>
      _StandaloneTeamsScreenState();
}

class _StandaloneTeamsScreenState
    extends ConsumerState<StandaloneTeamsScreen> {
  String? _sportId;

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUidProvider);
    final mine = ref.watch(myTeamsProvider).valueOrNull ?? const <Team>[];
    final independent = [
      for (final t in mine)
        if (t.isIndependent) t,
    ];

    return AppScaffold(
      title: 'Independent teams',
      subtitle: 'Squads with no club behind them',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          ContentBounds(
            maxWidth: 720,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Text(
                    'A team does not need a club. Five players from five '
                    'different clubs can enter a tournament as one side — '
                    'this is where that side lives.',
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.45,
                      color: Ps.muted,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                if (uid != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                      onPressed: () => context.push(Routes.createStandaloneTeam),
                      icon: const Icon(Icons.group_add_outlined),
                      label: const Text('Create a team'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: () => _joinByCode(context),
                      icon: const Icon(Icons.key_outlined),
                      label: const Text('Join with a code'),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                if (independent.isNotEmpty) ...[
                  const _Heading('YOUR INDEPENDENT TEAMS'),
                  _Card(
                    children: [
                      for (final t in independent)
                        ListTile(
                          leading: const Icon(Icons.shield_outlined,
                              color: Ps.primary),
                          title: Text(t.name),
                          subtitle: Text(
                            [
                              SportCatalog.byId(t.sportId).name,
                              '${t.memberUids.length} '
                                  '${t.memberUids.length == 1 ? 'player' : 'players'}',
                              if (t.homeArea?.isNotEmpty == true) t.homeArea!,
                            ].join('  ·  '),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push(Routes.team(t.id)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],

                const _Heading('FIND A TEAM TO JOIN'),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (final sport in SportCatalog.all)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(sport.name),
                            selected: _sportId == sport.id,
                            onSelected: (on) =>
                                setState(() => _sportId = on ? sport.id : null),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (_sportId == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Pick a sport to see the independent teams playing it.',
                      style: TextStyle(fontSize: 13, color: Ps.muted),
                    ),
                  )
                else
                  _SportTeams(sportId: _sportId!, myUid: uid),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Finds a team by the code its captain read out, and opens it.
  ///
  /// The code does not admit anybody — see `Team.joinCode`. It answers "which
  /// of the eleven teams called Warriors is my one", and the team's own page
  /// is where the asking happens.
  Future<void> _joinByCode(BuildContext context) async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Join with a code'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Team code',
            hintText: 'e.g. K7M2QP',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Find team'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.trim().isEmpty || !context.mounted) return;

    final team = await ref.read(teamRepositoryProvider).findByJoinCode(code);
    if (!context.mounted) return;
    if (team == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No team uses that code.')),
      );
      return;
    }
    context.push(Routes.team(team.id));
  }
}

/// The independent teams playing one sport, with a way onto each.
class _SportTeams extends ConsumerWidget {
  const _SportTeams({required this.sportId, required this.myUid});

  final String sportId;
  final String? myUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teams = ref.watch(independentTeamsProvider(sportId));

    return AsyncView(
      value: teams,
      onRetry: () => ref.invalidate(independentTeamsProvider(sportId)),
      builder: (all) {
        if (all.isEmpty) {
          return EmptyState(
            icon: Icons.groups_2_outlined,
            title: 'None yet',
            message: 'No independent '
                '${SportCatalog.byId(sportId).name.toLowerCase()} team has '
                'been created. Yours can be the first.',
          );
        }
        return _Card(
          children: [
            for (final t in all)
              ListTile(
                leading: const Icon(Icons.groups_2_outlined, color: Ps.muted),
                title: Text(t.name),
                subtitle: Text(
                  [
                    '${t.memberUids.length} '
                        '${t.memberUids.length == 1 ? 'player' : 'players'}',
                    if (t.homeArea?.isNotEmpty == true) t.homeArea!,
                  ].join('  ·  '),
                ),
                trailing: myUid != null && t.memberUids.contains(myUid)
                    ? const Text(
                        'You’re in',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Ps.primary,
                        ),
                      )
                    : const Icon(Icons.chevron_right, color: Ps.faint),
                onTap: () => context.push(Routes.team(t.id)),
              ),
          ],
        );
      },
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
          color: Ps.faint,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Ps.surface,
        borderRadius: BorderRadius.circular(Ps.radius),
        border: Border.all(color: Ps.border),
      ),
      child: Column(children: children),
    );
  }
}
