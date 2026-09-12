import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/async_combine.dart';
import '../../core/models/app_user.dart';
import '../../core/models/competition.dart';
import '../../core/models/enums.dart';
import '../../core/models/tournament.dart';
import '../../core/models/tournament_invite.dart';
import '../../core/providers.dart';
import '../../data/competition_repository.dart';
import '../../core/router/app_router.dart';
import '../../shared/identity.dart';
import '../../shared/ui_kit.dart';
import 'home_providers.dart';

// Seasons and tournaments a person could enter RIGHT NOW: two counted
// buttons on the home screen under the three big doors, and the two lists
// behind them.
//
// ## Why the dashboard grew this at all
//
// `HomeScreen` holds counts, not lists, and the reasoning behind that rule is
// on its own doc comment. This obeys it, and it is worth saying why it still
// had to be built: the Events counter says "6", which is a fact, and the only
// way to find out whether any of the six is *for you* is to open a screen,
// read a cross-club list and check six age categories by hand. A count cannot
// carry an opportunity, and an opportunity nobody sees closes.
//
// So these counts are not "events, again". "Active" is the strictly smaller
// set that satisfies all four of: open for entry now, REACHABLE by this
// profile, this profile is eligible, and this profile has not already entered
// it. Reachable means one of two things — a club this profile is in or
// follows, or a season at any club that one of this profile's clubs has been
// invited into; see `invitedSeasonEventsProvider` for why an invitation had
// to be a second door. Anything failing one of those is absent from the count and from
// the list, and the moment an entry deadline passes it leaves on its own —
// see `_stillTakingEntries` and `Competition.registrationIsOpen`.
//
// ## The two invariants everything below is arranged to keep
//
// ONE PROFILE. Every number here answers for the profile currently in use and
// for nobody else — never a parent's plus their children's added together.
// See `homeProfileProvider` for why the household fan-out was removed.
//
// DISJOINT LENSES. A season is on exactly one of the two tiles. Three seasons
// open with one entered reads "Active 2, Registered 1"; entering is what moves
// a row across. See `RegistrationLens` and `openRegistrationsProvider`.
//
// ## Why two buttons and not one list
//
// A season and a one-off tournament are different questions asked by
// different people — see [OpenRegistrationKind]. Two counts also let the
// dashboard say how much is open in two short lines, which is what the rest
// of the screen does, instead of spending five rows saying it.
//
// ## What one row says, and what it deliberately does not
//
// `Hyderabad Cricket Club — Summer League 2026 — Cricket`, and nothing else.
// No dates, no fee, no entry count, no status chip. A row here answers "is
// there something for us?"; every other question belongs on the board the row
// opens, which already answers all of them properly.

/// The sport line for a season that runs more than one.
///
/// A five-sport season has no single sport, and naming the first draw's would
/// be a lie the card tells about the season. This is the label the whole app
/// should use for that case if anything else ever needs it.
const String kMultiSportLabel = 'Multi Sport';

/// The two things this section counts, which are two different things.
///
/// A SEASON is a container — "Summer League 2026", "Sports Week" — with draws
/// under it, and entering one means entering a draw from its board. A
/// TOURNAMENT here is a competition standing on its own, with no season above
/// it, which a person enters directly.
///
/// The home screen offers them as separate buttons because they are separate
/// questions. "What is my club running this term?" and "is there a one-off I
/// can enter on Sunday?" are asked by different people at different moments,
/// and a single mixed list makes both of them scan past the other's answers.
enum OpenRegistrationKind {
  season('season', 'seasons'),
  tournament('tournament', 'tournaments');

  const OpenRegistrationKind(this.noun, this.plural);

  /// Singular, for counting: "1 season open to enter".
  final String noun;

  /// What a button and a screen title call this kind — "Active seasons".
  final String plural;
}

/// The two questions the buttons answer, which are not the same question.
///
/// "What can I enter?" is a decision waiting to be made and it expires. "What
/// have I entered?" is a commitment already made, and it is what a person
/// checks the morning of a match. Mixing them would leave a person scanning a
/// list of things they are already in to find the one thing they still have
/// to decide about.
///
/// The two are DISJOINT, and that is the whole point of having two. Three
/// seasons open, one entered, reads as "Active 2, Registered 1" — never
/// "Active 3, Registered 1", which double-counts the entered one and turns
/// the Active tile back into the events counter it was built to be sharper
/// than. Entering something is what moves it from the left tile to the right
/// one; see [openRegistrationsProvider].
enum RegistrationLens {
  open('Active', 'open to enter'),
  registered('Registered', 'you have entered');

