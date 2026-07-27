# PlaySphere — Build Playbook (Foundation → Real Sports OS)

### How to use this doc
Follow it top to bottom. Each step names the exact file in your current repo,
says what's wrong with it today, and tells you exactly what to change it to.
Don't skip ahead to Part 6 (roles/portals) or Part 8 (deep scoring) — they
all silently depend on Part 1-4 being real first. Building them on top of
the current fake-multi-tenant store just means re-doing them later.

Everything below assumes the repo structure you already have:
`lib/app/play_sphere_store.dart`, `lib/core/router/app_router.dart`,
`lib/domain/phase*.dart`, `lib/features/**`.

---

## PART 0 — Decisions to lock in before writing any code

Don't skip this — going back and forth on these mid-build is what kills
side projects.

**0.1 Backend: Supabase.** You already have `supabase_flutter` in
`pubspec.yaml` (unused today). Use it. It gives you Postgres (so the SQL
schema below just works), real Auth, Realtime (websocket) channels, and Row
Level Security — which is how you'll actually enforce the role/guardian
rules instead of leaving them as comments. Drop `cloud_firestore` and
`firebase_core`/`firebase_messaging` from `pubspec.yaml` now — decide later
if you want Firebase Cloud Messaging back just for push notifications, but
don't run two backends.

**0.2 One data layer, not two.** You currently have an orphaned
`EventRepository`/`EventRepositoryImpl` (Dio/REST) sitting unused next to
`PlaySphereStore`. Kill the Dio/REST path entirely for now. All data access
will go through the Supabase client. Delete or gut
`lib/core/network/api_client.dart`'s Dio setup once you confirm nothing else
depends on it.

**0.3 State management stays Riverpod**, but `PlaySphereStore` stops being
one 620-line god object. It gets replaced by small, focused Riverpod
providers, each backed by a Supabase query scoped to an org/season/fixture
id — never a global unfiltered list again.

**0.4 Auth: Supabase Auth, email+password to start**, phone OTP later once
you're ready for guardian/minor flows (spec §6). Don't build your own auth.

**0.5 Naming: keep `EventEntity`/`sport_competitions` as the name for what
the spec calls "SportCompetition."** Don't rename mid-build; it touches too
many files for no functional benefit right now.

---

## PART 1 — Stand up the real backend

**1.1** Go to supabase.com → New Project → name it `playsphere-dev`. Pick
the region closest to your actual users (Mumbai/Singapore for India).

**1.2** Note the **Project URL** and **anon public key** from
Project Settings → API. You'll need these in step 2.2.

**1.3** Open the SQL Editor in the Supabase dashboard. Paste and run the
core schema in this order (create these as separate migration files under
a new `supabase/migrations/` folder in your repo, numbered, so they're
version controlled — don't just run ad-hoc SQL in the dashboard and forget
what you ran):

- `0001_users_and_orgs.sql` — `users`, `organizations` (with `parent_org_id`,
  `org_type`, `feature_flags` jsonb), `organization_memberships`
  (unique `(org_id, user_id)`, `role` check constraint, `status`),
  `player_profiles` (one row per user, auto-created via trigger on
  `users` insert).
- `0002_seasons_and_competitions.sql` — `sports` (platform-curated
  catalog, not org-owned), `leagues`, `seasons`, `points_configs`,
  `sport_competitions`, `registrations` (unique partial index so only one
  active registration per player per competition).
- `0003_teams.sql` — `teams` (`team_kind` check: `ad_hoc`/`franchise`,
  franchise requires `league_id`+`owner_user_id`), `team_formation_strategies`,
  `franchise_roster_entries`, `auction_lots` (with a trigger: marking a lot
  `sold` must atomically insert the matching roster entry).
- `0004_fixtures_and_scoring.sql` — `stages`, `entrants` (the CHECK
  constraint enforcing exactly one of `player_profile_id`/`team_id` — this
  is the single most important constraint in the whole schema), `fixtures`
  (distinct-entrants check, dispute-window trigger), `match_events`
  (unique `(fixture_id, sequence_no)`), `standings`.
