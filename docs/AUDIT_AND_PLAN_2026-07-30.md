# PlaySphere OS — Code Audit & Task Plan (30 Jul 2026)

Verified against the working tree at commit `764b299` + ~28 uncommitted files.
`flutter analyze` = 13 lints, **0 errors**. `flutter test` = **427 tests pass**.

---

## Part 1 — Corrections to the 29 Jul report

The report was written before/without the last four commits. Five of its headline
items are already done:

| Report claim | Actual state | Evidence |
|---|---|---|
| ❌ "Per-player event payloads lack player IDs (Critical)" | **Built.** `ScoringContext` carries `lineupA/lineupB` of `MatchPlayer`, `player(id)`, `playerName(id)`; `PlayerStatLine`/`BoxScore`/`PlayerTally` framework exists; 12 of 17 plugins override `boxScore`; cricket has a dedicated `BattingLine`/`BowlingLine`/`FallOfWicket`/`InningsCard` model | `lib/domain/scoring/scoring_plugin.dart:137-183`, `lib/domain/scoring/player_stats.dart`, `lib/domain/scoring/plugins/cricket_scorecard.dart` |
| ❌ "Knockout winner advancement unwired" | **Built.** Finalize reads `feedsWinnerToFixtureId` and writes the winner into the target slot | `lib/data/scoring_service.dart:859-872` |
| ❌ "No scorer assignment UI" | **Built but unreachable** — `AssignOfficialSheet` exists and is imported by nothing | `lib/features/competitions/widgets/assign_official_sheet.dart` (orphan) |
| ❌ "No top-level /challenges, single-tenant block" | **Built** — rules, model, repo methods and a screen all exist (screen orphaned; accept path is broken, see B-3) | `firestore.rules:402-428`, `lib/core/models/challenge.dart`, `lib/data/community_repository.dart:80-126` |
| 🟡 "Missing village/individual org types; no waitlist promotion" | **Both built.** 11 `OrgType` values incl. `village`, `individual`; `withdrawAndPromoteWaitlist` promotes the oldest waitlisted entry | `lib/core/models/enums.dart:15-36`, `lib/data/community_repository.dart:45-78` |
| Coin toss missing | **Built** — toss recorded on the fixture, set in match setup | `lib/features/scoring/match_setup.dart`, `firestore.rules:728+` |

**Revised framing.** The report's "38/100" conflates two very different numbers.
The *engine* layer is near-complete and well tested. The *product surface* — the
part a user or a government officer touches — is where the deficit is. A large
amount of correct, tested Dart is currently dead code.

---

## Part 2 — What is actually missing (new findings)

### A. There is no server. At all.
- **No `functions/` directory exists.** `firebase.json` declares only `hosting`,
  `firestore`, `emulators`. No Cloud Functions, no Cloud Tasks, no scheduled
  jobs, no `cloud_functions` dependency.
- Consequence: everything in `lib/domain/payments/` (webhook processor, state
  machine, reconciliation, route split, GST invoice) is **structurally
  unrunnable** — Razorpay webhooks need an HTTPS endpoint. Same for gov
  aggregation, the weekly Glicko-2 rating period (CLAUDE.md §8.1), WhatsApp/SMS
  fallback, and FCM fan-out.
- Glicko-2 currently settles **client-side inside the scorer's finalize call**
  (`lib/data/scoring_service.dart:223`, `:803`). It works, but it is not the
  batch rating period the spec calls for, and a client can be denied mid-way.
- No `storage` block in `firebase.json`, no `storage.rules`, no
  `firebase_storage`/`image_picker` deps → **memories/photos are impossible
  today**, not merely unbuilt.

### B. 6 UI files are orphaned — built, tested-ish, unreachable
Referenced by nothing; the router registers only **9 routes**
(`lib/core/router/app_router.dart:100-174`):
1. `features/competitions/widgets/assign_official_sheet.dart` — scorer delegation
2. `features/competitions/challenges_screen.dart` — inter-club challenges
3. `features/orgs/umpire_registry_screen.dart`
4. `features/community/looking_for_board_screen.dart`
5. `features/orgs/tabs/club_feed_tab.dart` — announcements feed
6. `features/settings/language_picker.dart` — **the only i18n entry point**

