import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../data/scout_repository.dart';
import '../../domain/gov/age_group.dart';
import '../../domain/scout/player_verification_tier.dart';
import '../../domain/scout/talent_profile.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/glicko.dart';
import '../../shared/identity.dart';

const _sports = [
  ('cricket', 'Cricket'),
  ('football', 'Football'),
  ('kabaddi', 'Kabaddi'),
  ('basketball', 'Basketball'),
  ('badminton', 'Badminton'),
  ('hockey', 'Hockey'),
  ('volleyball', 'Volleyball'),
  ('tennis', 'Tennis'),
  ('table_tennis', 'Table Tennis'),
  ('athletics', 'Athletics'),
];

/// Talent discovery — §6 Module C's search, wired to real players for the
/// first time. See `ScoutRepository`'s class doc for exactly where the
/// privacy boundary lives (it is not this screen, and not the filters below
/// it — it is `firestore.rules` on `/users/{userId}`, already enforced
/// before a result ever reaches this list).
class ScoutSearchScreen extends ConsumerStatefulWidget {
  const ScoutSearchScreen({super.key, this.initialSportId});

  /// Pre-picked sport, when the search was opened from somewhere that already
  /// knew one — a sport hub's "Find players". Null when opened cold, which is
  /// the case the chip row above the filters exists for.
  final String? initialSportId;

  @override
  ConsumerState<ScoutSearchScreen> createState() => _ScoutSearchScreenState();
}

class _ScoutSearchScreenState extends ConsumerState<ScoutSearchScreen> {
  final _districtController = TextEditingController();
  double _minPercentile = 0;
  AgeGroup? _ageGroup;
  bool _recentFormOnly = false;
  bool _verifiedOnly = false;

  @override
  void initState() {
    super.initState();
    // After the first frame: `_runSearch` writes a provider, and a state
    // write during a widget's build phase is a framework error. Skipped when
    // the sport is not one this screen offers, rather than searching for a
    // chip the person cannot see selected.
    final sportId = widget.initialSportId;
    if (sportId == null || !_sports.any((s) => s.$1 == sportId)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _runSearch(sportId);
    });
  }

  @override
  void dispose() {
    _districtController.dispose();
    super.dispose();
  }

  void _runSearch(String sportId) {
    ref.read(scoutSearchQueryProvider.notifier).state = ScoutSearchQuery(
      sportId: sportId,
      filters: TalentSearchFilters(
        sportId: sportId,
        ageGroup: _ageGroup,
        district: _districtController.text.trim().isEmpty
            ? null
            : _districtController.text.trim(),
        minRatingPercentile: _minPercentile > 0 ? _minPercentile : null,
        minVerificationTier:
            _verifiedOnly ? PlayerVerificationTier.scorerVerified : null,
        activeWithin: _recentFormOnly ? const Duration(days: 90) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = ref.watch(scoutSearchQueryProvider);
    final results = ref.watch(scoutSearchResultsProvider);

    return AppScaffold(
      title: 'Talent discovery',
      subtitle: 'Find players by sport, age, district and form',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ContentBounds(
            maxWidth: 800,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (id, label) in _sports)
                        ChoiceChip(
                          label: Text(label),
                          selected: query.sportId == id,
                          onSelected: (_) => _runSearch(id),
                        ),
                    ],
                  ),
                ),
                if (query.sportId != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<AgeGroup?>(
                            value: _ageGroup,
                            decoration: const InputDecoration(
                              labelText: 'Age group',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('Any')),
                              for (final g in AgeGroup.values)
                                DropdownMenuItem(value: g, child: Text(g.label)),
                            ],
                            onChanged: (v) {
                              setState(() => _ageGroup = v);
                              _runSearch(query.sportId!);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _districtController,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'District',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (_) => _runSearch(query.sportId!),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Row(
                      children: [
                        Text('Min. rating percentile', style: theme.textTheme.bodySmall),
                        Expanded(
                          child: Slider(
                            value: _minPercentile,
                            min: 0,
                            max: 99,
                            divisions: 33,
                            label: _minPercentile.round().toString(),
                            onChanged: (v) => setState(() => _minPercentile = v),
                            onChangeEnd: (_) => _runSearch(query.sportId!),
                          ),
                        ),
                        SizedBox(
                          width: 32,
                          child: Text('${_minPercentile.round()}'),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Wrap(
                      children: [
                        FilterChip(
                          label: const Text('Recent form (90d)'),
                          selected: _recentFormOnly,
                          onSelected: (v) {
                            setState(() => _recentFormOnly = v);
                            _runSearch(query.sportId!);
                          },
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: const Text('Verified only'),
                          selected: _verifiedOnly,
                          onSelected: (v) {
                            setState(() => _verifiedOnly = v);
                            _runSearch(query.sportId!);
                          },
                        ),
                      ],
                    ),
                  ),
                  if (_verifiedOnly)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                      child: Text(
                        'No player has been scorer- or association-verified '
                        'yet — this filter will return nothing until that '
                        'exists.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.hintColor),
                      ),
                    ),
                  const SizedBox(height: 8),
                  results.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, _) => Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Search failed: $e'),
                    ),
                    data: (list) => list.isEmpty
                        ? const EmptyState(
                            icon: Icons.travel_explore_outlined,
                            title: 'No players match yet',
                            message:
                                'Try loosening a filter, or check back once '
                                'more matches have been played.',
                          )
                        : Column(
                            children: [
                              for (final result in list)
                                _ResultCard(result: result),
                            ],
                          ),
                  ),
                ] else
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: EmptyState(
                      icon: Icons.sports_outlined,
                      title: 'Pick a sport to start',
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

class _ResultCard extends ConsumerWidget {
  const _ResultCard({required this.result});

  final ScoutSearchResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = result.profile;
    // The scout board's own percentile below says where this player stands
    // inside ONE sport's population. This says how strong they are as a
    // competitor overall, which is the thing a scout reading a shortlist of
    // twenty names is actually sorting on, and the two are complementary
    // rather than redundant — see `OverallGlicko` on why a composite is not
    // a percentile.
    final badge = ref.watch(glickoBadgeProvider(profile.uid)).valueOrNull;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: ListTile(
        leading: PsAvatar(
          name: result.displayName,
          photoUrl: result.photoUrl,
          seed: result.profile.uid,
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(result.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            if (GlickoChip.forBadge(badge) case final chip?) ...[
              const SizedBox(width: 8),
              chip,
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                if (profile.geo.district != null) profile.geo.district!,
                '${profile.ratingPercentile.round()}th percentile',
                if (profile.lastMatchAt != null) 'Active',
              ].join(' · '),
            ),
            // What the person actually plays, and how well. A shortlist row
            // that says only "82nd percentile" leaves the reader to open the
            // profile to find out percentile *of what* — and a scout looking
            // for a left-arm spinner is filtering on the sports before
            // anything else.
            if (badge != null && badge.sports.isNotEmpty) ...[
              const SizedBox(height: 4),
              SportGlickoStrip(
                sports: badge.sports,
                hiddenCount: badge.hiddenSportCount,
              ),
            ],
          ],
        ),
        isThreeLine: badge != null && badge.sports.isNotEmpty,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(Routes.profile(profile.uid)),
        tileColor: theme.colorScheme.surface,
      ),
    );
  }
}
