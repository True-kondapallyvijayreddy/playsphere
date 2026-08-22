import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/competition.dart';
import '../../core/models/enums.dart';
import '../../core/models/fixture.dart';
import '../../core/models/match_player.dart';
import '../../core/models/squad_entry.dart';
import '../../core/providers.dart';

/// Who a side actually registered, resolved to names.
///
/// ## The bug this exists for
///
/// A team enters a competition and the entry records its squad — that is what
/// `Entrant.memberUids` is, and for an inter-club challenge it is what the
/// confirmed `squadEntries` are. Nothing on match day read either of them.
/// The team-sheet dialog offered *every active member of the club* with
/// nothing ticked, so the scorer's starting point on a match between two
/// registered teams was a blank list of the wrong people. Tick the wrong
/// name — and every name on the list is a plausible one, they are all real
/// club members — and a player who registered for a different team is now
/// scored as playing for this one, permanently, in that team's history and
/// in that player's career record.
///
/// So the registration is the default and the club's wider membership is the
/// exception. That is the only ordering that matches what an organizer means
/// by "the teams are already set".
class RegisteredSquad {
  const RegisteredSquad({
    required this.entrantId,
    required this.entrantName,
    required this.players,
    required this.isRegistered,
  });

  /// A side whose registration could not be found — an individual event, an
  /// entrant typed in by name, a knockout slot still waiting on a qualifier.
  /// [isRegistered] is false and the picker falls back to the club's members,
  /// which is the old behaviour and the right one when there is genuinely no
  /// registered squad to honour.
  const RegisteredSquad.unknown(this.entrantId, this.entrantName)
      : players = const [],
        isRegistered = false;

  final String entrantId;
  final String entrantName;

  /// The registered squad, in registration order.
  final List<MatchPlayer> players;

  /// Whether [players] came from a real registration rather than being empty
  /// for want of one. Distinct from `players.isNotEmpty`: a team that entered
  /// without naming anybody is registered and empty, and must not be treated
  /// as "no registration exists".
  final bool isRegistered;

  bool contains(String playerId) => players.any((p) => p.id == playerId);
}

/// Both sides' registered squads for one fixture.
class FixtureSquads {
  const FixtureSquads({required this.a, required this.b});

  final RegisteredSquad a;
  final RegisteredSquad b;

  RegisteredSquad forSide(int side) => side == 0 ? a : b;

  /// True when at least one side has a registration to honour. When neither
  /// does there is nothing this adds over the plain member list.
  bool get anyRegistered => a.isRegistered || b.isRegistered;
}

/// Resolves both sides' registered squads for a fixture.
///
/// Two shapes of registration exist and both are read here, because a scorer
/// does not know or care which kind of match they are standing at:
///
///  * A competition entrant (`entrants/{id}.memberUids`) — a team that entered
///    a season or a tournament.
///  * A fixture squad entry (`squadEntries/{uid}`) — one club filling its own
///    side of an inter-club challenge, where there is no competition-wide
///    entrant document to hold a roster.
///
/// Names come from the club's member list first, because that stream is
/// already open for the picker and costs nothing extra, and from the accounts
/// themselves for anyone it does not cover — a guest club's player in a
/// challenge, most obviously. A uid that resolves to neither still appears,
/// under a placeholder, rather than silently vanishing from a team sheet.
final registeredSquadsProvider =
    FutureProvider.family<FixtureSquads, FixtureRef>((ref, key) async {
  final fixture = await ref.watch(fixtureProvider(key).future);
  if (fixture == null) {
    return const FixtureSquads(
      a: RegisteredSquad.unknown('', ''),
      b: RegisteredSquad.unknown('', ''),
    );
  }

  // An inter-club challenge: the roster lives on the fixture, per side.
  if (fixture.participantOrgIds != null) {
    final entries = await ref.watch(squadEntriesProvider(key).future);
    return FixtureSquads(
      a: _fromSquadEntries(fixture, entries, 'a'),
      b: _fromSquadEntries(fixture, entries, 'b'),
    );
  }

  final entrants = await ref.watch(
    entrantsProvider(CompRef(key.orgId, key.compId)).future,
  );
  Entrant? entrantFor(String id) {
    if (id.isEmpty) return null;
    for (final e in entrants) {
      if (e.id == id) return e;
    }
    return null;
  }

  final entrantA = entrantFor(fixture.entrantAId);
  final entrantB = entrantFor(fixture.entrantBId);

  // One lookup for both squads, so a match costs one batched read rather than
  // one per player per side.
  final names = await _namesFor(
    ref,
    orgId: fixture.orgId,
    uids: {...?entrantA?.memberUids, ...?entrantB?.memberUids},
  );

  return FixtureSquads(
    a: _fromEntrant(fixture.entrantAId, fixture.entrantAName, entrantA, names),
    b: _fromEntrant(fixture.entrantBId, fixture.entrantBName, entrantB, names),
  );
});