  const RegistrationLens(this.adjective, this.blurb);

  /// Starts the button's label: "Active seasons", "Registered tournaments".
  final String adjective;

  /// The line under it, and the reason the button is worth pressing.
  final String blurb;

  String labelFor(OpenRegistrationKind kind) => '$adjective ${kind.plural}';
}

/// One thing that can be entered, as a home row.
///
/// Deliberately flat and already decided: the grouping, the eligibility test
/// and the sport reduction all happen in [openRegistrationsProvider], so the
/// widget below renders text and pushes a route and holds no rules of its own.
@immutable
class OpenRegistration {
  const OpenRegistration({
    required this.key,
    required this.kind,
    required this.orgId,
    required this.title,
    required this.sportLabel,
    required this.route,
    required this.createdAt,
  });

  /// `orgId/tournamentId` for a season, `orgId/compId` for a standalone
  /// tournament. Stable across rebuilds, so a row keeps its widget identity
  /// while the list around it changes.
  final String key;

  /// Which of the two lists this belongs on. Decided once, where the events
  /// are grouped — a row is a season exactly when it has a season document
  /// above it — so no screen has to re-derive it from `route` or `key`.
  final OpenRegistrationKind kind;

  final String orgId;

  /// The season's own name — "Summer League 2026" — never the sport-qualified
  /// name of one of its draws.
  final String title;

  /// One sport's name, or [kMultiSportLabel].
  final String sportLabel;

  /// The board this row opens. A season goes to its season board; a
  /// standalone tournament goes to its own event board. Both carry the full
  /// picture and the Register flow; neither is reachable from here by any
  /// other route.
  final String route;

  /// When the season or the tournament was created. Null only for records
  /// written before `createdAt` existed, which sort last rather than first.
  final DateTime? createdAt;
}

// ---------------------------------------------------------------------------
// Who this home screen is answering for
// ---------------------------------------------------------------------------

/// The one person this section speaks for: the profile currently in use.
///
/// Every count and every row on this section is that profile's own — what
/// THEY can enter, what THEY have entered — and nobody else's. Inside a
/// child's profile the app *is* that child; on the account holder's own home
/// screen it is the account holder, and a season only their daughter is
/// eligible for belongs on her home screen, reached by switching into it.
///
/// This used to fan out across the household — the parent's screen answered
/// for themselves plus every managed child at once — on the argument that a
/// parent should not have to switch profiles to notice an opportunity. The
/// cost was a screen that could not be read: "Active seasons 4" mixed one
/// club's under-11 championship with two of the parent's own leagues, the
/// tile could not say whose was whose, and pressing it opened a list where
/// half the rows led to a Register button the reader could not use. A count
/// that has to be attributed person by person after you read it is not a
/// count. One profile, one answer — which is what [currentUidProvider]
/// already means everywhere else in the app.
final homeProfileProvider = Provider<AppUser?>(
  (ref) => ref.watch(currentUserProvider).valueOrNull,
);

/// Every competition across the profile's own clubs, keeping whatever loaded.
///
/// The clubs are [myFeedOrgIdsProvider] — the ones this profile is in or
/// follows, the same definition of "related to me" the rest of the dashboard
/// runs on, and already scoped to the profile in use rather than the account.
/// Nothing else is reachable from here: a club this profile has no
/// relationship with is not discovery, it is noise, and the screen that DOES
/// answer "what is open anywhere" is `GlobalEventsScreen`.
///
/// Tolerant rather than strict: a club can refuse the read — an unlisted club
/// grants nothing to a follower whose membership lapsed — and one refused club
/// must cost that club's rows, not the whole section, which is the same lesson
/// `myLiveFixturesPartialProvider` records at greater length.
///
/// Unlike that one, the failures are counted and not shown. `PartialAsync`
/// exists on the principle that dropping a club quietly is unacceptable, and
/// the exception is argued rather than assumed: a missing LIVE match tells a
/// player standing at the ground that nothing is on, which is a lie about
/// where they are. A missing row here is a season the reader has no permission
/// to see and could not have entered — "1 club unavailable" on the crispest
/// section in the product would be a permanent apology for a club that is
/// deliberately private. The failures stay on [PartialAsync.failures] for
/// whoever wants them next.
final openRegistrationsPartialProvider =
    Provider<PartialAsync<Competition>>((ref) {
  final orgIds = ref.watch(myFeedOrgIdsProvider);
  if (orgIds.isEmpty) {
    return const PartialAsync(items: [], failures: [], isLoading: false);
  }
  return combineAsyncTolerant([
    for (final id in orgIds) ref.watch(competitionsProvider(id)),
  ]);
});

