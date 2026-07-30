# PlaySphere OS — Independent Scorecard

**Scope:** working tree at `764b299` + ~28 uncommitted files. 51 items scored on three axes.
**Verification basis:** `flutter analyze` (0 errors, 13 lints), `flutter test` (427 pass),
71 emulator rules tests read, full `lib/` reference graph traced, every screen's state
handling counted. Every score below is traceable to a file or a command.

**Two caveats that apply to every number:**
1. **There is no CI** — no `.github/workflows`, no pre-commit hook. All results are from one
   local run on 30 Jul 2026. Nothing continuously verifies them, which caps every
   production score.
2. ~28 files are uncommitted. This grades the working tree, not the committed branch.

---

## The rubric (so these scores are reproducible)

The previous audit's headline number could not be derived from its own tables. Ours can —
run `docs/score.py` equivalent arithmetic on the tables below and you get the same result.

**UI axis** — only applies to items with a user-facing surface. `N/A` for headless subsystems;
we do **not** award UI points to event sourcing, rules, or math engines.
| Band | Meaning |
|---|---|
| 0 | No widget exists |
| 1–25 | Widget exists but unreachable (orphaned), or data computed and never rendered |
| 26–50 | Reachable, but missing a required control, or no error/empty states |
| 51–75 | Reachable + states + responsive, but unlocalized and/or inaccessible |
| 76–90 | Complete, localized, handles errors, responsive |
| 91–100 | + accessible + performance-verified |

**Functional axis**
| Band | Meaning |
|---|---|
| 0 | No code |
| 1–25 | Code exists, **no caller and no test** — unvalidated by definition |
| 26–50 | Called **or** tested, not both; or a known live defect |
| 51–75 | Called + unit-tested; integration path unexercised |
| 76–90 | Unit + emulator/integration tested, edge cases covered |
| 91–100 | + golden-tested against an external authority (published paper, law of the game) |

**Production axis**
| Band | Meaning |
|---|---|
| 0 | Cannot run in production — required infrastructure absent |
| 1–25 | Runs but denied/broken/unbounded at real scale |
| 26–50 | Happy path only; missing enforcement, feedback, or scale characteristics |
| 51–75 | Deployable with known, documented limitations |
| 76–90 | Deployed, server-enforced, emulator-verified |
| 91–100 | + observability + verified offline/scale behaviour (nothing reaches this without CI) |

---

## Module A — Clubs & Communities

| Item | UI | Fn | Prod | Evidence |
|---|---|---|---|---|
| Club creation & entity types | 62 | 88 | 78 | `create_org_screen.dart` (167 L), 11 `OrgType`s incl. village/individual; rules-tested batch creation (`rules.test.mjs:141-201`). Unlocalized, no error state. |
| Member roles & approval | 60 | 90 | 80 | `members_screen.dart` (263 L); 5-tier roles via `capability.dart`, server-enforced. Rules tests cover self-join, role escalation, re-apply after decline, pending-rewrite tricks (`:203-347`). No empty or error state in UI. |
| Invite codes / links / QR | 55 | 78 | 68 | 6-char codes work; rules resolve codes for *unlisted* clubs and refuse enumerating all codes (`:226-244`). No deep links, no QR, no contacts sync. |
| Club feed & announcements | **8** | 45 | 15 | `club_feed_tab.dart` (184 L) **orphaned** — imported by zero files. Model + repo exist; thin test coverage. |
| Internal free events & registration | 68 | 85 | 72 | `create_competition_screen.dart` (260 L); `maxEntrants` + `withdrawAndPromoteWaitlist` (`community_repository.dart:45-78`). |
| Inter-club challenges | **12** | **30** | **5** | `challenges_screen.dart` (210 L) **orphaned**; `acceptChallenge` **P0-broken** (see F-1); `watchChallengesForOrg` streams the entire global collection. |
| "Looking For" board | **10** | 70 | 20 | `looking_for_board_screen.dart` (252 L, good empty states) **orphaned**. Rules tested incl. author-takeover defence (`:1121-1170`). |
| RSVP (going/maybe/no) & geo discovery | 0 | 5 | 0 | `geo.dart` model exists with zero callers. No RSVP, no proximity search. |
| Notifications (FCM / WhatsApp) | 5 | **12** | 0 | `firebase_messaging` in pubspec; **zero `FirebaseMessaging` references in `lib/`**. `notification_model.dart` has no caller and no test. No dispatcher can exist without a server. |
| i18n adoption | **15** | 80 | 20 | 144 keys × en/hi/te, generated delegates, `l10n_test.dart` green — but **1 of 22** UI files adopts it against **108** hardcoded literals. `language_picker.dart` orphaned. §12.7 MUST violation. |
| **Module A** | **29.5** | **58.3** | **35.8** | |

