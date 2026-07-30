# Why PlaySphere Scored 89 Engine / 45 UI / 43 Production

Meta-review of the 30-person team's granular audit, re-verified against the
working tree at `764b299` + uncommitted changes.

**Short answer:** the scores are a near-perfect photograph of the **test suite**
and of the **specification's density**, not of the team's effort. Every layer
that CLAUDE.md specified to the formula level and covered with golden tests
scored 95–100. Every layer whose only spec line was "build a dashboard," and
which no test can fail on, scored 0–30. The distribution is not random and it is
not a skills problem — it is a *process* signature, and six specific mechanisms
produced it.

---

## Part 1 — Which scores survive verification

These are evidence-backed and I would sign off on them:

| Item | Their score (UI/Fn/Prod) | Verification |
|---|---|---|
| 13 sport engines | 85 / 98 / 90 | Confirmed. Zero hardcoded point values; all params via `rule_config.dart`. 427 tests pass, `flutter analyze` 0 errors. |
| Event sourcing & replay | 88 / 96 / 92 | Confirmed at the *functional* level: zero-padded monotonic seq, append-only enforced at `firestore.rules`, `replay()` + reversal undo. |
| Glicko-2 | 0 / 98 / 20 | Confirmed. Glickman worked example to 2 dp in `glicko2_test.dart`. Zero UI callers — the 0 is correct and is the honest number in this report. |
| Per-player attribution | 15 / 90 / 35 | Confirmed. 12 plugins override `boxScore`; cricket has a full `InningsCard`. No widget in `lib/features/` reads any of it. |
| Inter-club challenges | 40 / 70 / 15 | Confirmed, and worse than scored — see §3.6. |
| i18n | 20 / 85 / 25 | Confirmed. 144 keys × 3 locales, 1 of 22 UI files adopts it, 108 hardcoded literals. |
| Cloud Functions | N/A / 0 / 0 | Confirmed. No `functions/` dir; `firebase.json` = hosting + firestore + emulators. |
| Memories / storage | 0 / 10 / 0 | Confirmed. No `firebase_storage`, no `storage.rules`, no bucket config. |
| Auth | 70 / 70 / 45 | Google-only confirmed; see §2.5 on the double-count. |
| Club feed, Looking-For, umpire registry, language picker | 60–75 UI | Confirmed orphaned — imported by zero files. |

---

## Part 2 — Eight scores that do not survive verification

### 2.1 "Net Run Rate — UI 100/100" is wrong. It is ~5/100.
NRR is computed (`standings_calculator.dart:165-180`) and it **does** influence
row ordering. But the standings `DataTable` renders exactly eight columns —
`# / Entrant / P / W / D / L / +− / Pts` — and **no NRR column**
(`competition_detail_screen.dart:428-436`). A cricket organizer cannot see the
number that decided who qualified. At grassroots level that number *is* the
dispute. Golden-tested invisible math is a 100 on the functional axis and close
to a zero on the UI axis; scoring it 100/100/95 hides the single most
disputable gap in the tournament module.

**Bonus defect found while checking this:** the table's subtitle is hardcoded to
`'Points, then score difference, then wins.'` regardless of the configured
tiebreak chain. For a cricket league it silently lies (the chain is NRR); for a
Swiss chess event it silently lies (Buchholz). `tiebreak.dart` supports both.

### 2.2 Four items were scored on an axis they do not have
"Event Sourcing — UI 88", "Knockout Winner Advance — UI 80", "NRR — UI 100",
and "Backend Cloud Functions — Functional 0" score non-existent surfaces.
Event sourcing has no UI; a directory that does not exist has no function to
grade. Awarding 80–100 UI points to three headless subsystems is what lifts the
UI average from the low 30s to 45. **The UI number is flattered by roughly 10
points.**

### 2.3 "Razorpay — Functional 70" is unearned. It is ~25.
Zero test files reference `payments`, `razorpay`, `route_split`, or
`payment_webhook_processor`. Zero call sites outside `lib/domain`. The code has
never been executed against a Razorpay payload of any kind. Untested,
never-run, unreachable code cannot be 70% functional — it is an unvalidated
design sketch. Same correction applies to `refund_policy` and `reconciliation`,
which have not even a domain-internal caller.

### 2.4 "Scout Portal — Functional 90" is unearned. It is ~50.
Split the item, because the two halves differ enormously:
- **Minor-safety rules: genuinely ~95.** `rules.test.mjs` has 8 dedicated
  guardian-consent tests including forged-`isMinor` rejection, scout
  self-minting rejection, and post-revocation access loss. Excellent work.
