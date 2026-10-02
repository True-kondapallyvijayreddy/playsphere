# PlaySphere Quality Assurance: Master Manual Test Specification
## Comprehensive Test Cases for Season & Tournament Flow

**Document Version:** 2.0  
**Target Product:** PlaySphere Multi-Sport Operating System  
**Test Suite Focus:** End-to-End Season & Tournament Lifecycle  
**Coverage:** Season Creation, Registration Modes, Venues & Grounds, Capacity Planning, Scheduling & Conflict Resolution, Officials Assignment & Neutrality, Matchday LIVE Operations, Scoring Pads, Retirements & Match Rulings, Leaderboards & Standings, Multi-Tier Stats Aggregation, Glicko-2 Rating Engine.

---

## 1. Traceability & Architecture Mapping

```
[Draft Season / Tournament] ────► [Add Competitions / Categories]
               │                                │
               ▼                                ▼
       [Open Entries] ──────────► [Registrations: Indiv / House / Team]
               │                                │
               ▼                                ▼
       [Close Entries] ─────────► [Entrant Promoter (Assemble & Validate)]
               │                                │
               ▼                                ▼
    [Venues / Grounds Plan] ────► [Capacity Modeling (Mins + Turnaround)]
               │                                │
               ▼                                ▼
      [Generate Schedule] ──────► [Conflict-Free Timetable & Rest Gaps]
               │                                │
               ▼                                ▼
      [Assign Officials] ───────► [Neutrality Hard Constraint Checks]
               │                                │
               ▼                                ▼
     [Matchday Live Launch] ────► [Concurrent Multi-Sport Matchdays]
               │                                │
               ▼                                ▼
     [Live Scoring Pads] ───────► [Ball/Point by Ball, Undo, Edit, Pause]
               │                                │
               ▼                                ▼
    [Retirements / Rulings] ────► [Normal / Retired (R) / Walkover (W/O)]
               │                                │
               ▼                                ▼
      [Finalization Sign-Off] ──► [PROVISIONAL ➔ OFFICIAL Transition]
               │                                │
    ┌──────────┴────────────────────────────────┴──────────┐
    ▼                                                      ▼
[Leaderboards & Standings]                     [Stats & Glicko-2 Engine]
 • Tournament League Tables                     • Match ➔ Player ➔ Season ➔ Career
 • Olympics Medal Board (🥇🥈🥉)                • Glicko-2 Movement (Season/Norm/Ret/≥4)
 • Sport-Wise Stats Accolades                   • Recalculate & Reconcile Pipeline
```

---

## 2. Test Severity & Priority Definitions
* **P0 (Critical / Blocker):** Core business logic, data loss, corrupted scores, incorrect Glicko-2 movement, unhandled scheduling clashes, invalid tournament promotion.
* **P1 (High):** Significant functional defects, validation bypasses, UI misleading states, official assignment rule violations.
* **P2 (Medium):** Edge cases, minor UI alignment glitches, secondary sorting nuances on tables, optional configuration overrides.

---

# Test Suite 1: Season & Tournament Creation & Configuration

---

### TC-SEAS-001: Multi-Sport Season Creation (Draft Initial State)
* **Module:** Season Management  
* **Priority:** P0  
* **Type:** Functional / Positive / State Transition  
* **Pre-conditions:**
  * User logged in as verified Organizer of Organization `org_hyd_central`.
* **Test Data:**
  * Season Name: `Hyderabad Annual Champions Trophy 2026`
  * Kind: `SeasonKind.season` (Multi-Sport)
  * Dates: `2026-10-01` to `2026-10-15`
  * Tournament Grade: `TournamentGrade.district` (Weight: 3)
  * Fee Mode: `SeasonFeeMode.wholeSeason` (Amount: ₹600)
  * Description: `Annual inter-club championship spanning Cricket, Football, Badminton, and Chess.`
* **Step-by-Step Procedure:**
  1. Navigate to **Organizer Console** > **Seasons** tab.
  2. Click **+ Create Season**.
  3. Fill in Season Name, Description, and Date Range.
  4. Select **Kind**: `Season (Multi-Sport)`.
  5. Select **Grade**: `District`.
  6. Select **Fee Structure**: `One fee for the whole season` and enter `600`.
  7. Click **Create & Save Draft**.
* **Expected Results:**
  1. Season document created in Firestore under `orgs/org_hyd_central/tournaments/{seasonId}`.
  2. Status is set to `TournamentStatus.draft` (`wire: "draft"`).
  3. UI displays a distinct gray/amber **Draft** badge.
  4. `acceptsEntries` evaluates to `false`. Public users cannot view a "Register" button.
  5. Fee mode is stored as `season` with `entryFeeRupees: 600`.

---

### TC-SEAS-002: Single-Sport Tournament vs Multi-Sport Season Validation
* **Module:** Season Management  
* **Priority:** P1  
* **Type:** Functional / Boundary  
* **Pre-conditions:**
  * User in the Create Container modal.
* **Step-by-Step Procedure:**
  1. Select **Kind**: `Tournament (Single-Sport)`.
  2. Select Primary Sport: `Cricket`.
  3. Proceed to the "Competitions & Categories" step.
  4. Attempt to add a competition for `Badminton`.
  5. Cancel, start again and select **Kind**: `Season (Multi-Sport)`.
  6. Add competitions for `Cricket (T20)`, `Badminton (Men's Singles)`, and `Football (7-a-side)`.