---

## Module B — Match Day & Scoring (the heart)

| Item | UI | Fn | Prod | Evidence |
|---|---|---|---|---|
| 13 sport engines + RuleConfig | N/A | **96** | 88 | 17 files = 13 sports + 4 shared bases. Zero hardcoded point values; presets (T20/ODI, 21-pt vs BWF 3×15, UKK S2, FIBA 3×3) all via `rule_config.dart`. Golden-tested per sport. |
| Event sourcing & replay | N/A | **95** | 88 | Zero-padded monotonic seq; `update`/`delete` on events denied by rules; `replay()` deterministic. Rules tests prove an event can never be rewritten (`:621`). |
| Live scoring pad | **45** | 85 | 60 | `scoring_screen.dart` (624 L) reachable and dense — but **no undo control** (B-1), **no sync/pending indicator** (B-2), no error state, unlocalized, zero a11y. |
| **Undo / correction control** | **0** | **55** | **25** | **B-1.** `ScoringService.undo()` exists and is correct — and has **zero callers in the app and zero in the tests** (`grep -rn "\.undo("` → nothing). Plugin-level reversal *is* excellently tested (12 cases in `undo_rebuild_test.dart`), so the math is sound and the button does not exist. Violates §2.4 (MUST) and §6 "UNDO always visible". |
| Per-player attribution & box scores | **3** | 88 | 40 | `BoxScore`/`PlayerStatLine`/`PlayerTally` built; 12 plugins override `boxScore`. **No widget in `lib/features/` reads any of it** — the only "scorecard" hit in the UI layer is a helper string at `match_setup.dart:64`. |
| Cricket scorecard depth | 0 | 90 | 40 | `BattingLine`/`BowlingLine`/`FallOfWicket`/`InningsCard` with correct maiden/economy/extras attribution. Never rendered. |
| Scorer lock & assignment | **8** | 90 | 45 | Rules enforce `scorerUids`, monotonic seq, no reopen (`:495-640`). `assign_official_sheet.dart` (191 L) **orphaned** → in practice only the competition creator can score. |
| Match setup: toss & lineups | 65 | 82 | 70 | `match_setup.dart` (356 L) — toss + lineups + player pickers; rules allow the scorer to set both pre-first-ball only. |
| Public spectator live view | **78** | 88 | 82 | `spectator_screen.dart` (317 L) — **the best screen in the repo**: the only one handling error *and* loading *and* empty state. Public route, no account. collectionGroup reads rules-tested for public and unlisted orgs. |
| Offline queue & sync visibility | **0** | 78 | 62 | **B-2.** `ScoringService` exposes a live `_pendingCountController` **stream**, with a doc comment explaining it exists so a badge can show "3 pending". **No UI consumes it.** An offline-first product gives the scorer zero feedback that anything is queued. Airplane-mode behaviour also never verified end-to-end. |
| AI team shuffle | 0 | 80 | 15 | `team_balancer.dart` + `team_balancer_test.dart` (snake draft + local search). No UI invokes it. |
| Dispute / injury / MVP / weather | 0 | 10 | 5 | `FixtureStatus.disputed` exists; no arbitration flow, no logs, no MVP capture. |
| **Module B** | **19.9** | **78.1** | **51.7** | |

---

## Module C — Profiles & Talent