- `0005_ratings_and_trust_safety.sql` — `rating_records`, `rating_history_entries`,
  `flagged_rating_events`, `achievements`, `guardian_links` (with the
  "guardian must be an adult" trigger), `scouting_invites` (with the
  "minor with no verified guardian can never receive an invite" trigger).
- `0006_rls_and_permissions.sql` — enable RLS on every table above, add the
  `has_org_role()` helper function, and the policies for: who can write
  competitions, who can approve registrations, who can see medical notes,
  who can see a minor's profile.

*(If you want, I can generate the actual SQL for all six files right now —
say the word and I'll write them out in full instead of just naming them.)*

**1.4** In Supabase Dashboard → Authentication → Providers, enable
**Email** (on) and leave Phone OTP off for now (you'll turn it on in Part 9
when you build the guardian flow).

**1.5** In Authentication → Policies, turn OFF "Confirm email" for local
dev only (turn it back on before any real user touches this) so you're not
blocked on email delivery while building.

**1.6** Create one throwaway test user via the dashboard's Authentication →
Users → Invite, so you have a real `auth.uid()` to test RLS policies
against before wiring the Flutter side.

---

## PART 2 — Wire real auth into the Flutter app

**2.1** In `pubspec.yaml`, remove `firebase_core`, `firebase_messaging`,
`cloud_firestore`. Keep `supabase_flutter`.

**2.2** In `lib/core/config/env_config.dart`, replace the Dio
`apiBaseUrl`/`environment` fields with `supabaseUrl` and `supabaseAnonKey`,
both via `String.fromEnvironment`, sourced from step 1.2. Never hardcode
these — pass them with `--dart-define` at run/build time, and add a
`.env.example` file to the repo (not committed real values) so the next
dev knows what to set.

**2.3** In `lib/main.dart`, delete the `Firebase.initializeApp(...)` try/catch
block. Replace with:
```
await Supabase.initialize(
  url: EnvConfig.supabaseUrl,
  anonKey: EnvConfig.supabaseAnonKey,
);
```
This must complete before `runApp()` — don't wrap it in a silent
try/catch like the old Firebase call was; if this fails, the app has no
backend and should show an error screen, not proceed into a fake demo mode.

**2.4** Create `lib/core/auth/session_provider.dart` — a Riverpod
`StreamProvider<AuthState>` wrapping
`Supabase.instance.client.auth.onAuthStateChange`. This is now the single
source of truth for "is anyone logged in," replacing the fake
`store.signIn(role)` method in `PlaySphereStore`.

**2.5** Rewrite `lib/features/auth/presentation/screens/login_screen.dart`.
Delete the "pick your role from a dropdown" UI entirely — that's the bug
you found. Replace with a real email+password form calling
`Supabase.instance.client.auth.signInWithPassword(...)`. Add a sign-up
form/screen alongside it that also inserts the `date_of_birth` field
required by `users` (needed for the `is_minor` logic later).

**2.6** In `lib/core/router/app_router.dart`:
  - Remove `initialLocation: '/org/maram-homes'`.
  - Add a `redirect:` callback to `GoRouter` that reads the session
    provider: if signed out and not already heading to `/login` or
    `/splash`, redirect to `/login`. If signed in and sitting on
    `/login`/`/splash`, redirect to the user's default org home (you'll
    need a "which orgs is this user a member of" query — see 3.4 — to pick
    a sensible landing org, or show an org-picker screen if they belong to
    more than one).
  - Add `errorBuilder: (context, state) => NotFoundScreen()` — build a
    trivial `NotFoundScreen` widget, don't leave this as go_router's
    default.

**2.7** Delete `store.toggleRole()` and `store.setActiveRole()` from
`PlaySphereStore` entirely (you'll be deleting the whole store soon anyway,
but do this now so nothing new gets built depending on it). Nothing should
ever let a user pick their own role again — role always comes from a DB
lookup (Part 4).

---

## PART 3 — Fix multi-tenancy (the single most important structural fix)

This is the bug where `store.competitions`/`store.seasons`/etc. return
every row in the system regardless of which org you're viewing. Fix this
before touching roles or portals — everything downstream assumes org
scoping is real.

