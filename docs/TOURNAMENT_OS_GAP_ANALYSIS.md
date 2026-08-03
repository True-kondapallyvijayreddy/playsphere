# Tournament OS — Gap Analysis & Build Plan

**Written:** 2026-08-03 · **Branch:** `fix/p0-blockers-and-rules-tests`

Triggered by a real observation: a badminton tournament in Hyderabad, 38 teams,
10:00 AM start, ran hours late; groups → quarters → semis → final managed by
hand; scoring on paper; results announced on a Telegram channel; nothing
recorded against any player's career.

Every claim below was checked against the code, not assumed. Where a rule
number is a federation figure I could not verify from a current rulebook, it is
marked **[verify]** — those belong in `RuleConfig` anyway (principle §3), so the
code must not depend on my recall of them.

---

## 0. The verdict in one paragraph

**The tournament mathematics is built, tested, and completely disconnected.**
`FixtureGenerator` (1,007 lines) already produces seeded knockouts, full double
elimination with loser routing and bracket reset, groups+knockout with snake
seeding and cross-seeded qualifiers, single/double round robin by the circle
method, and Swiss round one. `swiss_pairing.dart` pairs later rounds.
`match_scheduler.dart` assigns venue × time slot with capacity, clash detection
and rest gaps. `tiebreak.dart` carries nine criteria including Buchholz and
Sonneborn-Berger. `test/tournament_test.dart` covers all of it in 25 tests, and
they pass. **None of it is reachable from the app.** The persistence layer
throws away everything except the plain-knockout winner pointer. So the answer
to "can we do groups → quarters → semis automatically?" is: *the algorithm is
written and correct, and the app physically cannot run it.*

---

## 1. The wiring gap — the highest-value fix in the codebase

### 1.1 The draw is generated with five parameters missing

`lib/data/competition_repository.dart:682`

```dart
final planned = const FixtureGenerator().generate(
  format: competition.format,
  entrants: entrants,
);
```

`generate()` accepts, and this call omits: `shuffleSeed`, `doubleRoundRobin`,
`bracketReset`, `groupSize`, `numGroups`, `qualifiersPerGroup`. A
groups+knockout draw therefore always takes the fallback — roughly four per
group, two qualifiers each — regardless of what the organizer wanted. There is
no UI to set them and no field on `Competition` to store them.

### 1.2 The draw is persisted with four fields dropped

`competition_repository.dart:739-770` builds each `Fixture` and writes only
`feedsWinnerToFixtureId` and `feedsWinnerToSlot`. `PlannedFixture` also carries:

| Dropped field | What it means | Consequence of dropping it |
|---|---|---|
| `bracket` | winners / losers / group / grandFinal / grandFinalReset | Nothing downstream can tell a group match from a knockout match |
| `groupId` | "A", "B", … | **Per-group standings cannot be computed.** No group table → no qualifiers → the knockout stage reads "To be decided" forever |
| `qualifierA` / `qualifierB` | "winner of Group B" | Nothing knows which table position fills which slot |
| `feedsLoserToIndex` / `Slot` | Double-elim loser routing | **The losers bracket is written and nobody ever arrives in it** |

`lib/core/models/fixture.dart` has no field for any of these. This is the exact
mechanism by which the user's question #2 — "8 come out of group A and B, then
quarters and semis fill themselves in" — is designed, tested, and impossible.

### 1.3 Every match in the tournament is scheduled at the same moment

`competition_repository.dart:753-754`

```dart
venue: competition.venue,
scheduledAt: competition.startDate,
```

Every fixture in a 38-team draw gets the identical timestamp and the identical
venue string. There is no per-match time and no concept of a court. **This is
the Hyderabad failure, in one line.** The tournament did not run late because
of bad luck; there was never a schedule — only a start time and a room full of
people waiting to be called.

`MatchScheduler` exists, works, and is never called from anywhere in `lib/`.

### 1.4 Fix cost

Small, and it unlocks the most. Add the four fields to `Fixture`, pass the six
parameters through, add a `resolveQualifiers` step that runs when a group's
table is final, and call `MatchScheduler` at draw time. Roughly:

