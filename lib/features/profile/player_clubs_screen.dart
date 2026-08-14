import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../data/career_repository.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';

/// Every club a player has represented, each opening that club's page.
///
/// The profile's "Clubs" counter (`_CareerSummary`) counts the same set —
/// the union of `CareerStats.clubsPlayedFor` across every sport a player has
/// a record in — but had nowhere to send a tap. This is that destination:
/// one row per club, with which sports were played there and how many
/// matches, all derived from data the career screen already reads rather
/// than a new collection or a new club-side rollup.
class PlayerClubsScreen extends ConsumerWidget {
  const PlayerClubsScreen({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final career = ref.watch(careerProvider(uid));
    final isMe = ref.watch(currentUidProvider) == uid;

    return Scaffold(
      appBar: AppBar(title: Text(isMe ? 'My clubs' : 'Clubs')),
      body: AsyncView(
        value: career,
        onRetry: () => ref.invalidate(careerProvider(uid)),
        builder: (lines) {
          // orgId -> every sport line played there, so a club that fields a
          // player in two sports shows both rather than picking one.
          final byClub = <String, List<CareerLine>>{};
          for (final line in lines) {
            for (final orgId
                in line.stats?.clubsPlayedFor ?? const <String>{}) {
              (byClub[orgId] ??= []).add(line);
            }
          }

          // Most matches at that club first — the club someone is most
          // associated with leads, same reasoning as CareerLine.prominence.
          final clubIds = byClub.keys.toList()
            ..sort((a, b) {
              final aMatches =
                  byClub[a]!.fold<int>(0, (s, l) => s + l.matchesPlayed);
              final bMatches =
                  byClub[b]!.fold<int>(0, (s, l) => s + l.matchesPlayed);
              return bMatches.compareTo(aMatches);
            });

          if (clubIds.isEmpty) {
            return EmptyState(
              icon: Icons.shield_outlined,
              title: 'No clubs yet',
              message: isMe
                  ? 'A finished match credits the club it was played under '
                      '— play one and it appears here.'
                  : 'This player has not finished a match at a club yet.',
            );
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              ContentBounds(
                maxWidth: 900,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    for (final orgId in clubIds)
                      _ClubRow(orgId: orgId, lines: byClub[orgId]!),
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

class _ClubRow extends ConsumerWidget {
  const _ClubRow({required this.orgId, required this.lines});

  final String orgId;
  final List<CareerLine> lines;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final org = ref.watch(organizationProvider(orgId)).valueOrNull;
    final theme = Theme.of(context);
    final matches = lines.fold<int>(0, (s, l) => s + l.matchesPlayed);
    final sportNames = {
      for (final l in lines)
        SportCatalog.byId(l.sportId.split(':').first).name,
    }.join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundImage:
              org?.logoUrl != null ? NetworkImage(org!.logoUrl!) : null,
          child: org?.logoUrl == null
              ? Icon(Icons.shield_outlined, color: theme.hintColor)
              : null,
        ),
        title: Text(org?.name ?? 'Club'),
        subtitle: Text(
          '$matches ${matches == 1 ? 'match' : 'matches'} · $sportNames',
        ),
        trailing: Icon(Icons.chevron_right, color: theme.hintColor),
        onTap: () => context.push(Routes.org(orgId)),
      ),
    );
  }
}