/// The seasons at OTHER clubs that a club of this profile's has been invited
/// into, as their draws.
///
/// ## Why the feed alone was not enough
///
/// Everything above reaches only [myFeedOrgIdsProvider] — the clubs this
/// profile is in or follows — and a cross-club invitation is precisely the
/// case where the season you are wanted at belongs to a club you have no
/// relationship with. The host asks your club, your club says yes, and the
/// season stayed invisible to every member of it, including the people meant
/// to play in it. An invitation nobody at the invited club can see is the
/// same failure the invitation document was built to fix — see
/// [TournamentInvite] on why a link was not good enough.
///
/// Pending counts, not just accepted. "Your club has been asked" is already
/// news worth a member seeing, and the reply is the club's to make, not this
/// screen's to wait for.
///
/// Scoped to the clubs this profile is an ACTIVE MEMBER of — not the ones it
/// merely follows. Following is a reader's relationship; being invited
/// somewhere is something that happens to a club and its members, and a
/// follower is neither.
///
/// Only the invited tournament's own draws are pulled in, never the host's
/// whole calendar. Being invited to one season is not a relationship with the
/// club, and the screen that answers "what else are they running" is
/// `GlobalEventsScreen`.
final invitedSeasonEventsProvider = Provider<List<Competition>>((ref) {
  final events = <String, Competition>{};
  for (final orgId in ref.watch(myActiveOrgIdsProvider)) {
    final invites =
        ref.watch(liveIncomingTournamentInvitesProvider(orgId)).valueOrNull ??
            const <TournamentInvite>[];
    for (final invite in invites) {
      // A host whose org is private refuses this read outright, and it must
      // cost that one season rather than the section — the same tolerance
      // `openRegistrationsPartialProvider` is built on.
      final draws = ref
              .watch(tournamentEventsProvider((
                orgId: invite.fromOrgId,
                tournamentId: invite.tournamentId,
              )))
              .valueOrNull ??
          const <Competition>[];
      for (final c in draws) {
        events['${c.orgId}/${c.id}'] = c;
      }
    }
  }
  return events.values.toList();
});

/// Everything this home screen may draw a row from: the profile's own clubs,
/// plus the seasons its clubs have been invited into.
///
/// Merged by `orgId/compId` so a season that arrives down both paths — your
/// club was invited to a club you also follow — is one row, not two.
final homeCompetitionPoolProvider = Provider<List<Competition>>((ref) {
  final pool = <String, Competition>{};
  for (final c in ref.watch(openRegistrationsPartialProvider).items) {
    pool['${c.orgId}/${c.id}'] = c;
  }
  for (final c in ref.watch(invitedSeasonEventsProvider)) {
    pool['${c.orgId}/${c.id}'] = c;
  }
  return pool.values.toList();
});

// ---------------------------------------------------------------------------
// The four lists
// ---------------------------------------------------------------------------