- `Fixture` model + wire format: **~80 lines**
- `generateDraw` pass-through + persistence: **~60 lines**
- Per-group standings (`StandingsCalculator` filtered by `groupId`): **~40 lines**
- Qualifier resolution on group completion: **~120 lines**
- Loser routing on result (mirrors existing winner advancement): **~50 lines**
- Scheduler invocation + `courtId` on fixture: **~150 lines**

Under a week, and it converts a large body of already-tested dead code into the
product's headline capability.

---

## 2. What is structurally missing (not just unwired)

### 2.1 There is no `Tournament` above `Competition` — the biggest model gap

A `Competition` is **one draw**. A real tournament is a container of many draws
sharing one venue, one day, one pool of courts, and one pool of people:

> Hyderabad District Badminton Championship 2026
> ├── U13 Boys Singles (knockout, 32)
> ├── U13 Girls Singles (knockout, 16)
> ├── U17 Boys Doubles (groups → knockout, 24)
> ├── Senior Men's Singles (groups → knockout, 38)
> ├── Senior Women's Doubles …
> └── … 12 more events

This cannot be expressed. And it is not cosmetic — **the hard scheduling
problem only exists at this level**:

- One player enters singles + doubles + mixed. They must not be scheduled on
  two courts at once, and must get a rest gap between their own matches
  **across different draws**. The current scheduler reasons about one draw in
  isolation, so it cannot see the conflict.
- Six courts are shared by fifteen events. Court allocation is a global
  optimisation, not fifteen local ones.
- "Finish the U13 events by lunch so the kids can go home" is a per-event
  priority constraint that has nowhere to live.

**This is why tournaments run late.** Not the draw, not the scoring — the
cross-event resource contention. It is the single most valuable thing to model
correctly and nothing in the codebase is shaped for it yet.

Required: a `Tournament` entity (dates, venue, courts, officials, entry
deadlines) owning many `Competition` draws; entries at tournament level with a
person appearing in several events; a scheduler that solves across all of them.

### 2.2 A match can only end one way

`Fixture` has `winnerEntrantId` and `isDraw`. Real tournaments produce:

| Result type | Meaning | Different treatment needed |
|---|---|---|
| Normal | Played to completion | Counts everywhere |
| **Walkover (W/O)** | Opponent never arrived | Winner advances; usually **excluded from rating and from per-player stats** |
| **Retired (RET)** | Injury mid-match | Counts as played; partial stats are real and must be kept |
| **Disqualified (DSQ)** | Conduct / eligibility / equipment | Result stands, often with a sanction record |
| **No show / default** | Both absent | Match void |
| **Abandoned (ABD)** | Weather, light, venue | Replay or decided on standings rules |
| **Conceded** | Team withdrew from event | All their remaining fixtures resolve |

`grep` finds no `walkover` and no `no_show` anywhere in `lib/domain/scoring/`.
Only `set_based_plugin`, `cricket_plugin` and `badminton_plugin` know
`retired`; `athletics_plugin` and `set_based_plugin` know disqualification —
and none of it reaches the fixture as a *result type*.

Consequence: a walkover feeds Glicko-2 as a real win, and a retirement feeds
career stats as a completed match. **Both silently corrupt the lifelong profile
that is the product's whole Part 3 promise.** This is a correctness bug, not a
feature request, and it is cheap to fix.

### 2.3 Seeding ignores the ratings the product already computes

`Entrant.seed` is a manually-typed integer. `_seedOrShuffle` sorts by it, and
falls back to `Random(42)` when nobody is seeded — so an unseeded 38-team draw
is a raffle.

Meanwhile `lib/domain/rating/glicko2.dart` and `cross_sport_index.dart` are
built and tested. **Nothing connects them to a draw.** Every federation seeds
from ranking; PlaySphere computes a ranking and then ignores it.

Needed: seed from Glicko rating within (sport, event category), refuse to seed a
player whose RD is too high to be meaningful (an unrated entrant is *unseeded*,
not seed 1), and record the seeding basis on the competition so the draw is
explainable when an organizer is challenged on it.

