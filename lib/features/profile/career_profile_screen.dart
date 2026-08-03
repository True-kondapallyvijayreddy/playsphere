import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/app_user.dart';
import '../../core/models/memory.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../data/career_repository.dart';
import '../../domain/rating/glicko2.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import 'widgets/memory_grid.dart';

/// A player's lifelong profile — the thing CLAUDE.md §1 promises when it says a
/// player from a Hyderabad community club can move to Delhi and still have their
/// verified career ten years later.
///
/// ## What was already true before this screen existed
///
/// Every match finalize has been writing `users/{uid}/ratings/{sportId}` and
/// `users/{uid}/career_stats/{sportId}` for as long as ratings have shipped.
/// Nothing ever read them — there was no decoder and no screen — so a correct
/// Glicko-2 implementation and a full career tally were accumulating invisibly.
/// This screen is the first reader. It does not compute anything new.
///
/// Layout is deliberately close to a social profile: identity, then a stat
/// strip, then sports, then a photo grid. That shape is the one every user
/// already knows how to read, which matters more here than novelty.
class CareerProfileScreen extends ConsumerWidget {
  const CareerProfileScreen({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider(uid));
    final career = ref.watch(careerProvider(uid));
    final memories = ref.watch(playerMemoriesProvider(uid));
    final isMe = ref.watch(currentUidProvider) == uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          if (isMe)
            IconButton(
              tooltip: 'Edit profile',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => context.push(Routes.profileSetup),
            ),
        ],
      ),
      body: AsyncView(
        value: profile,
        onRetry: () => ref.invalidate(userProfileProvider(uid)),
        builder: (user) {
          if (user == null) {
            return const EmptyState(
              icon: Icons.person_off_outlined,
              title: 'This profile is not available',
              message: 'It may be private, or the player may have left.',
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
                    _Identity(user: user, isMe: isMe),
                    const SizedBox(height: 20),

                    _CareerSummary(career: career, memories: memories),
                    const SizedBox(height: 24),

                    Text('Sports', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Ratings settle after every match. A wide band means we '
                      'are still learning your level.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    AsyncErrorStrip(value: career, what: 'your sports record'),
                    _SportsList(career: career, isMe: isMe),

                    const SizedBox(height: 28),
                    Text(
                      'Memories',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isMe
                          ? 'Photos from matches you played in.'
                          : 'Photos from matches ${user.displayName} played in.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    AsyncErrorStrip(value: memories, what: 'memories'),
                    MemoryGrid(
                      memories: memories.valueOrNull ?? const [],
                      loading: memories.isLoading,
                      emptyMessage: isMe
                          ? 'No memories yet. Add photos from a match and they '
                              'will collect here for good.'
                          : 'No memories yet.',
                    ),
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

class _Identity extends StatelessWidget {
  const _Identity({required this.user, required this.isMe});

  final AppUser user;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final where = user.geo.district;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 40,
          backgroundImage:
              user.photoUrl != null ? NetworkImage(user.photoUrl!) : null,
          child: user.photoUrl == null
              ? Text(
                  user.displayName.characters.first.toUpperCase(),
                  style: theme.textTheme.headlineMedium,
                )
              : null,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.displayName, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 2),
              Text(
                [
                  if (where != null && where.isNotEmpty) where,
                  // Age rather than date of birth: a public profile should not
                  // publish a minor's exact birth date, and the age band is the
                  // only part anyone needs.
                  '${user.ageAt(DateTime.now())} yrs',
                ].join(' · '),
                style: theme.textTheme.bodyMedium,
              ),
              // The player code, shown on every profile and copyable from
              // one's own. It is the thing a person gives a captain who is
              // filling in a team sheet, and a code nobody can find is a code
              // nobody uses — so it lives beside the name rather than in a
              // settings page.
              if (user.playerCode case final code?) ...[
                const SizedBox(height: 6),
                ActionChip(
                  avatar: const Icon(Icons.badge_outlined, size: 16),
                  label: Text(code),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide.none,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isMe
                              ? 'Your player code is copied. Give it to '
                                  'whoever is filling in the team sheet.'
                              : 'Player code copied.',
                        ),
                      ),
                    );
                  },
                ),
              ],
              if (user.isMinor) ...[
                const SizedBox(height: 6),
                Chip(
                  avatar: const Icon(Icons.shield_outlined, size: 16),
                  label: const Text('Junior — guardian protected'),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide.none,
                  backgroundColor: theme.colorScheme.secondaryContainer,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The stat strip: matches, sports, memories. The three numbers a person
/// actually looks for when they open a profile.
class _CareerSummary extends StatelessWidget {
  const _CareerSummary({required this.career, required this.memories});

  final AsyncValue<List<CareerLine>> career;
  final AsyncValue<List<Memory>> memories;

  @override
  Widget build(BuildContext context) {
    final lines = career.valueOrNull ?? const <CareerLine>[];
    final matches = lines.fold<int>(0, (sum, l) => sum + l.matchesPlayed);
    final clubs = <String>{
      for (final l in lines) ...?l.stats?.clubsPlayedFor,
    }.length;

    return Row(
      children: [
        _Stat(label: 'Matches', value: '$matches'),
        _Stat(label: 'Sports', value: '${lines.where((l) => l.matchesPlayed > 0).length}'),
        _Stat(label: 'Clubs', value: '$clubs'),
        _Stat(
          label: 'Memories',
          value: '${(memories.valueOrNull ?? const []).length}',
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Semantics(
        label: '$value $label',
        excludeSemantics: true,
        child: Column(
          children: [
            Text(value, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 2),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _SportsList extends StatelessWidget {
  const _SportsList({required this.career, required this.isMe});

  final AsyncValue<List<CareerLine>> career;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    if (career.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final lines = career.valueOrNull ?? const <CareerLine>[];
    if (lines.isEmpty) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.sports_outlined),
          title: Text(isMe ? 'No matches yet' : 'No record yet'),
          subtitle: Text(
            isMe
                ? 'Play a match and your record starts building here '
                    'automatically — it follows you between clubs for good.'
                : 'This player has not finished a match yet.',
          ),
        ),
      );
    }

    return Column(
      children: [for (final line in lines) _SportCard(line: line)],
    );
  }
}

class _SportCard extends StatelessWidget {
  const _SportCard({required this.line});

  final CareerLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rating = line.rating;

    // A rating id is not always a sport id: chess is rated per time control
    // (`chess:blitz`), per §7.11. Strip the qualifier to look up the sport, but
    // keep it in the label so blitz and classical read as different records.
    final baseId = line.sportId.split(':').first;
    final qualifier = line.sportId.contains(':')
        ? line.sportId.split(':').last
        : null;
    final sport = SportCatalog.byId(baseId);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(sport.icon, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        qualifier == null
                            ? sport.name
                            : '${sport.name} · $qualifier',
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        '${line.matchesPlayed} '
                        '${line.matchesPlayed == 1 ? 'match' : 'matches'}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (rating != null) _RatingBadge(rating: rating),
              ],
            ),
            if (line.stats != null && line.stats!.tally.isNotEmpty) ...[
              const SizedBox(height: 12),
              _TallyStrip(tally: line.stats!.tally),
            ],
          ],
        ),
      ),
    );
  }
}

/// The Glicko tier, with the confidence band spelled out.
///
/// The tier leads and the raw number is secondary, per §8.1 — "Club" means
/// something to a village captain in a way that 1524 does not. The provisional
/// flag matters just as much: a rating off two games is a guess, and presenting
/// it with the same confidence as one off forty would be dishonest.
class _RatingBadge extends StatelessWidget {
  const _RatingBadge({required this.rating});

  final Rating rating;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (low, high) = rating.confidenceInterval;

    return Semantics(
      label: rating.isProvisional
          ? '${rating.tier}, provisional rating ${rating.rating.round()}'
          : '${rating.tier}, rating ${rating.rating.round()}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            children: [
              if (rating.isProvisional)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Tooltip(
                    message: 'Provisional — needs a few more matches to settle',
                    child: Icon(
                      Icons.hourglass_empty,
                      size: 14,
                      color: theme.hintColor,
                    ),
                  ),
                ),
              Text(rating.tier, style: theme.textTheme.titleSmall),
            ],
          ),
          Text(
            '${rating.rating.round()}  ·  ${low.round()}–${high.round()}',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Lifetime totals for a sport, as the engine keyed them.
///
/// Keys come straight from each plugin's box score, so this renders cricket runs
/// and kabaddi raid points without knowing anything about either. Formatting the
/// key is the only presentation concern: `raidPoints` reads as "Raid points".
class _TallyStrip extends StatelessWidget {
  const _TallyStrip({required this.tally});

  final Map<String, num> tally;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Largest first, capped: a career tally can carry a dozen counters and a
    // profile card is not a scorecard.
    final entries = tally.entries.where((e) => e.value != 0).toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final e in entries.take(6))
          Chip(
            visualDensity: VisualDensity.compact,
            side: BorderSide.none,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            label: Text(
              '${_humanize(e.key)} ${_format(e.value)}',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  static String _format(num v) =>
      v is int || v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(2);

  /// `raidPoints` → `Raid points`.
  static String _humanize(String key) {
    final spaced = key.replaceAllMapped(
      RegExp(r'(?<=[a-z0-9])(?=[A-Z])'),
      (_) => ' ',
    );
    return spaced[0].toUpperCase() + spaced.substring(1).toLowerCase();
  }
}
