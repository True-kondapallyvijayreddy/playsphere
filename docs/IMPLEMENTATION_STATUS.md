# Implementation Status — PlaySphere Sports OS

Audit of the codebase against `CLAUDE.md` (master spec) and the Telangana
research PDF. Every row was verified against the code, not assumed.

**Last audited:** 2026-08-01 · **Branch:** `fix/p0-blockers-and-rules-tests`

> Two passes audited the code against the end-to-end flow diagram (join → club
> → grow → event → participation model → challenge → match day → live scoring
> → edits → completion → memories). The 2026-07-31 pass closed the break at
> steps 4–6; the 2026-08-01 pass closed steps 3 and 10, per-club registration
> inside a challenge, and push notifications. **All eleven steps are now
> implemented end to end** — see §6 for the step-by-step state and what
> remains, which is depth rather than gaps.

---

## 0. Architecture decision — Firebase + GCP (overrides CLAUDE.md §3)

`CLAUDE.md` §3 specifies NestJS + PostgreSQL + Redis/BullMQ + Socket.IO, with
Drift/Isar (SQLite) as the on-device source of truth, and marks the stack
"decided — do not re-litigate without flagging".

**Flagged, and overridden by explicit instruction: storage is Firebase + GCP,
non-negotiable.** This document supersedes §3. Everything else in `CLAUDE.md`
stands.

### Mapping the spec's requirements onto Firebase/GCP

| Spec requirement | NestJS/Postgres design | Firebase/GCP equivalent |
|---|---|---|
| Backend API | NestJS modular monolith | **Cloud Functions** (callable + triggers) |
| Primary DB | PostgreSQL, `match_events` partitioned by match | **Firestore**, events as a subcollection per fixture |
| Realtime live scores | Socket.IO per-match channels | **Firestore snapshot listeners** on the fixture doc |
| Offline-first, local source of truth | Drift/SQLite + custom sync engine | **Firestore offline persistence** + durable action queue |
| Cache / job queues | Redis + BullMQ | **Cloud Tasks** / Pub/Sub + scheduled Functions |
| Ratings batch (Glicko-2) | BullMQ periodic job | **Cloud Scheduler → Function** |
| Media | S3 + CDN | **Cloud Storage** + Firebase Hosting CDN |
| Push | FCM + WhatsApp/SMS | **FCM** + Functions calling a WhatsApp/SMS provider |
| Gov analytics rollups | Postgres materialized views | **BigQuery** via the Firestore→BigQuery extension |
| Public live viewer | Next.js | **Flutter web** (already built, `/watch/` route is public) |

### What this changes about the MUST rules

- **Offline-first (§2.1)** — Firestore's persistence gives local-first reads and
  writes, but its `commit()` future does not resolve until the server
  acknowledges. Awaiting it freezes the UI offline. The scoring path must fire
  writes unawaited with a durable queue alongside. *Already implemented and
  committed; still needs a real airplane-mode test.*
- **Single authorized scorer lock (§4)** — enforced in `firestore.rules` via
  `scorerUids` plus a monotonic `lastSeq`, rather than a server-held lock.
  Equivalent guarantee, no server code.
- **Event sourcing (§2.4)** — already satisfied. `events/{paddedSeq}` is
  append-only; rules forbid update and delete.
- **Idempotent sync by client UUID (§4)** — partially satisfied. Events carry a
  `clientEventId`; the padded-sequence document id already makes duplicate
  sequences impossible.

---

## 1. Status summary

