import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/permissions/capability.dart';
import '../../../core/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/app_scaffold.dart';

/// Shows [child] only to the people who run this season.
///
/// For the season's management screens — the umpire panel, the venue
/// planner — which are reachable by URL, by a shared link and by the back
/// button, not only from the organizer's own buttons. Hiding the button was
/// never access control: the umpire panel screen checked nothing, so anybody
/// who landed on it was offered "Add an official". `firestore.rules` refuses
/// the write either way; this makes the screen say so before anybody tries.
///
/// [alsoAllow] admits a departmental brief on top of the organizer ranks —
/// the grounds brief for the venue planner, matching `canManageVenues` in the
/// rules.
class SeasonOrganizerGate extends ConsumerWidget {
  const SeasonOrganizerGate({
    super.key,
    required this.orgId,
    required this.tournamentId,
    required this.what,
    required this.child,
    this.alsoAllow,
  });

  final String orgId;
  final String tournamentId;

  /// What is being protected, for the sentence: "the umpire panel".
  final String what;
  final Widget child;
  final Capability? alsoAllow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Wait for the membership rather than failing an owner closed for the
    // frame before it arrives.
    if (ref.watch(myMembershipsProvider).isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final access = ref.watch(
        seasonAccessProvider((orgId: orgId, tournamentId: tournamentId)));
    final extra = alsoAllow != null &&
        ref.watch(myCapabilitiesProvider(orgId)).contains(alsoAllow);
    if (access.canManage || extra) return child;

    return EmptyState(
      icon: Icons.lock_outline,
      title: 'For the season organizers',
      message: 'Only the owner, admins and event managers running this '
          'season can change $what. Everything about the season — '
          'standings, schedule and results — is on the season page.',
      action: FilledButton(
        onPressed: () => context.go(Routes.tournament(orgId, tournamentId)),
        child: const Text('Go to the season'),
      ),
    );
  }
}