- **`talent_search.dart` filtering: ~30.** No test file references `scout` or
  `talent` search at all. No caller.

### 2.5 Auth double-counts one gap across two axes
Missing phone OTP is penalised in Functional (70) *and* Production (45). But
Google Sign-In, as built, works correctly on both platforms with a documented
web/native split. The *functional* score of what exists is ~90; the missing OTP
is a **scope** gap belonging on the production axis only. Charging one gap twice
is how a working subsystem ends up looking half-broken.

### 2.6 Two claims in the rationale document are unmeasured
- "score under 100ms tap-to-UI response" — **there is no performance test,
  benchmark, or trace anywhere in the repo.** CLAUDE.md §12.9 sets that budget
  (plus cold start < 3s on a 2GB device). Nothing measures either. Reporting a
  pass on an unmeasured MUST budget is the one item in this audit I would ask
  QA to retract outright.
- "Material 3 with a stadium dark theme" — `app_theme.dart` is a seeded M3
  `ColorScheme.fromSeed` pair, light **and** dark. Minor, but it suggests the
  theme was described from memory rather than read.

### 2.7 "17 sport plugins" is 13 sports in 17 files
Four of the 17 files are shared base classes / projections —
`goal_based_plugin`, `set_based_plugin`, `simple_points_plugin`,
`cricket_scorecard`. The report says "17 plugins" in one place and "13 sports"
in another. It weakens an otherwise correct claim.

### 2.8 The headline 43 is not reproducible from either stated method
| Method | Result |
|---|---|
| Average the Prod column of the 8-layer table (90,92,90,65,20,15,0,25) | **49.6** |
| The stated formula: 89×0.3 + 45×0.4 + 10×0.3 | **47.7** |
| Reported | **43** |

Both routes land at ~48–50. Also, `Cloud Infrastructure (10)` is an input that
appears **nowhere** in the layer table — it was introduced only in the formula.
And the prior report scored 38 while this one scores 43, with no stated
rebasing. The pattern is a number chosen first and rationalised second.

Separately, the 8 layers are averaged **unweighted**, which makes "i18n
Localization Adoption" count exactly as much as "Core Scoring & Rule Engines."
Weight by user-facing surface area and the honest production number is ~55, not
43 — the engine is a bigger share of this product than a flat mean allows.

**None of this means the audit is wrong in spirit.** Corrected, it reads roughly
**UI 36 / Engine 84 / Production 52**. The shape of the finding — world-class
engine, unwired product, no server — is exactly right.

---

## Part 3 — The actual root causes

### 3.1 The specification's density decided where the work went
CLAUDE.md §7 gives thirteen sub-specs of scoring math with exact formulas, legality
rules and edge cases to golden-test. §6's Module D gets six bullet lines. The team
built, with high fidelity, precisely what was specified precisely. **Where the spec
was a formula, you got 98. Where the spec was a noun phrase, you got 0.** That is
a spec-authoring outcome, not an engineering failure.

### 3.2 "Done" was defined at the domain boundary
Nothing in the workflow required *reachable from a route → rendered → localized*
before an item could be called complete. So `assign_official_sheet.dart` was
written, presumably eyeballed once, and marked done. Then it happened **five more
times**. Six independent orphans is not six mistakes; it is one missing exit
criterion applied six times.

### 3.3 The test pyramid has no top, so CI cannot see the deficit
24 test files, 427 tests, and exactly **one** `testWidgets` test
(`org_home_screen_test.dart`). Pure-Dart domain tests structurally cannot detect:
an unrouted screen, an unrendered `BoxScore`, a hardcoded English literal, or a
missing NRR column. **Compare the two columns:** every layer with golden tests
scored 95–100; every layer with no tests scored 0–30. The score distribution *is*
the test distribution. Add that **there is no CI at all** — no `.github/workflows`,
no pre-commit hook, stock `flutter_lints` — and "427 tests pass" is a statement
about somebody's laptop, not about the repo's state.

### 3.4 The Firebase pivot dropped five responsibilities, and the doc lists four
NestJS→Firestore was the right trade for realtime and offline. But NestJS also
owned **payments webhooks, notification fan-out, media signing, the Glicko-2 rating
period, and gov aggregation**. Firestore replaces none of those. `IMPLEMENTATION_STATUS.md`
documents four substitutions (Postgres, Socket.IO, Drift, Redis/BullMQ) and is
silent on the five orphans. With no server tier left, the only place those five
features *could* be written was pure Dart — which produces the exact signature the
audit measured: **high functional score, zero production score.** The pivot did not
cause bad work; it caused correct work with nowhere to run.

