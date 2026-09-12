/// Find someone to sponsor.
///
/// ## Why this is two lists and not one
///
/// This screen used to be a single feed of published `sponsorshipListings`,
/// which answered only half of the question its own title asks. A sponsor
/// arriving with money and no particular athlete in mind gets shown whoever
/// happened to write a listing — and the players most worth backing are
/// systematically the ones who have not written one, because publishing a
/// listing is the sort of thing a fourteen-year-old district champion does
/// *after* somebody tells them it is allowed. A board of self-nominations is
/// therefore not a shortlist of the best; it is a shortlist of the confident.
///
/// So there are two tabs, and they are different questions:
///
///  * **Asking** — open listings, athletes and teams, filtered. These people
///    have said what they need; the sponsor's job is to pick.
///  * **Top ranked** — the actual ladders, per sport, from
///    `rankingProvider` and `clubStandingsProvider`. Somebody with a listing
///    gets a "Back them" button straight to it; somebody without gets an
///    invitation, because "this player is winning and has never asked anyone
///    for anything" is the single most useful row this feature can show.
///
/// See `sponsorTopAthletesProvider` for the join, which is one listener for
/// the whole screen rather than one query per ranked player.
///
/// ## What the privacy posture still is
///
/// Unchanged, and it constrains the new tab: a ranked player who has no
/// listing has consented to nothing here, so their row shows exactly what the
/// public rankings already show — name, sport, points, results counted — and
/// offers no contact route whatsoever. The row is not actionable against the
/// player at all — it says, to the sponsor, that a listing would have to exist
/// first. See `SponsorshipListing`'s class doc.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/club_standing.dart';
import '../../core/models/enums.dart';
import '../../core/models/ranking_entry.dart';
import '../../core/models/sponsorship.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/identity.dart';
import '../../shared/ui_kit.dart';

class SponsorBrowseScreen extends ConsumerStatefulWidget {
  const SponsorBrowseScreen({super.key});

  @override
  ConsumerState<SponsorBrowseScreen> createState() =>
      _SponsorBrowseScreenState();
}