/// Groups competitions into seasons and standalone tournaments, keeps the
/// groups [qualifies] accepts, and turns each into a row — newest first.
///
/// Shared by both lenses so the two cannot describe the same season
/// differently. Everything that makes a row READ the way it does lives here;
/// what changes between the lenses is only which groups survive, which is the
/// callback.
List<OpenRegistration> _rowsFrom(
  Ref ref,
  Iterable<Competition> pool, {
  required bool Function(List<Competition> events) qualifies,
  required bool Function(Tournament season) seasonQualifies,
}) {
  // Grouped over EVERY competition handed in, not only the qualifying ones. A
  // season's sport line describes the season, so a five-sport sports week
  // whose other four draws have already closed is still Multi Sport.
  final groups = <String, List<Competition>>{};
  for (final c in pool) {
    // A single match and a challenge are stored as competitions too. Neither
    // is a thing anybody registers for — both are written straight to
    // `inProgress` — and this says so at the top rather than leaving it to a
    // status filter two files away to exclude them by coincidence.
    if (c.format.isSingleMatch) continue;
    (groups['${c.orgId}/${c.tournamentId ?? c.id}'] ??= <Competition>[]).add(c);
  }

  final rows = <OpenRegistration>[];
  for (final entry in groups.entries) {
    final events = entry.value;
    if (!qualifies(events)) continue;

    final first = events.first;
    final tournamentId = first.tournamentId;

    String title;
    DateTime? createdAt;
    String route;

    if (tournamentId == null) {
      title = first.name;
      createdAt = first.createdAt;
      route = Routes.competition(first.orgId, first.id);
    } else {
      final season = ref
          .watch(
            tournamentProvider(
              (orgId: first.orgId, tournamentId: tournamentId),
            ),
          )
          .valueOrNull;
      if (season != null && !seasonQualifies(season)) continue;

      title = season?.name ??
          // "Sports Week 2026 — Cricket" back to "Sports Week 2026", for the
          // one instant between the events arriving and the season document
          // reaching this listener. Same fallback `SeasonCard` uses.
          first.name.split(' — ').first;
      createdAt = season?.createdAt ?? _newestCreatedAt(events);
      route = Routes.tournament(first.orgId, tournamentId);
    }

    final sports = <String>{for (final c in events) c.sportName}
      ..removeWhere((s) => s.isEmpty);

    rows.add(OpenRegistration(
      key: entry.key,
      kind: tournamentId == null
          ? OpenRegistrationKind.tournament
          : OpenRegistrationKind.season,
      orgId: first.orgId,
      title: title,
      // Empty, not [kMultiSportLabel], when no draw names a sport at all.
      // "Multi Sport" is a claim about a season running several, and a record
      // whose sport went missing has not earned it; the row drops the segment
      // instead — see [OpenRegistrationRow].
      sportLabel: switch (sports.length) {
        0 => '',
        1 => sports.first,
        _ => kMultiSportLabel,
      },
      route: route,
      createdAt: createdAt,
    ));
  }

  // Newest first, and a record with no creation date sorts last rather than
  // to the top — an unknown date is not "just now".
  rows.sort((a, b) {
    final x = a.createdAt;
    final y = b.createdAt;
    if (x == null && y == null) return a.title.compareTo(b.title);
    if (x == null) return 1;
    if (y == null) return -1;
    return y.compareTo(x);
  });
  return rows;
}

/// Open, relevant, eligible, and NOT already entered — what the two "Active"
/// tiles count.
///
/// "Still to decide about" is the whole claim an Active tile makes, so a
/// season this profile already holds an entry in is not on it. It has moved
/// to [registeredRegistrationsProvider], where the question is no longer
/// whether to enter but when to turn up, and the two tiles side by side then
/// add up to the number of seasons that exist rather than over-reporting the
/// entered one twice.
///
/// Entered is judged per SEASON, not per draw, because the tile counts
/// seasons. A five-sport sports week whose cricket draw this profile entered
/// is a season they are in, and it leaves the Active tile even though its
/// badminton draw is still open — the other draws are one tap away on the
/// season board that the Registered row opens, which is the board the Active
/// row would have opened too.
final openRegistrationsProvider = Provider<List<OpenRegistration>>((ref) {
  final me = ref.watch(homeProfileProvider);
  // Still loading the profile document, or signed out. Either way there is
  // nobody to judge eligibility for, and a list built without that test would
  // be a list of things this person cannot enter.
  if (me == null) return const [];

  final entered = ref.watch(profileEntryRefsProvider);

  return _rowsFrom(
    ref,
    ref.watch(homeCompetitionPoolProvider),
    qualifies: (events) {
      // Any live entry anywhere under this season or tournament disqualifies
      // the whole group, including one filed for a draw that has since closed
      // — being in the season is what matters here, not which draw carried
      // the entry.
      if (events.any((c) => entered.contains('${c.orgId}/${c.id}'))) {
        return false;
      }
      final open = [
        for (final c in events)
          // `registrationIsOpen` and not `status == registrationOpen`: it is
          // the one place that already knows about a passed deadline, a
          // suspended event and a full field without a waitlist. A row for
          // something the Register button would refuse is worse than no row.
          if (c.registrationIsOpen) c,
      ];
      return open.isNotEmpty && _isEligible(open, me);
    },
    seasonQualifies: _stillTakingEntries,
  );
});