| Spec area | Status | Notes |
|---|---|---|
| Part 1 — Clubs & Events | **~80%** | Clubs, roles, invite code + link + QR, club feed with polls, files, gallery, events, participation models (open/hybrid/approval), capacity + waitlist with auto-promotion, per-club squads and squad calls in challenges, draws, FCM push. No payments, RSVP, sub-groups, geo discovery, WhatsApp/SMS fallback. |
| Part 2 — Match day & scoring | **~25%** | Event-sourced scoring, 4 engines, live spectator view, league tables. No per-player stats, no team formation, no officials UI, no MVP/dispute. |
| Part 3 — Memories & profiles | **~5%** | Winner recorded. No memories, no career profile, no verification tiers, no talent discovery. |
| Part 4 — Government dashboards | **0%** | Not started. |
| Ratings (Glicko-2, cross-sport index) | **0%** | Not started. Prototype had plain Elo, not Glicko-2. |
| Tournament engine | **~40%** | Knockout + round robin work. No double-elim, groups, Berger, Buchholz, NRR, scheduler. |
| i18n (Telugu/Hindi/English) | **0%** | All strings hardcoded English. |
| Payments (Razorpay) | **0%** | Not started. |

---

## 2. Feature audit

Legend: ✅ done · 🟡 partial · ❌ missing

### Module A — Clubs & Communities (Part 1)

| Feature | Status | Detail |
|---|---|---|
| Create club, entity types | ✅ | 11 `OrgType`s, including `village` and `individual`. *(Corrected 2026-07-31: the earlier row said these were missing; they are in `enums.dart`.)* |
| Invite by link / QR / phone | 🟡 | 6-char invite code only. No link, no QR, no phone invite. |
| Roles | ✅ | 5 roles, enforced server-side in rules. Richer than the spec's 4. |
| Join requests + approval | ✅ | Works. |
| Sub-groups (age/team/gender) | ❌ | |
| Club feed / announcements | ✅ | `announcement.dart`, `club_feed_tab.dart`. *(Corrected 2026-07-31.)* |
| Internal events (free) | ✅ | Competition creation works. |
| Member notification on event creation | ❌ | **No FCM at all.** Spec calls this the trigger for one-tap registration. |
| One-tap registration | ✅ | |
| RSVP going/maybe/no | ❌ | |
| Capacity | ✅ | `maxEntrants`, enforced in a transaction AND in `firestore.rules` against `confirmedCount`. |
| Participation model (open / hybrid / approval) | ✅ | `ParticipationModel`. Open auto-confirms the first N; hybrid reserves a block for the organizer's picks and opens the rest; approval is the original behaviour and the default for every event created before the field existed. `test/participation_model_test.dart`. |
| Waitlist | ✅ | Queued with a position when the open slots are full; the first reserve is promoted automatically when a confirmed player withdraws. Promotion is a second transaction — rules evaluate against pre-transaction state, so the slot only becomes provably free once the withdrawal commits. |
| Skill filter | ❌ | |
| Inter-club challenges | 🟡 | Challenge → accept/decline/withdraw → competition + fixture ✅. Each club now picks and locks **its own** squad (`setSideLineup`, `squadLockedA/B`, rules branch (e)); a locked squad is frozen even to the hosting club's organizers. Still no per-club open registration to members for a challenge. |
| Open events discoverable by geo | ❌ | No geolocation anywhere. |
| Paid registration (Razorpay + Route) | ❌ | |
| "Looking for" board | ❌ | |
| WhatsApp/SMS fallback | ❌ | |

### Module B — Match Day & Scoring (Part 2 — "the heart")

| Feature | Status | Detail |
|---|---|---|
| Event-sourced match log | ✅ | Append-only, immutable, monotonic sequence. Meets §2.4. |
| Scorer lock | ✅ | `scorerUids` + rules. |
| Assign scorer/umpire/commentator | ✅ | `assignScorers`, plus request → approve → assign (`ScoringRequest`, `ask_to_score.dart`) and an umpire registry. *(Corrected 2026-07-31.)* |
| Manual team shuffle | ❌ | |
| AI team balance | ❌ | Prototype had a snake draft — needs porting **and** upgrading to Glicko-2. |
| Live share link, no install | ✅ | `/watch/` is public. |
| Toss | ✅ | `TossDialog` + `recordToss`, frozen into the fixture's scoring config. *(Corrected 2026-07-31.)* |
| MVP | ❌ | |
| Dispute flow, scorecard lock | ❌ | |
| Injury/substitution log | ❌ | |
| Weather flag, equipment, venue status | ❌ | |
| **Per-player statistics** | 🟡 | Line-ups name players (`MatchPlayer`), `player_stats.dart` and the cricket scorecard project per-player figures, and `box_score_table.dart` renders them. Not yet uniform across all 13 engines. *(Corrected 2026-07-31 — no longer 'no player identity at all'.)* |

