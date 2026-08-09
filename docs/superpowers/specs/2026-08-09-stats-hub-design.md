# Stats Hub: Personal + Club Stats — Design

**Date:** 2026-08-09
**Status:** Approved, ready for implementation plan

## Problem

Player career stats already exist and are fully wired up: Profile → sport →
matches → full match scorecard + memories (`career_profile_screen.dart`,
`player_sport_screen.dart`, the existing `watch`/Spectator route). There is
no equivalent for a club: no aggregated club record, no way to browse a
club's matches by sport, and no stat leaderboards. The two also live in
different places today — this design puts both behind one entry point.

## Goals

- One place to reach both "my stats" and "club stats", branching from a
  single hub screen.
- Club stats should feel as fast and complete as the existing player stats:
  a club's record and full stat tally per sport, its match history with
  scores, and a tap into the exact same full-match-detail screen players
  already use.
- Stat leaderboards ("Orange Cap" style) both inside a club (its own top
  scorers) and globally across the app, linked from the club view.
- Existing history should not be invisible — a one-time backfill populates
  club stats and leaderboards from matches finished before this ships.

## Non-goals

- No changes to how player (`users/{uid}/career_stats`) stats are computed
  or displayed — that flow is reused as-is.
- No live, per-match recompute of the *global* leaderboard — see "Data
  model" below for why that's a scheduled job instead.
- No redesign of the existing match scorecard/memories screen
  (`spectator_screen.dart`) — club stats link into it unchanged.

## Navigation & screen hierarchy

- **Stats Hub** (new, standalone screen): reached via a button on the
  Profile screen, placed below the identity/summary block. Two cards:
  **"My Stats"** and **"Club Stats"**.
- **My Stats** card → navigates into the existing
  `career_profile_screen.dart` flow, unchanged.
- **Club Stats** card → new flow:
  1. **Club list screen** — defaults to the user's own clubs (same source
     `org_picker_screen.dart` uses today: `myMembershipsProvider`), with a
     search box that reaches the full club directory so any club can be
     looked up, not just ones the user belongs to.
  2. Tap a club → **sport picker for that club**, listing only sports the
     club has actually played (mirrors how the player profile only lists
     sports the player has played).
  3. Tap a sport → **Club Sport Stats screen** (new; mirrors the layout of
     `player_sport_screen.dart`):
     - Headline: Played / Won / Lost / Drawn / Points for that club in that
       sport.
     - Full lifetime stat tally for the club (same chip-list rendering
       pattern used for player tallies today — key humanizing, sorted by
       magnitude).
     - "Top scorers in this club" — a short list (3–5 rows) ranked by that
       sport's headline stat(s), plus a **"See full leaderboard"** link.
     - Full match list for the club in that sport (same tile pattern as
       `PlayerMatchTile`) → tap a match → the **existing** Spectator/watch
       route (`Routes.watch`) with its full scorecard + memories. No new
       match-detail screen.
  4. "See full leaderboard" → new **global per-sport leaderboard screen**,
     app-wide, not club-scoped.

## Data model

- **Club career stats** — new collection
  `orgs/{orgId}/career_stats/{sportId}`, deliberately shaped like the
  existing `users/{uid}/career_stats/{sportId}`:
  ```
  { matchesPlayed, won, lost, drawn, tally: Map<String, num>, lastUpdated }
  ```
  Matching the existing shape lets the UI reuse the same tally-rendering
  code (chip list, key humanizing, formatting) that player stats already
  use.

- **Headline stats per sport** — each scoring plugin (cricket, kabaddi,
  badminton, etc. — these already declare `PlayerPrompt`/`ValuePrompt`/etc
  per the existing scoring plugin architecture) gains a `headlineStats`
  field: an ordered list of 1–2 of its own tally keys that represent "the"
  stat for leaderboards, e.g.:
  - cricket → `runs`, `wickets`
  - kabaddi → `raidPoints`, `tacklePoints`
  This is metadata alongside what each plugin already declares — no new
  scoring logic.

- **Global leaderboards** — new collection
  `leaderboards/{sportId}/{statKey}` holding a precomputed top-50:
  `{ uid, displayName, value, rank }[]`. Unlike club/player stats, which
  update live on every match finalize, this is recomputed by a **scheduled**
  function (hourly) rather than on every finalize — ranking every player
  app-wide on every single match would be expensive for a leaderboard that
  doesn't need to be second-fresh.

- **Backfill** — a one-time script that walks every already-finished
  fixture across every org and (re)builds the `orgs/{orgId}/career_stats`
  docs and seeds the leaderboard collection, so pre-launch match history is
  represented.

## Write path (Cloud Functions)

- **Club stats**: extend the existing match-finalize function (the one that
  already writes `users/{uid}/ratings` and `users/{uid}/career_stats`) to
  also resolve each side's club and increment
  `orgs/{orgId}/career_stats/{sportId}` (tally + W/L/D). Additive to a
  trigger that already runs on every finalize — no new trigger.
- **Global leaderboard refresh**: a new, separate scheduled function (e.g.
  hourly) that reads `career_stats` across users for each sport's headline
  stat(s) and rewrites the top-50 in `leaderboards/{sportId}/{statKey}`.
  Deliberately decoupled from match-finalize to keep that hot path fast.
- **Backfill**: a one-off callable/admin function, run once by hand after
  deploy, doing the same aggregation the finalize hook does but over all
  historical finished fixtures. Not scheduled, not triggered — run once,
  then retired.

## Edge cases

- **Draws/ties**: sports like football or chess can end level, so both club
  and player records need a `drawn` count alongside `won`/`lost` — not a
  strict binary.
- **Every match already has a club**: fixtures are always created under a
  club's `orgId` (even "quick match" goes through `/org/{orgId}/...`), so
  there is no finished match with no club to attribute stats to.
- **Backfill idempotency**: the backfill script must *recompute from
  scratch and overwrite*, not increment on top of whatever the live hook
  has already written. Running it after some matches have already gone
  through the live path (or re-running it) must not double-count. This is a
  correctness requirement on the backfill's design, not an implementation
  detail to leave loose.

## Testing

- The aggregation logic (fixtures → tally/W-L-D) should be a pure function,
  unit-tested the same way the existing player `career_stats.dart`
  aggregation is — feed in fixture fixtures, assert the resulting tally.
- The backfill script gets a dry-run mode (compute and print, don't write)
  so counts can be sanity-checked against a couple of known clubs before
  it's trusted to write.

## Reuse summary

| Piece | Status |
|---|---|
| Player stats (Profile → sport → matches → detail) | Existing, unchanged |
| Match scorecard + memories screen | Existing, reused for club matches too |
| Tally chip rendering | Existing pattern, reused for club tally |
| Club membership list | Existing provider, reused as club-list default |
| Stats Hub screen | New |
| Club list + search | New (search is new; membership list is reused) |
| Club Sport Stats screen | New |
| Global leaderboard screen | New |
| `orgs/{orgId}/career_stats/{sportId}` | New collection |
| `leaderboards/{sportId}/{statKey}` | New collection |
| Match-finalize function | Extended (existing trigger) |
| Leaderboard scheduled function | New |
| Backfill script | New, one-time use |
