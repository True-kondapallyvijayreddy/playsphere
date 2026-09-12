import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/responsive.dart';
import '../../../core/permissions/capability.dart';
import '../../../core/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/ui_kit.dart';

/// Every section of one club, on that club's own page.
///
/// ## Why this exists
///
/// These ten screens used to be reachable only from two places: the bottom
/// bar, which could hold four of them, and the three-lines drawer, which was
/// attached to every route in the app and pointed at whichever club the
/// person had joined most recently.
///
/// That second part was the real defect. Open club B, pull out the drawer,
/// tap Gallery — and you were looking at club A's photographs, because the
/// drawer was a GLOBAL menu holding CLUB-scoped links. The club you were
/// reading had no index of its own.
///
/// So the club's sections moved onto the club, where [orgId] is the club in
/// front of you and cannot be anything else. The drawer is gone; nothing it
/// offered was lost, and the half of it that pointed at the wrong club can no
/// longer do so.
///
/// Deliberately not repeated here: **Live now** and **Challenges**, which the
/// bottom bar carries the whole time you are inside a club; **New event** and
/// **Quick match**, the two floating buttons on this screen; and **Club
/// settings**, the gear in the app bar. A door drawn twice on one screen is
/// the clutter this whole change exists to remove — see `MoreMenuScreen`.
class ClubSectionsGrid extends ConsumerWidget {
  const ClubSectionsGrid({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(myCapabilitiesProvider(orgId));
    final pending =
        ref.watch(pendingMembersProvider(orgId)).valueOrNull?.length ?? 0;

    // `(icon, label, route, badge)`. Pending join requests are the one thing
    // in this grid that expires if nobody looks, so they are the one count.
    final tiles = <(IconData, String, String, int)>[
      (
        Icons.emoji_events_outlined,
        'Tournaments',
        Routes.tournaments(orgId),
        0,
      ),
      (Icons.people_alt_outlined, 'Members', Routes.members(orgId), pending),
      (Icons.collections_outlined, 'Gallery', Routes.gallery(orgId), 0),
      (Icons.leaderboard_outlined, 'Rankings', Routes.rankings(orgId), 0),
      (Icons.stadium_outlined, 'Venues', Routes.venues(orgId), 0),
      (Icons.folder_outlined, 'Files', Routes.files(orgId), 0),
      (Icons.storefront_outlined, 'Store', '/org/$orgId/store', 0),
      // Hidden rather than disabled, exactly as the drawer had it: a member
      // without the right should see a club that does not contain analytics,
      // not a tile that refuses them.
      if (caps.contains(Capability.viewAnalytics))
        (Icons.insights_outlined, 'Analytics', Routes.analytics(orgId), 0),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Sections',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Ps.ink,
          ),
        ),
        const SizedBox(height: 8),
        PsCard(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: AdaptiveGrid(
            // Same 88/86 as the More index, so a club's sections and the
            // product's index are visibly the same kind of thing rather than
            // two grids that happen to sit in one app.
            minTileWidth: 88,
            spacing: 0,
            tileHeight: PsNavTile.gridHeight,
            children: [
              for (final (icon, label, route, badge) in tiles)
                PsNavTile(
                  icon: icon,
                  label: label,
                  badgeCount: badge,
                  onTap: () => context.push(route),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