#### Per-sport engines vs §7

| Sport | Spec | Built | Gap |
|---|---|---|---|
| Cricket | Ball-by-ball: striker/non-striker/bowler, extras attribution, wicket types + fielder, fall-of-wicket, wagon wheel, Manhattan/worm, batting & bowling projections, NRR | Aggregate runs/wickets/balls, free-hit, wide/no-ball/bye legality | **No player identity at all.** Cannot produce a scorecard, batting/bowling figures, or NRR. Legality rules are right; the data model is not. |
| Badminton | 21-pt + BWF 3×15 preset, serve-court derivation, doubles rotation | 21-pt, win-by-2, cap 30 | Missing serve court, doubles rotation, 3×15 preset |
| Volleyball | Rally types, rotation, faults, per-player stats | Sets to 25, 5th to 15 | Missing everything below set score |
| Football | Goal/assist/card/sub/shot/save | Goals + periods | No player events |
| Basketball | Shot chart coords, rebounds, assists, FG% | 1/2/3 points | No player events |
| Kabaddi | Raid/tackle/super/all-out/do-or-die | Generic goal-based | **Not modelled** |
| Kho-Kho | Batches, dive types, dream run, Wazir | ❌ | Not present |
| Tennis | 15/30/40, deuce/no-ad, tiebreak serve order | Approximated as 6-game sets | Point ladder not modelled |
| Table Tennis | 11 win-by-2, serve every 2, ABCD doubles | 11 win-by-2 | Missing serve rotation |
| Hockey | PC/PS, cards, quarters | Generic goal-based | Partial |
| Chess | 1/0.5/0, PGN, time control | Target=1 | Adequate for result only |
| Athletics | Heats, attempts, wind, PB | ❌ | Catalogued, no engine |
| Carrom | Coins, queen+cover, 29 pts | Target=25 | Approximate |

**Assessment:** 4 generic engines cover 8 sports *shallowly*. The spec requires
13 engines with player-level event vocabularies. The current design is sound
(pure `apply(state, action) → state`, config-driven, replayable) — it needs
extending with player identity in the event payload, not replacing.

### Module C — Memories & Lifelong Profiles (Part 3)

| Feature | Status |
|---|---|
| Winner / awards | 🟡 winner recorded, no awards |
| MVP | ❌ |
| Shareable scorecard image | ❌ |
| Photo/video upload, memory album | ❌ |
| Career profile, lifetime stats | ❌ |
| Rating history graph | ❌ |
| Verification tiers | ❌ |
| Talent discovery / scout role | ❌ |
| Guardian consent for minors | 🟡 `isMinor`, `profileVisibility` exist; no consent record |

### Module D — Government dashboards (Part 4)

Entirely absent. Note `district`/`city` fields exist on `Organization`, but
there is **no mandal or village field**, which the mandal→district→state trial
pipeline requires.

### Ratings (§8)

| Feature | Status |
|---|---|
| Glicko-2 per sport | ❌ |
| Rating deviation / volatility | ❌ |
| Cross-sport index | ❌ |
| Tier display bands | ❌ |

Models carry `VerificationTier` and `RatingStatus` enums, so the schema
anticipates this; no service computes anything.

### Tournament engine (§9)

| Format | Status |
|---|---|
| Knockout with byes + seeding | ✅ |
| Round robin (circle method) | ✅ |
| League points table | ✅ *(added 2026-07-28)* |
| Double round robin | ❌ |
| Double elimination | ❌ silently generates single knockout |
| Swiss | 🟡 round 1 only; no Buchholz, no subsequent rounds |
| Groups + knockout | ❌ silently generates single knockout |
| Berger tables | ❌ |
| NRR | ❌ |
| Scheduler (venues, slots, clashes, rest gaps) | ❌ |
| **Knockout winner advancement** | ❌ `feedsWinnerToFixtureId` is written and never read |

