import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/coach.dart';
import '../../core/models/competition.dart';
import '../../core/models/enums.dart';
import '../../core/models/fixture.dart';
import '../../core/models/ground.dart';
import '../../core/models/organization.dart';
import '../../core/models/sponsorship.dart';
import '../../core/models/team.dart';
import '../../core/router/app_router.dart';
import '../../data/scout_repository.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/live_dot.dart';
import '../../shared/ui_kit.dart';
import '../coaches/coach_card.dart';
import '../scoring/widgets/live_score_card.dart';
import 'sport_hub_providers.dart';

/// Everything happening in one sport.
///
/// ## What this replaces
///
/// The home screen used to carry nine sport tiles, and every one of them —
/// cricket, football, chess — pushed the same route: `Routes.sports`, the
/// directory. The sport id was built, passed to the tile, and thrown away at
/// the tap. Nine buttons, one destination, and nothing anywhere in the product
/// that answered "what is happening in cricket".
///
/// ## The model
///
/// A sport is not a category page. It is a scope: pick cricket and every list
/// on the screen means cricket. Live matches, the clubs putting it on, the
/// grounds that have a pitch for it, the events open for entry.
///
/// The rule that makes it useful is exclusion. Showing every club on the
/// platform with a cricket filter that matches all of them is a directory;
/// showing the clubs that are *actually running cricket* is a discovery
/// engine. See `sport_hub_providers.dart` for how each list is narrowed, and
/// why none of it is a stored `sportIds` field on a club.
class SportHubScreen extends ConsumerWidget {
  const SportHubScreen({super.key, required this.sportId});

  final String sportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sport = SportCatalog.byId(sportId);
    final visual = SportVisual.of(sportId);

    final live = ref.watch(sportLiveProvider(sportId)).valueOrNull ?? const [];
    final events =
        ref.watch(sportEventsProvider(sportId)).valueOrNull ?? const [];
    final clubs =
        ref.watch(sportClubsProvider(sportId)).valueOrNull ?? const [];
    final grounds =
        ref.watch(sportGroundsProvider(sportId)).valueOrNull ?? const [];
    final tournaments =
        ref.watch(sportTournamentsProvider(sportId)).valueOrNull ?? const [];
    final teams = ref.watch(sportTeamsProvider(sportId)).valueOrNull ?? const [];
    final sponsorships =
        ref.watch(sportSponsorshipsProvider(sportId)).valueOrNull ?? const [];
    final players =
        ref.watch(sportPlayersProvider(sportId)).valueOrNull ?? const [];
    final coaches =
        ref.watch(sportCoachesProvider(sportId)).valueOrNull ?? const [];
    final results =
        ref.watch(sportResultsProvider(sportId)).valueOrNull ?? const [];
    final row = ref.watch(sportStatRowProvider(sportId)).valueOrNull;
    final headlineStats = sportHeadlineStats(sportId);