* **Expected Results:**
  1. When kind is `tournament`, the UI restricts category creation strictly to the selected primary sport (`Cricket` categories only: U-14, U-19, Open).
  2. When kind is `season`, the sports catalog picker allows adding multiple disparate sports into the same top-level container.

---

### TC-SEAS-003: Performance Sport vs Versus Sport Configuration Validation
* **Module:** Competition Setup  
* **Priority:** P1  
* **Type:** Business Logic / Defensive  
* **Pre-conditions:**
  * Active Season container in Draft.
* **Step-by-Step Procedure:**
  1. In Season editor, click **Add Competition**.
  2. Select Sport: `Athletics (100m Sprint)` (`isPerformance: true`).
  3. Inspect available Competition Formats in the dropdown.
  4. Attempt to choose `Knockout` or `Round Robin`.
  5. Select Sport: `Badminton` (`isPerformance: false`).
  6. Inspect available formats.
* **Expected Results:**
  1. For `Athletics`, pairwise bracket formats (`knockout`, `roundRobin`, `groupThenKnockout`) are hidden or disabled. Only `finalOnly` and `heatsThenFinal` are selectable.
  2. Helper notice displays: *"Performance sports generate timed/measured heats, not pairwise bracket slots."*
  3. For `Badminton`, pairwise formats (`knockout`, `roundRobin`, `groupThenKnockout`) are available.

---

### TC-SEAS-004: Season Fee Mode Enforcement (`wholeSeason` vs `perEvent`)
* **Module:** Billing & Entries  
* **Priority:** P1  
* **Type:** Functional / Financial Logic  
* **Test Steps & Cases:**
  * **Case A (`wholeSeason`):**
    1. Set Season Fee Mode to `SeasonFeeMode.wholeSeason` with ₹500.
    2. Add Competition `Badminton Singles` and `Chess Open`.
    3. Open registration for both.
    4. Verify the entry fee input on individual competition setup is disabled and locked to ₹0.
    5. Register User X. Verify User X pays ₹500 once at the Season container level. User X can enter both Badminton and Chess without duplicate checkout.
  * **Case B (`perEvent`):**
    1. Set Season Fee Mode to `SeasonFeeMode.perEvent`.
    2. Set `Badminton Singles` fee to ₹300, `Cricket Team` fee to ₹1500.
    3. Register User Y for Badminton. Verify checkout asks for ₹300.
    4. Register User Y for Cricket. Verify checkout asks for ₹1500.
* **Expected Results:**
  * System strictly adheres to `SeasonFeeMode` without silent fee overwrites.

---

# Test Suite 2: Registration, Entries & Promoter Engine

---

### TC-REG-001: Automatic Season Status Lifting on Event Opening (`yieldsToAnOpenDraw`)
* **Module:** Season Lifecycle  
* **Priority:** P0  
* **Type:** State Transition / System Reaction  
* **Pre-conditions:**
  * Season status is `draft`.
  * Competitions created inside: `Badminton Singles` (status: `draft`), `Football Cup` (status: `draft`).
* **Step-by-Step Procedure:**
  1. Verify Season overview screen displays status badge: **Draft**.
  2. Navigate into `Badminton Singles` competition.
  3. Click **Open Entries** (`openEntriesForSeason`).
  4. Observe Competition status and navigate back to Season home.
* **Expected Results:**
  1. Competition status changes from `draft` to `registration_open`.
  2. Season container status automatically transitions from `draft` to `entries_open`.
  3. The Season appears publicly on the Discover/Home screen under *"Open Registrations"*.
  4. Note: If the season is already `scheduled`, `in_progress`, or `completed`, opening a secondary draw must NOT regress the season back to `entries_open` (`yieldsToAnOpenDraw == false` for non-draft states).

---

### TC-REG-002: Individual Registration Validation (`TeamEntryMode.individual`)
* **Module:** Entrant Engine  
* **Priority:** P0  
* **Type:** Functional / Positive  
* **Pre-conditions:**
  * Competition: `Tennis Open Singles` (`entrantType: individual`, `teamEntryMode: individual`, status: `registration_open`).
* **Step-by-Step Procedure:**
  1. Log in as Player `U_ALICE` (`uid: "alice_1"`).
  2. Navigate to `Tennis Open Singles` > click **Register**.
  3. Verify modal populates: Name: Alice, Age, Skill Level.
  4. Submit registration.
  5. Log in as Player `U_BOB` (`uid: "bob_2"`), `U_CHARLIE` (`uid: "charlie_3"`), `U_DAVID` (`uid: "david_4"`).
  6. Register each player.
* **Expected Results:**
  1. 4 individual records in `competitions/{compId}/registrations` with `status: confirmed`.
  2. Entrant count indicator shows: `4 Confirmed Entries`.
  3. Duplicate registration by `U_ALICE` is blocked with: *"You are already registered for this competition."*

---

### TC-REG-003: Intra-Club School House Batch Registration (`TeamEntryMode.houseBatch`)
* **Module:** Entrant Engine  
* **Priority:** P0  
* **Type:** Functional / Promotion Logic  
* **Pre-conditions:**
  * Competition: `Inter-House Basketball 5v5` (`teamEntryMode: houseBatch`, `entrantType: team`).
* **Test Data:**
  * 5 players register selecting `houseName: "Garuda House"`.
  * 5 players register selecting `houseName: "Kowshika House"`.
  * 5 players register selecting `houseName: "Mayura House"`.