// ---------------------------------------------------------------------------
// What this profile has already entered
// ---------------------------------------------------------------------------

/// Every event the profile in use holds a live entry in, as `orgId/compId`.
///
/// Both shapes of entry, and only this profile's: the ones they filed
/// themselves and the ones a team filed with them named in it. A parent's
/// screen does not carry their child's entries — that is the child's profile's
/// answer, and mixing the two is what made "Registered seasons" a number
/// nobody could attribute.
///
/// Withdrawn and rejected entries are not entries — somebody who pulled out is
/// not registered, and telling them they are is worse than saying nothing at
/// all.
///
/// Read by both lenses, which is what keeps them disjoint: the same set that
/// puts a season on the Registered tile is the set that takes it off Active.
final profileEntryRefsProvider = Provider<Set<String>>((ref) {
  final me = ref.watch(homeProfileProvider);
  if (me == null) return const {};

  final refs = <String>{};
  for (final entries in [
    ref.watch(userEntriesProvider(me.uid)).valueOrNull,
    ref.watch(userTeamEntriesProvider(me.uid)).valueOrNull,
  ]) {
    for (final entry in entries ?? const <MyEntry>[]) {
      switch (entry.registration.status) {
        case RegistrationStatus.withdrawn:
        case RegistrationStatus.rejected:
          continue;
        case RegistrationStatus.pending:
        case RegistrationStatus.confirmed:
        case RegistrationStatus.waitlisted:
          refs.add('${entry.orgId}/${entry.compId}');
      }
    }
  }
  return refs;
});

/// The events those entries are in, however far away they are.
///
/// Most come free: an entry is usually at a club this profile belongs to, and
/// every one of that club's competitions is already streaming for the
/// "Active" buttons. The rest are fetched one document at a time — a person
/// may enter an open event at a club they are not a member of, and an entry
/// whose event cannot be named is an entry that cannot be shown.
final _enteredCompetitionsProvider = Provider<List<Competition>>((ref) {
  final wanted = ref.watch(profileEntryRefsProvider);
  if (wanted.isEmpty) return const [];

  final pool = <String, Competition>{};
  for (final c in ref.watch(homeCompetitionPoolProvider)) {
    pool['${c.orgId}/${c.id}'] = c;
  }
  for (final key in wanted) {
    if (pool.containsKey(key)) continue;
    final parts = key.split('/');
    final c = ref
        .watch(competitionProvider(CompRef(parts.first, parts.last)))
        .valueOrNull;
    if (c != null) pool[key] = c;
  }
  return pool.values.toList();
});

/// What the two "Registered" tiles count: the seasons and tournaments this
/// profile is in AND still has to play.
///
/// Not "everything I have ever entered". An entry in a tournament that
/// finished in March is a result, and results live on the career profile;
/// this section sits among the things a person can act on today, and its
/// count is the answer to "what am I due to turn up for". So a group earns a
/// row only while it still has a live entry of this profile's in an event
/// that has not finished or been called off — and the season above it counts
/// for nothing once the season itself is completed or cancelled, however that
/// leaves the individual draw documents.
///
/// Unlike the open lens there is no entry deadline to respect: entries
/// closing does not end the season for somebody already in it — that is the
/// point of being in it.
final registeredRegistrationsProvider = Provider<List<OpenRegistration>>((ref) {
  final entered = ref.watch(profileEntryRefsProvider);
  if (entered.isEmpty) return const [];

  return _rowsFrom(
    ref,
    ref.watch(_enteredCompetitionsProvider),
    qualifies: (events) => events.any(
      (c) =>
          entered.contains('${c.orgId}/${c.id}') &&
          c.status != CompetitionStatus.completed &&
          c.status != CompetitionStatus.cancelled,
    ),
    seasonQualifies: (season) =>
        season.status != TournamentStatus.cancelled &&
        season.status != TournamentStatus.completed,
  );
});