**3.1** Create `lib/features/organization/data/organization_repository.dart`
with methods like `Future<List<Organization>> getMyOrganizations()` and
`Future<Organization> getOrganization(String orgId)`, each a thin wrapper
over `Supabase.instance.client.from('organizations').select()...`.

**3.2** Create `lib/features/events/data/sport_competition_repository.dart`
with `Future<List<SportCompetition>> getCompetitions({required String
orgId, String? seasonId})` — this MUST filter by `season_id` joined to
`org_id = orgId` in the query itself (`.eq()` clauses), not client-side
filtering after fetching everything.

**3.3** Repeat the same pattern for fixtures, teams, registrations,
standings — every list-fetching method takes the scoping id(s) as required
parameters and pushes the filter into the Supabase query. If you ever
write a method that fetches "all X" with no org/season/competition
parameter, that's the bug recurring — stop and re-scope it.

**3.4** Add `Future<List<OrganizationMembership>> getMyMemberships()` —
returns every org the signed-in user actually belongs to. This powers both
the router redirect in 2.6 and the org-switcher in the drawer (which
currently lists every org in the system, another scoping bug — fix it here
too).

**3.5** Convert each repository method into a Riverpod
`FutureProvider.family` keyed by the scoping id(s), e.g.:
```
final competitionsProvider =
    FutureProvider.family<List<SportCompetition>, ({String orgId, String? seasonId})>(
  (ref, args) => ref.watch(sportCompetitionRepositoryProvider)
      .getCompetitions(orgId: args.orgId, seasonId: args.seasonId),
);
```
This is what finally makes the `orgId` in your route path parameters
*mean something* — every screen reads its data via a provider keyed on the
`orgId`/`eventId` that's actually in the URL, not from a global store.

**3.6** Go through every screen currently reading `store.competitions`,
`store.seasons`, `store.fixtures`, `store.playerProfiles`,
`store.achievements` (organization_home_screen, event_list_screen,
event_detail_screen, fixture_board_screen, live_dashboard_screen,
member_profile_screen, discovery/talent_discovery_screen) and swap each
one to `ref.watch(competitionsProvider((orgId: widget.orgId, seasonId:
null)))` (or the equivalent provider), always passing the id that came
from the widget's constructor/route params — never a store-global value.

**3.7** Specifically fix `MemberProfileScreen`: it must fetch the profile
for `widget.memberId`, not `store.member`. Add
`playerProfileByIdProvider = FutureProvider.family<PlayerProfile, String>`
and use it. This is the fix that makes viewing someone else's career page
possible at all — currently impossible, as you found.

**3.8** Only once 3.1–3.7 are done, delete `PlaySphereStore` and
`lib/app/play_sphere_store.dart` entirely. Don't delete it earlier — you'll
break every screen at once with nothing to fall back on. Deleting it last
also forces you to confirm nothing still secretly depends on it.

---

## PART 4 — Real role model (replace the binary toggle)

**4.1** In Postgres, `organization_memberships.role` already has the real
five values (`owner`, `admin`, `event_manager`, `judge_scorer`, `member`)
per the schema in Part 1. Confirm this matches
`lib/domain/enums.dart`'s `MembershipRole` enum exactly (it already does —
you just need to start using it).

**4.2** Create `lib/core/auth/current_membership_provider.dart`:
```
final currentMembershipProvider =
    FutureProvider.family<OrganizationMembership?, String>((ref, orgId) {
  final userId = ref.watch(sessionProvider).valueOrNull?.session?.user.id;
  if (userId == null) return null;
  return ref.watch(organizationRepositoryProvider)
      .getMembership(orgId: orgId, userId: userId);
});
```
This — a real DB row, scoped to *this specific org* — is now the only
legitimate source of "what can this person do here." Delete every
remaining reference to `PortalRole` in the codebase.