* **Step-by-Step Procedure:**
  1. Register 15 students with their respective house tags.
  2. Navigate to Organizer Console > tap **Close Entries & Assemble Teams**.
  3. Execute `EntrantPromoter.promote()`.
* **Expected Results:**
  1. Individual registrations are NOT paired as individual match entrants.
  2. Promoter folds registrations into exactly **3 Entrant Teams**:
     * Entrant 1: `Garuda House` (contains 5 player UIDs)
     * Entrant 2: `Kowshika House` (contains 5 player UIDs)
     * Entrant 3: `Mayura House` (contains 5 player UIDs)
  3. `result.isReady` returns `true`.
  4. Fixture draws will pair `Garuda House vs Kowshika House`, preserving team integrity.

---

### TC-REG-004: Preformed Visiting Teams / External Club Registration (`TeamEntryMode.preformedTeam`)
* **Module:** Entrant Engine  
* **Priority:** P0  
* **Type:** Functional / Multi-Club  
* **Pre-conditions:**
  * Open Multi-Club Invitational Volleyball Tournament.
* **Step-by-Step Procedure:**
  1. Club Admin of `Cyberabad Spikers` submits entry with team roster of 8 verified club members.
  2. Club Admin of `Secunderabad RFC` submits entry with team roster of 8 verified club members.
  3. Close entries and run promoter.
* **Expected Results:**
  1. Promoter creates 2 team entrants keyed by team name and originating `clubId`.
  2. Roster members are locked to the competition squad sheet.
  3. Visiting club affiliation is preserved for neutrality checks.

---

### TC-REG-005: Entrant Promoter Error Diagnostics (Malformed House Batch)
* **Module:** Entrant Engine  
* **Priority:** P1  
* **Type:** Negative / Defensive  
* **Step-by-Step Procedure:**
  1. Set up competition with `TeamEntryMode.houseBatch`.
  2. Have 3 players register with NO house specified (`houseName: null`).
  3. Organizer clicks **Close Entries & Generate Draw**.
* **Expected Results:**
  1. Promotion fails cleanly (`result.isReady == false`).
  2. Clear explanatory diagnostic message: *"Cannot assemble house sides: 3 confirmed registrations have no house assigned."*
  3. System does not generate an empty or broken draw.

---

### TC-REG-006: Multi-Category Athlete Registration (Singles & Doubles)
* **Module:** Registration  
* **Priority:** P1  
* **Type:** Boundary / Concurrency  
* **Test Steps:**
  1. User `Rahul` enters `Badminton Men's Singles`.
  2. User `Rahul` enters `Badminton Men's Doubles` pairing with `Kiran`.
  3. Verify registration succeeds for both events under the same user UID.
* **Expected Results:**
  1. Both registrations are confirmed.
  2. Scheduler flags `Rahul`'s UID across both events for cross-draw schedule deconfliction.

---

# Test Suite 3: Venues, Grounds, Courts & Capacity Planning

---

### TC-VEN-001: Venue & Multi-Court Configuration
* **Module:** Venue Management  
* **Priority:** P1  
* **Type:** Functional  
* **Test Data:**
  * Venue Name: `Kotla Vijaya Bhaskar Reddy Indoor Stadium`
  * Operating Hours: `07:00` to `21:00` (14 hours / 840 minutes)
  * Courts: `Court A`, `Court B`, `Court C`
* **Step-by-Step Procedure:**
  1. Go to Season > **Venues** tab > **+ Add Venue**.
  2. Enter Name, set Open Hour = `7`, Close Hour = `21`.
  3. Add 3 courts. Click **Save Venue**.
* **Expected Results:**
  1. Venue saved with `openHour: 7`, `closeHour: 21`.
  2. 3 courts created with unique IDs (`c1`, `c2`, `c3`).
  3. Total daily court minutes available = $14 \times 60 \times 3 = 2,520\text{ minutes}$.

---

### TC-VEN-002: Mathematical Capacity Modeling (`SeasonCapacity.lineFor`)
* **Module:** Capacity Planner  
* **Priority:** P0  
* **Type:** Boundary / Mathematical Logic  
* **Pre-conditions:**
  * Single cricket ground operating `08:00` to `20:00` (12 hours = 720 minutes).
* **Test Data & Variations:**
  * **Variation 1 (Computed Standard):**
    * Match Minutes: `180` (3 hrs), Turnaround: `30` mins.
    * Total slot = `210` mins.
    * $\lfloor 720 / 210 \rfloor = 3$ matches.
    * Verify: `computedPerCourtPerDay == 3`.
  * **Variation 2 (Organizer Exceeds Reality):**
    * Organizer enters `maxMatchesPerCourtPerDay = 4`.
    * Verify: System displays `limitExceedsReality: true`.
    * System enforces `effectivePerCourtPerDay == 3`.
  * **Variation 3 (Organizer Restricts Below Reality):**
    * Organizer enters `maxMatchesPerCourtPerDay = 2`.
    * Verify: System adopts stricter limit: `effectivePerCourtPerDay == 2`.
* **Expected Results:**
  * Formula $\min(\text{computed}, \text{organizerLimit})$ is strictly adhered to. Fixture generator will never schedule more matches than the effective capacity allows.

---

# Test Suite 4: Scheduling, Timetable & Conflict Resolution

---

### TC-SCH-001: Knockout Draw Generation with Byes
* **Module:** Fixture Generator  
* **Priority:** P0  
* **Type:** Algorithmic / Bracket Integrity  
* **Pre-conditions:**
  * Competition: `Badminton Men's Singles`.
  * Entrants Confirmed: 6 players (`P1`, `P2`, `P3`, `P4`, `P5`, `P6`).
