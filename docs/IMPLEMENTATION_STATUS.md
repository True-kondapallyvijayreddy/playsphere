# Implementation Status — PlaySphere Sports OS

Audit of the codebase against `CLAUDE.md` (master spec) and the Telangana
research PDF. Every row was verified against the code, not assumed.

**Last audited:** 2026-07-28 · **Branch:** `fix/p0-blockers-and-rules-tests`

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
| Part 1 — Clubs & Events | **~35%** | Clubs, roles, invite codes, events, registration, draws work. No notifications, challenges, payments, RSVP, waitlist logic, sub-groups. |
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
| Create club, entity types | 🟡 | `OrgType` has school/college/academy/corporate/community/associations. **Missing `village` and `individual`** — both named in the spec. |
| Invite by link / QR / phone | 🟡 | 6-char invite code only. No link, no QR, no phone invite. |
| Roles | ✅ | 5 roles, enforced server-side in rules. Richer than the spec's 4. |
| Join requests + approval | ✅ | Works. |
| Sub-groups (age/team/gender) | ❌ | |
| Club feed / announcements | ❌ | |
| Internal events (free) | ✅ | Competition creation works. |
| Member notification on event creation | ❌ | **No FCM at all.** Spec calls this the trigger for one-tap registration. |
| One-tap registration | ✅ | |
| RSVP going/maybe/no | ❌ | |
| Capacity | ✅ | `maxEntrants` |
| Waitlist | 🟡 | `RegistrationStatus.waitlisted` exists; no logic promotes anyone. |
| Skill filter | ❌ | |
| Inter-club challenges | ❌ | **Architecturally blocked** — see §3. |
| Open events discoverable by geo | ❌ | No geolocation anywhere. |
| Paid registration (Razorpay + Route) | ❌ | |
| "Looking for" board | ❌ | |
| WhatsApp/SMS fallback | ❌ | |

### Module B — Match Day & Scoring (Part 2 — "the heart")

| Feature | Status | Detail |
|---|---|---|
| Event-sourced match log | ✅ | Append-only, immutable, monotonic sequence. Meets §2.4. |
| Scorer lock | ✅ | `scorerUids` + rules. |
| Assign scorer/umpire/commentator | ❌ | `assignScorers` exists in the repo with **no UI caller**; only the draw creator can score. |
| Manual team shuffle | ❌ | |
| AI team balance | ❌ | Prototype had a snake draft — needs porting **and** upgrading to Glicko-2. |
| Live share link, no install | ✅ | `/watch/` is public. |
| Toss | ❌ | Named by you; absent from spec, prototype and build. |
| MVP | ❌ | |
| Dispute flow, scorecard lock | ❌ | |
| Injury/substitution log | ❌ | |
| Weather flag, equipment, venue status | ❌ | |
| **Per-player statistics** | ❌ | **The largest single gap.** No engine records who did what — see below. |

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