**4.3** Recreate `lib/core/permissions/permission_matrix.dart` (you may
already have a version of this from earlier work — if not, build it now):
a pure function `bool can(MembershipRole role, Capability capability)` with
the exact table from spec §1.3 (owner: everything; admin: everything except
delete-org/transfer-ownership; event_manager: manage competitions + team
formation + scoring, not memberships; judge_scorer: scoring only; member:
register-self only). Every screen and every write path calls
`PermissionMatrix.can(...)` before rendering an action button or attempting
a mutation — but remember (per Part 1.6 in the schema) this is a client-side
fast-fail only; the real enforcement is the RLS policy in Postgres. Never
trust the client check alone.

**4.4** Go through `portal_scaffold.dart` and delete the FilterChip
role-toggle entirely. Replace the app bar's role indicator with a
**read-only** badge showing the current membership's actual role
(`admin`/`event_manager`/etc.), sourced from `currentMembershipProvider`,
never user-settable.

**4.5** Gate the "Create Event" and "Create Club" buttons in
`portal_scaffold.dart` behind
`PermissionMatrix.can(role, Capability.manageSeasonsAndCompetitions)` — they
currently render unconditionally for every signed-in user.

---

## PART 5 — Navigation cleanup

**5.1** Fix the hardcoded fixture id: `portal_scaffold.dart`'s drawer tile
`'Live Scoring Studio' → '/org/${activeOrg.id}/events/tt-2026/live'` must
become a real "my live matches" list screen instead of a direct link to one
match — build `LiveMatchesListScreen` that queries fixtures with
`status = 'live'` scoped to the org, and route the drawer tile there
instead.

**5.2** Add the missing routes:
  - `/p/:slug` → public career page screen (spec §8), no auth
    required, reads `player_profiles.career_page_slug`.
  - `/org/:orgId/seasons` and `/org/:orgId/seasons/:seasonId` → seasons are
    a first-class object in your domain model and currently invisible in
    navigation; add a `SeasonListScreen` and `SeasonDetailScreen`.
  - `/org/:orgId/registrations` (admin-only) → the approval queue you're
    building in Part 6.

**5.3** Switch every `GoRoute` to use the `name:` parameter and navigate
via `context.goNamed('eventDetail', pathParameters: {...})` instead of
hand-built interpolated strings like `context.go('/org/${widget.orgId}/events/${comp.id}')`
scattered across a dozen files. One typo in one of those strings currently
fails silently at runtime with no compile-time check; named routes catch it.

---

## PART 6 — Registration approval workflow

**6.1** Build `RegistrationQueueScreen` (admin/event_manager only) at
`/org/:orgId/events/:eventId/registrations`. Lists registrations with
`status = 'pending'` or `'waitlisted'` for that competition, with
Approve/Reject/Waitlist actions.

**6.2** Approve action calls a Supabase RPC (Postgres function) —
don't just do a client-side `.update()` — that:
  (a) checks the caller's role via `has_org_role()`,
  (b) flips `registrations.status` to `confirmed`,
  (c) if the competition is `entrant_kind = 'individual'`, creates the
      matching `entrants` row atomically in the same transaction.
  Wrap this as one Postgres function (`approve_registration(registration_id
  uuid)`) so it can never partially succeed.

**6.3** Wire the minor/guardian gate here too: if the registrant is a minor
with no verified `guardian_links` row, the approve RPC should refuse and
surface a clear error ("cannot confirm — no verified guardian on file")
rather than silently approving.

---

## PART 7 — Role-specific portals (the actual UX split)

Don't do this until Parts 3-4 are done — a role-specific screen backed by
fake global data is still fake.

**7.1 Owner console** — new screen `OrgSettingsScreen` at
`/org/:orgId/settings`, visible only if `role == owner`: edit org profile,
manage feature flags, view full membership list with role-change controls
(with the "can't demote the last owner" rule enforced both client-side and
by the DB trigger from Part 1.3), transfer ownership, delete org (soft
delete, with a confirmation step).