### C. 11+ domain modules have zero data/UI callers
Pure Dart, tested, wired to nothing outside `lib/domain`:
`payments/route_split`, `payments/split_pay`, `payments/gst_invoice`,
`payments/payment_webhook_processor`, `payments/payment_state_machine`,
`payments/reconciliation`, `payments/refund_policy`, `gov/gov_aggregator`,
`gov/gov_export`, `scout/talent_search`, `scout/talent_profile`,
`team/team_balancer` (AI shuffle), `rating/cross_sport_index`,
`draw/match_scheduler`, `draw/swiss_pairing`, `standings/tiebreak`,
`core/notifications/notification_model`, `core/models/scout_access`,
`core/models/geo`, `core/models/guardian_consent`.

### D. Box scores are computed and never displayed
`BoxScore` / `InningsCard` are produced by the plugins but **no widget in
`lib/features/` reads them** — the only hit for "scorecard" in the UI layer is a
helper string in `match_setup.dart:64`. Career stats *are* persisted on finalize
(`RatingService.processMatchRatings` → `/users/{uid}/career_stats/{sportId}`,
allowed by `firestore.rules:312`) but there is no profile screen to read them.

### E. i18n is declared, not adopted
144 keys in `app_en.arb` (+ hi, te), generated delegates present, `l10n_test.dart`
passing — but **1 of 22** files under `lib/features`+`lib/shared` uses
`AppLocalizations`, against **108** hardcoded English `Text('…')` literals.
Violates CLAUDE.md §12.7 (MUST).

### F. Identity contradicts the spec
`AuthService` offers **Google Sign-In only** (`lib/core/auth/auth_service.dart:56`).
CLAUDE.md §2.5 / §3 make **phone OTP the primary identity** and the basis of the
lifelong profile. Every rural/low-end user in the target market is locked out today.

### G. Real bugs
- **B-3 (P0): accepting a challenge is denied by rules.**
  `acceptChallenge` writes the fixture under the *challenger's* org
  (`community_repository.dart:100-107`), but `firestore.rules:690` requires
  `canManageCompetitions(orgId)` on **that** org. The accepting club's admin is
  not a member there → `PERMISSION_DENIED`. Only the challenger could accept
  their own challenge. Additionally nobody from the accepting club can ever
  score it (`canScore(orgA)` is false) and a private challenger org makes the
  fixture unreadable to them (`orgIsReadable`).
- **Phantom competition.** The same path hardcodes `compId: 'inter_club_league'`
  with no competition document ever created → competition-scoped screens,
  standings and rule-config resolution have nothing to read.
- **Unbounded query.** `watchChallengesForOrg` streams the *entire* `/challenges`
  collection and filters in Dart (`community_repository.dart:86-91`). Cost and
  latency grow with global usage.
- `sport_rule_repository.dart:11` — dead `_firestore` field (analyzer warning).

### H. Still genuinely 0%
Gov dashboards (Module D UI + export APIs), scout portal UI, career profile UI,
memories/media, Razorpay checkout, FCM/WhatsApp delivery, QR/deep-link/contacts
invites, RSVP going-maybe-no, geo proximity discovery, guardian-consent forms,
MVP voting, dispute-resolution flow, injury/weather logs.

---

## Part 3 — Task plan

Ordering principle: **surface what already works before building anything new.**
Phase 1 converts existing dead code into shipped features at very low cost; it is
by far the highest value-per-day work in this repo.

### Phase 0 — Repo hygiene (0.5 day)
| # | Task | Done when |
|---|---|---|
| 0.1 | Commit the ~28 modified files (models, router, plugins, rules, tests) as reviewed units, not one blob | `git status` clean; tests still 427 pass |
| 0.2 | Decide `README.md` (deleted) — restore or replace; `git add CLAUDE.md` (currently untracked) | Both tracked |
| 0.3 | Clear the 13 analyzer lints incl. dead `_firestore` in `sport_rule_repository.dart` | `flutter analyze` = 0 issues |

