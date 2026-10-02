# PlaySphere: Non-Tech Tester's Step-by-Step Guide
## Button-to-Button Manual Test Cases for the Complete Season & Tournament Flow

> **Who is this guide for?**  
> This guide is written for **non-technical testers, ground coordinators, tournament directors, and club volunteers**.  
> You do **not** need any coding knowledge or database tools. Every test case tells you:
> 1. Exactly **where to look** on the mobile or web screen.
> 2. Exactly **what button to tap** or **what text to type**.
> 3. Exactly **what visual confirmation to expect** on your screen.
> 4. What **mistakes or error messages** to watch out for.

---

## Quick Navigation Index

- [Phase 1: Creating a Season & Setting Up Sports](#phase-1-creating-a-season--setting-up-sports) (TC-01 to TC-06)
- [Phase 2: Opening Registrations & Entry Modes](#phase-2-opening-registrations--entry-modes) (TC-07 to TC-13)
- [Phase 3: Venues, Grounds, Courts & Capacity Planning](#phase-3-venues-grounds-courts--capacity-planning) (TC-14 to TC-16)
- [Phase 4: Generating Schedule & Checking Conflicts](#phase-4-generating-schedule--checking-conflicts) (TC-17 to TC-20)
- [Phase 5: Assigning Umpires & Checking Neutrality](#phase-5-assigning-umpires--checking-neutrality) (TC-21 to TC-24)
- [Phase 6: Match Day Live & Starting a Match](#phase-6-match-day-live--starting-a-match) (TC-25 to TC-27)
- [Phase 7: In-Match Live Scoring, Undo & Controls](#phase-7-in-match-live-scoring-undo--controls) (TC-28 to TC-31)
- [Phase 8: Retirements, Walkovers & Match Endings](#phase-8-retirements-walkovers--match-endings) (TC-32 to TC-35)
- [Phase 9: Disputes, Verification & Finalization](#phase-9-disputes-verification--finalization) (TC-36 to TC-38)
- [Phase 10: Checking Leaderboards & Standings](#phase-10-checking-leaderboards--standings) (TC-39 to TC-41)
- [Phase 11: Player Profiles, Stats & Glicko Ratings](#phase-11-player-profiles-stats--glicko-ratings) (TC-42 to TC-46)

---

# Phase 1: Creating a Season & Setting Up Sports

---

### Test Case 01: Creating a New Season Container (Draft Mode)
* **Goal**: Create a new multi-sport season container and verify it starts safely as a **Draft** so players cannot see or register for it prematurely.
* **Pre-conditions**: Open the PlaySphere app and log in with your Club Organizer account.
* **Step-by-Step Instructions**:
  1. On the bottom navigation bar, tap the **Club / Organizer** icon (briefcase icon).
  2. Look for the **Seasons & Tournaments** card and tap the **+ Create Season** button.
  3. You will see a form titled **"New season"** with the subtitle *"Several sports on one calendar"*.
  4. In the **"Season name"** box, tap and type: `Hyderabad Summer Games 2026`.
  5. Scroll down to **"Starts"**. Tap the date box.
     * In the calendar popup, select **tomorrow's date** (e.g., if today is October 1, tap October 2).
     * Tap **OK**.
     * *Note: The app will deliberately block you from selecting today or any past date.*
  6. Scroll to **"Ends (optional)"**. Tap the date box.
     * Pick a date **7 days after** the start date. Tap **OK**.
  7. Under **"Container Kind"**, make sure **"Season (Multi-Sport)"** is selected (not "Tournament").
  8. Under **"Tournament Grade"**, tap the dropdown and pick **"District"**.
  9. Scroll down to the bottom right and tap the blue button: **Save as Draft**.
* **What you should see on your screen**:
  * The screen returns to your Organizer Dashboard.
  * You see a card titled **Hyderabad Summer Games 2026**.
  * Next to the title, there is a prominent gray badge labeled **DRAFT**.
  * The card displays: *"Entries Closed / Not Open Yet"*.

---

### Test Case 02: Adding an Individual Sport (Badminton Men's Singles)
* **Goal**: Add a standard 1-on-1 knockout sport to your season.
* **Step-by-Step Instructions**:
  1. On your Organizer Dashboard, tap on **Hyderabad Summer Games 2026**.
  2. Scroll down to the **"Sports & Competitions"** section.
  3. Tap the button: **+ Add Sport / Category**.
  4. In the sports list that slides up, tap **Badminton**.
  5. Under **"Arrangement"**, tap **Singles (1 vs 1)**.
  6. Under **"Category / Age Group"**, tap **Men's Open**.
  7. Under **"Competition Format"**, select **Knockout**.
  8. Under **"Entry Mode"**, verify it defaults to **"Individual"**.
  9. Tap the **Save Category** button at the bottom.
* **What you should see on your screen**:
  * You return to the season page.
  * A new card appears under Sports: **Badminton — Men's Open Singles (Knockout)**.
  * The status chip on this card says **Draft**.

---

### Test Case 03: Adding an Intra-Club School House Sport (Football 7s)
* **Goal**: Add a sport where students from the same school/club register under their respective Houses (e.g., Red House, Blue House) and are grouped into teams.
* **Step-by-Step Instructions**:
  1. Inside **Hyderabad Summer Games 2026**, tap **+ Add Sport / Category**.
  2. In the list, tap **Football**.
  3. Under **"Arrangement"**, tap **7-a-side**.
  4. Under **"Category"**, pick **Junior Boys (U-16)**.
  5. Under **"Entry Mode"**, tap the option: **"House Batch (Club Members by House)"**.
  6. Under **"Format"**, select **Round Robin (League Table)**.
  7. Tap **Save Category**.
* **What you should see on your screen**:
  * A new card appears: **Football 7s — Junior Boys (Round Robin)**.
  * Notice the tag: **House Teams Entry**.

---

### Test Case 04: Adding a Visiting Club Sport (Cricket T20)
* **Goal**: Add a sport where outside visiting clubs register entire pre-formed teams.
* **Step-by-Step Instructions**:
  1. Inside the season, tap **+ Add Sport / Category**.
  2. Tap **Cricket**.
  3. Under **"Arrangement"**, tap **11-a-side (T20)**.
  4. Under **"Entry Mode"**, tap **"Pre-formed Team (External Clubs / Teams)"**.
  5. Tap **Save Category**.
* **What you should see on your screen**:
  * A card appears: **Cricket 11-a-side T20**.
  * Tag shows: **Team Entry (Visiting Clubs)**.

---

### Test Case 05: Checking the Warning on Performance Sports (Athletics 100m)
* **Goal**: Verify that running/swimming sports show a helpful warning explaining that they don't produce head-to-head match brackets.
* **Step-by-Step Instructions**:
  1. Tap **+ Add Sport / Category**.
  2. Tap **Athletics (Track & Field)** > select **100m Sprint**.
  3. Look at the **Competition Format** dropdown.
  4. Look at the notice card directly below it with a stopwatch icon.
* **What you should see on your screen**:
  * Knockout and Round Robin options are **not** present. Only **"Heats then Final"** or **"Final Only"** can be chosen.
  * Notice text states: *"Athletics 100m will not be timetabled as pairwise matches. These are recorded as timed heats."*
  * Tap **Cancel** to exit without saving.

---

### Test Case 06: Choosing Season Fee Mode (Flat Fee vs Per-Sport Fee)
* **Goal**: Test the two ways to charge players: once for the whole season or per individual sport.
* **Step-by-Step Instructions**:
  1. At the top of your season setup page, look at the **"Entry Fee"** section.
  2. **Option A (Whole Season Fee)**:
     * Tap the radio button: **"One fee for the whole season"**.
     * A text box appears below labeled **"Season Entry Fee (₹)"**.
     * Type `500`.
     * Scroll down to your Badminton and Football cards. Notice that the fee boxes on those cards disappear or read *"Included in season fee"*.
  3. **Option B (Per-Sport Fee)**:
     * Switch the radio button to: **"A separate fee for each sport"**.
     * Notice the top season fee box vanishes.
     * Look at the Badminton card: a text box appears labeled **"Entry Fee (₹)"**. Type `200`.
     * Look at the Cricket card: a text box appears. Type `1500`.
  4. Switch back to **"One fee for the whole season"**, enter `500`, and tap **Save Changes**.
* **What you should see on your screen**:
  * The season summary displays: *"Entry: ₹500 covers all sports"*.

---

# Phase 2: Opening Registrations & Entry Modes

---

### Test Case 07: Opening Entries and Automatic Status Transition
* **Goal**: Open the doors for registrations and verify the season status changes automatically from "Draft" to "Entries Open".
* **Step-by-Step Instructions**:
  1. Open your season **Hyderabad Summer Games 2026**.
  2. Tap on the **Badminton Men's Singles** card.
  3. Look at the top banner: it says *"Status: Draft (Closed)"*.
  4. Tap the green button labeled **Open Registrations**.
  5. A popup asks: *"Open registrations for this event? Players will be able to register immediately."* Tap **Confirm**.
  6. Tap the back arrow to return to the Season Home page.
* **What you should see on your screen**:
  * The gray **DRAFT** badge on the season has vanished!
  * It is replaced by a bright green badge: **ENTRIES OPEN**.
  * Switch to a different test user account (a regular player). On their app home screen, the season now appears under **"Open for Registration"**.

---

### Test Case 08: Individual Player Registration (Badminton)
* **Goal**: A regular player registers themselves for an individual event.
* **Step-by-Step Instructions**:
  1. Log in as regular player `Alice` (`alice@test.com`).
  2. Find **Hyderabad Summer Games 2026** and tap it.
  3. Tap on **Badminton Men's Singles**.
  4. Tap the large blue button at the bottom: **Register for Event**.
  5. A registration sheet slides up displaying Alice's Name, Age, and Contact info.
  6. Tap the checkbox: *"I agree to tournament rules"*.
  7. Tap the button: **Submit Registration**.
  8. Repeat this step with 3 more accounts: `Bob`, `Charlie`, and `David`.
* **What you should see on your screen**:
  * A green success banner: *"Registration Confirmed! You are entered in Badminton Men's Singles."*
  * On the organizer's screen, the entrant count updates to **"4 Registered"**.
  * If `Alice` taps the register button a second time, the app displays: *"You are already registered for this event."*

---

### Test Case 09: School House Registration (Garuda vs Kowshika)
* **Goal**: Students register for Football and select their respective school houses.
* **Step-by-Step Instructions**:
  1. Log in as Student 1. Go to **Hyderabad Summer Games 2026** > **Football 7s**.
  2. Tap **Register**.
  3. The form displays a dropdown: **"Select your House"**.
  4. Tap the dropdown and select **"Garuda House"**.
  5. Tap **Submit**.
  6. Have 3 more students register selecting **"Garuda House"**.
  7. Have 4 other students register selecting **"Kowshika House"**.
* **What you should see on your screen**:
  * Total registration counter shows **8 players registered**.
  * In the organizer view under Registrations, players are tagged with their respective houses:
    * 4 under `Garuda House`
    * 4 under `Kowshika House`

---

### Test Case 10: Visiting Club Team Registration (Cricket)
* **Goal**: A manager from an external club enters a pre-formed team with their squad roster.
* **Step-by-Step Instructions**:
  1. Log in as `Manager Mike` from visiting club **"Cyberabad Strikers"**.
  2. Open the season invitation link or find the season under Discover.
  3. Tap on **Cricket T20**.
  4. Tap **Register Team**.
  5. Enter Team Name: `Cyberabad Strikers XI`.
  6. Tap **+ Add Players from Club Roster**. Select 11 players from the checklist.
  7. Tap **Submit Team Entry**.
  8. Log in as Manager 2 from **"Secunderabad RFC"** and repeat with their 11 players.
* **What you should see on your screen**:
  * Organizer screen shows: **2 Confirmed Teams** (`Cyberabad Strikers XI` and `Secunderabad RFC`).
  * Both team squads are locked and visible.

---

### Test Case 11: One Athlete Registering in Two Categories
* **Goal**: Ensure an active player can enter multiple sports/categories without system errors.
* **Step-by-Step Instructions**:
  1. Log in as `Rahul`.
  2. Go to Badminton Men's Singles > tap **Register** > tap **Confirm**.
  3. Return to the season > tap **Badminton Doubles** > tap **Register** > pick partner `Kiran` > tap **Confirm**.
* **What you should see on your screen**:
  * Both entries show as **Confirmed** under Rahul's "My Registrations" tab.

---

### Test Case 12: Closing Entries & Running the Entrant Promoter
* **Goal**: Close the registration deadline and assemble the final list of entrants into the draw.
* **Step-by-Step Instructions**:
  1. Log in as the Organizer. Open **Hyderabad Summer Games 2026**.
  2. Tap on **Football 7s**.
  3. Tap the orange button: **Close Registrations**.
  4. A button appears labeled: **Assemble Teams & Build Field**. Tap it.
* **What you should see on your screen**:
  * The system processes the 8 students from TC-09.
  * Instead of 8 individual players, it displays **2 Confirmed Entrant Teams**:
    * Team 1: `Garuda House` (4 members)
    * Team 2: `Kowshika House` (4 members)
  * Status changes to **Ready for Draw**.

---

### Test Case 13: Error Check: Trying to Build a Draw with Less than 2 Entrants
* **Goal**: Verify the app prevents generating a draw when there are not enough players.
* **Step-by-Step Instructions**:
  1. Create a dummy test event: `Chess Open`.
  2. Register only **1 player**.
  3. Tap **Close Registrations**.
  4. Tap **Generate Fixtures**.
* **What you should see on your screen**:
  * An error dialog pops up: *"Cannot generate draw: At least 2 entrants are required to build a timetable."*
  * The button to create matches remains disabled.

---

# Phase 3: Venues, Grounds, Courts & Capacity Planning

---

### Test Case 14: Adding a Venue with Multiple Courts
* **Goal**: Add a sports complex with multiple playing courts/pitches and opening hours.
* **Step-by-Step Instructions**:
  1. Open your season > tap the **Venues & Grounds** tab.
  2. Tap the button: **+ Add Ground / Venue**.
  3. In **"Venue Name"**, type: `Gachibowli Sports Complex`.
  4. Under **"Daily Hours"**:
     * Set **Opens At**: `08:00 AM`.
     * Set **Closes At**: `08:00 PM` (12 total hours).
  5. Under **"Courts / Pitches"**, tap **+ Add Court**:
     * Court 1 name: `Badminton Court 1`.
     * Tap **+ Add Court** again > Court 2 name: `Badminton Court 2`.
     * Tap **+ Add Court** again > Court 3 name: `Main Football Ground`.
  6. Tap **Save Venue**.
* **What you should see on your screen**:
  * The venue card displays: **Gachibowli Sports Complex (3 Courts)**.
  * Operating Window shows: `08:00 - 20:00 (12 hours / day)`.

---

### Test Case 15: Setting Match Timings & Turnaround Buffers
* **Goal**: Configure how long matches take and how much buffer time is needed between matches.
* **Step-by-Step Instructions**:
  1. In the **Venues & Grounds** tab, tap **Timings & Capacity Plan**.
  2. Under **"Default Match Duration"**, type `45` minutes (for Badminton).
  3. Under **"Court Changeover / Turnaround"**, type `15` minutes (for cleaning/warmup).
  4. Under **"Athlete Rest Gap"**, type `30` minutes (minimum rest a player gets between two matches).
  5. Tap **Save Timings**.
* **What you should see on your screen**:
  * The app calculates that each match slot takes $45 + 15 = 60\text{ minutes}$ (1 hour).

---

### Test Case 16: Checking Mathematical Capacity (Does It Fit?)
* **Goal**: Check the built-in calculator that warns you if you try to squeeze too many matches into a day.
* **Step-by-Step Instructions**:
  1. Look at the **Capacity Forecast** card on the screen.
  2. With 12 operating hours and 1-hour match slots, notice it says: *"Capacity: 12 matches per court per day"*.
  3. Find the box labeled **"Organizer Daily Cap (optional)"**.
  4. Type `15`.
* **What you should see on your screen**:
  * An orange warning pill appears: **"Exceeds physical hours!"**
  * Subtitle reads: *"You set a limit of 15 matches, but operating hours only hold 12. The timetable will enforce 12 matches maximum."*
  * Change the box to `10`. The warning disappears and says: *"Strict limit of 10 matches active."*

---

# Phase 4: Generating Schedule & Checking Conflicts

---

### Test Case 17: Generating a Knockout Draw with Automatic Byes
* **Goal**: Generate a fair knockout bracket for our 4 badminton players (`Alice`, `Bob`, `Charlie`, `David`).
* **Step-by-Step Instructions**:
  1. Open **Badminton Men's Singles**.
  2. Tap the **Draw & Fixtures** tab.
  3. Tap the blue button: **Generate Draw**.
  4. In the format selector, pick **Knockout Bracket**.
  5. Tap **Build Fixtures**.
* **What you should see on your screen**:
  * A tournament bracket diagram appears on screen:
    * **Semifinal 1**: `Alice vs Bob`
    * **Semifinal 2**: `Charlie vs David`
    * **Final**: Winner SF1 vs Winner SF2
  * Both Semifinal matches are marked with status **Scheduled**.

---

### Test Case 18: Checking Player Conflict Prevention (Singles vs Doubles)
* **Goal**: Verify the timetable engine NEVER schedules the same player at the same time on two courts.
* **Pre-conditions**: Remember `Rahul` from TC-11 is in both Singles and Doubles.
* **Step-by-Step Instructions**:
  1. Open the **Season Timetable** tab.
  2. Tap the button: **Auto-Schedule All Events**.
  3. When scheduling finishes, look at Rahul's matches:
     * Find **Rahul's Singles Match**. Note the court and time (e.g., `Court 1 at 09:00 AM - 09:45 AM`).
     * Find **Rahul's Doubles Match**. Note the court and time.
* **What you should see on your screen**:
  * Rahul's Doubles match is **not** scheduled at 09:00 AM!
  * Even though `Court 2` was completely empty at 09:00 AM, the app refused to put Rahul there.
  * Rahul's Doubles match is placed at `10:15 AM` or later, giving him his mandatory 30-minute rest gap.

---

### Test Case 19: Preventing Court Overlap
* **Goal**: Verify you cannot manually drag or force two matches onto the same court at the same time.
* **Step-by-Step Instructions**:
  1. In the Timetable calendar view, tap on Match 2 (`Charlie vs David`).
  2. Tap **Edit Time & Court**.
  3. Set Court to `Court 1` and time to `09:15 AM` (which collides with Match 1 running 09:00 to 09:45).
  4. Tap **Save**.
* **What you should see on your screen**:
  * The screen rejects the save.
  * A red error banner pops up: *"Court Collision: Court 1 is already booked until 09:45 AM (+15m turnaround)."*
  * The match stays in its original valid slot.

---

### Test Case 20: Publishing the Schedule
* **Goal**: Make the schedule visible to players and the public.
* **Step-by-Step Instructions**:
  1. At the top of the Timetable page, tap the button: **Publish Timetable**.
  2. A confirmation asks: *"Publish timetable to all participants? Push notifications will be sent."*
  3. Tap **Publish**.
* **What you should see on your screen**:
  * The season status badge updates to **SCHEDULED**.
  * Players opening the app can now see their match timings, court numbers, and opponents under "My Upcoming Matches".

---

# Phase 5: Assigning Umpires & Checking Neutrality

---

### Test Case 21: Auto-Assigning a Neutral Umpire
* **Goal**: Ensure the umpire assigner picks an official who has NO ties to either playing team.
* **Pre-conditions**:
  * Match: `Cyberabad Strikers` vs `Secunderabad RFC`.
  * Available Officials in pool:
    * `Umpire Suresh` (Club: Cyberabad Strikers)
    * `Umpire Naresh` (Club: Secunderabad RFC)
    * `Umpire Peter` (Club: Warangal Warriors - Neutral)
* **Step-by-Step Instructions**:
  1. Open the season > tap the **Officials & Referees** tab.
  2. Tap the button: **Auto-Assign Match Officials**.
  3. Open the match card for `Cyberabad vs Secunderabad`.
  4. Look at the **Assigned Official** field.
* **What you should see on your screen**:
  * The assigned official is **Umpire Peter**!
  * Next to Peter's name is a shield icon with: **"Neutral Official"**.
  * Suresh and Naresh were skipped because their clubs were playing.

---

### Test Case 22: Assigning a Freelance / Unaffiliated Referee
* **Goal**: Verify that an independent referee with no club affiliation is treated as neutral everywhere.
* **Step-by-Step Instructions**:
  1. Add an official: `Umpire John` with Club field left **Blank** (Freelance).
  2. Run the assigner for any match.
* **What you should see on your screen**:
  * The assigner happily assigns `Umpire John` without any neutrality warnings.

---

### Test Case 23: Transparent Alert When No Neutral Umpire Exists
* **Goal**: Ensure the app does NOT quietly assign a biased referee when only club members are available.
* **Pre-conditions**: Temporarily remove Umpire Peter so only Suresh (Cyberabad) and Naresh (Secunderabad) are available.
* **Step-by-Step Instructions**:
  1. Run **Auto-Assign Match Officials**.
  2. Look at the match card for `Cyberabad vs Secunderabad`.
* **What you should see on your screen**:
  * The match official box says: **"Unstaffed (No Neutral Official Available)"** in yellow text.
  * Below it, a note explains: *"All available umpires belong to one of the contesting clubs. Assign manually if both captains agree."*

---

### Test Case 24: Enforcing Daily Match Limits on Umpires
* **Goal**: Make sure an official is not overworked beyond their daily limit.
* **Step-by-Step Instructions**:
  1. Edit `Umpire Peter`'s profile > set **"Max Matches Per Day"** = `2`.
  2. Schedule 3 matches throughout the day.
  3. Assign Peter to Match 1 and Match 2.
  4. Attempt to assign Peter to Match 3.
* **What you should see on your screen**:
  * In the dropdown picker for Match 3, Peter's name is grayed out.
  * Text beside his name reads: *"Daily quota reached (2/2 matches)"*.

---

# Phase 6: Match Day Live & Starting a Match

---

### Test Case 25: Viewing the Live Matchday Hub
* **Goal**: Verify that on game day, all sports running concurrently show up on one live dashboard.
* **Step-by-Step Instructions**:
  1. On the main bottom navigation bar, tap the **Match Day** tab (whistle icon).
  2. Select today's date on the date strip.
  3. Look at the screen.
* **What you should see on your screen**:
  * A clean, categorized screen showing all events scheduled for today:
    * Under **Badminton**: Semifinal 1 (`Alice vs Bob`), Semifinal 2 (`Charlie vs David`).
    * Under **Football**: `Garuda House vs Kowshika House`.
    * Under **Cricket**: `Cyberabad vs Secunderabad`.
  * Each card shows Court number, Time, and a gray **Scheduled** tag.

---

### Test Case 26: Pre-Match Setup (Toss & Court Side)
* **Goal**: Start a match and record the official toss.
* **Step-by-Step Instructions**:
  1. On the Match Day screen, tap on **Badminton Semifinal 1 (`Alice vs Bob`)**.
  2. Tap the large green button: **Start Match**.
  3. A pre-match dialog appears:
     * Under **"Toss Won By"**, tap **Alice**.
     * Under **"Elected To"**, tap **Serve**.
     * Under **"Court Side"**, tap **Left**.
  4. Tap the button: **Confirm & Open Scorepad**.
* **What you should see on your screen**:
  * The live digital scoring pad opens immediately.
  * In the background and on spectator screens, the match status changes from Scheduled to a pulsing red tag: **LIVE**.
  * Score displays: `Alice 0 - 0 Bob` with a small gray label: **Provisional**.

---

### Test Case 27: Multi-Sport Simultaneous Play Isolation
* **Goal**: Make sure two scorers on two separate phones can score different sports at the same time without cross-contamination.
* **Step-by-Step Instructions**:
  1. On **Phone 1**: Open Badminton (`Alice vs Bob`) and score 5 points.
  2. On **Phone 2**: Open Football (`Garuda vs Kowshika`), tap **Start Match**, and log a Goal for Garuda House.
  3. Check the spectator live feed on a third phone.
* **What you should see on your screen**:
  * Badminton shows `Alice 5 - 0 Bob`.
  * Football shows `Garuda House 1 - 0 Kowshika House`.
  * The events and scores are 100% isolated.

---

# Phase 7: In-Match Live Scoring, Undo & Controls

---

### Test Case 28: Live Badminton Scoring (Points, Deuce & Game End)
* **Goal**: Test standard point scoring, serving indicator, and deuce rules.
* **Step-by-Step Instructions**:
  1. On the Badminton scorepad:
     * Tap the big **+1 Alice** button 5 times.
     * Notice Alice's score is `5`, serving indicator is on Alice's side.
     * Tap **+1 Bob** 3 times. Bob's score is `3`.
  2. Fast-forward test (tap buttons) until the score reaches `20 - 20`.
  3. Notice a yellow badge appears: **DEUCE**.
  4. Tap **+1 Alice** (Score: `21 - 20`). Notice the game does **not** end because a 2-point lead is required!
  5. Tap **+1 Alice** again (Score: `22 - 20`).
* **What you should see on your screen**:
  * A celebration popup appears: **"Game 1 Won by Alice (22 - 20)"**!
  * Set score updates to: `Alice 1 - 0 Bob`.
  * A button prompts: **Start Game 2 (Swap Ends)**.

---

### Test Case 29: Live Cricket Scoring (Runs, Wides, Wickets)
* **Goal**: Test the cricket pad buttons and scorecard tracking.
* **Step-by-Step Instructions**:
  1. Open Cricket Match (`Cyberabad vs Secunderabad`) > tap **Start Match**.
  2. Select opening striker, non-striker, and bowler > tap **Start Scoring**.
  3. On the cricket keypad:
     * Tap **1**. Verify the score is `1/0 (0.1 ov)`. Notice the striker dot switches to the other batsman.
     * Tap **4** (Boundary). Verify score is `5/0 (0.2 ov)`. Striker stays on strike.
     * Tap **WD** (Wide). Verify score is `6/0 (0.2 ov)`. Over ball count did **not** advance!
     * Tap **WICKET**. A popup asks dismissal type. Tap **Caught** > select fielder > select next batsman > tap **Confirm**.
* **What you should see on your screen**:
  * Total score reads: `6/1 (0.2 overs)`.
  * Batter 1 shows: `5 runs (2 balls) - OUT`.
  * Bowler figures show: `0.2 overs, 1 wicket, 5 runs`.

---

### Test Case 30: Fixing a Mistake with the "Undo" Button
* **Goal**: Easily reverse an accidental tap without messing up the match state.
* **Step-by-Step Instructions**:
  1. On the cricket pad, accidentally tap **6** instead of **0**.
  2. Score jumps to `12/1`.
  3. Look at the bottom toolbar and tap the **Undo** button (counter-clockwise arrow).
* **What you should see on your screen**:
  * The last 6 runs are immediately cancelled.
  * Score returns to `6/1 (0.2 overs)`.
  * The batsman's individual runs and bowler's economy revert back seamlessly.

---

### Test Case 31: Pausing a Match (Rain Delay or Injury Stoppage)
* **Goal**: Temporarily pause a match and let spectators know what is happening.
* **Step-by-Step Instructions**:
  1. During live play, tap the top-right **Options (3 dots)** menu.
  2. Tap **Pause Match**.
  3. In the reason dialog, select **"Rain / Weather Stoppage"**. Tap **Confirm**.
  4. View the match on a spectator phone.
  5. After a few moments, on the umpire phone, tap **Resume Match**.
* **What you should see on your screen**:
  * While paused: The scoring buttons are locked, and the red LIVE badge changes to a yellow badge: **PAUSED (Rain / Weather Stoppage)**.
  * When resumed: Buttons unlock and the badge switches back to **LIVE**.

---

# Phase 8: Retirements, Walkovers & Match Endings

---

### Test Case 32: Player In-Match Injury / Retirement (Retire Hurt)
* **Goal**: Properly record when a player twists an ankle or suffers an injury and cannot continue playing.
* **Pre-conditions**:
  * Badminton match: `Alice vs Bob`.
  * Score in Game 2 is `Alice 14 - 10 Bob`.
  * `Alice` twists her ankle and cannot play.
* **Step-by-Step Instructions**:
  1. On the scorepad, tap the **Options (3 dots)** menu or **Match Ruling** button.
  2. Tap the red button: **Retire Player / Injury**.
  3. In the dialog:
     * Under **"Who is retiring?"**, tap **Alice**.
     * Under **"Reason"**, select **Injury / Medical**.
     * In the notes box, type: `Severe right ankle sprain during rally`.
  4. Tap the button: **Confirm Retirement**.
* **What you should see on your screen**:
  * The match ends immediately!
  * A dialog announces: **"Match Concluded by Retirement. Winner: Bob."**
  * The final score is recorded with an **(R)** badge: e.g., `10-14 (R)`.
  * The scoring pad is locked so no further buttons can be tapped.
  * **Crucial Rule**: Because real sport was played until the injury, this match counts as a genuine played match (Bob gets the win, Alice gets the loss).

---

### Test Case 33: Cricket Batsman Retired Hurt vs Retired Out
* **Goal**: Verify the difference between an injured batsman (not out) and a tactical retirement (counted as a wicket).
* **Step-by-Step Instructions**:
  1. **Case A (Retired Hurt)**:
     * Batter is hit by ball. Tap **Wicket / Retire** > choose **"Retired Hurt"**.
     * Pick replacement batter.
     * Look at team score: total wickets **does not** increase. Scorecard lists batter as `Retired Hurt (Not Out)`. Bowler is **not** given a wicket.
  2. **Case B (Retired Out)**:
     * Batter leaves tactically. Tap **Wicket / Retire** > choose **"Retired Out"**.
     * Look at team score: total wickets **increases by 1**. Bowler is **not** credited with a personal wicket. Scorecard lists `Retired Out`.

---

### Test Case 34: Handling a Walkover (Opponent No-Show)
* **Goal**: Award a match when one team fails to show up.
* **Step-by-Step Instructions**:
  1. Open a scheduled match where Team B did not arrive.
  2. Tap **Start Match Options** > select **Award Walkover (W/O)**.
  3. Select Winner: **Team A**.
  4. Reason: `Team B failed to report to ground within 30 minutes of scheduled start.`
  5. Tap **Confirm Walkover**.
* **What you should see on your screen**:
  * Match is marked **Completed**.
  * Score displays: **W/O** (Walkover).
  * Team A automatically advances to the next round in the bracket.
  * *Note: No balls or runs are recorded.*

---

### Test Case 35: Match Abandonment (Unplayable Pitch)
* **Goal**: Cancel a match due to waterlogged ground or power failure.
* **Step-by-Step Instructions**:
  1. Open the match > tap **Options** > tap **Abandon Match**.
  2. Select Reason: `Waterlogged pitch due to storm`.
  3. Tap **Confirm**.
* **What you should see on your screen**:
  * Match status displays **Abandoned (A)**.
  * Neither team is declared winner.
  * Tournament points table gives 1 shared point to both teams (or schedules a replay).

---

# Phase 9: Disputes, Verification & Finalization

---

### Test Case 36: Captain / Umpire Post-Match Sign-Off
* **Goal**: Both captains review the final scoresheet and sign off before official submission.
* **Step-by-Step Instructions**:
  1. After the final point/ball, the screen displays **"Match Summary Review"**.
  2. Show the phone to Team A Captain: Tap **Captain A Sign-off**.
  3. Show the phone to Team B Captain: Tap **Captain B Sign-off**.
  4. Umpire taps **Submit Official Scorecard**.
* **What you should see on your screen**:
  * Status changes from **PROVISIONAL** to **PENDING FINALIZATION**.

---

### Test Case 37: Raising a Match Dispute
* **Goal**: Test the complaint workflow if a team believes an umpire miscounted runs/points.
* **Step-by-Step Instructions**:
  1. As Team B Captain, on the match review screen, tap the link: **"Notice an error? Raise a Dispute"**.
  2. In the text box, type: `In Over 3.2, umpire signaled 4 runs, but scoreboard only added 1 run.`
  3. Tap **Submit Dispute**.
* **What you should see on your screen**:
  * The match status card displays a bold red badge: **DISPUTED**.
  * Next round bracket progression is **frozen** (the winner cannot play next round until this is resolved).
  * The Tournament Director receives an alert on their console.

---

### Test Case 38: Organizer Dispute Resolution & Official Finalization
* **Goal**: Tournament director reviews the event log, applies a correction, and locks the match officially.
* **Step-by-Step Instructions**:
  1. Log in as Tournament Director.
  2. Open the **Disputes** tab > tap the disputed match.
  3. Tap **Review Event Timeline**.
  4. Scroll to Over 3.2 > tap **Edit Event** > change runs from `1` to `4`.
  5. In Director Note, type: `Verified with scorebook; adjusted 3 missing runs.`
  6. Tap the green button: **Approve & Finalize Official Result**.
* **What you should see on your screen**:
  * The dispute is resolved.
  * The match status badge permanently turns dark green: **OFFICIAL**.
  * The winning team automatically moves into the next bracket slot!
  * Scorecard is permanently locked; no further edits allowed.

---

# Phase 10: Checking Leaderboards & Standings

---

### Test Case 39: Checking Single-Sport League Standings (Points Table)
* **Goal**: Verify that win, loss, points, and net run rate update correctly after a league match.
* **Pre-conditions**: Complete a football or cricket league match where Team A beats Team B.
* **Step-by-Step Instructions**:
  1. Open the Season > tap on **Football 7s**.
  2. Tap the **Standings / Table** tab.
  3. Look at the table columns.
* **What you should see on your screen**:
  * Table columns show: **P** (Played), **W** (Won), **L** (Lost), **D** (Draw), **GD/NRR**, **PTS** (Points).
  * Team A has: `P: 1, W: 1, L: 0, PTS: 3` (or 2 points depending on rules).
  * Team B has: `P: 1, W: 0, L: 1, PTS: 0`.
  * Team A is at the top of the table.

---

### Test Case 40: Multi-Sport Olympics Medal Board (Gold, Silver, Bronze)
* **Goal**: Verify the overall multi-sport leaderboard combining medals across Badminton, Football, and Cricket.
* **Pre-conditions**:
  * Badminton concludes: Gold = `Cyberabad Strikers`, Silver = `Secunderabad RFC`.
  * Football concludes: Gold = `Garuda House`, Silver = `Kowshika House`.
* **Step-by-Step Instructions**:
  1. Open the Season Home page.
  2. Tap the **Overall Season Leaderboard** tab.
  3. Look at the medal standings table.
* **What you should see on your screen**:
  * A podium/table styled like the Olympics:
    * Columns: **Rank**, **Club / House**, **🥇 Gold**, **🥈 Silver**, **🥉 Bronze**, **Total Points**.
    * Points calculated accurately: (e.g., Gold = 5 pts, Silver = 3 pts).
    * Clubs/Houses are ranked by most Golds first, then most Silvers, then Total Points.

---

### Test Case 41: Viewing a Team's Season Dossier (Entrant Record)
* **Goal**: Tap on any club/team on the leaderboard to see all their results in this season.
* **Step-by-Step Instructions**:
  1. On the Overall Leaderboard, tap on the row for **Cyberabad Strikers**.
  2. A dedicated card opens titled: *"Cyberabad Strikers in THIS Season"*.
  3. Look at the match list.
* **What you should see on your screen**:
  * It shows only matches relevant to Cyberabad Strikers.
  * Every match is labeled from THEIR perspective:
    * `WON vs Secunderabad RFC (142 - 120)` in green text.
    * `UPCOMING vs Titans Club` in blue text.

---

# Phase 41: Player Profiles, Stats & Glicko Ratings

---

### Test Case 42: Verifying Player Profile Stats Updated from Scorecard
* **Goal**: Check that runs, wickets, points scored in a match appear on the player's profile.
* **Pre-conditions**: In TC-29, batsman Vikram scored runs.
* **Step-by-Step Instructions**:
  1. In the app, tap on **Search** or **Community** > search for player `Vikram`.
  2. Tap on Vikram's profile.
  3. Tap the **Season 2026 Stats** tab.
* **What you should see on your screen**:
  * His batting runs match the scorecard figure.
  * His matches played count has incremented by 1.

---

### Test Case 43: Casual Match Isolation (Casual Matches Don't Taint Season Stats)
* **Goal**: Verify that playing a casual weekend challenge match outside the tournament does NOT affect season standings.
* **Step-by-Step Instructions**:
  1. Have player Vikram play a casual 1v1 challenge in the park and score 50 runs.
  2. Return to the **Hyderabad Summer Games 2026** Cricket Leaderboard.
  3. Check Vikram's run tally on the tournament leaderboard.
* **What you should see on your screen**:
  * His tournament run tally is **unchanged**. The casual match was kept outside the official season tournament stats!

---

### Test Case 44: Verifying Glicko-2 Skill Rating Update (Winner & Loser)
* **Goal**: Check that the official skill rating moves after an official season match.
* **Pre-conditions**:
  * Player A: Rating `1500`.
  * Player B: Rating `1500`.
* **Step-by-Step Instructions**:
  1. Play and officially finalize an official season match: Player A beats Player B.
  2. Go to Player A's profile > look at their **Skill Rating badge**.
  3. Go to Player B's profile > look at their **Skill Rating badge**.
* **What you should see on your screen**:
  * Player A's rating has **increased** (e.g., from `1500` to `1532`).
  * Player B's rating has **decreased** (e.g., from `1500` to `1468`).
  * Both players' rating confidence narrows (indicating more accuracy).

---

### Test Case 45: Verifying Rating Updates on Retired Matches
* **Goal**: Verify that when a player retires hurt (TC-32), ratings STILL update because genuine sport was played.
* **Step-by-Step Instructions**:
  1. Check ratings for Alice and Bob after Alice's injury retirement.
* **What you should see on your screen**:
  * Bob's rating increased (he was awarded the win).
  * Alice's rating decreased.
  * The match appears on their rating history as `Badminton (Ret.)`.

---

### Test Case 46: Verifying Rating DOES NOT Move on Walkovers or Small Fields
* **Goal**: Ensure no one can inflate their rating with fake walkovers or tiny 2-person tournaments.
* **Step-by-Step Instructions**:
  1. **Case A (Walkover)**: Check ratings after the Walkover in TC-34.
     * Verify: Ratings for both teams did **NOT** change!
  2. **Case B (Tiny 2-Person Event)**: In an event with only 2 or 3 entrants, finalize a match.
     * Verify: A note under rating history says: *"Unrated match: Competition requires at least 4 entrants to qualify for global rating points."*
* **What you should see on your screen**:
  * Ratings stay completely untouched, protecting fair play across PlaySphere!

---

# Non-Tech Tester's Quick "Golden Run" Checklist

Print or carry this 1-page checklist on the ground during tournament day:

```
[ ] 1. Season created as DRAFT.
[ ] 2. Added sports, formats, and venues.
[ ] 3. Opened registrations -> Badge turned to ENTRIES OPEN.
[ ] 4. Players/Houses/Teams registered successfully.
[ ] 5. Closed entries -> Entrant Promoter assembled correct teams.
[ ] 6. Generated schedule -> Checked NO player had 2 matches at same time.
[ ] 7. Verified rest gaps (at least 30 mins break).
[ ] 8. Assigned umpires -> Checked NO umpire officiated their own club.
[ ] 9. Matchday started -> Matches showed pulsing LIVE tag.
[ ] 10. Scored matches live -> Tested "Undo" button on a test point.
[ ] 11. Tested Retirement -> Selected injured player, verified (R) badge, pad locked.
[ ] 12. Captains signed off -> Match marked OFFICIAL.
[ ] 13. Checked Leaderboard -> Verified Gold/Silver/Bronze tally.
[ ] 14. Checked Player Profile -> Verified stats and rating badges updated.
```
