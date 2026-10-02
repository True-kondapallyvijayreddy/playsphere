# PlaySphere: Manual Test Guide for Seasons & Tournaments
## Tap-by-tap test cases for a non-technical tester using 4 devices

> **Who this is for:** anyone who can use a phone. You don't need any coding knowledge.
>
> **How to use it:** work through the tests **in order**, because later tests use what earlier ones created. For each test:
> 1. Do the steps on the device named in **bold** (for example **D1**).
> 2. Compare your screen with **✅ Expect**.
> 3. Tick **Pass** or **Fail**. If it fails, fill in a bug note (template at the end) and **carry on**. Don't stop the whole run for one failure.
>
> **Names on buttons:** button names in this guide are written exactly as the app shows them, **in bold**. If a button has a slightly different name but clearly does the same thing, that's a pass, but still write it down. If the button isn't there at all, that's a fail.

---

## 0. Before you start

### 0.1 The four devices

You need **4 devices** and **4 different Google accounts**, one per device. PlaySphere only has **Sign in with Google**. Don't use the same Google account on two devices: ratings and several tests need four *different people*.

| Device | Plays the role of | Suggested display name |
|---|---|---|
| **D1** | Organizer. Owns the host club | `Test Organizer` |
| **D2** | Player / student in the host club | `Test Player Two` |
| **D3** | Player in the host club **and** in the visiting club | `Test Player Three` |
| **D4** | Owner of the visiting club, and also a player in the host club | `Test Player Four` |

Stick a label on each device (D1, D2, D3, D4).

### 0.2 The names we'll create

| Thing | Name to type |
|---|---|
| Host club (owned by D1) | `PS Test Academy` |
| Visiting club (owned by D4) | `PS Visitors Club` |
| Season 1: inside the host club, with houses | `PS House Games 2026` |
| Season 2: open to other clubs | `PS Club Cup 2026` |
| Houses | `Garuda House`, `Kowshika House` |

> If a name is already taken (from an earlier test run), add a number, e.g. `PS House Games 2026 v2`. The app does not allow two seasons with the same name in one club. That's correct behaviour.

### 0.3 Where things are

* **Phone:** the bottom bar has **Home**, **My clubs**, **Live now**, **More**.
* **Laptop / web:** the same items sit in a sidebar on the left.
* **Club chip (top right):** shows which club you're looking at. **Everything you see belongs to that club only.** If something is "missing", first check that the right club is selected.

### 0.4 Timing

* A full run takes about **4–6 hours** with 4 people.
* Season dates must be **tomorrow or later**. Some tests (live scoring, match day) need matches scheduled for **today**. See the tip in Phase 6.
* A match result can be protested for **1 hour** after it finishes. Run Phase 11 soon after Phase 10.

---

# Phase 1: Accounts & Clubs

### TC-01: Sign in on all four devices
**All devices**
1. Open PlaySphere and tap **Sign in with Google**. Pick that device's Google account.
2. If asked to set up your profile, type the display name from table 0.1 and a date of birth that makes you **18 or older**. Finish the setup.

✅ Expect
* You land on **Home** without errors.
* Your name appears in the account/profile area (More → top card).

☐ Pass ☐ Fail

---

### TC-02: Create the host club and the visiting club
**D1**
1. **More** → **Create a club**.
2. Name: `PS Test Academy`. Fill in the required fields and save.

**D4**
3. **More** → **Create a club** → Name: `PS Visitors Club` → save.

✅ Expect
* Each club opens its own club page.
* The club page shows a **Club ID** / **Invite code**. Write both codes down.
* On D1, the club chip at the top right shows `PS Test Academy`. On D4 it shows `PS Visitors Club`.

☐ Pass ☐ Fail

---

### TC-03: Join clubs with the invite code
**D2, D3, D4**: join the **host** club
1. **More** → **Join a club** → enter the `PS Test Academy` invite code → send the request.

**D3**: also join the **visiting** club
2. **More** → **Join a club** → enter the `PS Visitors Club` code → send.

**D1**: approve
3. Open `PS Test Academy` → **Members**. Approve D2, D3 and D4 (**Approve**).

**D4**: approve
4. Open `PS Visitors Club` → **Members** → approve D3.

✅ Expect
* After approval, D2, D3 and D4 see `PS Test Academy` under **My clubs**.
* D3 sees **both** clubs under **My clubs**.
* A person who hasn't been approved yet doesn't appear as an active member.

☐ Pass ☐ Fail

---

### TC-04: The club chip keeps clubs separate
**D3** (member of both clubs)
1. Tap the club chip (top right) and pick `PS Visitors Club`.
2. Look at Home, invitations and notifications.
3. Switch the chip to `PS Test Academy` and look again.

✅ Expect
* With a club selected, you only see **that club's** events, invitations, approvals and live matches.
* Nothing from the other club is mixed in.

☐ Pass ☐ Fail

---

# Phase 2: Create Season 1 (inside the club, with houses)