    return AppScaffold(
      title: sport.name,
      subtitle: 'Everything in one sport',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 48),
        children: [
          ContentBounds(
            maxWidth: 1000,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Hero(sport: sport, visual: visual, row: row),
                const SizedBox(height: 18),

                // Live first, always. It is the only thing on this screen
                // that stops being true if you read it ten minutes later.
                if (live.isNotEmpty) ...[
                  const _Heading('Live now', live: true),
                  for (final f in live.take(4))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: LiveScoreCard(
                        fixture: f,
                        onTap: () => context.push(
                          Routes.watch(f.orgId, f.compId, f.id),
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                ],

                // Split rather than one "events" list, because the two
                // answer different questions: a multi-stage tournament is
                // something you enter weeks ahead, a single fixture is
                // something you turn up to. `sportTournamentsProvider` holds
                // the first, so the second is what is left.
                _Section<Competition>(
                  title: 'Tournaments & leagues',
                  emptyIcon: Icons.emoji_events_outlined,
                  empty: 'No ${sport.name.toLowerCase()} tournament is taking '
                      'entries right now.',
                  items: tournaments,
                  seeAll: () => context.push(Routes.globalEvents),
                  itemBuilder: (c) => _Row(
                    leading: Icons.emoji_events_outlined,
                    title: c.name,
                    subtitle: [
                      c.format.label,
                      if (c.venue != null && c.venue!.isNotEmpty) c.venue!,
                    ].join('  ·  '),
                    onTap: () =>
                        context.push(Routes.competition(c.orgId, c.id)),
                  ),
                ),

                _Section<Competition>(
                  title: 'Matches open for entry',
                  emptyIcon: Icons.event_busy_outlined,
                  empty: 'No one-off ${sport.name.toLowerCase()} match is '
                      'looking for entrants right now.',
                  items: [
                    for (final c in events)
                      if (c.format == CompetitionFormat.singleMatch) c,
                  ],
                  seeAll: () => context.push(Routes.globalEvents),
                  itemBuilder: (c) => _Row(
                    leading: Icons.sports_score_outlined,
                    title: c.name,
                    subtitle: [
                      if (c.venue != null && c.venue!.isNotEmpty) c.venue!,
                    ].join('  ·  '),
                    onTap: () =>
                        context.push(Routes.competition(c.orgId, c.id)),
                  ),
                ),

                // The other half of "matches": what already happened.
                // Live answers what is on now and the two sections above
                // answer what you can still enter — neither of which tells a
                // newcomer whether this sport is actually being played here.
                // A column of finished scorelines does.
                _Section<Fixture>(
                  title: 'Recent results',
                  emptyIcon: Icons.scoreboard_outlined,
                  empty: 'No ${sport.name.toLowerCase()} match has finished '
                      'here yet.',
                  items: results,
                  seeAll: () => context.push(Routes.globalEvents),
                  itemBuilder: (f) => _Row(
                    leading: Icons.scoreboard_outlined,
                    title: '${f.entrantAName}  v  ${f.entrantBName}',
                    subtitle: f.summary,
                    onTap: () => context.push(
                      Routes.watch(f.orgId, f.compId, f.id),
                    ),
                  ),
                ),

                _Section<Organization>(
                  title: 'Clubs playing ${sport.name.toLowerCase()}',
                  emptyIcon: Icons.groups_outlined,
                  empty: 'No club is running ${sport.name.toLowerCase()} yet. '
                      'Start one and it appears here.',
                  items: clubs,
                  seeAll: () => context.push(Routes.orgs),
                  itemBuilder: (o) => _Row(
                    leading: Icons.shield_outlined,
                    title: o.name,
                    subtitle: [
                      o.orgType.label,
                      if (o.district != null && o.district!.isNotEmpty)
                        o.district!,
                    ].join('  ·  '),
                    onTap: () => context.push(Routes.org(o.id)),
                  ),
                ),

                _Section<Team>(
                  title: '${sport.name} teams',
                  emptyIcon: Icons.groups_2_outlined,
                  empty: 'No standing ${sport.name.toLowerCase()} squad yet.',
                  items: teams,
                  seeAll: () => context.push(Routes.myTeams),
                  itemBuilder: (t) => _Row(
                    leading: Icons.group_outlined,
                    title: t.name,
                    subtitle: '${t.memberUids.length} '
                        '${t.memberUids.length == 1 ? 'player' : 'players'}',
                    onTap: () => context.push(Routes.team(t.id)),
                  ),
                ),

                // The only list here that is about people rather than
                // organisations, and the one a player opening a sport for
                // the first time is actually looking for. Ordered by who
                // played most recently — "active in this sport", not
                // "registered for it once".
                _Section<ScoutSearchResult>(
                  title: '${sport.name} players',
                  emptyIcon: Icons.person_outline,
                  empty: 'No public ${sport.name.toLowerCase()} record yet. '
                      'Players appear here once a match they played is '
                      'scored.',
                  items: players,
                  seeAll: () => context.push(Routes.scoutSearchIn(sportId)),
                  itemBuilder: (r) => _Row(
                    leading: Icons.person_outline,
                    title: r.displayName,
                    subtitle: [
                      if (r.profile.geo.district != null)
                        r.profile.geo.district!,
                      '${r.profile.ratingPercentile.round()}th percentile',
                    ].join('  ·  '),
                    onTap: () => context.push(Routes.profile(r.profile.uid)),
                  ),
                ),

                // Right after the players, because the two answer the
                // same question from opposite ends: a player browsing this
                // sport is either looking for people to play with or for
                // somebody to learn it from.
                _Section<CoachProfile>(
                  title: '${sport.name} coaches',
                  emptyIcon: Icons.school_outlined,
                  empty: 'No ${sport.name.toLowerCase()} coach has listed '
                      'themselves yet. If you coach it, you can be the first.',
                  items: coaches,
                  seeAll: () => context.push(Routes.coachesIn(sportId)),
                  itemBuilder: (c) => CoachCard(coach: c, dense: true),
                ),

                _Section<Ground>(
                  title: 'Grounds for ${sport.name.toLowerCase()}',
                  emptyIcon: Icons.stadium_outlined,
                  empty: 'No grounds listed for this sport yet.',
                  items: grounds,
                  seeAll: () => context.push(Routes.grounds),
                  itemBuilder: (g) => _Row(
                    leading: Icons.place_outlined,
                    title: g.name,
                    subtitle: [
                      if (g.city.isNotEmpty) g.city,
                      g.rateLabel,
                    ].join('  ·  '),
                    onTap: () => context.push(Routes.ground(g.id)),
                  ),
                ),

                _Section<SponsorshipListing>(
                  title: 'Sponsorship in ${sport.name.toLowerCase()}',
                  emptyIcon: Icons.handshake_outlined,
                  empty: 'Nobody is asking for ${sport.name.toLowerCase()} '
                      'backing yet.',
                  items: sponsorships,
                  seeAll: () => context.push(Routes.sponsorBrowse),
                  itemBuilder: (l) => _Row(
                    leading: Icons.handshake_outlined,
                    title: l.subjectDisplayName ?? l.orgName ?? l.headline,
                    subtitle: l.headline,
                    onTap: () => context.push(Routes.sponsorListing(l.id)),
                  ),
                ),

                // One board per stat the sport actually keeps, named by that
                // stat. This used to be a single "Rankings" tile on the
                // sport's first headline stat plus a "Statistics" tile that
                // pushed `Routes.sports` — the directory this screen was
                // reached FROM, throwing the scope away at the tap, which is
                // the exact bug the hub exists to fix. A cricketer looking
                // for the wicket-taking list now sees it named.
                if (headlineStats.isNotEmpty) ...[
                  const _Heading('Rankings'),
                  _Tiles(children: [
                    for (final stat in headlineStats)
                      _Tile(
                        icon: Icons.leaderboard_outlined,
                        label: psHumanizeCounter(stat),
                        onTap: () =>
                            context.push(Routes.leaderboard(sportId, stat)),
                      ),
                  ]),
                ],

                // Renamed off "Players & records" once the players section
                // above became a real list — two things called players, one
                // of them a row of buttons, is a menu pretending to be data.
                const _Heading('Talent & rules'),
                _Tiles(children: [
                  // Every one of these carries the sport with it.
                  _Tile(
                    icon: Icons.trending_up,
                    label: 'Rising talent',
                    onTap: () => context.push(Routes.risingTalent),
                  ),
                  _Tile(
                    icon: Icons.person_search_outlined,
                    label: 'Find players',
                    onTap: () =>
                        context.push(Routes.scoutSearchIn(sportId)),
                  ),
                  _Tile(
                    icon: Icons.menu_book_outlined,
                    label: 'Rules',
                    onTap: () => context.push(Routes.rules),
                  ),
                  _Tile(
                    icon: Icons.school_outlined,
                    label: 'Coaches',
                    onTap: () => context.push(Routes.coachesIn(sportId)),
                  ),
                  // Both carry the sport, like everything else in this row.
                  // A cricketer arriving at the warm-up library should land
                  // on the RAMP routine and the fast bowler's spine prep,
                  // not on a chip they have to press first.
                  _Tile(
                    icon: Icons.directions_run_outlined,
                    label: 'Warm-ups',
                    onTap: () =>
                        context.push(Routes.sportsWarmupsFor(sportId)),
                  ),
                  _Tile(
                    icon: Icons.medical_services_outlined,
                    label: 'Physios & doctors',
                    onTap: () =>
                        context.push(Routes.sportsMedicsIn(sportId)),
                  ),
                ]),
                const SizedBox(height: 22),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The sport, its colour, and the three platform-wide numbers behind it.
class _Hero extends StatelessWidget {
  const _Hero({required this.sport, required this.visual, required this.row});

  final SportSpec sport;
  final SportVisual visual;
  final dynamic row;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: visual.color,
        borderRadius: BorderRadius.circular(Ps.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(visual.icon, color: Colors.white, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  sport.name,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
            ],
          ),
          if (row != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                _HeroStat(label: 'Tournaments', value: row.tournamentCount),
                _HeroStat(label: 'Teams', value: row.teamCount),
                _HeroStat(label: 'Players', value: row.playerCount),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 9.5,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.live = false});

  final String text;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 16, 2, 10),
      child: Row(
        children: [
          Text(
            text.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: Ps.faint,
            ),
          ),
          if (live) ...[const SizedBox(width: 8), const LiveDot()],
        ],
      ),
    );
  }
}