| Item | UI | Fn | Prod | Evidence |
|---|---|---|---|---|
| Glicko-2 ratings | 0 | **97** | 50 | Reproduces Glickman's worked example to 2 dp; volatility + RD bands. Runs client-side at finalize (`scoring_service.dart:223`) with rules guarding `gamesPlayed +1` and a bounded rating delta (`:971`) — genuinely enforced, but not the weekly batch §8.1 specifies. No UI shows a rating. |
| Career stats persistence | 0 | 88 | 55 | Written to `/users/{uid}/career_stats/{sportId}` on finalize; rules reject uid mismatch, future dates and smuggled fields (`:996-1021`). No screen reads them. |
| Cross-sport index | 0 | 85 | 10 | `cross_sport_index.dart` + test. Zero callers. |
| Career profile screen | 0 | N/A | 0 | Does not exist. |
| Scout portal & talent search | 0 | **35** | 10 | `talent_search.dart` has **no test and no caller** — the filtering logic has never been executed. |
| Minor safety & consent enforcement | 0 | **92** | 70 | Strongest security work in the repo: 8 dedicated tests incl. forged-`isMinor` rejection, scout self-minting rejection, minor-self-consent rejection, and access loss after revocation (`:756-880`). Zero consent UI, so the flow is unreachable for real guardians. |
| Verification tiers | 5 | 40 | 30 | Enum + `player_verification_tier.dart`; almost no wiring. |
| Memories / media albums | 0 | 5 | 0 | No `firebase_storage`, no `storage.rules`, no bucket. Structurally impossible today. |
| **Module C** | **0.6** | **63.1** | **28.1** | |

---

## Module D — Government Layer

| Item | UI | Fn | Prod | Evidence |
|---|---|---|---|---|
| Mandal/district aggregators | 0 | 82 | 8 | `gov_aggregator.dart` + `gov_analytics_test.dart`. Zero callers outside domain. |
| Gov dashboards | 0 | N/A | 0 | Do not exist. |
| Export APIs / BigQuery | 0 | 45 | 0 | `gov_export.dart` — no caller, no dedicated test. Needs a server that does not exist. |
| Geo hierarchy on models | 0 | 20 | 5 | `geo.dart` unused; orgs/users carry no mandal/village markers in practice, so no aggregation is possible even if the job existed. |
| **Module D** | **0.0** | **49.0** | **3.2** | |

---

## Module E — Tournament & Standings

| Item | UI | Fn | Prod | Evidence |
|---|---|---|---|---|
| Draw generation (KO / RR / groups / Swiss) | 60 | 92 | 80 | `fixture_generator.dart` + `tournament_test.dart`; renders as a flat fixture list. |
| Standings table | 55 | 90 | 78 | `_StandingsTable` renders live (`competition_detail_screen.dart:375`). Unlocalized; see next two rows. |
| Net run rate | **5** | **100** | 85 | Golden-tested (balls/6, full allotted overs when bowled out, 3 dp) **and wired into `standings_calculator.dart:165-180`** — so it silently orders the table. But the `DataTable` renders 8 columns and **no NRR column** (`:428-436`). The number that decides qualification is invisible to the organizer who must defend it. |
| Tiebreak chains | **10** | 93 | 80 | NRR, Buchholz, Sonneborn-Berger, head-to-head all computed. **E-1:** the table's subtitle is hardcoded to `'Points, then score difference, then wins.'` regardless of the configured chain — it misstates the rule for every cricket league (NRR) and every Swiss event (Buchholz). |
| Knockout advancement | 40 | 94 | 85 | `_maybeAdvanceWinner` in the atomic finalize batch; rules test empty-slot-only advancement, no overwrite, no advance into a scored match (`:557-620`). Visible only as a list row. |
| Scheduler (venue / slot / clash) | 0 | 45 | 5 | `match_scheduler.dart` — no caller, no dedicated test. |
| Graphical bracket tree | 0 | N/A | 0 | Does not exist. |
| **Module E** | **24.3** | **85.7** | **59.0** | |

---

## Module F — Platform & Infrastructure