/// One button's worth: a lens, narrowed to a kind.
///
/// A `family` over the two lists rather than four providers building their
/// own: the order, the grouping and the sport reduction are decided once in
/// [_rowsFrom], so a button's count cannot disagree with the screen it opens.
typedef EntryListKey = ({OpenRegistrationKind kind, RegistrationLens lens});

final entryListProvider =
    Provider.family<List<OpenRegistration>, EntryListKey>((ref, key) {
  final rows = switch (key.lens) {
    RegistrationLens.open => ref.watch(openRegistrationsProvider),
    RegistrationLens.registered => ref.watch(registeredRegistrationsProvider),
  };
  return [
    for (final row in rows)
      if (row.kind == key.kind) row,
  ];
});

/// Whether the season itself is still taking entries.
///
/// Its draws are the authority on what can actually be registered for — that
/// is what [Competition.registrationIsOpen] already decided — so this only
/// looks for the three things a season knows and its events might not yet:
/// it is paused, it is off, or its own published deadline has passed.
bool _stillTakingEntries(Tournament season) {
  if (season.isSuspended) return false;
  if (season.status == TournamentStatus.cancelled) return false;
  final deadline = season.entryDeadline;
  return deadline == null || !DateTime.now().isAfter(deadline);
}

/// Whether the profile in use could enter any one of these draws.
///
/// One eligible draw is enough to earn the row: a player who fits the U-19
/// singles should see the season even though every other draw in it is closed
/// to them, because the season board is where they enter.
///
/// Judged for this profile alone — a draw only somebody else in the household
/// could enter earns nothing here, and shows up on their own home screen
/// instead.
bool _isEligible(List<Competition> open, AppUser person) {
  for (final c in open) {
    if (c.category.check(person, competitionStart: c.startDate).isEligible) {
      return true;
    }
  }
  return false;
}

DateTime? _newestCreatedAt(List<Competition> events) {
  DateTime? newest;
  for (final c in events) {
    final at = c.createdAt;
    if (at != null && (newest == null || at.isAfter(newest))) newest = at;
  }
  return newest;
}

// ---------------------------------------------------------------------------
// The section
// ---------------------------------------------------------------------------

/// "Active seasons & tournaments", or nothing at all.
///
/// Four tiles in two rows: what is open to enter, and what this household is
/// already in, each split into seasons and tournaments.
///
/// Absent rather than empty when all four are zero. An empty state here would
/// be a permanent block of the most valuable screen in the product spent
/// saying "no", on a section whose entire content is opportunities — and a
/// heading that is always there but usually empty is a heading people stop
/// reading. The Events counter above still carries the zero.
class ActiveSeasonsSection extends ConsumerWidget {
  const ActiveSeasonsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    int countOf(RegistrationLens lens, OpenRegistrationKind kind) =>
        ref.watch(entryListProvider((kind: kind, lens: lens))).length;

    final counts = {
      for (final lens in RegistrationLens.values)
        for (final kind in OpenRegistrationKind.values)
          (kind: kind, lens: lens): countOf(lens, kind),
    };
    if (counts.values.every((n) => n == 0)) return const SizedBox.shrink();

    Widget tile(EntryListKey key) => _KindTile(
          entry: key,
          count: counts[key] ?? 0,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Text(
            'SEASONS & TOURNAMENTS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: Ps.faint,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: [
              // A fixed 2×2 rather than a wrap, so the four read as two
              // questions asked twice — what is open, what am I in — with the
              // seasons under each other and the tournaments under each
              // other. A reflowing grid would put "Active tournaments" above
              // "Registered seasons" on some widths and destroy the pairing.
              for (final lens in RegistrationLens.values) ...[
                // `IntrinsicHeight` so the pair matches whichever of them is
                // taller — "Registered tournaments" wraps to two lines at
                // this width and "Active seasons" does not, and two tiles of
                // different heights side by side read as a mistake.
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final kind in OpenRegistrationKind.values) ...[
                        Expanded(child: tile((kind: kind, lens: lens))),
                        if (kind != OpenRegistrationKind.values.last)
                          const SizedBox(width: 10),
                      ],
                    ],
                  ),
                ),
                if (lens != RegistrationLens.values.last)
                  const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        // Owned by the section rather than left to the caller, because the
        // section draws nothing at all on an ordinary day and a gap supplied
        // from outside would double up with the one above it.
        const SizedBox(height: 26),
      ],
    );
  }
}