RegisteredSquad _fromEntrant(
  String entrantId,
  String entrantName,
  Entrant? entrant,
  Map<String, String> names,
) {
  // An individual entrant is not a squad and has no roster to honour — the
  // player IS the side. Treating them as an empty registered squad would
  // present a singles match as a team with nobody in it.
  if (entrant == null || entrant.entrantType == EntrantType.individual) {
    return RegisteredSquad.unknown(entrantId, entrantName);
  }
  return RegisteredSquad(
    entrantId: entrantId,
    entrantName: entrantName,
    isRegistered: true,
    players: [
      for (final uid in entrant.memberUids)
        MatchPlayer(id: uid, name: names[uid] ?? 'Player', uid: uid),
    ],
  );
}

RegisteredSquad _fromSquadEntries(
  Fixture fixture,
  List<SquadEntry> entries,
  String side,
) {
  final isA = side == 'a';
  final mine = [
    for (final e in entries)
      if (e.side == side && e.isPlaying) e,
  ];
  return RegisteredSquad(
    entrantId: isA ? fixture.entrantAId : fixture.entrantBId,
    entrantName: isA ? fixture.entrantAName : fixture.entrantBName,
    // A challenge always has a squad call, even when nobody has answered it
    // yet — an empty confirmed list means "nobody has put their hand up",
    // which is a real state and not an absent registration.
    isRegistered: true,
    players: [
      for (final e in mine)
        MatchPlayer(id: e.uid, name: e.displayName, uid: e.uid),
    ],
  );
}

/// uid -> display name, from the club's members first and the accounts second.
Future<Map<String, String>> _namesFor(
  Ref ref, {
  required String orgId,
  required Set<String> uids,
}) async {
  if (uids.isEmpty) return const {};

  final names = <String, String>{};
  final members = await ref.watch(orgMembersProvider(orgId).future);
  for (final m in members) {
    if (uids.contains(m.uid)) names[m.uid] = m.displayName;
  }

  final missing = uids.difference(names.keys.toSet());
  if (missing.isEmpty) return names;

  // Anyone the club's own member list does not cover — the visiting club's
  // players in a challenge, a player who has since left. Batched, and
  // tolerant of a profile this viewer may not read.
  try {
    final users = await ref.read(userRepositoryProvider).fetchMany(missing);
    users.forEach((uid, user) => names[uid] = user.displayName);
  } catch (_) {
    // Names are a courtesy here; the uid is what the scorecard is keyed on.
    // A failed lookup leaves the placeholder rather than emptying the sheet.
  }

  return names;
}

/// Copies each side's registered squad onto the fixture, for any side that
/// does not already have a team sheet.
///
/// This is what makes "the teams are already set" true in the data rather
/// than only in the organizer's head. The draw generator deliberately leaves
/// team line-ups empty — resolving names there would cost a read per entrant
/// at generation time — and its comment said they would be "filled at
/// match-start from the entrant's member list". Nothing ever did that, so
/// every registered team arrived at its match with an empty sheet, and the
/// scoring engine fell back to a single synthetic player named after the
/// team. That is why a scorecard could show the club's name where a player
/// should be, and why the picker had to be opened at all.
///
/// Called from both doors into a match — the Start button in Match Center and
/// the scoring pad itself, which is reachable directly from five other
/// screens.
///
/// Never overwrites an existing sheet: one that exists was put there by
/// somebody, and their decision outranks the registration it was made
/// against. Never runs once a ball has been scored, for the same reason.
///
/// Best-effort by design. A match must be startable even when the entrant
/// documents cannot be read — no signal, or a scorer without permission to
/// list them — because the picker is still there and blocking a match on a
/// convenience read is a worse failure than the one this fixes.
Future<void> adoptRegisteredSquads(WidgetRef ref, Fixture fixture) async {
  if (fixture.lastSeq > 0) return;
  if (fixture.lineupA.isNotEmpty && fixture.lineupB.isNotEmpty) return;

  try {
    final squads = await ref.read(
      registeredSquadsProvider(
        FixtureRef(fixture.orgId, fixture.compId, fixture.id),
      ).future,
    );
    if (!squads.anyRegistered) return;

    final lineupA =
        fixture.lineupA.isNotEmpty ? fixture.lineupA : squads.a.players;
    final lineupB =
        fixture.lineupB.isNotEmpty ? fixture.lineupB : squads.b.players;

    // Nothing to write. Two registered-but-empty squads is a real state — a
    // challenge nobody has answered yet — and writing two empty lists over
    // two empty lists is a wasted round trip on a match about to start.
    if (lineupA.isEmpty && lineupB.isEmpty) return;

    await ref.read(competitionRepositoryProvider).setLineups(
          fixture: fixture,
          lineupA: lineupA,
          lineupB: lineupB,
        );
  } catch (e) {
    debugPrint('[PlaySphere] could not adopt registered squads: $e');
  }
}
