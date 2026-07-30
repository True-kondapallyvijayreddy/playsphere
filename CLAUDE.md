# CLAUDE.md — Sports OS (India / Telangana)

> This file is the master specification and working instructions for the AI developer agent (Claude Opus 5) building **Sports OS** — an all-in-one grassroots sports platform for India, starting with Telangana. Read this file fully before writing any code. Treat every rule marked **MUST** as non-negotiable.

---

## 1. Project Identity & Vision

**Problem.** India's grassroots sports ecosystem is broken into silos: no shared infrastructure access, no communication layer between players/clubs/schools/villages, and no way to discover talent. People play sports as isolated individuals. Existing apps solve one slice each — venue booking (Playo, Hudle, KheloMore), cricket-only scoring (CricHeroes), Western team admin (TeamSnap, Spond). Nobody combines it all.

**Vision.** One operating system for sports where **any individual, community, school, college, or village** can:
1. Create clubs, invite members, and organize free internal events or inter-club challenges (Part 1).
2. Run match day end-to-end: team shuffling (manual + AI), sport-specific ball-by-ball / point-by-point scoring, and live score sharing — the **heart of the OS** (Part 2).
3. Declare winners, capture memories (photos/awards/MVP), and build **lifelong portable player profiles** — a player from a Hyderabad community club moves to Delhi University and 10 years later anyone can still see his full verified career stats (Part 3).
4. Feed aggregated participation data into **government dashboards** supporting the Telangana Sports Policy 2025 (CM Revanth Reddy's vision of sports as integral to society) and the National Sports Policy 2025 / Khelo Bharat Niti — tracking everything across sports, areas (mandal → district → state), and ages (Part 4).

**North-star benchmark:** be to *all sports* what CricHeroes is to cricket (40M+ registered cricketers, ~4.9M matches scored in 2025), plus club/event management, plus government analytics.

---

## 2. Non-Negotiable Product Principles

1. **Offline-first. MUST.** Scoring happens on grounds with zero/poor connectivity in rural Telangana. The local device DB is the source of truth; sync is background and eventual. A full match must be scorable in airplane mode.
2. **Scoring and club management are free forever.** Monetize organizers (PRO tiers), payments take-rate, venues, and B2G dashboards — never the scorer or player.
3. **Rules are configuration, not code. MUST.** Point values, match formats, target scores, best-of counts, timers vary by league/season (e.g., kho-kho UKK point changes, badminton's 21-pt vs upcoming 3×15 system). Every scoring engine reads a `RuleConfig` — never hard-code point values.
4. **Event sourcing for matches. MUST.** Every match is an append-only log of `MatchEvent`s (ball, point, raid, goal…). Scorecards, stats, and graphs are pure projections of the event log. UNDO = append a reversal event. Never mutate the log.
5. **One lifelong identity.** Phone-number-based identity that persists across clubs, cities, decades. Design profile IDs to be linkable to future national athlete registries (KIRTI/MyBharat).
6. **Multi-language from day one:** Telugu, Hindi, English. All strings through i18n; Telugu-first UX review.
7. **Minor safety & DPDP compliance. MUST.** Guardian consent for under-18 talent visibility; consent-gated scout access; India DPDP Act data handling.
8. **Low-end-device performance.** Target ₹8k Android phones, 2GB RAM, spotty 4G.

---

## 3. Tech Stack (decided — do not re-litigate without flagging)

| Layer | Choice | Notes |
|---|---|---|
| Mobile client | **Flutter** (Dart) | Single codebase; offline maturity |
| Local DB | **Drift** (SQLite) or **Isar** | Reactive streams; `is_synced` flags |
| State mgmt | **Riverpod** | |
| Backend API | **NestJS** (Node/TypeScript) | Modular monolith → services later |
| Primary DB | **PostgreSQL** | Partition match_events by match_id |
| Cache/queues | **Redis** + BullMQ | Sync ingestion, notifications, rating jobs |
| Realtime | **WebSockets** (Socket.IO) | Per-match channels for live viewers |
| Media | S3-compatible object storage + CDN | Memories, photos |
| Push | FCM + **WhatsApp/SMS fallback** | WhatsApp critical for low-engagement users |
| Payments | **Razorpay** — UPI, **Route** (split settlements), Subscriptions | UPI ≈ 85% of India digital payment volume |
| Public live view | Lightweight web app (Next.js) | Spectators follow via link, no install |
| Auth | Phone OTP (primary), optional email/OAuth | |

---

## 4. High-Level Architecture

```
Flutter App (offline-first)
 ├─ Local SQLite (source of truth on device)
 ├─ Scoring Engines (per-sport Dart modules, pure functions over event log)
 └─ Sync Engine (delta push/pull, client UUIDs, is_synced queue)
        │ HTTPS / WebSocket
        ▼
NestJS API  ──►  PostgreSQL (relational core + partitioned match_events)
 ├─ Sync Ingestion (idempotent by client UUID)
 ├─ Ratings Service (Glicko-2 batch per rating period)
 ├─ Tournament Engine (brackets, schedules, points tables, NRR)
 ├─ Stats Aggregator (match → career materialized rollups)
 ├─ Payments (Razorpay webhooks, Route splits)
 ├─ Notifications (FCM + WhatsApp/SMS)
 ├─ Media Service (signed uploads → S3/CDN)
 └─ Gov Analytics (materialized views: area × sport × age × gender)
        │
        ▼
Next.js public live-score viewer + Gov/Admin dashboards
```

**Sync protocol (MUST implement exactly):**
- Client generates UUIDv7 for every record. All writes hit local DB first with `is_synced=false`.
- Background sync pushes unsynced records in causal order (match → events), pulls deltas since `last_sync_cursor`.
- Server ingestion is idempotent (upsert by UUID). Conflicts: last-write-wins by device timestamp, EXCEPT match event logs — a match has a **single authorized scorer lock**; only the locked scorer's events are accepted, eliminating scoring conflicts by design. Scorer handoff is an explicit server-mediated transfer.
- Scorecard is reconstructable purely from the event log at any time on any device.

---

## 5. Core Data Model

Implement as PostgreSQL schema + mirrored Drift schema. Key entities (columns abbreviated; add audit fields `created_at`, `updated_at`, `client_uuid` everywhere):

- **users** — id, phone, name, dob, gender, photo, district, mandal, village, languages[], verification_tier (`self` | `scorer_verified` | `association_verified`), guardian_user_id (minors), external_ids jsonb (future KIRTI/MyBharat linkage)
- **clubs** — id, type (`individual`|`community`|`school`|`college`|`village`|`academy`|`corporate`), name, location (geo + district/mandal), logo, settings jsonb
- **memberships** — user_id, club_id, role (`owner`|`admin`|`member`|`guest`), status, subgroup (age group/team/gender)
- **events** — id, club_id, sport, title, description, venue (text + lat/lng), starts_at, capacity, waitlist_enabled, fee_amount (0 = free), visibility (`internal`|`open`|`invite`), skill_filter, status
- **event_registrations** — event_id, user_id/team_id, status (`registered`|`waitlisted`|`cancelled`), payment_id
- **challenges** — from_club_id, to_club_id, sport, proposed_slots[], status (`pending`|`accepted`|`declined`|`rescheduled`) → creates event on accept
- **tournaments** — id, event_id, format (`knockout`|`round_robin`|`double_round_robin`|`double_elim`|`swiss`|`groups_knockout`|`league`), seeding jsonb, points_config jsonb, tiebreak_config jsonb (NRR, Buchholz, head-to-head…), rule_config_id
- **teams** — id, scope (club/tournament/event), name, players[]
- **matches** — id, tournament_id/event_id, sport, team_a, team_b (or players for individual sports), venue, scheduled_at, scorer_user_id (lock), officials jsonb, status (`scheduled`|`live`|`completed`|`disputed`|`locked`), result jsonb, mvp_user_id, rule_config_id
- **match_events** — id (UUIDv7), match_id, seq, event_type, payload jsonb, actor refs, occurred_at, is_synced. **Append-only. Partitioned by match_id.** Polymorphic payload per sport (see §7).
- **innings / sets / periods** — match_id, index, structure per sport (projection tables, rebuildable)
- **player_match_stats** — match_id, user_id, sport, stats jsonb (projection)
- **player_career_stats** — user_id, sport, lifetime aggregates jsonb (materialized rollup; rebuild job)
- **ratings** — user_id, sport, glicko_rating, rd, volatility, games_count, updated_at; plus **cross_sport_index** (user_id, score, components jsonb)
- **rule_configs** — id, sport, name, config jsonb, owner (system|league|club) — ALL sport parameters live here
- **payments** — id, event_id, payer_user_id, amount, razorpay refs, split jsonb (Route), status, refunds
- **media / memories** — id, match_id/tournament_id, uploader_id, url, type, caption; **memory_albums** auto-compiled per match/tournament
- **scout_access** — scout_user_id, scope filters, consent records (guardian consent for minors), watchlists, shortlists, trial_invites
- **gov_aggregates** — materialized: period × state/district/mandal/village × sport × age_group × gender × disability → participants, matches, events, clubs, venue_utilization

---

## 6. Feature Modules (Parts 1–4)

### Module A — Clubs & Communities (Part 1)
- Create club (any entity type), invite via phone/link/QR, join requests + approvals, roles, subgroups.
- Club feed, member directory, announcements.
- **Internal events (free):** creation pushes notification to all members → one-tap register, RSVP (going/maybe/no), capacity + waitlist.
- **Inter-club challenges:** challenge → accept/decline/counter-schedule → fixture auto-created. School-vs-school, college-vs-college league support.
- **Open events:** discoverable by geo + sport + date + skill; anyone within limits can register.
- **Paid registration:** Razorpay UPI checkout; **Route** auto-split (organizer payout minus platform fee); teammate split-pay; refund flows; GST receipt.
- Discovery: "Looking for" board (players/teams/scorers/umpires/grounds — CricHeroes pattern).
- Notifications: FCM push + WhatsApp/SMS fallback for critical items (event reminder, match start, result).

### Module B — Match Day & Scoring (Part 2 — THE HEART)
- **Team formation:** manual drag-drop shuffle; captain-pick; **AI balance** — snake-draft by Glicko-2 rating then local-search optimize to minimize predicted team rating differential; handles late joins/dropouts.
- **Officials:** assign scorer (lock), umpire/referee, commentator; scorer quality score over time.
- **Live sharing:** public web link per match, WebSocket-fed, no app install needed.
- **Per-sport scoring engines** (§7): tap-optimized UIs, ≤2 taps per routine event, UNDO always visible, works fully offline.
- **Post-event extras:** MVP (voted or stat-computed), substitution/injury log, dispute flow (both captains confirm result → scorecard locks; admin arbitration on dispute), weather flag, equipment checklist, venue/ground status.

### Module C — Memories & Lifelong Profiles (Part 3)
- Winner declaration, awards, MVP; shareable scorecard image/link.
- Photo/video upload → auto **Memory album** per match/tournament with timeline.
- **Career profile:** every match ever played, per-sport lifetime stats, rating history graph, teams/clubs timeline, awards, memories. Portable across clubs/cities forever.
- Verification tiers: self → scorer-verified → association-verified.
- **Talent discovery:** scout role with filtered search (sport, age group, district/mandal, rating percentile, verified-only, recent form), watchlists, shortlist, trial invites. Consent-gated; guardian approval for minors. Designed to feed SAI/SATS mandal→district→state trials and KIRTI-style talent ID.

### Module D — Government Dashboards (Part 4)
- Hierarchical dashboards: state → district → mandal → village.
- KPIs: participants (by sport/age/gender/disability), clubs, events, matches, venue utilization, talent-pipeline funnel (identified → trialed → selected), women's & para participation.
- Sport filters aligned to Telangana's 14 priority sports; age filters aligned to Khelo India age groups.
- Export APIs for SATS, School Games Federation of India, Khelo India/MyBharat, Fit India.
- Public transparency views + admin-only detail. Positioned as the participation-data backbone for Telangana Sports Policy 2025 (₹465 cr budget, YIPESU, TSDF) and NSP 2025.

---

## 7. Per-Sport Scoring Engine Specifications

Each engine = (1) event vocabulary, (2) projection rules → scorecard/stats, (3) `RuleConfig` schema, (4) tap-first UI. All numeric parameters below are **defaults in RuleConfig**, never constants.

### 7.1 Cricket (flagship — benchmark: CricHeroes)
- **Per-ball event payload:** innings, over_no, ball_in_over, striker, non_striker, bowler, runs_off_bat (0–7+, incl. overthrows), extra {type: wide|no_ball|bye|leg_bye, runs}, wicket {type: bowled|caught|lbw|run_out|stumped|hit_wicket|retired, fielder?, keeper?, end?}, is_free_hit, wagon_wheel {angle_deg, distance_norm} (store from striker origin), commentary?
- **Legality rules:** 6 legal balls/over; wides & no-balls don't count and are re-bowled. Wide = +1 charged to bowler. No-ball = +1 charged to bowler, next ball free hit (limited-overs), byes/leg-byes off it recorded under extras. Byes/leg-byes → team total only (NOT batsman, NOT bowler; byes count against keeper stats).
- **Wickets:** run-out NOT credited to bowler; record fall-of-wicket (score + over.ball); credit catcher/keeper/fielder.
- **Batting projections:** runs, balls, SR = runs/balls×100, avg = runs/dismissals, 4s/6s, 50s/100s, not-outs.
- **Bowling projections:** overs (decimal = balls/6, i.e., 47.2 ov = 47.333), maidens, runs conceded = off-bat + wides + no-balls (NOT byes/leg-byes), wickets (excl. run-outs), economy = runs/overs, bowling avg, bowling SR.
- **Fielding:** catches, stumpings, run-outs (direct/assist).
- **Graphs:** wagon wheel, Manhattan, worm, run-rate, partnerships.
- **NRR (tournament):** (total runs scored / total overs faced) − (total runs conceded / total overs bowled), 3 decimals; if a side is bowled out, use its FULL allotted overs. Overs always decimalized by balls/6.
- **RuleConfig:** overs per innings (T10/T20/ODI/custom), balls per over, free-hit on/off, DLS on/off (Phase 2), wide/no-ball run values, super over rules, powerplay overs.
- Officials: 2 umpires, scorer, optional third umpire.

### 7.2 Football
- Events: goal {scorer, assist?, minute, type: open|penalty|own_goal|free_kick}, penalty_missed, card {yellow|red, player, minute}, substitution, foul, corner, offside, shot {on|off target}, save, period boundaries, extra_time, penalty_shootout {round, taker, result}.
- Stats: goals, assists, minutes, cards, clean sheets (GK), saves, shots; league points 3/1/0 (configurable).
- RuleConfig: squad size (5/7/11-a-side), half length, halves, extra time, shootout format.

### 7.3 Badminton
- Rally scoring. Default: game to **21, win by 2, cap 30**; best of 3. **BWF-approved 3×15 (cap 21, interval at 8) expected 2026 — MUST be selectable via RuleConfig.**
- Serve court auto-derived: server's score even → right, odd → left. Doubles service rotation tracked.
- Events: rally {winner, server, serve_side, stroke_count?, fault_type?}, interval (11 or config), change_ends, game_end.
- Stats: points on serve vs receive, games won, longest rally, deuce record.
- RuleConfig: target score, cap, best_of, interval point.

### 7.4 Volleyball
- Rally scoring; best of 5; sets to 25 win-by-2 (no cap); 5th set to 15 win-by-2.
- Events: rally {winner, point_type: attack|block|ace|opponent_error}, rotation, substitution, timeout, fault {net_touch|double_hit|foot_fault|four_hits|rotation_fault}.
- Stats: points, kills, blocks, aces, digs, assists, service errors.
- RuleConfig: sets, set target, deciding-set target, timeouts.

### 7.5 Kabaddi
- Default: 2 × 20-min halves; 7 on court + 5 subs; 30-second raid clock.
- Raid event: {raider, defenders_touched[], bonus (touching bonus line with 6+ defenders on court), result: touch_points|empty|tackled, is_do_or_die (after 2 consecutive empty raids), is_super_raid (3+ pts)}.
- Tackle event: {defenders[], is_super_tackle (≤3 defenders on court → 2 pts)}.
- All-out: opposing team fully out → +2 pts + full revival. Track revivals (in order out).
- Stats: raid points, tackle points, super raids, super tackles, Super-10s (10 raid pts), High-5s (5 tackle pts), do-or-die success.
- RuleConfig: half length, raid clock, bonus rules, super-tackle threshold, point values.

### 7.6 Kho-Kho (modern / Ultimate Kho Kho style)
- 2 innings; each = attack turn + defense turn (default **7 min** each; traditional 9 — config). Defenders enter in **batches of 3**.
- Events: kho_given, tag_out {attacker, defender, skill: regular|pole_dive|sky_dive|self_out}, batch_entry, dream_run {start, milestones}, all_out (Lona), foul, card, powerplay, review.
- **Point values VARY BY LEAGUE/SEASON (UKK S2: tag 2, pole dive 2, sky dive 2, dream run +1 @3min then +1/30s; other rulesets: 3 for dives, 2:30 dream-run threshold). ALL values MUST come from RuleConfig.**
- Wazir (multi-directional runner) flag supported.
- Stats: touch points, dive points, dream-run points, khos, time survived per batch.

### 7.7 Basketball
- Points 1 (FT) / 2 / 3. Events: shot {made|missed, value, shooter, assist?, coords? for shot chart}, rebound {off|def}, steal, block, turnover, foul {personal|technical, count tracking}, substitution, timeout, period.
- Stats: PTS, REB, AST, STL, BLK, TO, FG%/3P%/FT%, minutes, +/−.
- RuleConfig: quarters × minutes, shot clock, 3×3 mode (to 21 or 10 min), foul-out threshold, bonus rules.

### 7.8 Tennis
- Point ladder 0→15→30→40→game; deuce → advantage (win by 2) OR no-ad (config). Set = 6 games win-by-2; 6-6 → tiebreak to 7 win-by-2 (serve 1 then alternate every 2; change ends every 6 points). Deciding set: full set OR 10-point match tiebreak (config). Best of 3 default; best of 5 selectable. Change ends after odd games.
- Events: point {server, outcome: ace|double_fault|winner|unforced_error|forced_error|net?, break_point_flag}, game_end, set_end, tiebreak points.
- Stats: aces, DFs, 1st-serve %, 1st/2nd-serve points won %, break points faced/saved/converted, winners, UEs, hold/break %.

### 7.9 Table Tennis
- Game to **11, win by 2 (no cap)**; serve alternates every 2 points (every 1 at deuce ≥10-10). Best of 5 (club default) / best of 7 (config). Switch ends per game; deciding game switch at 5. Net-clip serve = let (unlimited lets). Doubles ABCD rotation enforced.
- Events: point {server, winner, serve_no, let?, edge?}, expedite_trigger, game_end.
- Stats: service/receive points won %, games, deuce record, longest rally.

### 7.10 Hockey (field)
- 4 × 15-min quarters (config). Events: goal {field|penalty_corner|penalty_stroke, scorer, assist?}, penalty_corner, penalty_stroke, card {green|yellow|red}, substitution (rolling), quarter, shootout.
- Stats: goals, assists, PC conversion %, saves, cards.

### 7.11 Chess
- Result 1 / 0.5 / 0. Time controls: classical|rapid|blitz|bullet (config). Optional PGN move capture.
- Tournament: Swiss or round-robin; tiebreaks Buchholz / Sonneborn-Berger.
- **Rating: Glicko-2 per time control** (mirror chess.com/lichess).

### 7.12 Athletics (track & field)
- Event-based, not head-to-head. Track: times to 0.01s, lanes, heats → finals, false starts, wind reading. Field: attempts (distance/height), best-of-attempts.
- Stats: personal bests, season bests, rankings by event × age group × area.

### 7.13 Carrom
- Points per pocketed coin + queen (with cover); board = 29 pts; best-of-N boards. Events: coin_pocketed {color}, queen {covered?}, foul, board_end. Config to state association rules.

**Adding a new sport = new engine module implementing the shared interface:** `applyEvent(state, event) → state`, `project(scorecard)`, `project(playerStats)`, `validate(event, state, ruleConfig)`. No core changes required.

---

## 8. Ratings & AI Team Balancing

### 8.1 Glicko-2 per sport (chosen over plain Elo)
- Each (user, sport): rating r (start 1500), rating deviation RD (start 350), volatility σ (start 0.06). Public-domain Glickman algorithm; recompute per **rating period** (weekly batch job).
- Why: RD models uncertainty → fast convergence with few games (grassroots reality); RD grows with inactivity; report confidence band (r ± 2×RD) in UI.
- Team sports: team rating = aggregate of player ratings; distribute team result to players TrueSkill-style, weighted by **sport-specific performance inputs** (e.g., cricket MVP points from batting/bowling/fielding contributions) — never pure win/loss for team members.
- Display tiers to users (Beginner → Legend bands) instead of raw numbers by default; raw + graph on profile.

### 8.2 Cross-Sport Index ("Sports OS Index")
`index = Σ over sports [ percentile_within_sport × recency_weight × confidence(1/RD) ]`, normalized 0–100. Materialized view, recomputed with rating batches. Used for profile headline + scout filters. Document formula in-app for transparency.

### 8.3 AI Team Shuffle
1. Pool players with (rating, RD, position/role tags).
2. Snake-draft by rating into N teams.
3. Local-search swaps to minimize max pairwise team-strength difference; respect constraints (keep/avoid pairs, role coverage e.g. ≥1 keeper).
4. Show predicted balance %; allow manual override drag-drop after.

---

## 9. Tournament Engine

Formats (all MUST support seeding, byes, points tables, printable/shareable brackets, auto round scheduling):
- **Knockout:** N−1 matches; byes to top seeds; bracket auto-gen for any N.
- **Round robin (single/double):** N(N−1)/2 matches; **Berger tables** scheduling; warn organizer when N > 12 for one-day events.
- **Double elimination:** winners + losers brackets, grand final (+reset option).
- **Swiss:** rounds ≈ ⌈log₂N⌉ (configurable); pair similar scores, no rematches; **Buchholz** tiebreak (sum of opponents' scores); ideal for large chess/TT fields.
- **Groups + knockout:** configurable group size, qualifiers per group, cross-seeding into bracket.
- **League:** ongoing points table with configurable points (win/draw/loss/bonus) and tiebreak chain (points → head-to-head → NRR/goal-diff → Buchholz → coin toss) per sport via tiebreak_config.
- Scheduler: assign matches to venues × time slots; detect player/team clashes; rest-gap constraints; reschedule flow feeding notifications.

---

## 10. Payments (Razorpay)

- Entry-fee checkout: UPI-first (UPI ≈ 85% of India digital payments), cards/netbanking fallback.
- **Route** split settlement: organizer share auto-transferred, platform fee retained; hold-until-event-complete option; refund/cancellation policies per event.
- Teammate split-pay links. GST invoice generation. Subscriptions (PRO organizer tier) via Razorpay Subscriptions/UPI AutoPay.
- Webhook-driven state machine; idempotent handlers; reconciliation report.

---

## 11. Build Phases (execute in order; each phase ships)

**Phase 1 — Foundation + Cricket + Badminton (MVP).**
Auth (OTP), users, clubs, memberships, invites; internal + open events, registrations, notifications (FCM); offline sync engine; match core + scorer lock; **cricket engine (full §7.1)** + **badminton engine**; public live-score web view; basic profiles + career stats for these sports; memories (photo upload + album). *Exit: 1,000 matches scored, 60% scorer retention across 3 pilot Hyderabad clubs/colleges.*

**Phase 2 — Tournament engine + payments + more sports.**
All tournament formats + scheduler + points/NRR; Razorpay + Route paid registration; engines: football, volleyball, kabaddi, basketball, table tennis, tennis; Glicko-2 service + AI team shuffle; inter-club challenges. *Exit: 20 paid tournaments settled cleanly; ratings converging (median RD < 100).*

**Phase 3 — Lifelong profiles + talent discovery.**
Career aggregation service + verification tiers; kho-kho, chess, hockey, athletics, carrom engines; cross-sport index; scout role + consent/guardian flows; memories v2 (highlights, tournament albums); WhatsApp notification channel.

**Phase 4 — Government layer.**
Gov aggregates + state/district/mandal/village dashboards; export APIs (SATS, SGFI, Khelo India/MyBharat, Fit India); public transparency views; DPDP compliance audit; SATS pilot district onboarding.

---

## 12. Engineering Conventions & Guardrails for the Agent

1. **Never mutate `match_events`.** Corrections are new reversal/correction events. Projections must be rebuildable from scratch (`rebuildMatch(match_id)` must exist and be tested).
2. **Every sport parameter through RuleConfig.** If you find yourself typing a point value in engine code, stop and move it to config.
3. **Idempotent sync ingestion** keyed on client UUIDv7. Test double-delivery explicitly.
4. **Scorer lock enforced server-side**, not just UI.
5. **All engines are pure Dart modules** with golden tests: replay a fixture event log → assert exact scorecard + stats (build fixtures for: cricket wide+no-ball+run-out edge cases, badminton 29-29→30, TT deuce 10-10→13-11, volleyball 5th-set switch, kabaddi super-tackle/all-out, tennis tiebreak serve order).
6. **NRR math:** overs decimalized as balls/6; bowled-out teams use full allotted overs; 3-decimal precision — golden tests required.
7. i18n: no hard-coded user-facing strings; Telugu, Hindi, English resource files from Phase 1.
8. Minors: block scout visibility without guardian consent record; verify age from DOB at query time.
9. Performance budgets: cold start < 3s on 2GB device; scoring tap→UI < 100ms (all local); sync batches ≤ 500 events.
10. When ambiguous, prefer: offline correctness > feature breadth; configurability > cleverness; CricHeroes parity for cricket UX > novelty.

## 13. Known Caveats (encode as config/flags, not assumptions)
- Kho-kho point values differ across UKK seasons and KKFI-aligned rulesets → RuleConfig presets per season.
- Badminton mid-transition (21-pt vs BWF 3×15 for 2026) → both as presets.
- National "One Sport ID" not yet formalized → keep `external_ids` extensible.
- CricHeroes figures are self-reported marketing benchmarks, used for positioning only.
- Telangana Sports Policy 2025 figures (₹465 cr budget, YIPESU by 2028, TSDF) sourced from government statements/press — track for updates before gov integrations.