**7.2 Admin console** — make `OrganizationHomeScreen` this, for
`admin`/`owner`: pending registrations count (link to 6.1's screen),
competitions list with create/edit, quick links to team formation and
finance. This is close to what exists today; mainly needs the data-scoping
fix from Part 3 and the button-gating from Part 4.5.

**7.3 Event manager workspace** — new screen scoped to competitions they're
assigned to (add an `event_manager_assignments` join table if you want
per-competition scoping rather than org-wide event_manager rights — worth
adding now while you're touching the schema). Shows only their
competitions, with create/edit + team formation + scoring, no membership or
finance screens in their nav at all.

**7.4 Judge/scorer view** — new screen `MyScoringAssignmentsScreen`: a
simple list of fixtures where `officiated_by_user_id` (or a new
`fixture_officials` assignment table, better long-term) matches them,
`status IN ('scheduled','live')`. Tapping one goes straight into the
scoring pad for that fixture — no drawer, no other admin nav visible at
all for this role. This is the "single-purpose" experience from the
earlier discussion; build it as its own route/screen, not as a cut-down
admin screen.

**7.5 Participant home** — replace what participants see at
`/org/:orgId` (currently the same `OrganizationHomeScreen` as admins, with
a smaller button set) with a genuinely different `ParticipantHomeScreen`:
"My upcoming matches," "My registrations" (with status), "My rating &
achievement timeline" (pulls from `rating_history_entries` +
`achievements` for their own `player_profile_id`), "Discover competitions"
(a browse/search list of open-registration competitions across orgs they
can join). None of "AI Team Studio," "Premier Auction," or finance screens
should be reachable from here at all — not hidden buttons, just absent
navigation.

**7.6** Update the router (`app_router.dart`) so `/org/:orgId` itself
branches by role at the redirect layer — participants land on
`ParticipantHomeScreen`, admin/owner land on the admin console, event
managers land on their workspace, judge/scorers land on
`MyScoringAssignmentsScreen`. This is a `redirect:` rule keyed off
`currentMembershipProvider`, not a widget-level `if (isAdmin)` branch.

---

## PART 8 — Deep scoring engine (the "CricHeroes-level" rebuild)

Do this after Parts 1-7 so the scoring events actually persist to a real
`match_events` table and broadcast to real spectators, not just a local
`ChangeNotifier`.

**8.1** Design the cricket state shape properly before writing plugin code.
Replace the current flat `{homeRuns, homeWickets, awayRuns, awayWickets}`
in `RunBasedScoringPlugin` with a nested structure:
```
{
  "currentInnings": 1,
  "innings": [
    {
      "battingEntrantId": "...",
      "totalRuns": 0, "totalWickets": 0, "oversBowled": "0.0",
      "extras": {"wides": 0, "noBalls": 0, "byes": 0, "legByes": 0},
      "overs": [
        {"overNumber": 1, "bowlerId": "...", "balls": [
          {"ballNumber": 1, "runs": 4, "extraType": null, "isWicket": false,
           "strikerId": "...", "nonStrikerId": "..."}
        ]}
      ],
      "battingCard": { "playerId": {"runs": 0, "balls": 0, "fours": 0, "sixes": 0, "dismissal": null} },
      "bowlingCard": { "playerId": {"oversBowled": "0.0", "runsConceded": 0, "wickets": 0, "maidens": 0} }
    }
  ],
  "targetScore": null,
  "freeHitNext": false
}
```
**8.2** Rewrite `applyEvent` in `RunBasedScoringPlugin` to handle each
`eventType` from the SRS doc you already wrote (`run_scored`, `wicket`,
`wide`, `no_ball`, `bye`, `leg_bye`, `end_of_over`, `end_of_innings`) as a
pure function: given the nested state above + one event, return new state.
Wides/no-balls add to `extras` and do NOT increment `ball_number` (legal
delivery count). No-ball sets `freeHitNext = true`; consume it on the next
ball.

**8.3** Add validation *before* accepting an event (reject, don't silently
correct): overs can't exceed the competition's configured max; a bowler
can't exceed 20% of total overs; wickets can't exceed `team_size - 1`.
Surface a `ValidationException` (you already have the exception hierarchy
in `app_exception.dart`) back to the scoring UI as a clear error, not a
crash.

**8.4** Add a **projection function**, separate from `applyEvent`, that
folds the finished innings' ball array into `battingCard`/`bowlingCard`/
fall-of-wickets — this is what the Full Scorecard View and post-match
player-stat rollups both read. Never compute strike rate/economy inline in
a widget; compute it once here.

**8.5** `deriveResult` reads `targetScore` vs second-innings `totalRuns`
per the win/loss/tie rules already written in your SRS doc — implement
exactly what's documented there; it's already correct on paper.

**8.6** Repeat steps 8.1-8.5 for one more sport as your second reference
implementation — build `goal_based` (football/kabaddi/basketball) properly
now, with a clock/period sub-state and a foul/card log, instead of leaving
it unimplemented. Once you have two real plugins (run_based, goal_based)
built to this depth, `set_based` (badminton/volleyball, adding serve
possession + deuce state machine) is a much smaller lift by the same
pattern.

**8.7** Every `MatchEvent` insert goes through a Postgres function that
(a) checks `sequence_no` is exactly `last + 1` for that fixture (reject
otherwise — this is your concurrency guard), (b) runs the plugin's
`applyEvent` server-side too if you want tamper-proof scoring (recommended:
duplicate the pure Dart logic as a Postgres/edge function, or better, run
the projection in a Supabase Edge Function written in the same
TypeScript/Dart-transpiled logic so there's one source of truth for the
math — decide this now rather than accepting client-computed results as
truth).

---

## PART 9 — Realtime wiring

**9.1** On the scoring screen, after inserting a `match_events` row,
nothing else is needed for the *scorer's own* view (they already have the
updated local state). For *spectators*, subscribe:
```
Supabase.instance.client
  .channel('fixture:$fixtureId')
  .onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public',
      table: 'match_events', filter: PostgresChangeFilter(column: 'fixture_id', value: fixtureId),
      callback: (payload) => /* fold new event into local state, re-render */)
  .subscribe();
```
This is what finally makes "the whole community watching that event sees
it update live" true — today it isn't, at all.