### Phase 1 — Reachability sprint · P0 (4–5 days)
| # | Task | Files | Done when |
|---|---|---|---|
| 1.1 | Route + entry point for `AssignOfficialSheet` from competition detail / fixture row | `app_router.dart`, `competition_detail_screen.dart` | An org admin can set `scorerUids` from the UI; a delegated non-creator can score |
| 1.2 | Route `/org/:orgId/challenges` + nav tile for `ChallengesScreen` | `app_router.dart`, `org_home_screen.dart` | Screen reachable |
| 1.3 | **Fix the challenge→fixture model (P0 bug B-3).** Either (a) keep the fixture under the challenger org and grant the accepting org's admins scoped rights via a `participantOrgIds` array on the fixture + rules clause, or (b) hold the match on the `/challenges` doc itself with an events subcollection. Kill the hardcoded `'inter_club_league'`; create a real competition doc or make `compId` nullable end-to-end | `community_repository.dart`, `firestore.rules`, `fixture.dart` | Emulator test: org B admin accepts org A's challenge, a B-side scorer scores it, both orgs read it |
| 1.4 | Narrow `watchChallengesForOrg` to two indexed queries (`fromOrgId`, `toOrgId`) merged client-side | `community_repository.dart`, `firestore.indexes.json` | No full-collection stream |
| 1.5 | Route `LookingForBoardScreen` + `UmpireRegistryScreen`; mount `ClubFeedTab` in `OrgHomeScreen` | `app_router.dart`, `org_home_screen.dart` | All three reachable |
| 1.6 | Mount `LanguagePicker` in an app-bar/settings menu | `app_scaffold.dart` | Locale switchable at runtime |
| 1.7 | **Build the scorecard surface**: a `BoxScoreTable` widget driven by `StatColumn`/`PlayerStatLine`, plus a cricket `InningsCard` view (batting/bowling/FoW). Show on `ScoringScreen` and `SpectatorScreen` | new `features/scoring/widgets/box_score_table.dart`, `scoring_screen.dart`, `spectator_screen.dart` | Per-player figures visible live and to spectators for all 13 sports |
| 1.8 | Add `boxScore` for cricket via the existing scorecard projection; audit the 4 base plugins (`goal_based`, `set_based`, `simple_points`) for coverage | `cricket_plugin.dart`, base plugins | Every registered sport returns a non-empty box score |

### Phase 2 — i18n retrofit · MUST-rule debt (2–3 days)
| # | Task | Done when |
|---|---|---|
| 2.1 | Sweep the 108 hardcoded literals across 21 UI files into `AppLocalizations` | `grep -c "Text('[A-Z]"` in `lib/features` ≈ 0 |
| 2.2 | Fill hi/te for every new key; extend `l10n_test.dart` to fail on key drift between the three arbs | Test fails if a key is missing in any locale |
| 2.3 | Telugu-first read-through of the scoring pad (CLAUDE.md §2.6) | Screenshot review, no overflow at te string lengths |

### Phase 3 — Server foundation + identity (5–7 days)
| # | Task | Done when |
|---|---|---|
| 3.1 | Create `functions/` (TypeScript, asia-south1), add to `firebase.json`, wire `cloud_functions` in `pubspec.yaml` | `firebase deploy --only functions` succeeds |
| 3.2 | **Phone OTP auth** as the primary path, Google retained as secondary; migrate/link existing Google accounts | Sign-in works with an Indian mobile number on Android + web |
| 3.3 | FCM: token registration per user, topic/fan-out function on fixture start, result and membership approval; foreground+background handlers | A member device receives a match-start push |
| 3.4 | `NotificationChannel` abstraction behind `notification_model.dart` with a WhatsApp/SMS provider (Gupshup or Twilio) fallback for the critical three | Fallback fires when FCM token is absent/stale |
| 3.5 | Move Glicko-2 settlement to a scheduled rating-period function; keep the client path as an optimistic write reconciled by the job | Weekly job recomputes ratings idempotently |
| 3.6 | Airplane-mode verification of the offline queue: score a full T20 innings with radios off, kill the app, restore connectivity | Zero events lost; projection matches replay |

