import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/coach.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui_kit.dart';
import 'coach_card.dart';

/// What somebody types into the coach directory.
///
/// A record rather than two `useState`s so the results provider has one key
/// to watch: a sport and some words are asked together, and re-running the
/// search twice because they arrived in two frames is a wasted read.
typedef CoachQuery = ({String? sportId, String keywords, bool acceptingOnly});

final coachQueryProvider = StateProvider<CoachQuery>(
  (ref) => (sportId: null, keywords: '', acceptingOnly: false),
);

final coachSearchProvider =
    FutureProvider.autoDispose<List<CoachProfile>>((ref) {
  final q = ref.watch(coachQueryProvider);
  // Neither a sport nor a word: nothing has been asked yet, and reading the
  // whole collection to fill a screen somebody has not addressed is the
  // unbounded query this design exists to avoid.
  if (q.sportId == null && q.keywords.trim().isEmpty) {
    return Future.value(const <CoachProfile>[]);
  }
  return ref.watch(coachRepositoryProvider).searchCoaches(
        sportId: q.sportId,
        keywords: q.keywords,
        acceptingOnly: q.acceptingOnly,
      );
});

/// Find a coach, and list yourself as one.
///
/// The third public directory in the product, after grounds and sponsorship,
/// and built to the same shape deliberately — a sport, some words, and a list
/// — because a parent looking for a cricket coach and a captain looking for a
/// pitch are doing the same thing and should not have to learn two screens.
class CoachesScreen extends ConsumerStatefulWidget {
  const CoachesScreen({super.key, this.initialSportId});

  /// Set when the sport hub sends somebody here, so the list is already
  /// scoped to the sport they were reading about rather than making them
  /// pick it a second time.
  final String? initialSportId;

  @override
  ConsumerState<CoachesScreen> createState() => _CoachesScreenState();
}

class _CoachesScreenState extends ConsumerState<CoachesScreen> {
  final _words = TextEditingController();

  @override
  void initState() {
    super.initState();
    final sportId = widget.initialSportId;
    if (sportId == null) return;
    // After the first frame: this writes to a provider, which cannot happen
    // during a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(coachQueryProvider.notifier).state =
          (sportId: sportId, keywords: '', acceptingOnly: false);
    });
  }

  @override
  void dispose() {
    _words.dispose();
    super.dispose();
  }

  void _update(CoachQuery q) =>
      ref.read(coachQueryProvider.notifier).state = q;

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(coachQueryProvider);
    final results = ref.watch(coachSearchProvider);
    final mine = ref.watch(myCoachProfileProvider).valueOrNull;
    final signedIn = ref.watch(currentUidProvider) != null;

    return AppScaffold(
      title: 'Coaches',
      subtitle: 'Find someone to learn from',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ContentBounds(
            maxWidth: 700,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: TextField(
                    controller: _words,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Name, area, or a certification',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (v) =>
                        _update((
                          sportId: query.sportId,
                          keywords: v,
                          acceptingOnly: query.acceptingOnly,
                        )),
                  ),
                ),

                const SizedBox(height: 10),
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
                            selected: query.sportId == sport.id,
                            onSelected: (on) => _update((
                              sportId: on ? sport.id : null,
                              keywords: _words.text,
                              acceptingOnly: query.acceptingOnly,
                            )),
                          ),
                        ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Only coaches taking students',
                          style: TextStyle(fontSize: 13, color: Ps.muted),
                        ),
                      ),
                      Switch(
                        value: query.acceptingOnly,
                        onChanged: (v) => _update((
                          sportId: query.sportId,
                          keywords: _words.text,
                          acceptingOnly: v,
                        )),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 6),
                results.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Search failed: $e'),
                  ),
                  data: (list) {
                    if (query.sportId == null && query.keywords.trim().isEmpty) {
                      return const EmptyState(
                        icon: Icons.sports_outlined,
                        title: 'Pick a sport to start',
                        message: 'Or search by name, area or certification.',
                      );
                    }
                    if (list.isEmpty) {
                      return const EmptyState(
                        icon: Icons.person_search_outlined,
                        title: 'No coach listed yet',
                        message:
                            'Nobody has listed themselves for this yet. If you '
                            'coach it, you can be the first.',
                      );
                    }
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Ps.surface,
                        borderRadius: BorderRadius.circular(Ps.radius),
                        border: Border.all(color: Ps.border),
                      ),
                      child: Column(
                        children: [
                          for (final c in list) CoachCard(coach: c),
                        ],
                      ),
                    );
                  },
                ),

                const SizedBox(height: 20),
                if (signedIn)
                  Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    child: ListTile(
                      leading: const Icon(
                        Icons.school_outlined,
                        color: Ps.primary,
                      ),
                      title: Text(
                        mine == null ? 'Do you coach?' : 'Your coach listing',
                      ),
                      subtitle: Text(
                        mine == null
                            ? 'List yourself and be found by players nearby'
                            : mine.isActive
                                ? 'Listed for '
                                    '${mine.sportIds.length} '
                                    '${mine.sportIds.length == 1 ? 'sport' : 'sports'}'
                                : 'Currently delisted',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(Routes.myCoachProfile),
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