* **Step-by-Step Procedure:**
  1. Tap **Generate Bracket** > Format: `Knockout`.
  2. Inspect generated bracket structure.
* **Expected Results:**
  1. Next power of 2 bracket size = 8.
  2. Number of byes = $8 - 6 = 2\text{ byes}$.
  3. Byes assigned to Seed 1 and Seed 2.
  4. Round 1 contains 2 matches:
     * Match 1: Seed 3 vs Seed 6
     * Match 2: Seed 4 vs Seed 5
  5. Seed 1 and Seed 2 placed directly into Semifinals (Round 2).

---

### TC-SCH-002: Athlete Cross-Draw Concurrent Match Conflict Prevention
* **Module:** Tournament Scheduler  
* **Priority:** P0  
* **Type:** Conflict Resolution / Algorithmic  
* **Pre-conditions:**
  * Player `Karthik` is scheduled in:
    * `Badminton Singles Match #1` (Match Duration: 40 mins, turnaround: 10 mins).
    * `Badminton Doubles Match #1` (Match Duration: 40 mins, turnaround: 10 mins).
  * 2 Courts available simultaneously (`Court 1`, `Court 2`) at `10:00 AM`.
* **Step-by-Step Procedure:**
  1. Run **Season Auto-Scheduler**.
  2. Inspect timetable assignments for both matches.
* **Expected Results:**
  1. The scheduler MUST NOT place both matches in the `10:00 AM` window even though 2 separate courts are open.
  2. Singles match placed at `10:00 AM - 10:40 AM`.
  3. Scheduler enforces athlete rest buffer (e.g., 30 mins rest).
  4. Doubles match placed at or after `11:10 AM`.

---

### TC-SCH-003: Venue & Court Overlap Prevention
* **Module:** Tournament Scheduler  
* **Priority:** P0  
* **Type:** Resource Allocation  
* **Step-by-Step Procedure:**
  1. Match A scheduled on `Court 1` from `09:00` to `10:00`.
  2. Attempt to manually drag or assign Match B to `Court 1` at `09:30`.
* **Expected Results:**
  1. UI flags hard collision error: *"Court 1 is occupied by Match A until 10:00 (+15m turnaround)."*
  2. Drop action is rejected; timetable retains integrity.

---

# Test Suite 5: Officials Assignment & Neutrality Constraints

---

### TC-OFF-001: Neutrality Hard Constraint Check
* **Module:** Officials Assigner  
* **Priority:** P0  
* **Type:** Integrity / Business Rules  
* **Pre-conditions:**
  * Match: `Secunderabad RFC` vs `Cyberabad CC`.
  * Available Officials:
    * `Official_1`: Affiliated with `Secunderabad RFC`.
    * `Official_2`: Affiliated with `Cyberabad CC`.
    * `Official_3`: Affiliated with `Warriors Sports Club` (Neutral).
* **Step-by-Step Procedure:**
  1. Trigger **Assign Officials** (`OfficialsAssigner.assign`).
  2. Inspect assigned roster.
* **Expected Results:**
  1. `Official_3` is assigned to the fixture.
  2. `Official_1` and `Official_2` are strictly excluded.
  3. Neutrality audit field logs: `isNeutral: true`.

---

### TC-OFF-002: Freelance / Unaffiliated Official Assignment
* **Module:** Officials Assigner  
* **Priority:** P1  
* **Type:** Functional  
* **Pre-conditions:**
  * Match between Club A and Club B.
  * Available Official: `Official_Free` (`clubId: null`).
* **Step-by-Step Procedure:**
  1. Run assigner.
* **Expected Results:**
  1. `Official_Free` is recognized as universal neutral referee and assigned successfully.

---

### TC-OFF-003: Transparent Reporting of Unstaffed Conflict Slots
* **Module:** Officials Assigner  
* **Priority:** P1  
* **Type:** Negative / Transparency  
* **Pre-conditions:**
  * Match between Club A and Club B.
  * Only officials in the pool belong to Club A and Club B.
* **Step-by-Step Procedure:**
  1. Run assigner.
  2. View Officials Roster status.
* **Expected Results:**
  1. Assigner DOES NOT silently assign a partisan referee.
  2. Slot remains `unstaffed` (`isComplete == false`).
  3. Detailed diagnostic displayed: *"Unstaffed slot: No neutral official available (all candidates belong to participating clubs)."*

---

### TC-OFF-004: Official Concurrent Match & Daily Quota Caps (`maxMatches`)
* **Module:** Officials Assigner  
* **Priority:** P1  
* **Type:** Workload Constraint  
* **Pre-conditions:**
  * `Official_X` has `maxMatches: 2`.
  * Season has 3 matches scheduled sequentially at 09:00, 11:00, and 14:00.
* **Step-by-Step Procedure:**
  1. Assign `Official_X` to Match 1 (09:00) and Match 2 (11:00).
  2. Run auto-assign for Match 3 (14:00).
* **Expected Results:**
  1. `Official_X` is excluded from Match 3 due to hitting daily limit ($2/2$).
  2. Match 3 assigned to another available official or reported unstaffed.

---

# Test Suite 6: Matchday Operations & Start Match

---