### 2.4 The draw is a ranked ladder, not a federation draw

`_mirrorSlots` places **every** entrant deterministically by seed. That is a
ladder. A supervised federation draw is different in two ways that matter:

1. **Seeds are pinned, everyone else is random.** Seed 1 top, seed 2 bottom,
   seeds 3–4 drawn randomly into the two remaining quarters, seeds 5–8 drawn
   randomly into the four remaining eighths, and all non-seeds drawn randomly
   into what is left. This is what makes a draw *fair* rather than *predicted* —
   two unseeded players of equal standing should not have their round-one
   opponent determined by list order.
2. **Protection.** Two entrants from the same club (or, at international level,
   the same nation) should not meet in round one where the draw permits an
   alternative. Absent entirely.

Both are well-defined algorithms. Neither exists.

### 2.5 Standings cannot express how real federations break ties

`Tiebreak` has nine criteria applied as a **flat chain over the whole table**.
Two common real-world rules cannot be expressed:

- **Recursive sub-group tiebreak (FIBA, and most volleyball).** When three
  teams tie, you rank them using *only the matches played among those three* —
  and if that still ties two of them, you recurse again. A flat chain over the
  full table gives a different, wrong answer.
- **Ratio-based criteria (FIVB).** Sets ratio (sets won ÷ sets lost) and points
  ratio, which are neither `scoreDifference` nor `scoreFor`. Volleyball's
  standard chain is: match points → sets ratio → points ratio → head-to-head.
- **Match points that are not 3/1/0.** Volleyball awards 3 for a 3-0/3-1 and
  2/1 for a 3-2. Kabaddi leagues award a bonus point for losing narrowly.
  `StandingsCalculator` has no configurable points model of that shape.

### 2.6 No ranking-points ledger — the missing "why does this tournament matter"

Glicko-2 answers *how good is this player*. It does not answer *what have they
won*, and federations run entirely on the latter: BWF, ITTF and every state
association award ranking points as **tournament grade × finishing round**,
accumulated over a rolling window (typically 52 weeks), and that table decides
seeding, selection and funding.

PlaySphere has no concept of a tournament *grade*, no points table, no rolling
window, no ranking list. This is the mechanism that would replace the Telegram
channel — a player wins a district event and their district ranking moves,
visibly, that night.

### 2.7 No recognition layer at all

The user's sharpest complaint: *"no tracking and no encouragement — top players
use a Telegram channel to say they won."* Missing:

- **Public tournament page** — draws, live results, schedule, medal table, one
  shareable link. Only single-match `/watch/` exists.
- **Digital certificates** — winner / runner-up / semi-finalist / participation,
  auto-generated as a shareable image with tournament, date and organizer.
  Roughly a day of work; enormous perceived value at grassroots.
- **Honours board** per club and per district.
- **Head-to-head record** between any two players across their careers.
- **Result-to-profile push** — a notification the moment a result is official:
  "You reached the QF of the Hyderabad District Championship. Your district
  ranking moved 14 → 9."

### 2.8 No match-control layer