You can see the compensation in the code: Glicko-2 now settles client-side inside
the scorer's finalize call (`scoring_service.dart:223`, `:803`) instead of in the
weekly batch CLAUDE.md §8.1 specifies.

### 3.5 i18n was installed as infrastructure, never enforced as a constraint
144 keys, 3 locales, generated delegates, and a **passing** `l10n_test.dart` — which
validates the `.arb` files, not the screens. Nothing fails when a developer types
`Text('Save')`. A MUST rule with a green test and no enforcement point decays from
day one, and it did: 1 adopter, 108 literals.

### 3.6 The P0 challenge bug: the security test mirrors the rules file, not the call site
This is the most instructive finding in the whole audit, so it is worth stating exactly.

`rules.test.mjs:1087` — `it('lets an admin of the TO club accept the challenge')` —
does this:

```js
updateDoc(doc(db, 'challenges', 'ch1'), { status: 'accepted' })   // ✅ passes
```

But `acceptChallenge()` (`community_repository.dart:118-125`) commits a **batch of
two writes**:

```dart
batch.set(fixRef, fixture.toCreate());        // ← never tested. DENIED by rules:690
batch.update(challengeRef, {'status': 'accepted', ...});  // ← the only half tested
```

The test exercises the second write. The repository's first write lands under the
**challenger's** org path, where `firestore.rules:690` demands
`canManageCompetitions(orgId)` — which the accepting club's admin does not have. A
Firestore batch is atomic, so the whole accept fails with `PERMISSION_DENIED`.

**71 security-rules tests were green while the feature was 100% broken**, because
they were written against the rules file rather than against the client call sites
the rules exist to serve. That is a generalizable process defect: it is very likely
hiding in other multi-write batches too.

---

## Part 4 — What actually moves these numbers

Ranked by score-points per day, using the corrected baseline:

| Action | Cost | Moves |
|---|---|---|
| Route the 6 orphans; attach the official sheet + language picker | 1.5 d | **UI +12** — the single highest-yield item in the repo |
| `BoxScoreTable` widget on scoring + spectator screens | 1 d | UI +8; converts the entire per-player engine into product |
| Add the NRR / configured-tiebreak column + fix the lying subtitle | 0.5 d | UI +3; removes the top dispute risk in cricket |
| Fix `acceptChallenge` (real cross-tenant fixture home) | 0.5 d | Prod +5; clears the only P0 |
| Stand up `functions/` (asia-south1) | 2 d | **Prod +15** — unblocks payments, FCM, gov, rating batch simultaneously |
| i18n sweep of 108 literals | 2 d | UI +6; clears a MUST violation |
| Career profile screen | 1 d | UI +7; surfaces Glicko-2 + career stats already being written |

### Process changes, which matter more than any of the above
1. **Add CI today.** `flutter analyze` + `flutter test` + the emulator rules suite on
   every push. Without it none of the below can be enforced.
2. **Extend Definition of Done to: routed, rendered, localized, widget-tested.** This
   one line would have prevented all six orphans and the i18n decay.
3. **Write security tests against repository methods, not against rules clauses.** Call
   `acceptChallenge()` under the emulator with two real orgs. Rules tests that never
   replay the client's actual batch are theatre — proven above.
4. **Add a lint/grep gate on hardcoded UI strings** so §12.7 cannot decay again.
5. **Measure the §12.9 budgets** (100ms tap, 3s cold start on 2GB) or stop reporting
   them as met.
6. **Score orphaned code as 0 on the functional axis, not 70–90.** Code with no caller
   and no test has unvalidated behaviour by definition. Today's scoring rewards volume
   of written Dart, which is exactly the incentive that produced 20 orphaned modules.

---

## Bottom line for the team

Nobody on that 30-person team did poor work — the Glicko-2 implementation,
the NRR math, the 71-test rules suite and the 13 engines are genuinely strong,
and the audit's honesty about the 0-scores is a good sign about the culture.

What the scorecard is really measuring is that **the project was built in
horizontal layers instead of vertical slices, and the pivot removed the layer
that five features needed to exist in.** The engine is finished and the product
is not connected to it. That is a wiring problem measured in days, not a rebuild
measured in months — which is why the corrected 52 production score is a much
better position than "43/100" makes it sound.