| Item | UI | Fn | Prod | Evidence |
|---|---|---|---|---|
| Authentication | 62 | 88 | **45** | Google Sign-In works on both platforms with a documented web/native split — functionally sound. But **no phone OTP**, which §2.5/§3 make the primary identity and the basis of the lifelong profile. The target user has no Gmail. |
| Security rules | N/A | **93** | 80 | 887 lines, 71 emulator tests, append-only events, minor safety, collectionGroup scoping, organizer-cannot-overwrite-score. Prod held to 80 by F-1 below, not by the rules' quality. |
| Offline persistence | N/A | 78 | 65 | `persistenceEnabled: true` + unlimited cache (`main.dart:87`); durable `SharedPreferences` queue with UUIDv7 idempotency. Never verified in true airplane mode. |
| Backend Cloud Functions | N/A | **0** | **0** | **No `functions/` directory exists.** `firebase.json` declares hosting + firestore + emulators only. |
| Razorpay payments | 0 | **22** | **0** | 7 domain modules (webhook processor, state machine, Route split, GST, refunds, reconciliation, split-pay). **Zero test files reference payments or razorpay. Zero call sites. No `razorpay_flutter` dependency. No HTTPS endpoint.** Never executed against any payload. |
| Cloud Storage / media infra | 0 | 0 | 0 | Absent entirely. |
| CI/CD & release engineering | N/A | **0** | 5 | No workflows, no hooks, stock `flutter_lints`. "427 tests pass" is a statement about one laptop. |
| Observability & error reporting | N/A | 8 | 10 | `debugPrint` only. No Crashlytics, no structured logging, no alerting. Rating-settlement failures are printed and swallowed (`scoring_service.dart:229`). |
| Accessibility | **5** | N/A | 20 | **F-2: zero `Semantics` widgets and zero `semanticLabel`s in the entire UI.** For a product whose gov dashboards explicitly track para participation, this is a policy risk, not just a polish gap. |
| Performance budget verification | N/A | 0 | 30 | §12.9 sets 100 ms tap→UI and <3 s cold start on a 2 GB device. **No benchmark, trace or perf test exists.** Unmeasured, therefore unmet. |
| **Module F** | **16.8** | **32.1** | **25.5** | |

---

## Rollup

```
┌──────────────────────────────────────┬────────┬────────┬────────┬────────┐
│ Module                               │   UI   │  Func  │  Prod  │ Weight │
├──────────────────────────────────────┼────────┼────────┼────────┼────────┤
│ A. Clubs & Communities               │  29.5  │  58.3  │  35.8  │  0.20  │
│ B. Match Day & Scoring               │  19.9  │  78.1  │  51.7  │  0.30  │
│ C. Profiles & Talent                 │   0.6  │  63.1  │  28.1  │  0.15  │
│ D. Government Layer                  │   0.0  │  49.0  │   3.2  │  0.05  │
│ E. Tournament & Standings            │  24.3  │  85.7  │  59.0  │  0.12  │
│ F. Platform & Infrastructure         │  16.8  │  32.1  │  25.5  │  0.18  │
├──────────────────────────────────────┼────────┼────────┼────────┼────────┤
│ WEIGHTED OVERALL                     │   18   │   63   │   39   │  1.00  │
│ (unweighted mean of all 51 items)    │   17   │   62   │   37   │        │
└──────────────────────────────────────┴────────┴────────┴────────┴────────┘
Weights = share of user-facing surface area. Both methods agree within 2 points.
```

### The UI number needs decomposition — 18 is not "the screens are bad"

| Measure | Score | Meaning |
|---|---|---|
| **Quality of the 11 screens a user can actually reach** | **59** | The delivered screens are decent: responsive (13 files use `responsive.dart`), M3 light+dark theming, sensible empty states. Held below 75 by no localization, no a11y, and swallowed errors. |
| **Coverage of the specified UI surface** | **18** | For roughly two-thirds of CLAUDE.md there is nothing a user can open. |

Report both. Quoting 18 alone slanders good work; quoting 59 alone hides that the product is
mostly unreachable.

---

## Where we differ from the 30-person audit, and why

| Item | Their score | Ours | Reason |
|---|---|---|---|
| Overall UI | 45 | **18** | They awarded 80–100 UI points to four headless subsystems (event sourcing 88, knockout advance 80, NRR 100, and a Functional score to a non-existent `functions/` dir). Removing category errors and counting the *unbuilt* surface drops it. |
| Overall Functional | 89 | **63** | They averaged 8 hand-picked layers, most of which were the well-tested engines. We score all 51 items, and code with no caller **and** no test caps at 25 — that is what "unvalidated" means. |
| Overall Production | 43 | **39** | Closest agreement. Their 43 was also not reproducible from their own tables (the column averages 49.6; their stated formula yields 47.7). |
| Razorpay Functional | 70 | **22** | Zero tests, zero callers, no SDK, never executed. |
| Scout portal Functional | 90 | **35** | Conflated two things: consent *rules* are ~92 (8 tests); `talent_search` is untested and uncalled. |
| NRR UI | 100 | **5** | Never rendered in any widget. |
| Live scoring pad UI | ~85 | **45** | They missed the missing undo and the missing sync indicator. |
| "Tap→UI under 100 ms" | claimed met | **unmeasured** | No perf test exists in the repo. |

