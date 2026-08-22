import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/sports_medic.dart';
import '../../core/router/app_router.dart';
import '../../shared/identity.dart';
import '../../shared/ui_kit.dart';

/// One practitioner, as every list in the hub shows them.
///
/// Shared between the directory and the "physios near you" strip on the hub,
/// so the two cannot drift. What it puts on the row is what somebody with a
/// swollen knee on a Sunday actually needs before tapping: what kind of
/// practitioner this is, where they are, whether PlaySphere has checked the
/// registration number, and whether they are taking anybody at all.
class SportsMedicCard extends StatelessWidget {
  const SportsMedicCard({super.key, required this.medic});

  final SportsMedicProfile medic;

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (medic.experienceYears > 0) '${medic.experienceYears} yrs',
      medic.feeLabel,
      // At most two modes on the row. A listing offering all four turns the
      // line into a paragraph, and the page lists them in full anyway.
      ...medic.consultationModes.take(2).map((m) => m.label),
    ].join('  ·  ');

    return ListTile(
      onTap: () => context.push(Routes.sportsMedic(medic.uid)),
      leading: PsAvatar(
        name: medic.displayName,
        photoUrl: medic.photoUrl,
        seed: medic.uid,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              medic.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Set by PlaySphere and unwritable by any client. Its absence is
          // not a mark against anybody — the detail page explains in words
          // what the badge does and does not mean, which is why there is no
          // "unverified" badge to pair with it.
          if (medic.isVerified) ...[
            const SizedBox(width: 6),
            const Icon(Icons.verified, size: 15, color: Ps.primary),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            medic.subtitleLine,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Ps.muted),
          ),
          if (meta.isNotEmpty)
            Text(
              meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: Ps.faint),
            ),
        ],
      ),
      trailing: medic.acceptingNewPatients
          ? const Icon(Icons.chevron_right, size: 18, color: Ps.faint)
          // Said on the row rather than left to the page, because the point
          // of the list is to save somebody ringing round with an injury.
          : const Text(
              'Not taking',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Ps.faint,
              ),
            ),
    );
  }
}