### TC-05: Open the season wizard
**D1** (club chip = `PS Test Academy`)
1. On **Home** (or the club page), tap **New event**.
2. You see four choices: **Season**, **Tournament**, **Single match**, **Challenge another club**.
3. Tap **Season** (tap the card itself, not the small ⚡ icon).

✅ Expect
* A step-by-step screen titled **Create Season** opens, starting at **Season Details**.
* A banner names the club (`PS Test Academy`) and its Club ID.

☐ Pass ☐ Fail

---

### TC-06: Season Details and the name check
**D1**
1. Leave **Season Name** empty. The **Next** button should not move you forward.
2. Type `PS House Games 2026`. Optionally fill **Short Name** (`PHG`) and **Organizer**.
3. Tap **Next**.

✅ Expect
* **Next** only works once a name is typed.
* If a season with the same name already exists in this club, an error under the name says so and **Next** stays blocked.

☐ Pass ☐ Fail

---

### TC-07: Select sports and categories
**D1**, on the **Select Sports** step
1. Tick **Badminton**.
2. Tick **Football**.
3. Tick **Chess** (we'll use it later to test "not enough entries").
4. Tap **Next**.

✅ Expect
* **Next** stays blocked until at least one sport is ticked.
* Each ticked sport shows a category count.

☐ Pass ☐ Fail

---

### TC-08: Competition Structure
**D1**, on the **Competition Structure** step. There is one card per sport.
1. **Badminton:** **Arrangement** = **Singles**, **Category (Age / Gender)** = an open/adult category that all 4 testers qualify for, **Format** = **Single Knockout**, **Maximum entries** = `8`.
2. **Football:** **Arrangement** = **5 a side (futsal)** or **7 a side**, adult/open category, **Format** = **Round Robin**, **Maximum teams** = `4`.
3. **Chess:** open category, **Format** = anything, **Maximum entries** = `4`.
4. At the top, find the **Entry fee** card:
   * Choose **A separate fee for each sport**. Each sport card now shows **Entry fee — Badminton**, **Entry fee — Football** and so on. Type `200` for Badminton.
   * Switch to **One fee for the whole season**. The per-sport fee boxes disappear, and a single **Fee for the whole season** box appears. Type `500`.
5. Read the notice under the fee: it must say the fee is **not collected in the app** (paid at the venue).
6. Try to give Badminton a second card with the **same** arrangement and category (**Add More Sport Categories (+)** → Badminton → same choices).
7. Tap **Next**.

✅ Expect
* Fee boxes switch between "one per sport" and "one for the season" as described.
* A message says the fee is settled offline / not collected by PlaySphere.
* Step 6 is refused with a message that the category is already in the season.

☐ Pass ☐ Fail

---

### TC-09: Schedule step (dates, a ground, timings)
**D1**, on the **Schedule** step
1. **Start Date**: try to pick **today**. It should not be selectable. Pick **tomorrow**.
2. **End Date**: pick **2 days after** the start.
3. Leave **Entries Close (optional)** empty.
4. Try tapping **Next** without a ground. It should stay blocked.
5. In the grounds section, tap **Add a ground**:
   * **Venue / Ground Name**: `PS Test Ground`
   * **Courts / Pitches (comma-separated)**: `Court 1, Court 2, Pitch 1`
   * Save (**Add Venue**).
6. Make sure the new ground is ticked for the season.
7. In the timings: **Changeover** `10`, **Min Rest Gap** `30`, **Daily Hours** 08:00–20:00.
8. Look at the plan/"fits" panel.
9. Tap **Next**.

✅ Expect
* Today and past dates can't be picked.
* **Next** is blocked until there is a start date **and** at least one ground.
* The plan panel says whether the season **fits**. If it doesn't fit, it suggests fixes such as **Add a day**.

☐ Pass ☐ Fail

---

### TC-10: Registration step: houses
**D1**, on the **Registration** step
1. Leave **Open to other clubs** **OFF**.
2. Read the sentence below it: only your club's members can enter, and they're confirmed straight away.
3. In **Houses & Groups**, change the houses so there are exactly two: `Garuda House` and `Kowshika House` (edit the names, use **Add a house**, remove the extras).
4. Tap **Next**.

✅ Expect
* The houses card is only shown while **Open to other clubs** is OFF. Turn it ON for a moment to check, then turn it back OFF.

☐ Pass ☐ Fail

---

### TC-11: Review & Publish, then entries open immediately
**D1**, on the **Review & Publish** step
1. Check the summary: 3 sports, start/end dates, ground, entries.
2. If a red problems card is shown, **Publish Season** is disabled. Go back and fix what it lists.
3. Tap **Publish Season**.

✅ Expect
* The season page opens.
* The season is **live straight away**. It is **not** a "Draft". Its status reads **Entries open**.
* **D2** (club chip = `PS Test Academy`): on **Home**, the "Active seasons" tile count goes up, and the season can be opened.
* Members get a notification that the season is open. It may take a minute; note it if none arrives.

☐ Pass ☐ Fail

---

### TC-12: Sport that has no matches (performance sports)
**D1**
1. **New event** → tap the small **⚡ (Quick create)** icon on the **Season** card.
2. Type any name, e.g. `PS Sprint Test`. Under **Categories** tap **Add Categories (+)** and add **Athletics** (any running event).
3. Look below the fee section.
4. **Don't create it.** Press back.

✅ Expect
* A notice with a stopwatch icon: *"Athletics … will not be timetabled"*. It explains that these take entries and results but aren't drawn or put on the schedule.
* The Athletics format choices are **Single Final** or **Heats + Final**, not Knockout or Round Robin.

☐ Pass ☐ Fail

---

# Phase 3: Entries for Season 1

### TC-13: Individual entry (Badminton Singles)
**D1, D2, D3, D4** (all with club chip = `PS Test Academy`)
1. Open `PS House Games 2026` → tap the **Badminton** event.
2. Tap **Register**.

✅ Expect
* Message: *"You are in. See you there."*
* The button is replaced by your status (e.g. **Confirmed**) and a **Withdraw** button. You can't register twice.
* On **D1**, the entries card reads **Entries (4)**, with "4 confirmed".

☐ Pass ☐ Fail

---

### TC-14: Withdraw and re-enter
**D4**
1. On the Badminton event, tap **Withdraw** and confirm.
2. Check the entries count on **D1**. It should drop to 3.
3. On **D4**, tap **Register** again.

✅ Expect
* The count goes 4 → 3 → 4.

☐ Pass ☐ Fail

---

### TC-15: House entry (Football)
**D1 and D2**
1. Open the **Football** event → **Register**.
2. A dialog **Select Your Group** lists `Garuda House` and `Kowshika House`. Pick **Garuda House** → **Confirm Entry**.

**D3 and D4**
3. Same, but pick **Kowshika House**.

✅ Expect
* Each person gets the "You are in" message.
* On **D1**, the Football entries list shows 4 people, each with their house.

☐ Pass ☐ Fail

---

### TC-16: Close entries and build the house teams
**D1**
1. Open the **Football** event. At the bottom, the main button reads **Close entries**. Tap it.

✅ Expect
* A message like *"2 entrants confirmed."*
* The Football field now has **2 entrants**, `Garuda House` (D1, D2) and `Kowshika House` (D3, D4), instead of 4 separate people.
* The main button changes to **Make the draw**.

☐ Pass ☐ Fail

---

### TC-17: Only one Chess entry
**D2**
1. Open the **Chess** event → **Register**.

(Nobody else enters Chess.)

✅ Expect
* Chess shows **Entries (1)**. We'll use this in TC-27.

☐ Pass ☐ Fail

---

### TC-18: A non-member cannot enter Season 1
**D4**
1. Switch the club chip to `PS Visitors Club`.
2. Look for `PS House Games 2026` on Home.

✅ Expect
* It does **not** appear while `PS Visitors Club` is selected. It belongs to the other club.
* Switch back to `PS Test Academy` and it appears again.

☐ Pass ☐ Fail

---

# Phase 4: Season 2, open to other clubs (club teams)

### TC-19: Create the Club Cup
**D1** (chip = `PS Test Academy`)
1. **New event** → **Season**.
2. Name `PS Club Cup 2026` → **Next**.
3. Tick **Cricket** → **Next**.
4. Cricket: **Arrangement** = **6 a side** (or 8 a side), **Format** = **Round Robin**, **Maximum teams** = `4` → **Next**.
5. Start **tomorrow**, end **2 days later**, tick `PS Test Ground`, set the timings → **Next**.
6. **Registration:** turn **Open to other clubs** **ON**. Read the sentence: entries from outside your club must be approved by you.
7. **Publish Season**.

✅ Expect
* The season page opens with entries open.
* There is **no** houses card while "Open to other clubs" is ON.

☐ Pass ☐ Fail

---

### TC-20: Invite the visiting club
**D1**
1. On the `PS Club Cup 2026` page, tap the **Organizer desk** card → **Invite clubs**.
2. You see an editable letter (*"Dear sports enthusiasts, we from PS Test Academy…"*).
3. Search the directory for `PS Visitors Club` (by name or Club ID) and select it.
4. Tap **Send to 1 club**.

✅ Expect
* A success message. The club shows as invited/pending.
* **Copy registration link** and **Share on WhatsApp & more** are available.

☐ Pass ☐ Fail

---

### TC-21: Accept the invitation
**D4** (chip = `PS Visitors Club`)
1. **More** → **Invitations** (the **Received** tab).
2. The Club Cup invitation card shows the letter. Tap **Accept & register**.

✅ Expect
* The invitation is accepted, and you're taken to the season or cricket event.
* **D3** (chip = `PS Visitors Club`) can see the invited season but **cannot** enter a team. Only the club owner/admin can. D3 may see a "show interest" option instead.

☐ Pass ☐ Fail

---

### TC-22: Each club creates and enters a cricket team
**D1** (chip = `PS Test Academy`)
1. Open the Club Cup **Cricket** event → **Enter a team** → **Create a team**.
2. **Team name** `Academy XI`, **Sport** Cricket, search members and add **D1** and **D2** → save.
3. Back on the event → **Enter a team** → tap **Enter** next to `Academy XI`.

**D4** (chip = `PS Visitors Club`)
4. Open the Cricket event → **Enter PS Visitors Club** (or **Enter a team**) → **Create a team** → `Visitors XI` with **D4** and **D3** → save → **Enter**.

✅ Expect
* `Academy XI` is confirmed straight away, because it's the host club's own team.
* `Visitors XI` shows as **pending**, because it's an outside club.

☐ Pass ☐ Fail

---

### TC-23: Organizer approves the outside team
**D1**
1. On the Cricket event's entries list, find `Visitors XI` (pending). Tap the **Confirm** (✓) icon.

✅ Expect
* `Visitors XI` becomes confirmed. The entries show 2 confirmed teams.
* Try the **Reject** (✕) icon on a test entry only if you have a spare one. Don't reject `Visitors XI`.

☐ Pass ☐ Fail

---

### TC-24: Doubles entry (check carefully)
**D1**
1. Open `PS House Games 2026` → **Organizer desk** → **Add a sport or event** → add **Badminton**, arrangement **Doubles**, open category.

**D2**
2. Open the new Badminton **Doubles** event → register.

✅ Expect (the correct behaviour)
* D2 is asked about a **partner** (**Have Partner** / **Need Partner (Solo)**), **or** is asked to enter a pair/team.
* ❌ **Fail** if D2 is registered alone as a single player with no partner question. Doubles would then be drawn as one person against one person.

☐ Pass ☐ Fail

---

# Phase 5: Venues & Capacity

### TC-25: Venue planner and "Maximum matches a day"
**D1**
1. `PS House Games 2026` → **Organizer desk** → **Venue planner**.
2. Open `PS Test Ground`. Check **Playing areas** (Court 1, Court 2, Pitch 1), **Available dates** and **Playing sessions**.
3. **Match duration here** = `45`. **Turnaround between matches** = `15`.
4. **Maximum matches per area per day** = `50`.
5. Change it to `5`.

✅ Expect
* With `50`: a red note like *"You allow 50 a day but a 45-minute match with a 15-minute turnaround only fits N in these sessions. The schedule will use N."* N is the real number that fits, e.g. 12 for 08:00–20:00.
* With `5`: the red note disappears. **You allow** 5 and **Actually fits** N are shown separately.

☐ Pass ☐ Fail

---

### TC-26: Blackout a day
**D1**, still in the Venue planner
1. In **Available dates**, untick the **last** day of the season → **Save**.
2. Open **Organizer desk** → **Timetable** and look at the capacity card (**Schedule feasible** / **Will not fit as planned**).

✅ Expect
* The capacity numbers (**Slots available**) go down.
* If the season no longer fits, the card lists what would help.
* **Put the day back afterwards** (tick it again → **Save**).

☐ Pass ☐ Fail

---

# Phase 6: Draw, Timetable & Publish (one sport at a time)

> **Tip for match-day tests:** matches can only be played once they're on the timetable. If you want to play today, ask the organizer to use the event's **Edit** option on the season page to set the start date to today, or run Phases 6–10 on the season's first day.

### TC-27: Not enough entries (Chess)
**D1**
1. `PS House Games 2026` → **Organizer desk** → **Timetable**. Tap the **Chess** chip so the page title reads **Chess schedule**.
2. Tap **Draw & schedule Chess** → in the timings dialog tap **Draw & Schedule Chess**.

✅ Expect
* No matches are created for Chess.
* A message titled like **Chess laid out, with gaps** lists under **Not drawn**: *"… 1 entered, needs at least 2"*.

☐ Pass ☐ Fail

---

### TC-28: Knockout draw for 4 players (Badminton)
**D1**
1. **Timetable** → tap the **Badminton** chip → **Draw & schedule Badminton**.
2. In **Schedule Timings**, leave *"Each event's own (recommended)"* → tap **Draw & Schedule Badminton**.

✅ Expect
* **2 semi-finals + 1 final** are created.
* All four players appear **exactly once** in the semi-finals. The pairs may be in any order.
* The final shows placeholders or "to be decided" names until the semi-finals finish.
* Every match has a **court** and a **time** inside 08:00–20:00. No two matches share a court at the same time.
* The page says it's a **draft**: *"This is a draft. Times and courts can still change."*
* **D2** (a player) doesn't see draft times yet, or sees them clearly marked as draft.

☐ Pass ☐ Fail

---

### TC-29: A player is never in two places at once
**D1**
1. **Timetable** → **Football** chip → **Draw & schedule Football** → confirm.
2. Look at the times for **D1** and **D2**. Each is in a Badminton semi-final **and** in `Garuda House`'s football match.

✅ Expect
* Football was placed **around** Badminton. No person has two matches overlapping.
* Between the end of one of a person's matches and the start of their next, there are at least **30 minutes** (the rest gap from TC-09).
* **Schedule health** shows **no** "Player conflicts" or "Rest violations".

☐ Pass ☐ Fail

---

### TC-30: Moving a match onto a busy court
**D1**, on the **Badminton schedule** page
1. Tap semi-final 2 → **Move this match**.
2. Set **Date and time** to the **same start time** as semi-final 1, and **Playing area** to **the same court** as semi-final 1 → **Move**.

✅ Expect
* A dialog **That move causes a conflict** explains the clash.
* Tap **Leave it where it was**. The match stays in its original slot.
* (Optional) Repeat and tap **Move anyway**. You get *"Moved. The conflict is listed under Schedule health."* Then move it back to a free slot until the message *"Match moved. Schedule still clean."* appears.

☐ Pass ☐ Fail

---

### TC-31: Publish the Badminton schedule
**D1**
1. On the **Badminton schedule** page, tap **Publish Badminton schedule**.
2. The dialog **Publish the Badminton schedule?** says it closes new entries for Badminton and notifies players. Tap **Lock & Notify**.
3. Also publish **Football**, and on `PS Club Cup 2026` draw, schedule and publish **Cricket**.

✅ Expect
* *"Badminton schedule published."*
* The badge reads **Published** for that sport. Other sports stay as they were until published themselves.
* **D2, D3, D4** receive a notification. Their matches, times and courts are visible on the season page and under their own matches.

☐ Pass ☐ Fail

---

# Phase 7: Umpires & Officials

> In PlaySphere, an official counts as **from a club** only if you added them **by searching the host club's members**. Officials added by **PlaySphere ID** or from the umpire registry count as **unaffiliated**.

### TC-32: Build the umpire panel
**D1**, on `PS Club Cup 2026`
1. **Organizer desk** → **Umpire panel** (screen title **Officials**).
2. Tap the **Add an official** icon (person with +).
3. In **Search this club by name**, type `Test Player Two` → **Choose**. In the next sheet, tick **Cricket** → save.

✅ Expect
* *"Test Player Two added to the panel."*
* The **Panel (1)** list shows them.

☐ Pass ☐ Fail

---

### TC-33: The auto-assigner refuses a non-neutral umpire
The cricket match is `Academy XI` (host club) vs `Visitors XI`. D2 belongs to the host club, so D2 is not neutral.

**D1**
1. Tap **Assign officials across the bracket**.

✅ Expect
* The cricket match is **not** given to D2.
* A dialog **Some matches still need an official** says: *"Every official free on this date belongs to one of the two clubs playing. Add a neutral official, or assign one by hand and record that both sides agreed."*
* The match appears under **Still need an official**.

☐ Pass ☐ Fail

---

### TC-34: An unaffiliated official is used
**D1**
1. Ask a 5th person (or reuse any account that isn't in either cricket team) for their **PlaySphere ID**. If nobody is available, **skip this test** and write "skipped".
2. **Add an official** → type the ID in **PlaySphere ID** → tick **Cricket** → save.
3. Tap **Assign officials across the bracket** again.

✅ Expect
* *"1 match staffed. Every match has a neutral official."*

☐ Pass ☐ Fail ☐ Skipped

---

### TC-35: Assign by hand
**D1**
1. Under **Still need an official**, tap **Assign** next to a match → pick a name.

✅ Expect
* The match leaves the "still need" list.
* The assigned person sees the match under **Your matches to umpire** on the season page.

☐ Pass ☐ Fail

---

### TC-36: Daily match limit for an official
**D1**, on `PS House Games 2026` → **Umpire panel**
1. Add **D3** (search by name) and tick **Badminton**.
2. Tap the **Sports & availability** icon on D3's row → set **Most matches in one day** to `1` → **Save**.
3. Tap **Assign officials across the bracket**.

✅ Expect
* D3 is put on **at most 1** Badminton match per day (and never on a match D3 plays in).
* Other matches are listed as unstaffed with a reason such as *"…already reached their match limit for this day"* or *"…on another court at this time"*.
* ⚠️ Also try the manual **Assign** button to give D3 a second match that day. **Write down whether the app stops you.** If it lets you, note it as a bug.

☐ Pass ☐ Fail

---

# Phase 8: Match Day

### TC-37: Start a match and take the toss
**D1** (organizer)
1. Open the season → tap **Badminton semi-final 1** → **Match Center**.
2. Tap **Start Match**.
3. The **Take the toss** screen appears. Tap the coin (or tap the side that won the toss at the ground), then pick **Serve** / **Receive** / **Choose ends**.
   * You can also tap **Skip and start scoring**.

✅ Expect
* The scoring pad opens. The status line names who serves and from which court (e.g. *"… to serve from the right court"*).
* The badminton toss offers **Serve / Receive / Choose ends**. There is no "Bat/Field".

☐ Pass ☐ Fail

---

### TC-38: Only one device can score a match
While D1 is scoring semi-final 1:

**D2** (a player in that match)
1. Open the same match → try to score.

✅ Expect
* D2 sees that **someone else is scoring** (e.g. **Take control** / **This match is being scored on another device**).
* Points tapped on D1 are **not** doubled or lost.
* (Optional) Hand over: on D1 tap **Hand over** and pick D2. Now D2 scores and D1 can't.

☐ Pass ☐ Fail

---

### TC-39: Spectators see the score live
**D3 and D4**
1. Tap **Live now** (bottom bar). The match appears under **Your clubs**.
2. Open it (**Watch this match**).
3. **D1** scores 3 points.

✅ Expect
* The score changes on D3 and D4 **within a few seconds, without pulling to refresh**.
* The match is marked **LIVE**.

☐ Pass ☐ Fail

---

### TC-40: Two sports scored at the same time stay separate
**D1** keeps scoring Badminton semi-final 1.
**D3** (or whoever is allowed) starts the **Football** match `Garuda House vs Kowshika House` and records **1 goal for Garuda House**.
**D4** watches both from **Live now**.

✅ Expect
* Badminton shows only badminton points, and Football shows `1 – 0`.
* Nothing from one match appears in the other.
* The season page shows both under **On court now**.

☐ Pass ☐ Fail

---

# Phase 9: Scoring

### TC-41: Badminton points, deuce and game end
**D1**, on semi-final 1
1. Under **Rally won by**, tap the player names to score. Bring the game to **20 – 20**.
2. Tap the **first** player once (**21 – 20**).
3. Tap the **first** player again (**22 – 20**).

✅ Expect
* At 20 – 20 the status line shows **Deuce**.
* At 21 – 20 the game **does not** end, and the leader is tagged **Game point**.
* At 22 – 20 the game ends. The games score (**GAMES WON**) becomes 1 – 0 and **Game 2** starts at 0 – 0.
* The status line shows **CHANGE ENDS** when players should switch sides, and **INTERVAL** at 11 points.

☐ Pass ☐ Fail

---

### TC-42: Undo (Badminton)
**D1**
1. Tap a point for the wrong player.
2. Tap **Undo** (on the pad).

✅ Expect
* Only the last point is removed, and the server returns to who served before.
* A message says *"Last action withdrawn."*

☐ Pass ☐ Fail

---

### TC-43: Finish the match
**D1**
1. Win game 2 for the same player.

✅ Expect
* A result screen: *"<name> won"* with a **Done** button, and the message that standings, ratings and records are updated.
* The winner moves into the **Final** slot on the bracket.
* **The last point was wrong — reopen** is offered. Don't tap it now.

☐ Pass ☐ Fail

---

### TC-44: Cricket runs, wide, wicket
**D1** (Club Cup cricket match; the line-ups must include D1, D2 vs D4, D3)
1. Open the match → **Start Match** → toss: winner picks **Bat** or **Field**.
2. If asked **Set the line-ups first**, tap **Choose players** and pick the two players for each side.
3. **Who is playing?** → pick **On strike**, **Non-striker**, **Bowling**.
4. Tap **1**.
5. Tap **4**.
6. Tap **WD** (wide).
7. Tap **Caught** (in the **Wicket** group) → pick **Caught by** → pick the next batter.

✅ Expect
* After **1**: total 1, **0.1** overs, and the strike moves to the other batter.
* After **4**: total 5, **0.2** overs, and strike stays.
* After **WD**: total 6, still **0.2** overs, because a wide isn't a legal ball.
* After **Caught**: 6 for **1** wicket, **0.3** overs. The bowler is credited with the wicket, and the scorecard below the pad shows the out batter.

☐ Pass ☐ Fail

---

### TC-45: Undo (Cricket)
**D1**
1. Tap **6** by mistake.
2. Tap **Undo** (or **Undo the last ball**).

✅ Expect
* The total goes back exactly, and so do the batter's runs and balls and the bowler's figures and balls.

☐ Pass ☐ Fail

---

### TC-46: Cricket batter retires
**D1**
1. In the **Wicket** group tap **Retired** → **Who retired** → pick the batter → pick the next batter.

✅ Expect (cricket laws)
* The retired batter shows as retired on the scorecard.
* The **bowler is NOT credited** with a wicket.
* The **over's ball count does NOT go up**, because retiring is not a delivery. ❌ If the overs move on (e.g. 0.3 → 0.4), mark **Fail**.
* Write down whether the team's **wicket count** went up.

☐ Pass ☐ Fail

---

# Phase 10: Matches That Don't Finish Normally

> All of these are on the scoring pad, inside the section **Match did not play normally**. Some choices are organizer-only.

### TC-47: A player retires injured (Badminton semi-final 2)
**D1**
1. Start semi-final 2 and score until one player leads, e.g. 14 – 10.
2. Open **Match did not play normally** → under **Retired**, tap **<leader> wins**.
3. Confirm (**Record as retired?** → **Confirm**). Optionally type a reason.

✅ Expect
* The match ends at once. The winner goes to the Final.
* The score is kept and shown with **(R)**, e.g. `14-10 (R)`.
* The dialog says it **counts towards ratings and career statistics**.
* The pad is closed for scoring. A card at the top offers **Withdraw this decision** (organizer only).

☐ Pass ☐ Fail

---

### TC-48: Walkover (Badminton Final)
**D1**
1. Open the **Final** in **Match Center** (don't start it).
2. Tap **Award Walkover / Forfeit** → choose **Win: <one finalist>** → keep the note → confirm.

✅ Expect
* *"Walkover awarded. Standings & bracket updated!"*
* The result shows **W/O**. No points or games are recorded.
* The badminton event now has a champion.

☐ Pass ☐ Fail

---

### TC-49: Abandoned match
**D1**
1. **New event** → **Single match** → create a quick badminton match between D3 and D4.
2. Start it, score a couple of points.
3. **Match did not play normally** → **Abandoned** → confirm.

✅ Expect
* Status **Abandoned**, marker **(A)**.
* No winner. The dialog says nothing counts towards ratings.

☐ Pass ☐ Fail

---

### TC-50: Withdraw a ruling
**D1**, on the abandoned match from TC-49
1. Tap **Withdraw and resume the match** (or **Withdraw this decision**) → confirm.

✅ Expect
* *"Match resumed from where it stopped."* The earlier points are still there.
* Finish or abandon it again afterwards.

☐ Pass ☐ Fail

---

### TC-51: Players can't record organizer-only rulings
**D3** (a player, not an organizer), on any live match they're in
1. Open **Match did not play normally**.

✅ Expect
* **Walkover**, **Abandoned**, **Neither side arrived** and **Mark as disputed** are **not** offered.
* A note says those are recorded by an organizer.

☐ Pass ☐ Fail

---

# Phase 11: Protests (within 1 hour of the result)

### TC-52: A player protests a result
**D2**, who **lost** Badminton semi-final 1, within 1 hour of TC-43
1. Open that match (it opens the scoring pad / result view). Scroll to the **Result** card.
2. Tap **Protest this result** → pick a **Reason** → in **What happened** type `Game 2 was 21-19, recorded as 21-18.` → **Raise it**.

✅ Expect
* The card turns red: **Result under protest**. The match status is **Disputed**.
* ⚠️ Check the bracket: does the Final still show the semi-final winner? **Write down what you see.** A result under protest should not be treated as final.

☐ Pass ☐ Fail

---

### TC-53: The raiser can't decide their own protest
**D2**

✅ Expect
* D2 sees **no** Uphold/Reject buttons.

☐ Pass ☐ Fail

---

### TC-54: Organizer decides the protest
**D1**
1. Open the same match → **Result under protest** card.
2. Tap **Reject — result stands** → type a note → **Record the decision**.
3. (Second run, optional) On another protested match tap **Uphold — reopen for correction** → **Record the decision**, fix the score with **Undo** or the **Corrections** buttons (**−1 …**), and finish again.

✅ Expect
* Reject: the protest shows its status and note, and the result stays as it was.
* Uphold: the match reopens for correction, and the corrected result replaces the old one when finished.

☐ Pass ☐ Fail

---

### TC-55: The protest window closes after 1 hour
**Any player**, more than 1 hour after a match finished
1. Open the finished match.

✅ Expect
* The card says *"The protest window has closed."* and there is **no** **Protest this result** button.

☐ Pass ☐ Fail

---

# Phase 12: Standings, Season Page & Certificates

### TC-56: Football points table
Finish the football match `Garuda House vs Kowshika House` with Garuda winning (see TC-40).

**Any device**
1. Open `PS House Games 2026`. Find the **Football** panel.

✅ Expect
* A table with **# · Team · P W (D) L Pts**.
* `Garuda House`: P 1, W 1, L 0, with win points (normally 3). `Kowshika House`: P 1, W 0, L 1, Pts 0.
* Garuda is listed first.

☐ Pass ☐ Fail

---

### TC-57: Knockout sport panel
**Any device**
1. Look at the **Badminton** panel.

✅ Expect
* No points table (it's a knockout). A wins board or bracket progress is shown instead.
* The champion from TC-48 is shown, and the season page lists **Champions**.

☐ Pass ☐ Fail

---

### TC-58: Members see a plain season page
**D2** (a member, not an organizer)
1. Open `PS House Games 2026`.

✅ Expect
* Stats, tables, results and upcoming matches only.
* **No** **Organizer desk**, no "NEEDS YOUR ATTENTION", and no draft timetables or staffing tools.
* **D1** sees the **Organizer desk** card.

☐ Pass ☐ Fail

---

### TC-59: One team's record in the season
**Any device**
1. On the Football panel, tap `Garuda House`.

✅ Expect
* A page for Garuda House in **this season**, with only its matches, e.g. won against Kowshika House, with the score.

☐ Pass ☐ Fail

---

### TC-60: Certificates and memories
**D1**
1. **Organizer desk** → **Certificates** (only shown once a sport has champions).
2. Open a certificate.
3. On the season page tap **Memories**, add a photo to a finished match, and check it appears in the season's memory book.

✅ Expect
* The certificate names the right player, event and season.
* The photo appears in the season memories.

☐ Pass ☐ Fail

---

# Phase 13: Player Profiles & Ratings

> Ratings update on the server, usually **within a minute** of a result. On a match's result screen the row **Player stats updated** turns ✓ when done. Before each rating test, **write down the current rating** from the player's profile.

### TC-61: Career stats come from the scorecard
**Any device**
1. Open **D1**'s profile (tap D1's name on a scorecard, or **More** → your profile on D1).
2. Open **Cricket** stats.

✅ Expect
* Runs, balls and wickets match what was scored in TC-44 (after the undo in TC-45).
* Matches played went up by 1.

☐ Pass ☐ Fail

---

### TC-62: A normal season match moves the rating
Badminton had **4 entries**, so its matches are rated.

**Any device**
1. Compare the badminton rating of the semi-final 1 **winner** and **loser** (TC-43) with what you wrote down before.

✅ Expect
* The winner's rating **went up** and the loser's **went down**.
* A new player may show **Provisional (1 match)**. That's normal.

☐ Pass ☐ Fail

---

### TC-63: A retirement still moves the rating
1. Compare ratings for both players of semi-final 2 (TC-47).

✅ Expect
* Winner up, loser down. A retirement counts as a real result.

☐ Pass ☐ Fail

---

### TC-64: A walkover does NOT move the rating
1. Compare ratings for both finalists (TC-48).

✅ Expect
* **No change** from the walkover.

☐ Pass ☐ Fail

---

### TC-65: A field under 4 is not rated
The cricket event had only **2 teams**, and Football only **2 houses**.

1. Compare cricket and football ratings for D1–D4 before and after those matches.

✅ Expect
* **No rating change.** A competition needs at least 4 entries to be rated.
* Career stats (runs, goals, matches played) **do** still update.

☐ Pass ☐ Fail

---

### TC-66: A quick match doesn't touch the season or ratings
**D3 vs D4**
1. **New event** → **Single match** → Badminton, D3 vs D4. Play it to the end.
2. Check D3's and D4's badminton ratings.
3. Open `PS House Games 2026` → Badminton panel / season leaderboard.

✅ Expect
* Ratings **unchanged**. Single matches and challenges are never rated.
* The quick match appears in D3's and D4's match history.
* The season's badminton numbers and leaderboard **don't** include the quick match.

☐ Pass ☐ Fail

---

# Quick "Golden Run" Checklist

```
[ ] 1.  4 devices, 4 Google accounts, 2 clubs, members approved
[ ] 2.  Club chip shows only the selected club's things
[ ] 3.  Season published → Entries open at once (no Draft)
[ ] 4.  Today can't be the start date; a ground is required
[ ] 5.  Fee mode switch works; "not collected in app" notice shown
[ ] 6.  Individual entry, withdraw, re-enter
[ ] 7.  House entry → Close entries → 2 house teams built
[ ] 8.  Invite club → accept → both clubs enter teams → approve outside team
[ ] 9.  Doubles asks for a partner (known risk — check!)
[ ] 10. Venue planner shows "You allow" vs "Actually fits"
[ ] 11. Draw & schedule per sport; <2 entries refused; knockout = 2 SF + F
[ ] 12. No player double-booked; rest gap kept; move-conflict dialog shown
[ ] 13. Publish per sport → players notified
[ ] 14. Umpire from a playing club not auto-assigned; daily cap respected
[ ] 15. Start Match → toss → only one device can score
[ ] 16. Spectators see LIVE score update without refresh
[ ] 17. Badminton deuce 20-20, game at 22-20; cricket 1/4/WD/Caught correct
[ ] 18. Undo reverses exactly one action
[ ] 19. Retired (R), Walkover (W/O), Abandoned (A) markers correct
[ ] 20. Protest within 1 hour; organizer rejects/upholds
[ ] 21. Points table P W L Pts correct; champion shown
[ ] 22. Member sees plain season page; organizer sees Organizer desk
[ ] 23. Rating: normal + retired move; walkover, <4 entries, quick match don't
```

---

# Bug Note Template

Copy this for every failure:

```
Test ID:           (e.g. TC-29)
Device:            (D1 / D2 / D3 / D4)  Phone model / laptop browser:
Account name:
Club selected (top right):
What I tapped:     (step numbers)
What I expected:   (copy from ✅ Expect)
What I saw:        (exact message text if any)
Screenshot/video:  (attach)
Date & time:
Happens again if I repeat it?  Yes / No / Didn't try
```