### TC-MD-001: Multi-Sport Matchday Dashboard Isolation
* **Module:** Matchday Live  
* **Priority:** P0  
* **Type:** Real-time Concurrency  
* **Pre-conditions:**
  * Date: `2026-10-05`.
  * Matches scheduled:
    * Cricket Pitch 1: Match `CRIC_01` (Warriors vs Titans)
    * Badminton Court 1: Match `BADM_01` (Alice vs Bob)
    * Football Ground: Match `FOOT_01` (Rangers vs Dynamos)
* **Step-by-Step Procedure:**
  1. Open Season Matchday screen on `2026-10-05`.
  2. Verify sport tabs and status cards.
  3. Start all 3 matches simultaneously on 3 separate scoring devices.
* **Expected Results:**
  1. All 3 matches transition to `in_progress`.
  2. Scores update independently in real time with zero cross-sport event bleeding.
  3. Viewers can filter by sport without UI lag.

---

### TC-MD-002: Start Match — Toss, Lineups & Provisional State
* **Module:** Match Execution  
* **Priority:** P0  
* **Type:** State Transition  
* **Step-by-Step Procedure:**
  1. Umpire opens Match `CRIC_01`.
  2. Click **Start Match**.
  3. Enter Toss: Won by `Warriors`, elected to `Bat`.
  4. Select Striker: `Player 1`, Non-Striker: `Player 2`, Opening Bowler: `Player 3`.
  5. Click **Confirm & Launch Pad**.
* **Expected Results:**
  1. Fixture status updates from `scheduled` to `in_progress`.
  2. Score state marked as **PROVISIONAL**.
  3. Public live score ticker displays `0/0 (0.0 overs)`.

---

# Test Suite 7: Live Scoring Pads & In-Match Controls

---

### TC-SCOR-001: Cricket Scoring Pad Operations
* **Module:** Scoring Engine  
* **Priority:** P0  
* **Type:** Functional / Sport Rules  
* **Step-by-Step Procedure:**
  1. Ball 0.1: Tap `1` run. Verify striker swaps.
  2. Ball 0.2: Tap `4` runs (Boundary). Verify striker remains unchanged.
  3. Ball 0.3: Tap `Wide`. Verify score increments by 1 run, legal ball count does NOT increment.
  4. Ball 0.3 (re-bowl): Tap `Out` > Select `Caught` > select fielder > select next batsman.
* **Expected Results:**
  1. Total score reads `6/1 (0.3 overs)`.
  2. Batsman 1 recorded: `5 runs (2 balls), ct Fielder b Bowler`.
  3. Bowler figures: `0.3 overs, 6 runs, 1 wicket`.

---

### TC-SCOR-002: Racket Sports (Badminton) Pad & Deuce Logic
* **Module:** Scoring Engine  
* **Priority:** P0  
* **Type:** Functional / Sport Rules  
* **Step-by-Step Procedure:**
  1. Score rallies until `20 - 20` (Deuce).
  2. Side A scores: `21 - 20`. Verify game does NOT terminate.
  3. Side B scores: `21 - 21`.
  4. Side A scores two consecutive points: `23 - 21`.
* **Expected Results:**
  1. System enforces 2-point clear margin rule.
  2. At 23-21, Game 1 concludes; awarded to Side A.
  3. Pad prompts end-change and launches Game 2.

---

### TC-SCOR-003: In-Match Undo Functionality
* **Module:** Scoring Engine  
* **Priority:** P0  
* **Type:** Error Recovery / Timeline  
* **Step-by-Step Procedure:**
  1. Current Cricket Score: `45/2 (5.4 overs)`.
  2. Scorer accidentally taps `Out (Bowled)`.
  3. Immediately tap **Undo** button.
* **Expected Results:**
  1. Wicket event is revoked from canonical event stream.
  2. Score reverts to `45/2 (5.4 overs)`.
  3. Dismissed batsman is restored to active striker position.
  4. Bowler's wicket tally decrements by 1.

---

### TC-SCOR-004: Match Pause & Technical Stoppage
* **Module:** Match Operations  
* **Priority:** P1  
* **Type:** Operational  
* **Step-by-Step Procedure:**
  1. During live match, tap **Options** > **Pause Match**.
  2. Select reason: `Rain Delay`.
  3. Check public spectator view.
  4. Tap **Resume Match**.
* **Expected Results:**
  1. Public badge reads `PAUSED (Rain Delay)`.
  2. Scoring buttons disabled during pause.
  3. Upon resumption, timer and controls return to `LIVE`.

---

# Test Suite 8: Retirements, Walkovers & Match Endings

---

### TC-RET-001: Player In-Match Retirement (Injury / Retired Hurt)
* **Module:** Match Rulings  
* **Priority:** P0  
* **Type:** Critical Business Logic / Ruling  
* **Pre-conditions:**
  * Badminton Singles Match: Player A vs Player B.
  * Score: Game 1 (14 - 10). Player A twists knee.
* **Step-by-Step Procedure:**
  1. Umpire selects **End Match / Ruling** > **Retire Player**.
  2. Select Retiring Side: `Player A`.
  3. Select Reason: `Injury`.
  4. Enter note: *"Sprained right knee during rally"*.
  5. Tap **Confirm Retirement**.
* **Expected Results:**
  1. Match status transitions to `completed`.
  2. `resultType` is set to `MatchResultType.retired` (`wire: "retired"`).
  3. Match winner is awarded to `Player B`.
  4. Final score reads with `(R)` notation: e.g., `10-14 (R)`.
  5. Scorepad locks immediately (`endedByDecision == true`).
  6. **Fundamental Business Rule:** This counts as a PLAYED match (not a walkover) because real gameplay occurred.

