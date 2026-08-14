import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/app_user.dart';
import '../../core/models/memory.dart';
import '../../core/models/team.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../data/career_repository.dart';
import '../../domain/career/head_to_head.dart';
import '../../domain/rating/glicko2.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui_kit.dart';
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
class CareerProfileScreen extends ConsumerStatefulWidget {
  const CareerProfileScreen({super.key, required this.uid});

  final String uid;

  @override
  ConsumerState<CareerProfileScreen> createState() =>
      _CareerProfileScreenState();
}

class _CareerProfileScreenState extends ConsumerState<CareerProfileScreen> {
  // Anchors for the "Sports" and "Memories" counters up top: both sections
  // already exist in full further down this same page, so a tap jumps to
  // them rather than opening a thinner screen that repeats what's already
  // here. Held on the State, not rebuilt per `build`, so a key attached in
  // one frame is still the one the next frame's tap scrolls to.
  final _sportsKey = GlobalKey();
  final _memoriesKey = GlobalKey();

  void _scrollTo(GlobalKey key) {
    final target = key.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.uid;
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

                    _CareerSummary(
                      uid: uid,
                      career: career,
                      memories: memories,
                      onSportsTap: () => _scrollTo(_sportsKey),
                      onMemoriesTap: () => _scrollTo(_memoriesKey),
                    ),
                    const SizedBox(height: 20),

                    // Only on your own profile: a squad you're on is not
                    // part of the public career record the way a match or a
                    // rating is, and there's no reader-facing reason a
                    // visitor to someone else's profile needs the roster
                    // picker one tap away.
                    if (isMe) ...[
                      const _TeamsStrip(),
                      const SizedBox(height: 20),
                    ],

                    // The per-sport breakdown the sample design leads with:
                    // pick a sport, see that sport's own numbers. It sits
                    // above the rating cards because "how many runs have I
                    // scored" is the question people open a profile for, and
                    // the Glicko band below is the specialist answer.
                    _SportBreakdown(career: career, uid: uid),
                    const SizedBox(height: 24),

                    Text(
                      'Sports',
                      key: _sportsKey,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Ratings settle after every match. A wide band means we '
                      'are still learning your level.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    AsyncErrorStrip(value: career, what: 'your sports record'),
                    _SportsList(career: career, isMe: isMe, uid: uid),

                    const SizedBox(height: 28),
                    // Built and tested since head-to-head shipped, and never
                    // shown anywhere until now — a career total says how good
                    // someone is; it has never been able to answer "how do I
                    // do against them", which is the question a rivalry is
                    // actually about.
                    _HeadToHead(uid: uid),

                    const SizedBox(height: 28),
                    Text(
                      'Memories',
                      key: _memoriesKey,
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

/// A quick look at the signed-in person's active squads, with a way to see
/// every one of them.
///
/// Reads [myTeamsProvider] directly rather than taking it as a parameter —
/// unlike career and memories, which the screen already has open for the
/// stat strip below, nothing else on this page needs the team list, so there
/// is nothing to share by lifting it.
class _TeamsStrip extends ConsumerWidget {
  const _TeamsStrip();

  static const _preview = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teams = ref.watch(myTeamsProvider).valueOrNull ?? const <Team>[];
    final theme = Theme.of(context);

    return PsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Teams', style: theme.textTheme.titleMedium),
              ),
              TextButton(
                onPressed: () => context.push(Routes.myTeams),
                child: Text(teams.isEmpty ? 'Browse' : 'See all'),
              ),
            ],
          ),
          if (teams.isEmpty)
            Text(
              'Not on a team yet. A club owner raises one from its members '
              "list — you'll see it here the moment you're picked.",
              style: theme.textTheme.bodySmall,
            )
          else
            for (final team in teams.take(_preview))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundImage: team.photoUrl != null
                      ? NetworkImage(team.photoUrl!)
                      : null,
                  child: team.photoUrl == null
                      ? Text(SportCatalog.byId(team.sportId).icon)
                      : null,
                ),
                title: Text(team.name),
                subtitle: Text('${team.memberUids.length} players'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.team(team.id)),
              ),
        ],
      ),
    );
  }
}

/// The stat strip: matches, sports, clubs, memories — each one now a
/// shortcut to the list it's counting, the same "tap the number, see the
/// list" pattern [PsStat.onTap] already uses for a club's member count.
/// "Sports" and "Memories" jump down to the sections already on this page
/// rather than opening a thinner screen that would just repeat them.
class _CareerSummary extends StatelessWidget {
  const _CareerSummary({
    required this.uid,
    required this.career,
    required this.memories,
    required this.onSportsTap,
    required this.onMemoriesTap,
  });

