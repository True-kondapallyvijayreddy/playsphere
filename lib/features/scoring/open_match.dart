import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/fixture.dart';
import '../../core/router/app_router.dart';

/// Where a tap on a match goes, wherever the match was tapped.
///
/// Three screens draw a list of fixtures — an event's own board, a season's
/// programme and the public spectator page — and each had (or, in the
/// season's case, had lost) its own answer to "what happens when I tap one".
/// They must agree, because the answer is not cosmetic: it is the only route
/// to the scoring pad, and a screen that forgets to wire it is a schedule
/// full of matches that cannot be scored.
///
/// The order is deliberate and matches `docs/Heart_of_the_playsphere.md`
/// §3/§4:
///
/// - A **draft** fixture has placeholder sides. There is nothing to score or
///   watch, so the tap goes to [onDraft] — editing its slot — or nowhere.
/// - A match that has **not started** opens the Match Center, the hub where
///   the toss is taken and the pen is picked up. Not the pad: an empty
///   scoreboard with nobody assigned is not a useful place to land.
/// - A **live or finished** match goes straight to the score — the pad for
///   whoever may write, the read-only board for everybody else.
void openMatch(
  BuildContext context, {
  required Fixture fixture,
  required String? myUid,
  required bool canManage,
  VoidCallback? onDraft,
}) {
  final f = fixture;
  if (f.isDraft) {
    onDraft?.call();
    return;
  }

  final started = f.isLiveAt(DateTime.now()) || f.status.isResulted;
  if (!started) {
    context.push(Routes.matchCenter(f.orgId, f.compId, f.id));
    return;
  }

  final canScore = myUid != null && f.canBeScoredBy(myUid, isOrgManager: canManage);
  context.push(
    canScore
        ? Routes.scoring(f.orgId, f.compId, f.id)
        : Routes.watch(f.orgId, f.compId, f.id),
  );
}