/// One tile: how many, of what, and the way in.
///
/// The count leads. It is the whole argument for pressing the tile, and at
/// this size a number the eye lands on first is what makes four tiles
/// readable in the half-second the dashboard gets.
///
/// A tile with nothing behind it stays on the screen, greyed and unpressable,
/// where the two-button version used to drop out. Four tiles that come and go
/// independently would relayout the section under the reader every time an
/// entry closed; a fixed grid that dims is steadier to read and still says
/// the true thing.
class _KindTile extends StatelessWidget {
  const _KindTile({required this.entry, required this.count});

  final EntryListKey entry;
  final int count;

  @override
  Widget build(BuildContext context) {
    final empty = count == 0;
    // Green for what is open, blue for what is already entered — the same
    // two meanings the dashboard's counters above already carry, so the
    // colour is not a fifth thing to learn.
    final accent = switch (entry.lens) {
      RegistrationLens.open => Ps.primary,
      RegistrationLens.registered => const Color(0xFF3B82F6),
    };

    return Material(
      color: Ps.surface,
      borderRadius: BorderRadius.circular(Ps.radiusSm),
      child: InkWell(
        borderRadius: BorderRadius.circular(Ps.radiusSm),
        onTap: empty ? null : () => context.push(Routes.entryList(entry)),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Ps.radiusSm),
            border: Border.all(color: Ps.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      letterSpacing: -1,
                      color: empty ? Ps.faint : accent,
                    ),
                  ),
                  const Spacer(),
                  if (!empty)
                    const Icon(Icons.chevron_right, size: 18, color: Ps.faint),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                entry.lens.labelFor(entry.kind),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  color: empty ? Ps.muted : Ps.ink,
                ),
              ),
              const SizedBox(height: 2),
              // "open to enter" and not "available": everything behind an
              // Active tile is something this household can register for
              // today, which is a stronger claim than the Events counter
              // above makes and the reason this section exists at all.
              Text(
                entry.lens.blurb,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, color: Ps.faint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One line: club, season, sport — and a door.
///
/// Shared by the home preview and `ActiveSeasonsScreen` rather than written
/// twice, so the two lists cannot drift into saying the same season
/// differently.
class OpenRegistrationRow extends ConsumerWidget {
  const OpenRegistrationRow({super.key, required this.row});

  final OpenRegistration row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final org = ref.watch(organizationProvider(row.orgId)).valueOrNull;

    // An em dash with ordinary spaces, exactly as the section was specified —
    // "Hyderabad Cricket Club — Summer League 2026 — Cricket" is one sentence
    // a person reads, not three columns.
    const separator = TextSpan(
      text: ' — ',
      style: TextStyle(color: Ps.faint, fontWeight: FontWeight.w400),
    );

    return ListTile(
      // The crest earns its place by carrying no words: it is what makes two
      // clubs' "Summer League 2026" tellable apart at a glance, and the club's
      // name is on the line anyway.
      leading: PsCrest(
        name: org?.name ?? '?',
        logoUrl: org?.logoUrl,
        seed: row.orgId,
        size: 34,
      ),
      title: Text.rich(
        TextSpan(
          children: [
            // Omitted, rather than replaced with a placeholder, while the club
            // document is still in flight or was refused. "? — Summer League
            // 2026" tells a reader less than "Summer League 2026" does.
            if (org != null) ...[
              TextSpan(
                text: org.name,
                style: const TextStyle(
                  color: Ps.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              separator,
            ],
            TextSpan(
              text: row.title,
              style: const TextStyle(
                color: Ps.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            // Same reasoning as the club segment above: a part with nothing to
            // say takes its separator with it rather than leaving the line
            // ending in a dash.
            if (row.sportLabel.isNotEmpty) ...[
              separator,
              TextSpan(
                text: row.sportLabel,
                style: const TextStyle(
                  color: Ps.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, height: 1.25),
      ),
      trailing: const Icon(Icons.chevron_right, size: 18, color: Ps.faint),
      onTap: () => context.push(row.route),
    );
  }
}