  final String uid;
  final AsyncValue<List<CareerLine>> career;
  final AsyncValue<List<Memory>> memories;
  final VoidCallback onSportsTap;
  final VoidCallback onMemoriesTap;

  @override
  Widget build(BuildContext context) {
    final lines = career.valueOrNull ?? const <CareerLine>[];
    final matches = lines.fold<int>(0, (sum, l) => sum + l.matchesPlayed);
    final clubs = <String>{
      for (final l in lines) ...?l.stats?.clubsPlayedFor,
    }.length;

    // Matches / Sports / Clubs / Memories, not the sample design's
    // Matches / Runs / Wickets / Win Rate. Runs and wickets are cricket
    // counters and this header is above every sport a person plays — a chess
    // player's summary cannot lead with wickets. The sport-specific numbers
    // are one section down, under the sport they belong to.
    return PsCard(
      child: PsStatRow(
        stats: [
          PsStat(
            value: psGrouped(matches),
            label: 'Matches',
            onTap: matches == 0
                ? null
                : () => context.push(Routes.playerMatches(uid)),
          ),
          PsStat(
            value: '${lines.where((l) => l.matchesPlayed > 0).length}',
            label: 'Sports',
            onTap: lines.isEmpty ? null : onSportsTap,
          ),
          PsStat(
            value: '$clubs',
            label: 'Clubs',
            onTap: clubs == 0 ? null : () => context.push(Routes.playerClubs(uid)),
          ),
          PsStat(
            value: '${(memories.valueOrNull ?? const []).length}',
            label: 'Memories',
            onTap: (memories.valueOrNull ?? const []).isEmpty
                ? null
                : onMemoriesTap,
          ),
        ],
      ),
    );
  }
}

/// A tab per sport played, and that sport's own totals underneath.
///
/// The tally is a `Map<String, num>` keyed exactly as each sport's engine
/// keys it — `runs`, `wickets`, `strikeRate` for cricket; `points`, `aces`
/// for volleyball. That is why this renders whatever keys are present rather
/// than a fixed Runs/Wickets/Average grid: the same widget has to be correct
/// for fifteen sports whose engines share no vocabulary, and hard-coding
/// cricket's would leave every other sport blank.
class _SportBreakdown extends StatefulWidget {
  const _SportBreakdown({required this.career, required this.uid});

  final AsyncValue<List<CareerLine>> career;
  final String uid;

  @override
  State<_SportBreakdown> createState() => _SportBreakdownState();
}

class _SportBreakdownState extends State<_SportBreakdown> {
  /// The sport id showing, or null to mean "whatever is most prominent".
  /// Held as an id rather than an index so it survives the list reordering
  /// underneath when a match finishes and changes what someone plays most.
  String? _selected;

  /// Six, then stop. The tally for a full cricket career runs to a dozen-odd
  /// counters, and a profile that opens with twelve tiles is a spreadsheet.
  /// The sport's own page shows every one of them.
  static const _maxTiles = 6;

