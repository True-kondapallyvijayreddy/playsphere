import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui_kit.dart';
import '../home/home_providers.dart';

/// Everything the product does, on one screen.
///
/// This was eighteen full-width cards, each an icon, a bold title and a
/// sentence of explanation — "Official jerseys and merchandise" under `Club
/// Store`, "Certified umpires, referees & judges" under `Official Registry`.
/// At 72pt a row that is roughly four phone screens of scrolling, so the
/// modules near the bottom were three flicks and a hunt away, and the
/// sentences that cost all that height are read once and never again.
///
/// A grid of icon tiles fits the same eighteen destinations in one screen with
/// no scrolling on a phone, which is the actual click reduction: not fewer
/// taps on the destination — it was always one — but no scroll-and-scan
/// before it. The labels carry the meaning the sentences used to; where a
/// label could not, it was renamed rather than annotated.
class MoreMenuScreen extends ConsumerWidget {
  const MoreMenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final primaryOrgId = ref.watch(primaryOrgIdProvider);
    final isAdmin = ref.watch(isPlatformAdminProvider).valueOrNull == true;

    return AppScaffold(
      title: 'More',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
            ContentBounds(
              maxWidth: 720,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ProfileRow(
                    name: user?.displayName ?? 'Sports person',
                    // The player code is the thing another club asks for by
                    // name, so it wins the one line available over an email
                    // address the person already knows.
                    detail: user?.playerCode ?? user?.email,
                    onTap: () => context.push(Routes.myProfile),
                  ),
                  if (primaryOrgId != null)
                    _Section(
                      title: 'Club',
                      tint: Ps.primary,
                      tiles: [
                        (Icons.shield_outlined, 'Club', Routes.org(primaryOrgId)),
                        (
                          Icons.emoji_events_outlined,
                          'Tournaments',
                          Routes.tournaments(primaryOrgId)
                        ),
                        (
                          Icons.sports_kabaddi_outlined,
                          'Challenges',
                          Routes.challenges(primaryOrgId)
                        ),
                        (
                          Icons.collections_outlined,
                          'Gallery',
                          Routes.gallery(primaryOrgId)
                        ),
                        (
                          Icons.people_alt_outlined,
                          'Members',
                          Routes.members(primaryOrgId)
                        ),
                        (
                          Icons.storefront_outlined,
                          'Store',
                          '/org/$primaryOrgId/store'
                        ),
                      ],
                    ),
                  const _Section(
                    title: 'Discover',
                    tint: Color(0xFF2563EB),
                    tiles: [
                      (Icons.groups_outlined, 'All clubs', Routes.orgs),
                      // Above search deliberately: it answers a question the
                      // visitor has not had to formulate.
                      (
                        Icons.trending_up_outlined,
                        'Rising talent',
                        Routes.risingTalent
                      ),
                      (
                        Icons.travel_explore_outlined,
                        'Talent search',
                        Routes.scoutSearch
                      ),
                      (
                        Icons.person_search_outlined,
                        'Looking for',
                        Routes.lookingFor
                      ),
                      (
                        Icons.verified_user_outlined,
                        'Officials',
                        Routes.umpireRegistry
                      ),
                      (Icons.menu_book_outlined, 'Rulebook', Routes.rules),
                    ],
                  ),
                  _Section(
                    title: 'Community',
                    tint: const Color(0xFFEA580C),
                    tiles: [
                      (Icons.volunteer_activism_outlined, 'Give', Routes.give),
                      (Icons.handshake_outlined, 'Sponsor', Routes.sponsor),
                      (Icons.campaign_outlined, 'Advertise', Routes.adConsole),
                      if (isAdmin)
                        // Platform staff only — hidden rather than
                        // shown-and-denied. A tile that leads to "Restricted"
                        // for 99.9% of accounts is worse than no tile.
                        (
                          Icons.query_stats_outlined,
                          'Government',
                          Routes.govDashboard
                        ),
                    ],
                  ),
                  const _Section(
                    title: 'Yours',
                    tint: Color(0xFF7C3AED),
                    tiles: [
                      (
                        Icons.shopping_bag_outlined,
                        'Orders',
                        Routes.myClubOrders
                      ),
                      (
                        Icons.fastfood_outlined,
                        'Food orders',
                        Routes.myFoodOrders
                      ),
                    ],
                  ),
                ],
              ),
          ),
        ],
      ),
    );
  }
}

/// The account, as one row rather than the card-with-avatar-and-two-lines it
/// was. Tapping it opens the profile, which is the only thing it ever did.
class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.name,
    required this.detail,
    required this.onTap,
  });

  final String name;
  final String? detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PsCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: onTap,
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: Ps.primary,
            child: Text(
              // `characters` is not needed for one glyph of an initial, but
              // `substring` is: a name that begins with an emoji or a
              // combining Devanagari cluster would throw on a raw index.
              name.isEmpty ? 'P' : name.characters.first.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Ps.ink,
                  ),
                ),
                if (detail != null && detail!.isNotEmpty)
                  Text(
                    detail!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Ps.muted),
                  ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 18, color: Ps.faint),
        ],
      ),
    );
  }
}

/// A titled block of tiles.
///
/// The tint is the grouping device. With no sentences under the labels the
/// eye needs something other than whitespace to tell one block from the next,
/// and colouring the glyphs does it without adding a rule or a box per
/// section.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.tint,
    required this.tiles,
  });

  final String title;
  final Color tint;

  /// `(icon, label, route)`. A record rather than a widget list so the caller
  /// reads as a menu — one line per destination — instead of forty lines of
  /// constructor.
  final List<(IconData, String, String)> tiles;

  @override
  Widget build(BuildContext context) {
    if (tiles.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: Ps.faint,
            ),
          ),
        ),
        PsCard(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: AdaptiveGrid(
            // 88 puts four across a phone and stops the tiles ballooning on a
            // laptop, where ContentBounds has already capped the page at 720.
            minTileWidth: 88,
            spacing: 0,
            tileHeight: 86,
            children: [
              for (final (icon, label, route) in tiles)
                PsNavTile(
                  icon: icon,
                  label: label,
                  tint: tint,
                  onTap: () => context.push(route),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