- **Officials are not assigned to court-slots.** An umpire registry exists;
  nothing rosters umpire → court → time, or enforces neutrality (an umpire from
  club X should not officiate club X's match).
- **No referee / technical delegate role.** Every federation has one person who
  approves the draw, resolves disputes and signs off results. No dispute flow
  exists at all.
- **No call-room / marshalling state.** Real venues track *called → on court →
  in progress → finished*. Without it there is no way to know a match is late
  because a player is missing rather than because the previous match overran.

### 2.9 Every engine is missing substitutions, timeouts and reviews

Verified by grep across `lib/domain/scoring/`:

- **`substitution` — appears nowhere.** Football, hockey, basketball,
  volleyball, kabaddi and kho-kho all require it. Without it, "minutes played"
  is uncomputable and a per-player stat line is guesswork.
- **`timeout` — only a `RuleConfig` key**, no event. Basketball, volleyball and
  kabaddi need it.
- **`challenge` / `review` — appear nowhere.** Badminton (Instant Review),
  volleyball, basketball, tennis and hockey all have formal challenge systems
  with a retained-if-correct budget.

---

## 3. How Olympics and World Championships actually run a tournament

The operating model is remarkably uniform across sports. PlaySphere implements
roughly stages 5 and 6 of eleven.

| # | Stage | What happens | PlaySphere |
|---|---|---|---|
| 1 | **Qualification** | Quota places by world ranking, continental quotas, host place, universality places | — |
| 2 | **Entry & confirmation** | Entry deadline, confirmation deadline, withdrawal/replacement rules | 🟡 registration exists, no deadlines |
| 3 | **Seeding** | Ranking frozen at a published cut-off date; seeds published before the draw | ❌ manual ints |
| 4 | **Draw** | Public, supervised. Seeds pinned to fixed positions, remainder drawn at random, nation/club protection applied | 🟡 deterministic ladder, no protection |
| 5 | **Schedule** | Sessions, courts, "not before" times, minimum rest between a competitor's matches, TV windows | ❌ one timestamp for everything |
| 6 | **Field of play** | Call room, warm-up allocation, toss/service choice, equipment check | 🟡 toss only |
| 7 | **Officiating** | Referee + umpires + line judges; review/challenge system; formal protest window | 🟡 registry, no rostering, no protest |
| 8 | **Result** | Signed by referee, protest window, then official; W/O, RET, DSQ recorded distinctly | ❌ single winner field |
| 9 | **Progression** | Winners advance, losers to repechage/classification, group tables recompute, next round seeded | 🟡 knockout only; groups never resolve |
| 10 | **Ranking points** | Grade × finishing round into a rolling ranking list | ❌ |
| 11 | **Honours** | Medals, certificates, records ratified, permanent public archive | ❌ |

### 3.1 The formats the majors actually use

**[verify] against current rulebooks before coding — all values belong in
`RuleConfig`.**

- **Badminton (BWF).** Olympic singles: groups of 3–4, group winner advances to
  a knockout of 16. Olympic doubles: 4 groups of 4, top 2 advance to quarters.
  World Championships: straight 128 knockout, 16 seeds. *PlaySphere's
  groups+knockout generator already produces exactly this shape — it just
  cannot persist it.*
- **Table tennis (ITTF).** Olympic singles: straight knockout, seeds byed to
  round 3. Teams: a tie is 5 matches (2 singles, 1 doubles, 2 singles), first to
  3 match-wins. **A "tie made of sub-matches" is a structure PlaySphere cannot
  represent at all** and it is shared by tennis (Davis/BJK Cup), table tennis
  and badminton (Thomas/Uber Cup) — a very common Indian inter-club format too.
- **Tennis (ITF/Olympic).** 64 knockout, 16 seeds from ATP/WTA ranking,
  best-of-3, tiebreak at 6-6, 10-point match tiebreak in the deciding set.
- **Volleyball (FIVB).** Pools → top *n* to quarters. Pool ranking by match
  points (3 for a 3-0/3-1, 2/1 for a 3-2), then **sets ratio**, then **points
  ratio**, then head-to-head. Rally to 25, deciding set to 15, win by 2, no cap.
  Two challenges per set, retained if successful.
- **Basketball (FIBA).** 3 groups of 4 → top 2 plus the 2 best third-placed →
  **a draw for the quarter-finals**, constrained so group opponents cannot meet
  again. Classification is **recursive within the tied subgroup**: wins → head-
  to-head among the tied → point difference among the tied → points scored.
- **Kabaddi (IKF / Asian Games).** Pools → semis → final. 2 × 20-minute halves.
  30-second raid clock, do-or-die raid after consecutive empty raids, super raid
  (3+ points), super tackle when the defence is down to ≤3, all-out bonus with
  full revival. League points models vary and include a bonus point for a narrow
  loss — **must be config**.
- **Kho-Kho (KKFI).** The first Kho Kho World Cup ran in New Delhi in January
  2025 — pools → knockout, men's and women's. Two innings, each an attack turn
  plus a defence turn; defenders enter in batches of 3; points for tags, dives,
  dream run, and Lona for an all-out. **Point values differ between UKK seasons
  and KKFI rules — this is exactly the caveat `CLAUDE.md` §13 already flags.**
  *No software in the world does Kho-Kho properly. This is PlaySphere's single
  clearest opportunity to be definitively best-in-class at something.*

---

## 4. Per-sport engine gaps

Engine quality is **much higher than `IMPLEMENTATION_STATUS.md` claims** — that
document is stale and says "no player identity at all" for cricket while
`cricket_plugin.dart` is 1,093 lines with a full scorecard projection. Verified
event vocabularies:

| Sport | Handles today | Missing for federation-grade |
|---|---|---|
| **Badminton** (576 L) | rally, interval, change_ends, retire, set_first_server, correct, serve-court derivation, doubles rotation, 21 & 3×15 presets | Instant Review (challenge budget), injury timeout, coaching windows, shuttle change, rally length |
| **Cricket** (1,093 L) | Full ball-by-ball + scorecard projection | DLS, super over, powerplay tracking, wagon-wheel capture |
| **Tennis** (456 L) | `point` only | retirement, change-ends, challenge, serve statistics (1st-serve %, break points saved/converted) |
| **Table tennis** (309 L) | point, correct | serve rotation enforcement, expedite rule, doubles ABCD order, let |
| **Volleyball** (432 L) | point, dig, switch_ends | **rotation**, libero, substitution, timeout, challenge, kill/block/ace typing, sets & points ratio for standings |
| **Basketball** (509 L) | shot, rebound, steal, block, turnover, foul, next_period | **substitution** (→ no minutes, no +/−), timeout, team-foul bonus, shot coordinates, free-throw sequences |
| **Kabaddi** (546 L) | raid, tackle, next_period, revival | **all-out event**, do-or-die flag, super raid/tackle flags, substitution, timeout, Super-10 / High-5 milestones |
| **Kho-Kho** (381 L) | tag, kho, batch_entry, end_turn | **dream run**, dive typing (pole/sky), Lona, Wazir, powerplay, per-batch survival time |
| **Football** (456 L) | goal, own_goal, card, foul, shot, save, penalty_missed | **substitution** (→ no minutes), offside, corner, penalty shootout, extra time |
| **Hockey** (380 L) | goal, card, penalty_corner, save, next_period | penalty stroke, shootout, rolling substitutions, PC conversion % |

**The cross-cutting fix is one shared framework, not ten separate ones:**
substitution, timeout, challenge/review and period management are the *same
four concepts* in every sport. Build them once in `scoring_plugin.dart` as
optional mixins that a plugin opts into via `RuleConfig`, and every engine gains
them together. That is the leverage point.

---

## 5. Prioritised build plan

Ordered by value ÷ cost. Every phase ships and is tested.

### Phase T1 — Reconnect the dead code ✅ **DONE 2026-08-03**
1. ✅ `bracket`, `groupId`, `qualifierA/B`, `feedsLoserToFixtureId/Slot`, `courtId` on `Fixture` — `Bracket` and `QualifierSource` moved to `core/models/draw_slot.dart` as wire types
2. ✅ All six generator parameters passed through `generateDraw`, stored as `DrawConfig` / `ScheduleConfig` on `Competition`
3. ✅ `StandingsCalculator.computeGroups` + `isGroupComplete`; `groupStandingsProvider`
4. ✅ `CompetitionRepository.resolveQualifiers` — idempotent, promotes only from complete groups
5. ✅ Loser routing folded into `_maybeAdvanceWinner`, in the same batch as the result
6. ✅ `_planSchedule` calls `MatchScheduler` at draw time; unresolvable placeholders get a "not before" time rather than nothing
7. ✅ `DrawSetupSheet` (groups, qualifiers, courts, match length, changeover, rest gap), `_QualifierCard` ("Update the bracket"), per-group tables with a qualification line, court + time on every match card

**Tests:** `test/qualifier_resolution_test.dart`, 15 new. Suite 593 → 608.

**Two pre-existing breakages found and fixed on the way:** `competition_repository.dart` referenced an undefined `uuidV7()` and never imported `ChunkedBatch`, so `lib/` did not compile; and `test/tournament_test.dart` referenced `PlannedFixture.isBye`, removed when `SlotFill` replaced it, so all 27 tournament tests were silently not running.

*Result: groups → quarters → semis → final fills itself in, on a real timetable across real courts. Exactly what was done by hand in Hyderabad.*

**Still deliberately out of T1:** seeding from Glicko (T4), federation-style random draws (T4), result types (T2), and the cross-event scheduling that only a `Tournament` entity makes possible (T3). The schedule laid down here is per-competition and static — it does not yet reflow when a match runs late.

### Phase T2 — Result integrity *(≈3 days, fixes silent data corruption)*
8. `MatchResultType` enum: normal / walkover / retired / disqualified / no-show / abandoned / conceded
9. Rating and career-stat pipelines respect it (a W/O must not feed Glicko)
10. Withdrawal cascade — a team pulling out resolves its remaining fixtures

### Phase T3 — The tournament container *(≈2 weeks, the structural unlock)*
11. `Tournament` entity owning many `Competition` draws; shared courts, dates, officials
12. Tournament-level entry: one person, many events
13. **Cross-event scheduler** — no player on two courts at once, rest gaps enforced across draws, per-event priority windows
14. **Rolling "not before" times** — recompute the day live as matches finish early or late, and push the change to players. *This is the single feature that fixes waiting-at-the-venue-since-10am.*
15. Match duration model per (sport, category, round) with a variance buffer
16. Call-room states: called → on court → in progress → finished

### Phase T4 — Fair draws & real seeding *(≈1 week)*
17. Seed from Glicko-2 within (sport, category); unrated ⇒ unseeded, never seed 1
18. Federation draw: seeds pinned, remainder randomised from a published seed
19. Club/association protection in round one
20. Draw sheet export (PDF/image), and a public draw page

### Phase T5 — Recognition *(≈1 week, highest emotional return)*
21. Public tournament page: draws, live results, schedule, medal table, one link
22. Digital certificates — winner / runner-up / SF / participation, shareable image
23. **Ranking-points ledger**: tournament grade × finishing round, 52-week rolling window, district/state ranking lists
24. Honours board per club and district; head-to-head records
25. Result-to-profile push: "You reached the QF. District ranking 14 → 9."

### Phase T6 — Federation-grade standings & match control *(≈1 week)*
26. Recursive sub-group tiebreak (FIBA/FIVB shape)
27. Ratio tiebreaks — sets ratio, points ratio
28. Configurable match-points models (3/2/1/0, narrow-loss bonus)
29. Officials rostered to court-slots with neutrality checks
30. Referee role, dispute flow, protest window, scorecard lock

### Phase T7 — Engine depth *(≈2–3 weeks)*
31. **Shared framework first**: substitution, timeout, challenge/review, period management as opt-in mixins in `scoring_plugin.dart`
32. Adopt across all ten engines
33. Per-sport specifics from the §4 table — volleyball rotation/libero, basketball minutes and bonus, kabaddi all-out and milestones, **kho-kho dream run, dive typing, Lona, Wazir**, football and hockey substitutions and shootouts, tennis serve statistics, TT serve rotation and expedite
34. Tie format (Davis Cup / Thomas Cup / ITTF teams) — a fixture composed of sub-matches

---

## 6. Two corrections to the existing docs

1. **`IMPLEMENTATION_STATUS.md` is stale and understates the codebase badly.**
   It reports "Ratings 0%", "Payments 0%", "Government 0%", "Part 3 ~5%" — yet
   `lib/domain/` contains `rating/glicko2.dart`, `rating/cross_sport_index.dart`,
   seven files under `payments/`, five under `gov/`, three under `scout/`, and
   `career/career_stats.dart`, with tests for each. It also claims cricket has
   "no player identity at all" against a 1,093-line plugin with a scorecard
   projection. It should be re-audited before it misleads a planning decision.

2. **107 files are uncommitted**, including entire untracked subsystems
   (`functions/`, `lib/features/analytics/`, `lib/features/home/`). Worth
   committing before starting T1, so this work is reviewable in isolation.
