import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../network/club_network_providers.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/identity.dart';
import '../../shared/ui_kit.dart';

/// Everything the product does, on one screen — and now the ONLY screen that
/// carries a menu.
///
/// ## Why this grew
///
/// PlaySphere used to answer "where is X?" with four different menus: the
/// bottom bar, an Explore list on the dashboard, this screen, and a
/// three-lines drawer attached to every single route. Eighteen destinations
/// appeared on two or more of them, and — worse — under a different name on
/// each: `/orgs` was "My clubs" on the bar, "Clubs" on the dashboard and "All
/// clubs" here; `/community/officials` was "Officials" here and "Umpire &
/// scorer registry" in the drawer. A person who had found a screen once could
/// not reliably find it again, because the door they remembered was labelled
/// something else the second time.
///
/// The drawer is gone and the dashboard's Explore list is gone. What they
/// held is now in exactly one place each, under one name, split three ways:
///
/// * **The bottom bar** — the handful of screens reached constantly.
/// * **A club's own page** — that club's sections, scoped to the club in
///   front of you rather than to whichever one you joined most recently.
///   See `ClubSectionsGrid`.
/// * **This screen** — everything else, once.
///
/// The third rule is what keeps this from becoming a fourth menu. The club
/// section that used to sit at the top of this screen — Gallery, Members,
/// Rankings, Venues, Files, Store — is gone from here, because the club page
/// carries all six and pointed at the right club while this screen could
/// only ever point at the default one.
///
/// A grid of icon tiles rather than full-width cards with a sentence each:
/// the same destinations in a quarter of the height, which is what makes one
/// complete index practical at all. The labels carry the meaning the
/// sentences used to; where a label could not, it was renamed rather than
/// annotated.
class MoreMenuScreen extends ConsumerWidget {
  const MoreMenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final isAdmin = ref.watch(isPlatformAdminProvider).valueOrNull == true;
    // Sponsoring, advertising, Premium, ground listings and the order history
    // are the ACCOUNT's, not the profile's — hidden while a guardian is
    // inside a child's profile, the same way the account menu hides them.
    final isChildProfile = ref.watch(isActingAsChildProvider);