---

### TC-RET-002: Cricket Batsman Retired Hurt vs Retired Out
* **Module:** Cricket Scoring  
* **Priority:** P1  
* **Type:** Sport Rules Integrity  
* **Test Steps & Cases:**
  * **Case A (Retired Hurt):**
    1. Batsman injured by bouncer. Select **Retire** > **Retired Hurt**.
    2. Verify: Bowler is NOT credited with a wicket. Batting team wicket count does NOT increment. Next batsman enters. Batsman marked `Retired Hurt`.
  * **Case B (Retired Out):**
    1. Batsman leaves field tactically without injury. Select **Retire** > **Retired Out**.
    2. Verify: Batting team wicket count increments by 1. Bowler does NOT receive wicket credit. Scorecard records `Retired Out`.

---

### TC-RET-003: Walkover (W/O), Conceded & Abandoned Rulings
* **Module:** Match Rulings  
* **Priority:** P0  
* **Type:** Classification & Distinctions  
* **Test Cases:**
  * **Walkover (`walkover`):**
    * Team fails to report to pitch. Awarded to present team. `resultType: "walkover"`. Winner advances in bracket. Score shows `W/O`.
  * **Abandoned (`abandoned`):**
    * Rain cancels match before minimum overs bowled. `resultType: "abandoned"`. No winner awarded. Points shared or rescheduled.
  * **Disqualified (`disqualified`):**
    * Ineligible over-age player fielded. Offending side disqualified. `resultType: "disqualified"`.
* **Expected Results:**
  * System distinguishes these non-performance rulings from `retired`. Walkover, Abandoned, and Disqualified matches are flagged as ineligible for Glicko-2 ratings.

---

# Test Suite 9: Results Verification, Disputes & Finalization

---

### TC-DISP-001: Raising a Match Dispute
* **Module:** Dispute Management  
* **Priority:** P0  
* **Type:** Workflow / Integrity  
* **Step-by-Step Procedure:**
  1. Match concludes. Losing captain notices scorekeeper missed 2 penalty runs.
  2. Losing captain clicks **Raise Dispute** before official sign-off.
  3. Enters description: *"2 penalty runs awarded in 8th minute were not credited on scoreboard."*
  4. Submits dispute.
* **Expected Results:**
  1. Match status enters `disputed`.
  2. Bracket progression for the winner is temporarily blocked.
  3. High-priority dispute alert appears on the Tournament Director's dashboard.

---

### TC-DISP-002: Dispute Adjudication & Official Finalization
* **Module:** Dispute Management  
* **Priority:** P0  
* **Type:** Resolution & Audit  
* **Step-by-Step Procedure:**
  1. Tournament Director reviews official timeline log and umpire remarks.
  2. Director applies correction: adds 2 penalty points.
  3. Director adds resolution note: *"Reviewed by Director. Penalty verified and added."*
  4. Director clicks **Resolve & Finalize Official Score**.
* **Expected Results:**
  1. Match moves to `completed`.
  2. State changes from `PROVISIONAL` to `OFFICIAL`.
  3. Scorecard permanently locks against any future edits.
  4. Winner progresses to next tournament round.

---

# Test Suite 10: Season Leaderboards & Standings

---

### TC-LEAD-001: Single-Sport League Standings (Points Table)
* **Module:** Leaderboard Engine  
* **Priority:** P0  
* **Type:** Mathematical Verification  
* **Test Data:**
  * Standard Rules: Win = 2, Draw/Tie = 1, Loss = 0.
* **Test Steps:**
  1. Complete Match 1: Team A defeats Team B (Runs: 160 vs 120, 20 overs each).
  2. Complete Match 2: Team C draws with Team D.
  3. Open Standings Table.
* **Expected Results:**
  * `Played (P)`: A:1, B:1, C:1, D:1.
  * `Won (W)`: A:1, others: 0.
  * `Points (PTS)`: Team A = 2, Team C = 1, Team D = 1, Team B = 0.
  * `Net Run Rate (NRR)`:
    * Team A NRR: $+2.000$
    * Team B NRR: $-2.000$
  * Sorting: Team A (1st), Team C/D (Tied 2nd), Team B (4th).

---

### TC-LEAD-002: Olympics-Style Multi-Sport Season Leaderboard (Medal Tally)
* **Module:** Season Leaderboard  
* **Priority:** P0  
* **Type:** Aggregation / Multi-Sport  
* **Configured Medal Points:** Gold = 5, Silver = 3, Bronze = 1.
* **Test Data:**
  * Event 1 (Badminton):
    * Gold: `Cyberabad CC`
    * Silver: `Secunderabad RFC`
    * Bronze: `Warriors FC`
  * Event 2 (Football):
    * Gold: `Secunderabad RFC`
    * Silver: `Cyberabad CC`
    * Bronze: `Titans Club`
* **Step-by-Step Procedure:**
  1. Finalize both events.
  2. Open **Season Overall Medal Standings**.
* **Expected Results:**
  * Standings Table:
    1. **Secunderabad RFC:** 1🥇, 1🥈, 0🥉 | Total Points: **8**
    2. **Cyberabad CC:** 1🥇, 1🥈, 0🥉 | Total Points: **8**
    3. **Warriors FC:** 0🥇, 0🥈, 1🥉 | Total Points: **1**
    4. **Titans Club:** 0🥇, 0🥈, 1🥉 | Total Points: **1**
  * Tiebreaker sorting behaves according to rule: Most Golds -> Most Silvers -> Head-to-Head -> Total Points.

