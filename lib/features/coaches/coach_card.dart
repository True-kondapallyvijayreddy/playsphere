import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/coach.dart';
import '../../core/router/app_router.dart';
import '../../shared/identity.dart';
import '../../shared/ui_kit.dart';

/// One coach, as every list in the product shows them.
///
/// Shared between the directory and the sport hub so the two cannot drift.
/// What it puts on the row is what somebody deciding whether to ring a
/// stranger actually needs: the name, whether PlaySphere has checked them,
/// whether they are taking anybody, and one line in their own words.
class CoachCard extends StatelessWidget {
  const CoachCard({super.key, required this.coach, this.dense = false});

  final CoachProfile coach;

  /// Drops the credential chips, for the four-row preview on a sport hub
  /// where the row has to stay the height of every other row on the screen.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (coach.city.isNotEmpty) coach.city,
      if (coach.yearsExperience > 0) '${coach.yearsExperience} yrs',
      coach.rateLabel,
    ].join('  ·  ');

    return ListTile(
      onTap: () => context.push(Routes.coach(coach.uid)),
      leading: PsAvatar(
        name: coach.displayName,
        photoUrl: coach.photoUrl,
        seed: coach.uid,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              coach.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Set by PlaySphere and unwritable by the client — see
          // `CoachProfile.isVerified`. Its absence is not a mark against
          // anybody, which is why there is no "unverified" badge to pair
          // with it; the page says what verification means instead.
          if (coach.isVerified) ...[
            const SizedBox(width: 6),
            const Icon(Icons.verified, size: 15, color: Ps.primary),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            coach.headline?.isNotEmpty == true ? coach.headline! : subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Ps.muted),
          ),
          if (!dense && coach.headline?.isNotEmpty == true)
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: Ps.faint),
            ),
        ],
      ),
      trailing: coach.acceptingStudents
          ? const Icon(Icons.chevron_right, size: 18, color: Ps.faint)
          // Said on the row rather than left to the page, because the whole
          // point of the list is to save somebody ringing round.
          : const Text(
              'Full',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Ps.faint,
              ),
            ),
    );
  }
}
