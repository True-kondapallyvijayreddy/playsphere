import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../data/career_repository.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';

/// The sports a player has a record in, each opening its own page.
///
/// The other half of Bug #2: "Matches" and "Sports" were two home-screen
/// tiles that pushed the same `/me` route. This is what Sports means on its
/// own — one row per sport, and a real destination behind each row rather
/// than a card on a profile that cannot be tapped.
class MySportsScreen extends ConsumerWidget {
  const MySportsScreen({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final career = ref.watch(careerProvider(uid));
    final isMe = ref.watch(currentUidProvider) == uid;

    return Scaffold(
      appBar: AppBar(title: Text(isMe ? 'My sports' : 'Sports')),
      body: AsyncView(
        value: career,
        onRetry: () => ref.invalidate(careerProvider(uid)),
        builder: (lines) {
          if (lines.isEmpty) {
            return EmptyState(
              icon: Icons.sports_outlined,
              title: 'No sports yet',
              message: isMe
                  ? 'Finish a match and the sport appears here with your '
                      'record in it.'
                  : 'This player has not finished a match yet.',
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
                    for (final line in lines)
                      _SportRow(uid: uid, line: line),
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

class _SportRow extends StatelessWidget {
  const _SportRow({required this.uid, required this.line});

  final String uid;
  final CareerLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // A rating id is not always a sport id: chess is rated per time control
    // (`chess:blitz`, §7.11). Strip the qualifier to find the sport, keep it
    // in the label so blitz and classical read as separate records.
    final baseId = line.sportId.split(':').first;
    final qualifier =
        line.sportId.contains(':') ? line.sportId.split(':').last : null;
    final sport = SportCatalog.byId(baseId);
    final rating = line.rating;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Text(sport.icon, style: const TextStyle(fontSize: 26)),
        title: Text(
          qualifier == null ? sport.name : '${sport.name} · $qualifier',
        ),
        subtitle: Text(
          [
            '${line.matchesPlayed} '
                '${line.matchesPlayed == 1 ? 'match' : 'matches'}',
            if (rating != null) '${rating.tier} · ${rating.rating.round()}',
          ].join(' · '),
        ),
        trailing: Icon(Icons.chevron_right, color: theme.hintColor),
        onTap: () => context.push(Routes.playerSport(uid, line.sportId)),
      ),
    );
  }
}