    final isPremium = ref.watch(isPremiumProvider);
    // The club network is an owner's surface — see `myOwnedOrgIdsProvider`
    // and the matching rule. Hidden rather than shown-and-denied, for the
    // same reason the Operations tile is: a tile that leads to "for club
    // owners" for almost everybody is worse than no tile.
    final ownsAClub = ref.watch(myOwnedOrgIdsProvider).isNotEmpty;

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
                  photoUrl: user?.photoUrl,
                  uid: user?.uid,
                  // The player code is the thing another club asks for by
                  // name, so it wins the one line available over an email
                  // address the person already knows.
                  detail: user?.playerCode ?? user?.email,
                  onTap: () => context.push(Routes.myProfile),
                ),

                // --- Belonging to a club, or starting one --------------
                _Section(
                  title: 'Clubs & teams',
                  tint: const Color(0xFF4F46E5),
                  tiles: [
                    // The deliberate exception to "nothing that is on the
                    // bar is also in here": the bar carries `/orgs` only on
                    // the global screens, and drops it for the club's own
                    // four while you are inside one. Without this tile a
                    // person in a club would have no named way back to the
                    // list of their clubs. Same name in both places — it
                    // used to be "My clubs" on the bar and "All clubs" here,
                    // which made one screen look like two.
                    const _Dest(
                        Icons.groups_2_outlined, 'My clubs', Routes.orgs),
                    const _Dest(Icons.vpn_key_outlined, 'Join a club',
                        Routes.joinOrg),
                    const _Dest(Icons.add_business_outlined, 'Create a club',
                        Routes.createOrg),
                    const _Dest(Icons.groups_outlined, 'Independent teams',
                        Routes.standaloneTeams),
                    // The only club-to-CLUB surface in the product: an
                    // owner's inbox, and the directory of clubs there are
                    // still to talk to. It sits here rather than under
                    // Discover because the thing being found is a fixture
                    // partner, not somewhere to play.
                    if (ownsAClub)
                      const _Dest(Icons.handshake_outlined, 'Club network',
                          Routes.clubNetwork),
                  ],
                ),

                // --- Looking outward -----------------------------------
                //
                // Finding somebody and BEING findable are two different jobs,
                // and they used to be scrambled together across this menu and
                // the screens below it. "List your ground" sat under Yours
                // next to Food orders; registering as an official, a coach or
                // a physiotherapist was not in this menu at all — each was a
                // button hidden inside the directory you had to already be
                // looking at. So a physiotherapist who wanted to be listed had
                // to first go looking for physiotherapists, which is the one
                // search they would never think to run.
                //
                // Split in two: everything below finds somebody, everything in
                // the section after it lists you.
                const _Section(
                  title: 'Discover',
                  tint: Color(0xFF2563EB),
                  tiles: [
                    // First in the section, and first for a reason: these
                    // two answer "I have just arrived and know nobody", which
                    // is the state a large share of new accounts are in and
                    // the one every other tile below assumes away.
                    //
                    // Two tiles onto one screen's two tabs, rather than one
                    // tile named after both. Somebody scanning this list is
                    // looking for a noun — a club, or people — and a combined
                    // label is the one they skip.
                    _Dest(Icons.explore_outlined, 'Clubs near me',
                        Routes.discover),
                    _Dest(Icons.person_pin_circle_outlined, 'Players near me',
                        Routes.discoverPeople),
                    _Dest(Icons.event_outlined, 'Find events',
                        Routes.globalEvents),
                    _Dest(Icons.stadium_outlined, 'Find grounds',
                        Routes.grounds),
                    // Kept, and kept distinct. This one is the scout's search
                    // — filtered on rating percentile, form and verification
                    // over players who have actually played. "Near me" above
                    // is the newcomer's, and answers a different question.
                    _Dest(Icons.query_stats_outlined, 'Scout players',
                        Routes.scoutSearch),
                    _Dest(Icons.school_outlined, 'Find coaches',
                        Routes.coaches),
                    _Dest(Icons.verified_user_outlined, 'Umpires & officials',
                        Routes.umpireRegistry),
                    // Straight at the practitioner directory, not at the
                    // sports-medicine hub. Discover answers "who can I
                    // reach", and somebody who needs a physiotherapist today
                    // should not have to pass through a page about warm-ups
                    // to find one. The hub keeps its own tile below for its
                    // other three sections, which are a reading library
                    // rather than a search.
                    _Dest(Icons.medical_services_outlined, 'Doctors & physios',
                        Routes.sportsMedics),
                    // Above the plain searches deliberately: it answers a
                    // question the visitor has not had to formulate.
                    _Dest(Icons.trending_up_outlined, 'Rising talent',
                        Routes.risingTalent),
                    _Dest(Icons.campaign_outlined, 'Looking for',
                        Routes.lookingFor),
                    _Dest(Icons.storefront_outlined, 'Sports shops',
                        Routes.sportsShops),
                    _Dest(Icons.healing_outlined, 'Sports medicine',
                        Routes.sportsMedicine),
                    _Dest(Icons.menu_book_outlined, 'Rulebook', Routes.rules),
                  ],
                ),

                // --- Being findable ------------------------------------
                //
                // The other half of every directory above. Each of these
                // already existed and was reachable from exactly one place:
                // inside the list you would appear in. Collecting them here
                // is the whole point — somebody who has never opened the
                // officials directory can still discover that registering as
                // one is a thing this product does.
                //
                // Hidden inside a child's profile, for the same reason the
                // account menu hides Premium and ground listings: standing as
                // a paid official, listing a ground, or advertising a practice
                // are the ACCOUNT's business, and a guardian browsing as their
                // eleven-year-old should not be offered them.
                if (!isChildProfile)
                  const _Section(
                    title: 'Register',
                    tint: Color(0xFF0891B2),
                    // Labels that stand on their own, like every other tile
                    // here. "As an official" under a REGISTER heading is
                    // shorter, but it only means anything while the heading
                    // is on screen — which is not true for a screen reader
                    // walking the grid, nor for somebody scrolling past the
                    // heading on a phone.
                    tiles: [
                      _Dest(Icons.person_pin_circle_outlined,
                          'Be findable nearby', Routes.myPlayerListing),
                      _Dest(Icons.verified_user_outlined, 'Become an official',
                          Routes.umpireRegister),
                      _Dest(Icons.school_outlined, 'Become a coach',
                          Routes.myCoachProfile),
                      _Dest(Icons.local_hospital_outlined, 'List your practice',
                          Routes.mySportsMedicProfile),
                      _Dest(Icons.storefront_outlined, 'List your shop',
                          Routes.mySportsShop),
                      _Dest(Icons.business_center_outlined, 'List your ground',
                          Routes.myGrounds),
                      _Dest(Icons.ads_click_outlined, 'Advertise',
                          Routes.adConsole),
                    ],
                  ),

                // --- Giving something back -----------------------------
                // --- Building sides --------------------------------------
                //
                // Its own section rather than a tile under Clubs & teams. An
                // auction is not a club thing — it is called by whoever runs
                // the tournament, who may belong to no club at all, and the
                // requirement was explicit that it work irrespective of club,
                // district or village. Filing it under Clubs & teams would
                // have taught every reader the opposite.
                const _Section(
                  title: 'Auctions',
                  tint: Color(0xFF0D9488),
                  tiles: [
                    _Dest(Icons.gavel_outlined, 'Player auctions',
                        Routes.auctions),
                  ],
                ),

                _Section(
                  title: 'Community',
                  tint: const Color(0xFFEA580C),
                  tiles: [
                    const _Dest(Icons.volunteer_activism_outlined, 'Give',
                        Routes.give),
                    if (!isChildProfile)
                      const _Dest(Icons.handshake_outlined, 'Sponsor',
                          Routes.sponsor),
                    if (isAdmin)
                      // Platform staff only — hidden rather than
                      // shown-and-denied. A tile that leads to "Restricted"
                      // for 99.9% of accounts is worse than no tile.
                      //
                      // One tile now, not four. Advertising requests,
                      // donations, needs and ground listings all used to be
                      // queues with no destination; `OpsHomeScreen` is the
                      // one door to all of them and shows what is waiting on
                      // each, which four peer tiles here could not.
                      const _Dest(Icons.inbox_outlined, 'Operations',
                          Routes.ops),
                  ],
                ),

                // --- The account's own business ------------------------
                _Section(
                  title: 'Yours',
                  tint: const Color(0xFF7C3AED),
                  tiles: [
                    const _Dest(Icons.shopping_bag_outlined, 'Shop', Routes.shop),
                    if (!isChildProfile) ...[
                      _Dest(
                        isPremium
                            ? Icons.workspace_premium
                            : Icons.workspace_premium_outlined,
                        // A member who is already paying should not be sold
                        // to every time they open the menu.
                        isPremium ? 'Premium' : 'Get Premium',
                        Routes.premium,
                      ),
                      const _Dest(Icons.receipt_long_outlined, 'Orders',
                          Routes.myClubOrders),
                      const _Dest(Icons.fastfood_outlined, 'Food orders',
                          Routes.myFoodOrders),
                    ],
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

/// One destination in the index.
class _Dest {
  const _Dest(this.icon, this.label, this.path);

  final IconData icon;
  final String label;
  final String path;
}

/// The account, as one row rather than the card-with-avatar-and-two-lines it
/// was. Tapping it opens the profile, which is the only thing it ever did.
class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.name,
    required this.detail,
    required this.onTap,
    this.photoUrl,
    this.uid,
  });

  final String name;
  final String? detail;
  final VoidCallback onTap;

  /// The row drew a green disc with an initial in it and never looked at the
  /// photo, so the one place a person sees their own account in the menu was
  /// the one place their own face was missing.
  final String? photoUrl;
  final String? uid;

  @override
  Widget build(BuildContext context) {
    return PsCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: onTap,
      child: Row(
        children: [
          PsAvatar(
            name: name.isEmpty ? 'P' : name,
            photoUrl: photoUrl,
            seed: uid,
            size: 40,
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
  final List<_Dest> tiles;

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
            tileHeight: PsNavTile.gridHeight,
            children: [
              for (final t in tiles)
                PsNavTile(
                  icon: t.icon,
                  label: t.label,
                  tint: tint,
                  onTap: () => context.push(t.path),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
