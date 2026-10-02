import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/tournament/season_entry_status.dart';
import '../home/home_providers.dart';
import '../home/open_registrations.dart';

/// "Have I already registered for this season?" — asked by the season page,
/// the register page and each event's entry card, answered in one place.
///
/// Lives in the feature layer rather than in `core/providers.dart` because it
/// composes two things that only meet here: the season's events, and what the
/// PROFILE IN USE has entered anywhere. The second is the home screen's
/// `profileEntryRefsProvider`, deliberately reused rather than re-derived —
/// the set that takes a season off the home screen's "Open to enter" list is
/// exactly the set that must turn this season's Register button into
/// "Already registered", and two definitions of "a live entry" would drift
/// until the two screens disagreed in front of the same user.
final seasonEntryStatusProvider = Provider.family<SeasonEntryStatus,
    ({String orgId, String tournamentId})>((ref, key) {
  final events = ref.watch(tournamentEventsProvider(key)).valueOrNull;
  if (events == null) return SeasonEntryStatus.none;

  // A member of an invited club who does not run it never gets a personal
  // Register button — the entry is the club's. See `InvitedClubBlock`.
  final invited = ref.watch(invitedSeasonContextProvider(
    (hostOrgId: key.orgId, tournamentId: key.tournamentId),
  ));

  return SeasonEntryStatus.of(
    events: events,
    entryRefs: ref.watch(profileEntryRefsProvider),
    clubEntersForMe: invited != null && !invited.canEnterForClub,
  );
});

/// The same question for one event, so an event card can say "Entered"
/// without each screen re-deriving what counts as an entry.
final competitionEnteredProvider =
    Provider.family<bool, CompRef>((ref, key) {
  return ref
      .watch(profileEntryRefsProvider)
      .contains('${key.orgId}/${key.compId}');
});