---

## The five findings the earlier audits missed

**B-1 — The scoring pad has no undo button.** `ScoringService.undo()` is written and correct;
`grep -rn "\.undo("` across `lib/` and `test/` returns **nothing**. A scorer who mis-taps on a
rural ground has no recovery path, on the screen CLAUDE.md calls "THE HEART", against a MUST
rule that names undo twice (§2.4, §6). *Highest-severity product gap in the repo.*

**B-2 — The sync badge was built for a UI that never consumed it.** `_pendingCountController`
is a live stream whose own doc comment explains it exists so a badge can show queued events.
Nothing reads it. The one promise offline-first makes to a scorer — "your taps are safe" — is
never displayed.

**F-1 — Errors are silently swallowed across the UI: 20 `valueOrNull` vs 1 `.when(`/`hasError`.**
A Firestore `PERMISSION_DENIED` renders as an empty list, not an error. **This is the mechanism
that let the P0 challenge bug go unnoticed** — the feature fails invisibly. Fix this before
anything else, because it is currently hiding defects we have not found yet.

**F-2 — Zero accessibility annotations** in the entire UI (no `Semantics`, no `semanticLabel`),
in a product being pitched to a state government that measures para participation.

**E-1 — The standings table misstates its own tiebreak rule** with a hardcoded subtitle, for
every cricket and chess competition. Combined with the missing NRR column, an organizer cannot
show a disputing captain why a team qualified.

---

## What moves these numbers, ranked by points per day

| # | Action | Cost | Effect |
|---|---|---|---|
| 1 | **Surface errors** — replace `valueOrNull` with `.when(error:…)` on the 20 sites; add a global error surface | 0.5 d | Prod +6, and stops hiding unknown defects |
| 2 | **Add an undo button** to the scoring pad wired to the existing `ScoringService.undo()` + a widget test | 0.5 d | UI +4 on the heart screen; clears a MUST violation |
| 3 | **Show the pending-sync badge** from the existing stream | 0.25 d | UI +2, Prod +4 — makes offline-first legible |
| 4 | **Route the 6 orphans** + attach the official sheet and language picker | 1.5 d | **UI +12** — highest single yield in the repo |
| 5 | **`BoxScoreTable`** on scoring + spectator screens | 1 d | UI +8; converts the whole per-player engine into product |
| 6 | **Add CI** (analyze + test + emulator rules) | 0.5 d | Unlocks every other number; without it nothing stays fixed |
| 7 | **Fix `acceptChallenge`** cross-tenant fixture home | 0.5 d | Prod +5; clears the P0 |
| 8 | **NRR + configured-tiebreak column**, kill the hardcoded subtitle | 0.5 d | UI +3; removes the top dispute risk |
| 9 | **Stand up `functions/`** (asia-south1) | 2 d | **Prod +15** — unblocks payments, FCM, gov, rating batch at once |
| 10 | **i18n sweep** of 108 literals + a lint gate | 2 d | UI +6; clears §12.7 |
| 11 | **Career profile screen** | 1 d | UI +7; surfaces Glicko-2 and career stats already being written |

Items 1–8 total **5.25 days** and move the projection to roughly **UI 45 / Fn 68 / Prod 55**.
Adding 9–11 (5 more days) reaches roughly **UI 58 / Fn 72 / Prod 70**. Nothing exceeds 90 on
the production axis until observability and the §12.9 performance budgets are actually measured.

---

## Verdict

**Engine: 63 overall, but 85–100 wherever it was specified as a formula.** The Glicko-2
implementation, the NRR math, the 13 rule-configured engines and the 71-test rules suite are
professional work that would survive external review.

**Product: 18.** Roughly 20 domain modules and 6 screens are written, correct, and unreachable.
The gap is not competence — it is that the project was built horizontally and no exit criterion
ever required a feature to be *reachable*.

**Platform: 39, capped structurally.** No server, no CI, no observability, no accessibility, no
measured performance. Five features cannot run at all, not because they were built badly but
because the Firebase pivot removed the tier they needed and nothing replaced it.

The 5-day list above is the whole difference between this and a demoable product. That is an
unusually good position to be in — the expensive part (correct, tested domain logic) is done.