---

### TC-LEAD-003: Sport-Wise Leaderboard & Player Accolades
* **Module:** Season Leaderboard  
* **Priority:** P1  
* **Type:** Filtering & Accuracy  
* **Test Steps:**
  1. Open Season Leaderboard and toggle tabs: `Cricket`, `Badminton`, `Football`.
* **Expected Results:**
  1. `Cricket`: Correctly tabulates Top Run Scorers (Orange Cap), Top Wicket Takers (Purple Cap), Economy rates.
  2. `Badminton`: Ranks players by match win percentage and game differential.
  3. Cross-sport data is completely segregated without leakage.

---

### TC-LEAD-004: Season Entrant Perspective Card (`SeasonEntrantRecord`)
* **Module:** Entrant Dossier  
* **Priority:** P1  
* **Type:** Perspective-Aware UI  
* **Test Steps:**
  1. From the Season Board, click on `Cyberabad CC`.
* **Expected Results:**
  1. Opens season card answering: *"How is Cyberabad CC doing in THIS season?"*
  2. Lists all matches involving Cyberabad CC across all sports.
  3. Every match is labeled from THEIR side (Won vs X, Lost vs Y, Upcoming vs Z).
  4. Career/historical statistics are separated to avoid cluttering the season dossier.

---

# Test Suite 11: Statistical Engine & Career Aggregation

---

### TC-STAT-001: Multi-Tier Statistical Aggregation Reconciliation
* **Module:** Stats Engine  
* **Priority:** P0  
* **Type:** Mathematical Invariant  
* **Test Steps:**
  1. Complete Match M01 where Player `Vikram` scores 64 runs off 42 balls.
  2. Verify:
     $$\text{Match Scorecard} \equiv 64\text{ runs}$$
     $$\Delta\text{Season Player Stats} \equiv +64\text{ runs}$$
     $$\Delta\text{Team Season Runs} \equiv +64\text{ runs}$$
     $$\Delta\text{Player Career Stats} \equiv +64\text{ runs}$$
* **Expected Results:**
  * All statistical layers increment identically with zero dropped events.

---

### TC-STAT-002: Strict Isolation of Casual & Practice Matches
* **Module:** Stats Engine  
* **Priority:** P0  
* **Type:** Data Isolation / Anti-Pollution  
* **Test Steps:**
  1. Player Vikram plays a casual 1v1 challenge match outside the season and scores 50 runs.
  2. Finalize the casual match.
  3. Check Vikram's **Season Stats** vs **Career Stats**.
* **Expected Results:**
  1. Vikram's **Season Stats** do NOT change (remains 64 runs).
  2. Vikram's **Career Stats** increase by 50 runs ($64 + 50 = 114\text{ runs}$).
  3. Official season leaderboards are protected from casual/unverified games.

---

### TC-STAT-003: Deterministic Event-Sourced Recalculation
* **Module:** Stats Maintenance  
* **Priority:** P0  
* **Type:** Disaster Recovery / Audit  
* **Step-by-Step Procedure:**
  1. Admin triggers backend function: `recalculateSeason({ seasonId: "season_2026" })`.
* **Expected Results:**
  1. Engine streams raw ball-by-ball and point-by-point canonical event logs.
  2. Rebuilds match scores, tournament tables, player season stats, and medal leaderboards.
  3. Final rebuilt data exactly matches the current state with 0 discrepancies.

---

# Test Suite 12: Glicko-2 Rating Engine Settlement

---

### TC-GLK-001: Valid Season Match Glicko-2 Movement (Normal Win)
* **Module:** Glicko-2 Trigger  
* **Priority:** P0  
* **Type:** Rating Math & Eligibility  
* **Pre-conditions:**
  * `sourceType: "season"`.
  * `entrantCount: 8` ($\ge 4$).
  * Player A: Rating $R = 1500$, $RD = 200$, Volatility $\sigma = 0.06$.
  * Player B: Rating $R = 1500$, $RD = 200$, Volatility $\sigma = 0.06$.
* **Step-by-Step Procedure:**
  1. Finalize match: Player A defeats Player B (`resultType: "normal"`).
  2. Inspect Glicko backend trigger output (`functions/glicko2.js`).
* **Expected Results:**
  1. `ratingWithheldReason` evaluates to `null` (Eligible).
  2. Player A (Winner) rating increases: $R > 1500$, $RD$ decreases ($RD < 200$).
  3. Player B (Loser) rating decreases: $R < 1500$, $RD$ decreases ($RD < 200$).
  4. Fixture document stamped: `ratingSettled: true`.

---

### TC-GLK-002: Retirement is Rated (`resultType: "retired"`)
* **Module:** Glicko-2 Trigger  
* **Priority:** P0  
* **Type:** Rating Math / Domain Rule  
* **Pre-conditions:**
  * Season match where Player A leads Player B, but Player A retires due to injury.
  * Winner awarded to Player B with `resultType: "retired"`.
* **Step-by-Step Procedure:**
  1. Finalize match.
  2. Trigger rating calculation.
* **Expected Results:**
  1. `RATED_RESULT_TYPES` explicitly includes `retired`.
  2. Rating is **settled**:
     * Player B (awarded win) gains rating.
     * Player A (retired) loses rating.
  3. Rationale verified: Genuine competition occurred until physical incapacity.

---