**9.2** Also subscribe to `standings` changes the same way on the
Standings tab, and `fixtures` status changes on the Fixtures board, so
those screens update without a manual refresh.

---

## PART 10 — Testing you actually need before trusting this with real matches

**10.1** Unit-test every `ScoringPlugin.applyEvent` against a scripted
sequence of balls with a known expected final state — this is cheap to
write and is what catches "wide didn't skip the ball counter" bugs before
a real match hits them.

**10.2** Unit-test `EloRatingService`/rating_service against the worked
examples already in your own spec doc (1400 beats 1600 → ~1424 at K=32) —
you have the expected numbers already written down, just assert them.

**10.3** Write one RLS test per policy in Part 1.3f — Supabase lets you run
SQL as a specific role (`set local role authenticated; set local
request.jwt.claims = '...'`) to confirm a non-member genuinely cannot read
another org's medical notes, a non-guardian genuinely cannot edit a minor's
visibility, etc. This is the only way to know the policies you wrote
actually do what you think.

---

## Suggested build order, week by week (adjust to your pace)

1. **Week 1** — Part 0, Part 1 (schema live in Supabase), Part 2 (real auth,
   login screen rebuilt, router redirect working).
2. **Week 2** — Part 3 (multi-tenancy fix, `PlaySphereStore` deleted).
   Don't move on until switching orgs in the UI actually changes the data
   you see.
3. **Week 3** — Part 4 (real roles) + Part 5 (nav cleanup).
4. **Week 4** — Part 6 (registration approval) + Part 7 (five distinct
   portals).
5. **Weeks 5-6** — Part 8 (cricket + one more sport rebuilt to real
   ball-by-ball depth), Part 9 (realtime).
6. **Week 7** — Part 10 (tests), then go back and harden whatever broke.

Everything after this (venue/officiating marketplace, payments, AI video
highlights — your own Phase 9/10) is genuinely fine to defer; none of it
is load-bearing for the other features the way Parts 1-4 are.

---

## If you want me to just do it

Say which Part to start on and I'll write the actual code/SQL for it
directly against your uploaded repo, file by file, instead of you
translating these instructions yourself.
