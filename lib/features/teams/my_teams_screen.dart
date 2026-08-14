import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/enums.dart';
import '../../core/models/team.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';

/// Every active squad the signed-in person is on — a club's permanent side,
/// an independent team of friends, or a squad raised for one tournament.
///
/// The other half of the "My clubs" panel: a club is *who you belong to*, a
/// team is *who you take onto a field together*, and a person with one club
/// membership can still be on three different elevens inside it.
class MyTeamsScreen extends ConsumerWidget {
  const MyTeamsScreen({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teams = ref.watch(myTeamsProvider);
    final isMe = ref.watch(currentUidProvider) == uid;

    return Scaffold(
      appBar: AppBar(title: Text(isMe ? 'My teams' : 'Teams')),
      body: AsyncView(
        value: teams,
        onRetry: () => ref.invalidate(myTeamsProvider),
        builder: (all) {
          if (all.isEmpty) {
            return EmptyState(
              icon: Icons.shield_outlined,
              title: 'No teams yet',
              message: isMe
                  ? 'A club owner raises a team from its members list — once '
                      "you're picked for one, it shows up here."
                  : 'No teams to show.',
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ContentBounds(
                maxWidth: 720,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final team in all) _TeamRow(team: team),
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

class _TeamRow extends ConsumerWidget {
  const _TeamRow({required this.team});
  final Team team;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sport = SportCatalog.byId(team.sportId);
    final club = team.clubId == null
        ? null
        : ref.watch(organizationProvider(team.clubId!)).valueOrNull;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundImage:
              team.photoUrl != null ? NetworkImage(team.photoUrl!) : null,
          child: team.photoUrl == null ? Text(sport.icon) : null,
        ),
        title: Text(team.name),
        subtitle: Text(
          [
            sport.name,
            if (club != null) club.name,
            if (team.type == TeamType.event) 'Tournament squad',
            '${team.memberUids.length} players',
          ].join(' · '),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(Routes.team(team.id)),
      ),
    );
  }
}