### Phase 4 — Lifelong profiles & talent (6–8 days)
| # | Task | Done when |
|---|---|---|
| 4.1 | Career profile screen: per-sport lifetime stats from `/career_stats`, rating history graph with `r ± 2·RD` band, clubs timeline, verification tier badge | Reachable at `/u/:uid`, honours `ProfileVisibility` |
| 4.2 | Guardian consent UI (request, grant, revoke) on top of `guardian_consent.dart` + `consent_policy.dart` | Under-18 profile stays private until an unrevoked consent doc exists; matches `firestore.rules:347` |
| 4.3 | Scout dashboard over `talent_search.dart` (sport, age group, district/mandal, rating percentile, verified-only, recent form) + watchlist/shortlist/trial invite | Consent-gated results; minors excluded without consent |
| 4.4 | Surface `cross_sport_index` on the profile headline with the formula shown in-app (§8.2 transparency) | Index rendered, explainer visible |
| 4.5 | AI team shuffle modal over `team_balancer.dart` — snake draft, predicted balance %, manual drag override | Usable from match setup |

### Phase 5 — Payments (5–7 days, depends on Phase 3)
| # | Task | Done when |
|---|---|---|
| 5.1 | Razorpay UPI checkout in the Flutter client for paid registrations | Test-mode payment completes end-to-end |
| 5.2 | Webhook Function → `payment_webhook_processor` + `payment_state_machine`, idempotent by event id | Double-delivered webhook is a no-op |
| 5.3 | Route split settlement + hold-until-event-complete; GST invoice from `gst_invoice.dart` | Organizer payout minus platform fee reflected in test dashboard |
| 5.4 | Teammate split-pay links; refund/cancellation per `refund_policy.dart`; reconciliation report | Reconciliation matches ledger for a seeded month |

### Phase 6 — Memories & media (3–4 days)
| # | Task | Done when |
|---|---|---|
| 6.1 | Add `firebase_storage` + `image_picker`; `storage.rules`; storage block in `firebase.json` | Deployed rules reject non-members |
| 6.2 | Per-match/tournament memory album with timeline; MVP (voted or stat-computed); shareable scorecard image | Album renders; MVP recorded on the fixture |

### Phase 7 — Match-day completeness (3–4 days)
| # | Task | Done when |
|---|---|---|
| 7.1 | Dispute flow: both captains confirm → scorecard locks; admin arbitration on dispute (`FixtureStatus.disputed` already exists) | Locked scorecard rejects further events server-side |
| 7.2 | Substitution/injury log, weather flag, equipment/ground-status checklist | Recorded as events, visible in the audit trail |
| 7.3 | Wire `match_scheduler` + `swiss_pairing` + `tiebreak` into the tournament UI (venue×slot assignment, clash detection, tiebreak chain display) | Organizer can schedule a 16-team day without clashes |

### Phase 8 — Government layer (7–10 days)
| # | Task | Done when |
|---|---|---|
| 8.1 | Add mandal/village geo markers to org + user models, backfill existing docs | `geo.dart` actually populated |
| 8.2 | Scheduled aggregation function over `gov_aggregator.dart` → `/gov_aggregates` (period × area × sport × age × gender × disability) | Job produces stable aggregates for seeded data |
| 8.3 | Dashboard UI: state → district → mandal → village drill-down, Telangana 14 priority sports + Khelo India age groups, women's/para participation, talent funnel | Officer can drill state→village |
| 8.4 | Export APIs (SATS, SGFI, Khelo India/MyBharat, Fit India) + BigQuery sink over `gov_export.dart`; public transparency view vs admin detail | Export endpoint returns a schema-validated payload |
| 8.5 | DPDP compliance audit pass across the whole surface | Documented audit, minors' data verified non-leaking |

---

## Part 4 — Recommended immediate action

Do **Phase 0 + Phase 1** first, in that order. It is ~5 days and it converts
already-written, already-tested code into visible product: scorer delegation,
inter-club challenges (with the P0 rules bug fixed), the community board, the
umpire registry, the club feed, language switching, and — most importantly —
per-player scorecards for all 13 sports, which is the feature the previous report
wrongly believed was unbuilt at the data layer.

Phase 1.3 is the only item there that needs a real design decision (fixture
ownership for cross-org matches); everything else is wiring.