/// A titled list capped at four, with a way to the full one.
///
/// Four because this screen is an index, not a directory: its job is to prove
/// there is something here and hand you to the screen that lists it properly.
class _Section<T> extends StatelessWidget {
  const _Section({
    required this.title,
    required this.items,
    required this.itemBuilder,
    required this.empty,
    required this.emptyIcon,
    required this.seeAll,
  });

  final String title;
  final List<T> items;
  final Widget Function(T) itemBuilder;
  final String empty;
  final IconData emptyIcon;
  final VoidCallback seeAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 16, 2, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: Ps.faint,
                  ),
                ),
              ),
              if (items.length > 4)
                TextButton(
                  onPressed: seeAll,
                  child: Text('All ${items.length}'),
                ),
            ],
          ),
        ),
        if (items.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Ps.surface,
              borderRadius: BorderRadius.circular(Ps.radius),
              border: Border.all(color: Ps.border),
            ),
            child: Row(
              children: [
                Icon(emptyIcon, size: 20, color: Ps.faint),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    empty,
                    style: const TextStyle(fontSize: 13, color: Ps.muted),
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: Ps.surface,
              borderRadius: BorderRadius.circular(Ps.radius),
              border: Border.all(color: Ps.border),
            ),
            child: Column(
              children: [
                for (final item in items.take(4)) itemBuilder(item),
              ],
            ),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(leading, size: 20, color: Ps.muted),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Ps.muted),
            ),
      trailing: const Icon(Icons.chevron_right, size: 18, color: Ps.faint),
      onTap: onTap,
    );
  }
}

class _Tiles extends StatelessWidget {
  const _Tiles({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 8, runSpacing: 8, children: children);
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Ps.surface,
      borderRadius: BorderRadius.circular(Ps.radiusSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Ps.radiusSm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Ps.radiusSm),
            border: Border.all(color: Ps.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: Ps.primary),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Ps.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