  @override
  Widget build(BuildContext context) {
    final lines = (widget.career.valueOrNull ?? const <CareerLine>[])
        .where((l) => l.matchesPlayed > 0)
        .toList()
      ..sort((a, b) => b.prominence.compareTo(a.prominence));

    if (lines.isEmpty) return const SizedBox.shrink();

    final selected = lines.firstWhere(
      (l) => l.sportId == _selected,
      orElse: () => lines.first,
    );

    final tally = selected.stats?.tally ?? const <String, num>{};
    final counters = tally.entries.where((e) => e.value != 0).toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    final tiles = counters.take(_maxTiles).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: lines.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final line = lines[i];
              final isSelected = line.sportId == selected.sportId;
              return InkWell(
                onTap: () => setState(() => _selected = line.sportId),
                borderRadius: BorderRadius.circular(Ps.radiusSm),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: isSelected ? Ps.primary : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    SportCatalog.byId(line.sportId).name,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? Ps.primary : Ps.muted,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        if (tiles.isEmpty)
          PsCard(
            child: Text(
              'No totals recorded for '
              '${SportCatalog.byId(selected.sportId).name} yet.',
              style: const TextStyle(fontSize: 13, color: Ps.muted),
            ),
          )
        else ...[
          LayoutBuilder(
            builder: (context, constraints) {
              // Three across on a phone, more where there is room. Fixed at
              // three would leave a tablet with a third of a row of tiles and
              // two thirds of nothing.
              final columns = (constraints.maxWidth / 130).floor().clamp(2, 4);
              return GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.75,
                children: [
                  for (final tile in tiles)
                    _CounterTile(
                      label: tile.key,
                      value: tile.value,
                      // Same destination as "Season, tournament and
                      // challenge splits" below, landed on this exact
                      // counter — CricHeroes' pattern of a stat being its
                      // own drill-down rather than just a number on a card.
                      onTap: () => context.push(
                        Routes.playerStats(
                          widget.uid,
                          selected.sportId,
                          highlight: tile.key,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          // The way through to §18's scoped view. The tiles above are this
          // sport's lifetime totals; this is where "and how many of those
          // were in a tournament" gets answered.
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => context.push(
                Routes.playerStats(widget.uid, selected.sportId),
              ),
              icon: const Icon(Icons.query_stats, size: 18),
              label: const Text('Season, tournament and challenge splits'),
            ),
          ),
        ],
      ],
    );
  }
}

/// One counter from the tally — "Runs / 1,824". Tapping it opens that stat's
/// own scoped breakdown (season/tournament/challenge splits, and — once a
/// player has one — where it ranks), the same way a single number on
/// CricHeroes opens into its own page rather than staying a static tile.
class _CounterTile extends StatelessWidget {
  const _CounterTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final num value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PsCard(
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            psHumanizeCounter(label),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, color: Ps.muted),
          ),
          const SizedBox(height: 4),
          Text(
            _formatValue(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Ps.ink,
            ),
          ),
        ],
      ),
    );
  }

  /// Whole numbers stay whole; averages and rates keep two places. A strike
  /// rate rendered as "132" and an average as "45" would both be wrong in the
  /// direction that flatters, which is the direction people notice.
  static String _formatValue(num v) =>
      v is int || v == v.roundToDouble() ? psGrouped(v.round()) : v.toStringAsFixed(2);

}

class _SportsList extends StatelessWidget {
  const _SportsList({
    required this.career,
    required this.isMe,
    required this.uid,
  });

  final AsyncValue<List<CareerLine>> career;
  final bool isMe;
  final String uid;

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
      children: [
        for (final line in lines) _SportCard(line: line, uid: uid),
      ],
    );
  }
}

class _SportCard extends StatelessWidget {
  const _SportCard({required this.line, required this.uid});

  final CareerLine line;
  final String uid;

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
      clipBehavior: Clip.antiAlias,
      // Feature #14: a sport opens its own page — that sport's matches, their
      // scorecards, the leaderboard and the full tally. All four already
      // existed in the data; this card was where the journey stopped.
      child: InkWell(
        onTap: () => context.push(Routes.playerSport(uid, line.sportId)),
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
                  Icon(Icons.chevron_right, color: theme.hintColor),
                ],
              ),
              if (line.stats != null && line.stats!.tally.isNotEmpty) ...[
                const SizedBox(height: 12),
                _TallyStrip(tally: line.stats!.tally),
              ],
            ],
          ),
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
              '${psHumanizeCounter(e.key)} ${_format(e.value)}',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  static String _format(num v) =>
      v is int || v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(2);

}

/// Every rival this player has faced, best-known record first.
///
/// [HeadToHead.forPlayer] is a pure function of the player's own fixtures —
/// see its doc for why a career total cannot answer this — and this is the
/// first screen to actually render what it produces.
class _HeadToHead extends ConsumerWidget {
  const _HeadToHead({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsAsync = ref.watch(headToHeadProvider(uid));
    final records = recordsAsync.valueOrNull ?? const <HeadToHeadRecord>[];
    // Quietly absent rather than an empty-state card: a player with no
    // opponents yet already gets that message from `_SportsList` above, and
    // repeating it here would just be noise.
    if (records.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Head to head', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Record against everyone this player has faced.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        for (final r in records.take(10))
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              title: Text(r.opponentName),
              subtitle: r.lastMet == null
                  ? null
                  : Text('Last met ${_stamp(r.lastMet!)}'),
              trailing: Text(
                '${r.line} (${r.played})',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: r.isAhead
                      ? theme.colorScheme.primary
                      : r.isLevel
                          ? theme.hintColor
                          : theme.colorScheme.error,
                ),
              ),
              onTap: () => context.push(Routes.profile(r.opponentUid)),
            ),
          ),
      ],
    );
  }

  static String _stamp(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
}