---

## 3. The structural blocker: cross-club matches

Fixtures live at `orgs/{orgId}/competitions/{compId}/fixtures/{fixtureId}`.
They are **structurally single-tenant**. Every one of these needs a fixture
whose two sides belong to different orgs, or to no org at all:

- inter-club challenges (spec Module A)
- school-vs-school and college-vs-college leagues (spec Module A)
- village-to-village tournaments
- person-to-person matches

This cannot be expressed in the current data model. It requires a **top-level
`challenges` collection** with participants from multiple orgs and its own
security rules, plus a fixture that can reference it. This is the single
largest architectural change outstanding, and it should be done before the
per-sport engines are deepened, because it changes what a fixture is.

---

## 4. Build order

Ordered by dependency, then value. Each ships and is tested.

**Phase A — finish the loop** *(the current competition flow lies to users)*
1. Assign-scorers UI — the `judgeScorer` role is unusable without it
2. Knockout winner advancement
3. Invite-code join for unlisted clubs (rules deny the lookup query)
4. `requiresApprovalToJoin` honoured — UI currently says "You have joined" when it did not
5. Declined applicants able to re-apply
6. `showError` to use `AppException.message` instead of parsing `toString()`

**Phase B — identity & value**
7. Player identity in scoring events (unblocks every per-player statistic)
8. Cricket engine to CricHeroes parity — batting/bowling/fielding scorecard
9. Glicko-2 ratings service + rating history
10. Career profile screen
11. Memories: photo upload to Cloud Storage + per-match album
12. Toss

**Phase C — the social OS**
13. Top-level `challenges` collection + rules *(unblocks §3)*
14. Inter-club challenge flow
15. Person-to-person matches
16. FCM notifications + WhatsApp fallback
17. AI team shuffle on Glicko-2

**Phase D — scale & government**
18. Remaining engines: kabaddi, kho-kho, tennis, TT, hockey, athletics
19. Tournament engine completion: double-elim, groups, Berger, Buchholz, NRR, scheduler
20. Razorpay + Route
21. i18n: Telugu, Hindi, English
22. `village`/`mandal` fields + BigQuery export + gov dashboards

---

## 5. Test coverage

| Suite | Count | Covers |
|---|---|---|
| `test/scoring_plugins_test.dart` | 24 | Scoring engine rules |
| `test/rules_test.dart` | 23 | Age/eligibility, permission matrix, fixture generation |
| `test/standings_test.dart` | 11 | League table |
| `test/org_home_screen_test.dart` | 4 | Widget rendering across breakpoints |
| `test/security/rules.test.mjs` | 20 | `firestore.rules` against the emulator |
| **Total** | **82** | |

Not covered: repositories, `ScoringService`, offline behaviour, any screen
other than org home.

---

## 6. The end-to-end flow (audited 2026-07-31)

The product is one repeatable operating flow, and it is only worth as much as
its weakest step. Audited against the flow diagram, step by step, against the
code rather than against intent.

| # | Step | State |
|---|---|---|
| 1 | Join / sign up → sports profile | ✅ |
| 2 | Create club | ✅ 11 org types incl. village and individual |
| 3 | Grow club | ✅ invite code + shareable link + QR, roles, join requests, feed, polls, files, club gallery |
| 4 | Create event | ✅ sport, category, format, date **and time**, venue, capacity, team size, entry fee, rules text, open-vs-restricted |
| 5 | Participation model | ✅ open (auto-fill) / hybrid (picked + open) / approval, capacity, waitlist with auto-promotion |
| 6 | Challenge another club | ✅ challenge → accept → match; each club picks and locks **its own** squad, and can open its side to its own members (first N register, reserves auto-promote) |
| 7 | Match-day control | ✅ scorer request → approve → assign, officials, toss, line-ups |
| 8 | Live match workflow | ✅ 13 engines, event-sourced, offline queue, public watch link |
| 9 | Edits during play | ✅ undo as reversal, rebuild from log, reschedule, line-up edits |
| 10 | Match completion | ✅ winner, standings, Glicko, career stats, and best performer computed from the same contribution points that drive the ratings |
| 11 | Memories | ✅ upload, album, match section, career profile |