class _SponsorBrowseScreenState extends ConsumerState<SponsorBrowseScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Find someone to sponsor',
      subtitle: 'Athletes and teams worth backing',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  label: Text('Asking'),
                  icon: Icon(Icons.campaign_outlined),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text('Top ranked'),
                  icon: Icon(Icons.emoji_events_outlined),
                ),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
          ),
          Expanded(
            child: _tab == 0 ? const _AskingTab() : const _TopRankedTab(),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 1 — open listings
// ---------------------------------------------------------------------------

class _AskingTab extends ConsumerStatefulWidget {
  const _AskingTab();

  @override
  ConsumerState<_AskingTab> createState() => _AskingTabState();
}

class _AskingTabState extends ConsumerState<_AskingTab> {
  final _districtController = TextEditingController();

  /// Applied on the client, not in the query.
  ///
  /// `SponsorRepository.watchListings` already carries three server-side
  /// filters and every one of them is an inequality-free equality clause on a
  /// separate field; adding a fourth on `asks[].category` would need an
  /// `arrayContains` that cannot coexist with the district filter's own
  /// clause in one composite index. The board is capped at 100 rows, so
  /// filtering the delivered page costs nothing and the sponsor gets the
  /// filter that actually matters to them — "who needs shoes" rather than
  /// "who is in my district".
  SponsorshipSupportCategory? _category;

  @override
  void dispose() {
    _districtController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(sponsorBrowseFilterProvider);
    final listings = ref.watch(sponsorshipListingsProvider);

    return AsyncView(
      value: listings,
      onRetry: () => ref.invalidate(sponsorshipListingsProvider),
      skeleton: const PsListSkeleton(),
      builder: (all) {
        final list = _category == null
            ? all
            : all
                .where((l) => l.asks.any((a) => a.category == _category))
                .toList(growable: false);

        return ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            ContentBounds(
              maxWidth: 700,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    child: SegmentedButton<SponsorshipTargetType?>(
                      segments: const [
                        ButtonSegment(value: null, label: Text('All')),
                        ButtonSegment(
                          value: SponsorshipTargetType.athlete,
                          label: Text('Athletes'),
                          icon: Icon(Icons.person_outline),
                        ),
                        ButtonSegment(
                          value: SponsorshipTargetType.team,
                          label: Text('Teams'),
                          icon: Icon(Icons.groups_outlined),
                        ),
                      ],
                      selected: {filter.targetType},
                      onSelectionChanged: (s) => ref
                          .read(sponsorBrowseFilterProvider.notifier)
                          .update((f) => f.copyWith(targetType: () => s.first)),
                    ),
                  ),

                  // A dropdown rather than the free-text field this used to
                  // be. `sport` is matched with `isEqualTo` against ids like
                  // `table_tennis`, so anybody typing "Table Tennis" got an
                  // empty board and no explanation — a filter that silently
                  // requires you to know the wire format is a filter that
                  // reads as a broken screen.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String?>(
                            value: filter.sport,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Sport',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: null,
                                child: Text('All sports'),
                              ),
                              for (final s in SportCatalog.all)
                                DropdownMenuItem(
                                  value: s.id,
                                  child: Text(s.name),
                                ),
                            ],
                            onChanged: (v) => ref
                                .read(sponsorBrowseFilterProvider.notifier)
                                .update((f) => f.copyWith(sport: () => v)),
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
                            onSubmitted: (v) => ref
                                .read(sponsorBrowseFilterProvider.notifier)
                                .update((f) => f.copyWith(
                                      district: () =>
                                          v.trim().isEmpty ? null : v.trim(),
                                    )),
                          ),
                        ),
                      ],
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 2),
                    child: SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: const Text('Any support'),
                              selected: _category == null,
                              onSelected: (_) =>
                                  setState(() => _category = null),
                            ),
                          ),
                          for (final c in SponsorshipSupportCategory.values)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text('${c.emoji} ${c.label}'),
                                selected: _category == c,
                                onSelected: (_) =>
                                    setState(() => _category = c),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),
                  if (list.isEmpty)
                    const EmptyState(
                      icon: Icons.travel_explore_outlined,
                      title: 'No open listings match yet',
                      message:
                          'Try clearing a filter — or look at Top ranked, '
                          'where the players winning in each sport are '
                          'listed whether or not they have asked for help.',
                    )
                  else
                    for (final listing in list) _ListingCard(listing: listing),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ListingCard extends StatelessWidget {
  const _ListingCard({required this.listing});

  final SponsorshipListing listing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final who = listing.isAthlete
        ? (listing.subjectDisplayName ?? 'An athlete')
        : (listing.orgName ?? 'A team');

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: InkWell(
        onTap: () => context.push(Routes.sponsorListing(listing.id)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    listing.isAthlete
                        ? Icons.person_outline
                        : Icons.groups_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      listing.headline,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [
                  who,
                  SportCatalog.byId(listing.sport).name,
                  if (listing.geo.district != null) listing.geo.district!,
                ].join(' · '),
                style:
                    theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              ),
              if (listing.story.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  listing.story,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final ask in listing.asks.take(4))
                    Chip(
                      label: Text(ask.category.label),
                      avatar: Text(ask.category.emoji),
                      visualDensity: VisualDensity.compact,
                    ),
                  if (listing.sponsorsCount > 0)
                    Chip(
                      label: Text(
                        '${listing.sponsorsCount} sponsor'
                        '${listing.sponsorsCount == 1 ? '' : 's'}',
                      ),
                      avatar: const Icon(Icons.favorite, size: 16),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 2 — the ladders
// ---------------------------------------------------------------------------

class _TopRankedTab extends ConsumerStatefulWidget {
  const _TopRankedTab();

  @override
  ConsumerState<_TopRankedTab> createState() => _TopRankedTabState();
}

class _TopRankedTabState extends ConsumerState<_TopRankedTab> {
  String _sportId = SportCatalog.all.first.id;
  bool _teams = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const sports = SportCatalog.all;

    return Column(
      children: [
        PsUnderlineTabs(
          labels: [for (final s in sports) s.name],
          selected: sports.indexWhere((s) => s.id == _sportId),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          onSelected: (i) => setState(() => _sportId = sports[i].id),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('Players'),
                selected: !_teams,
                onSelected: (_) => setState(() => _teams = false),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('Clubs'),
                selected: _teams,
                onSelected: (_) => setState(() => _teams = true),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  'Ranked on results',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.hintColor),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _teams
              ? _ClubLadder(sportId: _sportId)
              : _AthleteLadder(sportId: _sportId),
        ),
      ],
    );
  }
}

class _AthleteLadder extends ConsumerWidget {
  const _AthleteLadder({required this.sportId});

  final String sportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targets = ref.watch(sponsorTopAthletesProvider(sportId));

    return AsyncView(
      value: targets,
      onRetry: () => ref.invalidate(rankingProvider(sportId)),
      skeleton: const PsListSkeleton(),
      builder: (rows) => rows.isEmpty
          ? EmptyState(
              icon: Icons.emoji_events_outlined,
              title: 'No ranked players in '
                  '${SportCatalog.byId(sportId).name} yet',
              message: 'Rankings fill up as tournaments finish. Try another '
                  'sport, or look at who is already asking.',
            )
          : ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 32),
              itemCount: rows.length,
              itemBuilder: (_, i) => ContentBounds(
                maxWidth: 700,
                child: _AthleteRow(target: rows[i]),
              ),
            ),
    );
  }
}

