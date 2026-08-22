import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/sport_stat_row.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/ui_kit.dart';

/// How a sport is grouped in the directory's filter row.
///
/// Not a field on `SportSpec`. The catalogue describes what the *scoring
/// engine* needs to know — archetype, entrant type, plugin — and a browse
/// category is a presentation concern that would have no meaning to any of
/// the engines reading that class. Keeping it here means adding a filter
/// never touches the scoring domain.
enum _SportGroup {
  team('Team Sports'),
  racket('Racket Sports'),
  indoor('Indoor Sports');

  const _SportGroup(this.label);
  final String label;
}

/// Which group each sport falls in.
///
/// A sport can genuinely sit in more than one — table tennis is both a racket
/// sport and an indoor one — so this is a set per sport rather than a single
/// category. Filtering on "Indoor" and not finding table tennis is the kind
/// of small wrongness that makes a directory feel unreliable.
const Map<String, Set<_SportGroup>> _groups = {
  'cricket': {_SportGroup.team},
  'football': {_SportGroup.team},
  'volleyball': {_SportGroup.team},
  'basketball': {_SportGroup.team},
  'kabaddi': {_SportGroup.team},
  'hockey': {_SportGroup.team},
  'kho_kho': {_SportGroup.team},
  'throwball': {_SportGroup.team},
  'badminton': {_SportGroup.racket, _SportGroup.indoor},
  'table_tennis': {_SportGroup.racket, _SportGroup.indoor},
  'tennis': {_SportGroup.racket},
  'chess': {_SportGroup.indoor},
  'carrom': {_SportGroup.indoor},
};

/// Every sport the platform runs, and how busy each one is.
///
/// The screen a club opens when deciding what to enter next, and the one a
/// visitor opens to find out whether anything is happening in their sport at
/// all. Counts come from the nightly rollup in `functions/sports.js` rather
/// than from a live query — see that file for why a client cannot count this
/// correctly for itself.
class SportsDirectoryScreen extends ConsumerStatefulWidget {
  const SportsDirectoryScreen({super.key});

  @override
  ConsumerState<SportsDirectoryScreen> createState() =>
      _SportsDirectoryScreenState();
}

class _SportsDirectoryScreenState
    extends ConsumerState<SportsDirectoryScreen> {
  /// Index into the chip row: 0 is "All", the rest map onto [_SportGroup].
  int _filter = 0;

  /// Null until the search icon is tapped. Distinct from an empty string,
  /// which means the field is open and the person has cleared it — the first
  /// shows the title, the second shows an empty field.
  String? _query;

  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<SportSpec> get _visible {
    final query = _query?.trim().toLowerCase() ?? '';
    return SportCatalog.all.where((spec) {
      if (_filter != 0) {
        final group = _SportGroup.values[_filter - 1];
        if (!(_groups[spec.id]?.contains(group) ?? false)) return false;
      }
      if (query.isEmpty) return true;
      return spec.name.toLowerCase().contains(query);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(sportStatsProvider);
    // A directory that renders every sport at zero while the rollup loads is
    // better than a spinner: the sport names and the ordering are the part
    // people navigate by, and those are known without the network. The counts
    // fill in underneath them a moment later.
    final stats = statsAsync.valueOrNull ?? const <String, SportStatRow>{};
    final sports = _visible;

    return Scaffold(
      backgroundColor: Ps.canvas,
      appBar: AppBar(
        backgroundColor: Ps.surface,
        foregroundColor: Ps.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        // Overrides the app-wide AppBarTheme, which paints a dark green bar
        // with white text — correct everywhere else, wrong for a screen whose
        // whole layout assumes a white chrome.
        iconTheme: const IconThemeData(color: Ps.ink),
        title: _query == null
            ? const Text(
                'Sports',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Ps.ink,
                ),
              )
            : TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (value) => setState(() => _query = value),
                style: const TextStyle(fontSize: 16, color: Ps.ink),
                decoration: const InputDecoration(
                  hintText: 'Search sports',
                  hintStyle: TextStyle(color: Ps.faint),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
        actions: [
          IconButton(
            icon: Icon(_query == null ? Icons.search : Icons.close),
            tooltip: _query == null ? 'Search sports' : 'Close search',
            onPressed: () => setState(() {
              if (_query == null) {
                _query = '';
              } else {
                _query = null;
                _searchController.clear();
              }
            }),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PsFilterChips(
              labels: [
                'All',
                for (final group in _SportGroup.values) group.label,
              ],
              selected: _filter,
              onSelected: (i) => setState(() => _filter = i),
            ),
          ),
        ),
      ),
      body: sports.isEmpty
          ? const _NoMatches()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              itemCount: sports.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final spec = sports[i];
                return _SportRow(
                  spec: spec,
                  stat: stats[spec.id] ?? SportStatRow.empty(spec.id),
                );
              },
            ),
    );
  }
}

class _SportRow extends StatelessWidget {
  const _SportRow({required this.spec, required this.stat});

  final SportSpec spec;
  final SportStatRow stat;

  @override
  Widget build(BuildContext context) {
    return PsCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      // The per-sport landing page the tap target was kept for. Until it
      // existed this row was deliberately inert — a row that navigates
      // nowhere being better than one that pushes a plausible but wrong
      // destination. See [SportHubScreen].
      onTap: () => context.push(Routes.sport(spec.id)),
      child: Row(
        children: [
          SportBadge(sportId: spec.id),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spec.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Ps.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${psGrouped(stat.tournamentCount)} '
                  '${stat.tournamentCount == 1 ? 'Tournament' : 'Tournaments'}'
                  '  •  ${psGrouped(stat.headlineEntrantCount)} '
                  '${stat.headlineEntrantLabel}',
                  style: const TextStyle(fontSize: 12.5, color: Ps.muted),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Ps.faint, size: 22),
        ],
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 40, color: Ps.faint),
            SizedBox(height: 12),
            Text(
              'No sports match that',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Ps.ink,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Try a different name, or clear the filter.',
              style: TextStyle(fontSize: 13, color: Ps.muted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