### TC-GLK-003: Rating Withheld on Walkover / Abandonment / Disqualification
* **Module:** Glicko-2 Trigger  
* **Priority:** P0  
* **Type:** Defensive Integrity  
* **Test Cases:**
  * Case A: Match ended as `walkover` (`W/O`).
  * Case B: Match ended as `abandoned`.
  * Case C: Match ended as `disqualified`.
* **Expected Results:**
  1. `ratingWithheldReason` returns the respective ruling string (`walkover`, `abandoned`, `disqualified`).
  2. Glicko rating calculation is aborted.
  3. Both players' $R$, $RD$, and $\sigma$ remain unchanged.
  4. Log records: *"Rating withheld: Rulings without physical play do not calibrate skill ratings."*

---

### TC-GLK-004: Anti-Forgery Field Floor Check ($\text{Entrant Count} < 4$)
* **Module:** Glicko-2 Anti-Cheat  
* **Priority:** P0  
* **Type:** Security / Anti-Exploit  
* **Pre-conditions:**
  * Fraudulent or private organizer creates a 2-person tournament with 2 dummy accounts.
  * `entrantCount: 2`.
* **Step-by-Step Procedure:**
  1. Complete match with `resultType: "normal"`.
  2. Check rating trigger response.
* **Expected Results:**
  1. `competitionRatingWithheldReason` returns `field_of_2`.
  2. Rating settlement is rejected (`MIN_RATED_ENTRANTS = 4` enforced).
  3. Protects global talent boards and scout rankings from fake 2-person tournaments.

---

### TC-GLK-005: Source Type Restriction (Challenges & Single Matches Withheld)
* **Module:** Glicko-2 Trigger  
* **Priority:** P0  
* **Type:** Scope Integrity  
* **Step-by-Step Procedure:**
  1. Player A challenges Player B in a casual 1-on-1 match (`sourceType: "challenge"`).
  2. Score and finalize match normally.
* **Expected Results:**
  1. Rating is withheld (`sourceType: "challenge"` not in `RATED_SOURCE_TYPES`).
  2. Rationale: Challenges lack impartial organizer oversight, draws, or independent scorekeepers.

---

### TC-GLK-006: Sybil / Self-Playing Defense
* **Module:** Glicko-2 Anti-Cheat  
* **Priority:** P0  
* **Type:** Security / Anti-Exploit  
* **Pre-conditions:**
  * Roster inspection detects Player A's UID present on both Side 1 and Side 2.
* **Step-by-Step Procedure:**
  1. Attempt match settlement.
* **Expected Results:**
  1. System flags `same_account_on_both_sides`.
  2. Rating settlement blocked immediately; security incident logged.

---

# Test Suite 13: End-to-End Master Acceptance Test Run

| Step | Action Description | Input / Payload | Verification Point | Status |
| :--- | :--- | :--- | :--- | :--- |
| **01** | Create Season Container | Name: "Hyderabad Summer Games", Kind: `season`, Fee: ₹500 flat | Status is `draft`. Badge displays "Draft". Registrations closed. | [ ] PASS |
| **02** | Add Competitions | Badminton Singles (Individual), Football 7s (HouseBatch), Cricket (Teams) | Formats match sport type; performance warnings checked. | [ ] PASS |
| **03** | Open Badminton Entries | Click "Open Registrations" | Badminton is `registration_open`. Season lifts to `entries_open`. | [ ] PASS |
| **04** | User Registrations | 4 Badminton singles players, 14 Footballers with House tags | Registrations confirm; counters increment accurately. | [ ] PASS |
| **05** | Close Entries & Promote | Tap "Close Entries & Build Draw" | Entrant Promoter builds 4 solo seeds and 2 House teams. | [ ] PASS |
| **06** | Setup Venues & Times | Add Stadium (2 Courts, 08:00 - 18:00, 45m match + 15m turnaround) | Capacity calculated as $\le 10$ matches/court/day. | [ ] PASS |
| **07** | Generate Timetable | Auto-Schedule all matches | Zero player overlap; rest gap enforced; no double-booked courts. | [ ] PASS |
| **08** | Assign Officials | Run Neutral Assigner with neutral & partisan pool | Only neutral referees assigned; unstaffed conflicts reported. | [ ] PASS |
| **09** | Launch Matchday Live | Start Matchday 2026-10-05 | Concurrent matches show LIVE; provisional scores active. | [ ] PASS |
| **10** | Live Scoring Pad | Score 1st set of Badminton. Use Undo button once. | Score timeline reflects points; undo reverts cleanly. | [ ] PASS |
| **11** | Player Retirement | Player A injured at 18-12. Umpire selects "Retire Player A". | Match `completed`; Winner = B; Score reads `12-18 (R)`. Pad locked. | [ ] PASS |
| **12** | Sign-Off & Finalize | Resolve any dispute and finalize match | Status moves to `completed`; badge changes from PROVISIONAL to OFFICIAL. | [ ] PASS |
| **13** | Standings & Leaderboard | Check Season Leaderboard | Medal tally updates (Gold/Silver/Bronze); Player dossier reflects result. | [ ] PASS |
| **14** | Stats Reconciliation | Compare player profile stats with match scorecard | Match score $\equiv$ Season player stats $\equiv$ Career stats delta. | [ ] PASS |
| **15** | Glicko Settlement | Inspect Cloud Function execution log | Source = `season`, Result = `retired`, Field $\ge 4$: Ratings updated accurately. | [ ] PASS |