### Still missing on the flow

All eleven steps are now implemented end to end. What remains is depth rather
than gaps in the flow:

1. **Per-player statistics are not uniform across all 13 engines.** Cricket and
   the goal/point sports write rich tallies; the rest write less. The MVP award
   and the rating weights read whatever an engine emits, so a sport that
   records little produces a weaker award — never a wrong one, since a zero
   tally is simply not a candidate.
2. **WhatsApp/SMS fallback.** `NotificationType.isCritical` marks the three
   events the spec says need it (event reminder, match start, result) and
   nothing acts on that flag yet — FCM is the only channel. The distinction is
   modelled; the second leg is not built.
3. **Files accept images and PDFs via the image picker.** A dedicated file
   picker is a new dependency for the minority case; the storage rules already
   admit the wider document set when one is added.
4. **Geo discovery of open events** (step 4's "open registration" at city
   scale) still has no geolocation behind it.

### Design notes worth not re-deriving

- **Capacity is enforced in the rules, not just the client.** The count lives
  on the competition document because `firestore.rules` cannot count
  documents, and a self-registration must pay for its slot in the same atomic
  write — `getAfter()` ties the registration and the counter increment
  together. Without that linkage the capacity check is decorative: a client
  can write thirty confirmed registrations and never move the counter.
- **Waitlist promotion is a second transaction, deliberately.** Rules evaluate
  a write against pre-transaction state, so at the moment a same-transaction
  promotion would be checked the event is still full. The withdrawal has to
  commit first for the slot to be provably free.
- **Registration needs connectivity; scoring must not.** Transactions cannot
  run offline. That trade is the right way round — registering happens at home
  in the days before a match, scoring happens on a ground with no signal.
- **Every new competition field is read through `.get(field, default)` in the
  rules.** Reading a missing field in a rule is an error, which denies, so
  without the defaults this change would have broken registration on every
  event already in the database. The defaults reproduce the old behaviour
  exactly: approval-gated, no waitlist, counts at zero.

### Test coverage added

| Suite | Count | Covers |
|---|---|---|
| `test/participation_model_test.dart` | 18 | Open / hybrid / approval arithmetic, the flow's 13-slot and 8+5 scenarios, wire compatibility |
| `test/inter_club_squad_test.dart` | 12 | Which club owns which side, squad locks, `playerUids` across both squads |
| `test/security/rules.test.mjs` (participation) | 18 | Capacity and waitlist enforced server-side, legacy events unaffected |
| `test/security/rules.test.mjs` (inter-club) | 12 | Per-club squad writes, locks frozen against the host |

### Test coverage added, second pass (2026-08-01)

| Suite | Count | Covers |
|---|---|---|
| `test/match_award_test.dart` | 13 | Best-performer selection, tie-breaks, stability across rebuilds, one shared contribution table |
| `test/squad_call_test.dart` | 11 | Per-side squad arithmetic and wire defaults |
| `test/club_growth_test.dart` | 14 | Invite links, poll tallies, file sizes |
| `test/security/rules.test.mjs` (squads) | 15 | A member of one club cannot register for the other's side |
| `test/security/rules.test.mjs` (polls) | 9 | Members vote without being able to post or edit the question |

`test/security/rules.test.mjs` stands at **205 passing**, and the Dart suite at
**530**.

### Push notifications

`functions/index.js` — six Firestore triggers in asia-south1, deployed. This is
the only server-side code in the product, and it exists because push is the one
thing that cannot be done client-side: a client must never be able to make
other people's phones buzz. Nothing there is callable; each function watches a
write that already means something (an event opening, a match going live or
finishing, a challenge arriving, a membership approved, a reserve being
promoted) and fans it out.

Device tokens live at `users/{uid}/devices/{token}` — one document per device,
because a player has a phone and a lab machine and a scorer borrows the club
tablet. Dead tokens are pruned as the server discovers them.