class _AthleteRow extends StatelessWidget {
  const _AthleteRow({required this.target});

  final SponsorTarget target;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final RankingRow row = target.row;
    final listing = target.listing;
    final best = row.best;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: InkWell(
        onTap: () => context.push(Routes.profile(row.uid)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _RankBadge(rank: row.rank),
                  const SizedBox(width: 12),
                  PsAvatar(
                    name: row.displayName,
                    seed: row.uid,
                    size: 40,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.displayName,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${row.points} pts · '
                          '${row.eventsCounted} '
                          'result${row.eventsCounted == 1 ? '' : 's'}'
                          '${best == null ? '' : ' · best: ${best.tournamentName}'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.hintColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (listing != null)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        listing.headline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () =>
                          context.push(Routes.sponsorListing(listing.id)),
                      child: const Text('Back them'),
                    ),
                  ],
                )
              else
                // The row this tab exists for. No contact route and no
                // nomination — a ranked player who has published nothing has
                // consented to nothing here, so all this can honestly do is
                // tell the sponsor what would have to happen first.
                Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 16, color: theme.hintColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Not asking for backing yet — they would need to '
                        'publish a listing.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.hintColor),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClubLadder extends ConsumerWidget {
  const _ClubLadder({required this.sportId});

  final String sportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final standings = ref.watch(clubStandingsProvider(sportId));
    final index = ref.watch(openListingsBySubjectProvider).valueOrNull ??
        const <String, SponsorshipListing>{};

    return AsyncView(
      value: standings,
      onRetry: () => ref.invalidate(clubStandingsProvider(sportId)),
      skeleton: const PsListSkeleton(),
      builder: (table) {
        // The all-time window, matching what the club page's own ladder
        // shows. A sponsor picking a club to back is making a multi-season
        // decision, not reading a form guide.
        final rows = table.ranked('all');
        if (rows.isEmpty) {
          return EmptyState(
            icon: Icons.groups_outlined,
            title: 'No club results in '
                '${SportCatalog.byId(sportId).name} yet',
            message: 'The club ladder is built from finished inter-club '
                'matches and tournaments.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 32),
          itemCount: rows.length,
          itemBuilder: (_, i) => ContentBounds(
            maxWidth: 700,
            child: _ClubRow(
              rank: i + 1,
              club: rows[i],
              listing: index[rows[i].clubId],
            ),
          ),
        );
      },
    );
  }
}

class _ClubRow extends StatelessWidget {
  const _ClubRow({
    required this.rank,
    required this.club,
    required this.listing,
  });

  final int rank;
  final ClubStanding club;
  final SponsorshipListing? listing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tally = club.tallyFor('all');

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: InkWell(
        onTap: () => context.push(Routes.org(club.clubId)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              _RankBadge(rank: rank),
              const SizedBox(width: 12),
              PsCrest(
                name: club.name,
                logoUrl: club.logoUrl,
                seed: club.clubId,
                size: 40,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      club.name,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${tally.points} pts · ${tally.won}W-${tally.lost}L '
                      'from ${tally.played}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.hintColor),
                    ),
                  ],
                ),
              ),
              if (listing != null)
                FilledButton(
                  onPressed: () =>
                      context.push(Routes.sponsorListing(listing!.id)),
                  child: const Text('Back them'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    // The top three carry the brand green; everything below is neutral. A
    // ladder where row 47 is as loud as row 1 has no ladder in it.
    final top = rank <= 3;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: top ? Ps.primary : Ps.canvas,
        borderRadius: BorderRadius.circular(Ps.radiusSm),
        border: Border.all(color: top ? Ps.primary : Ps.border),
      ),
      child: Text(
        '$rank',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 13,
          color: top ? Colors.white : Ps.muted,
        ),
      ),
    );
  }
}
