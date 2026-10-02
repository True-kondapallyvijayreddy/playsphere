# PlaySphere Season & Tournament Flow — Master E2E Test Case Specification (Consolidated)

**Document ID:** `PS-QA-SEASON-MASTER-2026-V1`
**Supersedes:** `season_tournament_e2e_validation_test_cases.md` (Downloads copy, 26 cases) and `season_tournament_e2e_validation_test_cases.md` (Desktop/docs copy, claimed 215 cases). See **Section 0** for why a consolidation was needed instead of just picking one.
**Target System:** PlaySphere (Flutter iOS/Android/Web + Firebase Firestore/Cloud Functions/Security Rules)
**Scope:** Every admin (season-creator) button/scenario and every participating-club/player button/scenario in the season & tournament flow.

---

## 0. Alignment Audit — Are the two existing docs aligned?

**Short answer: mostly, but not fully — and the bigger of the two has a hidden content gap that erases exactly one of the things you asked to test.**

| # | Finding | Evidence |
|---|---|---|
| 1 | **Both docs cover the same core skeleton.** Season/tournament creation, dynamic add/edit/cancel of events, house allocation, officials + neutrality, draw generation, schedule publish-gate, invite→RSVP→squad-build→submit flow, duplicate-player guard, solo-vs-team guard, age-21 gate, and public discovery vs invite-only are all present in both. | Cross-read of both files in full. |
| 2 | **The Desktop/docs copy is not really 215 unique cases — it's 200.** Suite "1.6: Venue Planning, Ground Calendars, Court Turnarounds & Capacities" (advertised as `TC-CREATOR-071` to `085`, 15 cases) contains **zero real content**. The generator accidentally pasted Suite 1.5's House Management block (`TC-CREATOR-056`–`070`) a second time in its place. Grepping the file confirms `TC-CREATOR-071` through `085` never appear as a heading anywhere in the document. | `grep -oE "^### TC-CREATOR-[0-9]+"` on the file shows `056`–`070` each appearing **twice**, and `071`–`085` appearing **zero times**. |
| 3 | **This directly undercuts your "adding grounds for all the matches" requirement.** The *only* real venue/ground-planning test case across both documents is `TC-CREATOR-009` in the smaller Downloads doc (multi-venue setup, court turnaround gaps, capacity math). The larger doc has none. | Confirmed by full read + grep for `venue plan|ground|court turnaround|operating hours`. |
| 4 | **Neither doc tests the admin actually *sending* an invite.** Both docs jump straight to the visiting club *receiving* the invitation (`TC-PLAYER-001`/`TC-PLAYER-002` etc.). There is no test case anywhere for the host admin composing an invite from the season page — searching for a club, picking sports, writing the letter, hitting "Send Invite." | `grep -i "send.*invit\|compose invit\|Invite a Club"` returns nothing on the sending side in either file. |
| 5 | **Neither doc validates the 4-tier access model you asked for (owner / admin / umpire / co-ordinator).** Both only test a binary owner-vs-regular-member gate, plus a generic "grant/revoke Manage Competitions capability" pair (`TC-CREATOR-115/116`). There's no test asserting what a **co-ordinator** can't do that an **admin** can, or what an **umpire**'s access is scoped to (scoring only vs. season settings). | `grep -i "coordinator"` returns only the grant/revoke pair; `grep -i "umpire.*access\|umpire.*permission"` returns nothing. |
| 6 | **No dedicated "match stats" viewing test case** (aggregated player/team stats, separate from the live scorecard or the dispute-resolution flow). | `grep -i "match stat\|player stat"` returns nothing relevant. |
| 7 | **No player-side "my house" test case.** Both docs test the *admin* allocating/renaming/transferring house members, but neither tests the *player's* experience of registering into an internal season, seeing which house they landed in, or entering a house-scoped single/multi-sport event as a participant. | `grep -i "my house\|player.*house"` returns nothing beyond the role-matrix table row. |
| 8 | **Minor inconsistency inside the larger doc itself:** it mixes ID prefixes — the first 15 admin cases are `TC-ADM-###`, then it switches to `TC-CREATOR-###` for the rest of the admin section, while the smaller doc uses `TC-CREATOR-###` throughout. Not a functional bug, just an authoring inconsistency. | `grep -n "^## Suite"` header list. |

**Conclusion:** treat neither existing file as the source of truth on its own. This document folds in everything real from both, fixes the venue-planning hole, and adds the missing invite-sending, role-matrix, match-stats, and player-side-house cases so nothing on your checklist is left untouched. IDs below use `TC-ADM-###` (creator/admin side) and `TC-CLUB-###` (participating club/player side) to avoid the prefix collision in finding #8.

---

## Role Matrix (used throughout)

| Persona | Device | Role | Notes |
|---|---|---|---|
| Host Owner | D1 | `owner` | Full rights on the season; only role that can transfer ownership |
| Host Co-ordinator | D1b | `coordinator` | Delegated by owner; day-to-day season ops, cannot delegate further or touch finances |
| Host Admin | D1c | `admin` | Same as coordinator + can grant/revoke other admins/coordinators, cannot transfer ownership |
| Umpire/Official | D5 | `umpire` | Scoped strictly to matches they're assigned; no season-setting access |
| Host Regular Player | D2 | `member` | Host club member, house athlete |
| Dual-Club Player | D3 | `member` (2 clubs) | Member of host club AND visiting club |
| Visiting Club Owner | D4 | `owner` (other org) | Receives invite, builds entries |
| Visiting Club Admin | D4b | `admin` (other org) | Can act on invites on owner's behalf |
| Uninvited Club Owner | D6 | `owner` (other org) | Not on host's invite list |

---

# PART A — SEASON CREATOR / ADMIN SIDE

## A1. Smooth Season/Tournament Creation

### TC-ADM-001: Create Multi-Sport Season Draft in Under 60 Seconds
* **Perspective:** Host Owner (D1)
* **Screen:** `ActiveSeasonsScreen → CreateSeasonScreen`
* **Objective:** The wizard must be completable with only mandatory fields — name, kind, dates — so a non-technical club owner can spin up a season fast.
* **Steps:** Tap **+ Create Season** → enter name → leave Kind at default (`Season (Multi-Sport)`) → pick a date range → tap **Create & Save Draft**.
* **Expected:** Draft is created with zero sports/events/venues/houses attached; all of those are addable later. Toast: *"Season created as draft."* Lands on `TournamentDetailScreen` showing a `DRAFT` badge and a checklist card: *"Add sports · Add venues · Open registrations."*
* **Edge Cases:** Empty name blocked client + server side; duplicate name in same club blocked; whitespace-only name blocked.

### TC-ADM-002: Create Single-Sport Tournament with Category Lock
* Selecting `Tournament (Single-Sport)` + Primary Sport = Cricket restricts every later category picker to Cricket sub-formats only (T20, 40-Overs, U-19, Veterans). Verified in Firestore: `kind == "tournament"`, `primarySportId == "cricket"`.

### TC-ADM-003: Fee Mode — Whole Season vs Pay-Per-Event
* Selecting "One fee for the whole season" locks all per-event fee fields to ₹0 and charges once at club/individual checkout. Selecting "Pay per event/category" hides the season-level fee and unlocks per-category pricing (e.g., ₹300 Badminton Singles, ₹2,500 Cricket Team).

### TC-ADM-004: Draft Invisibility Before First Publish Step
* A draft season with `acceptsEntries == false` shows zero "Register" affordance anywhere in Explore, is absent from any club's Invitations, and 404s on direct link for anyone outside the host club. This is the first checkpoint of the visibility-gating requirement (see A14).

## A2. Fully Editable Anytime — Add/Remove Events

### TC-ADM-005: Add a New Sport Tab Mid-Season
* Adding Basketball 3x3 to a season that's already live with Cricket + Badminton creates a new tab instantly without disturbing existing draws/fixtures. `tournament.sportCount` increments; no other competition doc is touched.

### TC-ADM-006: Add a New Category Under an Existing Sport
* Adding "Boys U-17 Singles" under an existing Badminton tab (which only had Men's Open) opens entries for U-17 independently — different `acceptsEntries`, different draw, different capacity — while Men's Open keeps running unaffected.

### TC-ADM-007: Bulk-Add Multiple Sports in One Pass
* Selecting Badminton Singles + Cricket 11s + Table Tennis Singles + Chess Solo + Football 7s in the bulk selector and tapping **Add Selected Categories (5)** batch-writes 5 competition docs atomically; the sports nav bar reflects all 5 tabs. Roll back on partial failure — either all 5 or none commit.

### TC-ADM-008: Edit Live Event Parameters (Duration, Capacity, Age Bound)
* Editing a Men's Open Badminton event that's already accepting entries — changing match duration 30→45 min, adding `Age 21+`, capping capacity at 32 — updates the live event without breaking already-approved entrants; only *new* entrants are checked against the new age rule going forward (existing approved entrants are flagged for admin review, not auto-rejected).

### TC-ADM-009: Open / Close Registrations Per Category Independently
* "Open Registrations" and "Close Entries" toggle `acceptsEntries` on a single category without affecting sibling categories in the same sport or other sports in the season.

### TC-ADM-010: Reorder Events via Drag-and-Drop
* Long-press drag on an event row reorders `displayOrder`; order persists across devices/refresh.

## A3. Cancel Event

### TC-ADM-011: Cancel an Event With Zero Entrants
* Cancel goes through immediately with no reason prompt (nothing to notify) and no confirmation friction beyond a single tap-confirm.

### TC-ADM-012: Cancel an Event With Active Entrants — Mandatory Reason + Notification Fan-Out
* Cancelling Table Tennis Open Blitz (6 registered) requires a non-empty cancellation reason before the "Yes, Cancel Event" button enables. On confirm: event flips to a red `CANCELLED` chip, "Open Entries"/"Build Draw" permanently disable, all 6 entrants get a push + inbox notification with the exact reason text, and any fixtures already scheduled for this event are pulled from the timetable (freeing the court slot for reuse by other sports).
* **Edge:** Cancelled events can never be reopened — organizer must create a fresh category if reinstating.

### TC-ADM-013: Delete vs Cancel Guard
* "Delete Event" is only offered when the category has **zero** registrations; the moment there's even one entrant, the overflow menu only offers "Cancel Event" (soft, auditable) — deletion is hidden to prevent silent data loss.

## A4. Draws & Anti-Overlap Scheduling

### TC-ADM-014: Build Knockout Draw With Rating-Based Seeding
* 16 entrants → Build Draw → Knockout → seed-by-Glicko places seed 1 and seed 2 at opposite bracket ends, seeds 3–4 in opposite halves, preventing a top-4 collision before the semifinal.

### TC-ADM-015: Build Round-Robin League Table
* 6 cricket teams → Round Robin generates all 15 matches (`n(n-1)/2`) with an empty 6-row standings table (0 P/W/L/Pts) ready to populate.

### TC-ADM-016: Build Groups-Then-Knockout Draw
* 8 football teams, 2 groups of 4, top-2 advance → renders Group A/B (6 matches each) feeding two semifinals; group winners/runners-up auto-map to bracket slots.

### TC-ADM-017: Same-Club Multiple Teams Kept Apart in Groups
* When a visiting club has entered 2+ teams (e.g., Lions and Tigers), the draw generator must place them in different groups/bracket halves so sister teams don't meet before the latest possible round.

### TC-ADM-018: Zero Player-Overlap Across Multiple Sports (Single Player, Two Events)
* A player entered in both Badminton (09:00–09:45, Venue A) and Cricket must not be double-booked. Scheduler places the Cricket match no earlier than `badminton_end + rest_gap(20m) + venue_transition_gap(45m)` = 10:50, so the engine actually books it at 11:15. Verified: `0 Player Clashes Detected`.

### TC-ADM-019: Zero Player-Overlap Across Same Sport, Multiple Categories (One Player, Two Categories)
* A player entered in both Badminton Men's Singles and Badminton Men's Doubles at the same venue must not have singles and doubles matches booked concurrently — engine enforces the same rest-gap rule within a single sport, not just across sports.

### TC-ADM-020: Court/Venue Double-Booking Guard
* No two matches may occupy the same court in overlapping windows; next match on a court starts strictly after `previous_end + turnaround_gap`.

### TC-ADM-021: Manual Drag-and-Drop Override With Live Conflict Detection
* Dragging a match card to a new court/time that collides with another match immediately outlines both cards red and raises a banner: *"1 Conflict: Court 1 double-booked at 10:00."* The schedule cannot be published while any conflict is outstanding (`TournamentSchedule.isComplete == false`).

### TC-ADM-022: Multi-Player-Sport vs Single-Player-Sport Scheduling Differences
* Multi-player sports (Cricket, Football) schedule at the *team* level — one slot blocks all 11/7 players simultaneously. Single-player sports (Badminton Singles, Chess) schedule at the *individual* level — the engine must still prevent the same individual from appearing in two individual-sport slots at once, and must prevent a team-sport player's individual-sport slot from overlapping their team match.

### TC-ADM-023: Whole-Day Reschedule (Rain Delay) Shift Tool
* Shifting an entire day's fixtures by +1 day preserves court/time-of-day assignments and pushes a "Timetable shifted due to weather" notification to everyone with a fixture that day.

### TC-ADM-024: Running-Late Broadcaster
* Marking a match "+30 mins" surfaces a delay card on the season home and flags all *following* matches on that same court with the delay, so downstream players know to arrive later.

## A5. House Management (Internal Club Seasons)

### TC-ADM-025: Author Custom Houses With Names + Colors
* Creating "Kakatiya Dynamos" / "Nizam Strikers" / "Chalukya Warriors" / "Satavahana Kings" each with a picked hex color persists to `tournament.presetHouses`; house cards show name, color avatar, `0 members`.

### TC-ADM-026: Use a Pre-Built House Template
* Applying "Classic 4 Colors" or "Engineering Depts (CSE/ECE/MECH/CIVIL)" or "Classes A–D" instantly populates 4 house rows instead of manual typing; applying a template over an already-populated list warns before overwriting.

### TC-ADM-027: Bulk-Allocate 100 Members Evenly Across 4 Houses
* Auto-distribute mode splits 100 members into exactly 25/25/25/25 with 0 unassigned; an odd total (e.g., 101) distributes the remainder sequentially starting from House 1.

### TC-ADM-028: Bulk-Allocate With Skill/Gender Balancing
* Toggling "Balance Skill & Gender" runs a snake-draft so no single house stacks all top-rated athletes; average Glicko rating per house stays within a tight band.

### TC-ADM-029: Manual Single-Member Transfer Between Houses
* Moving one player from House A to House B updates both counts immediately and propagates to every connected client in real time.

### TC-ADM-030: House Rename With Zero-Loss Member Migration
* Renaming "Nizam Strikers" → "Charminar Strikers" batch-rewrites all 26 members' `houseName` field; querying the old name returns 0 records, the new name returns all 26.

### TC-ADM-031: House Deletion Returns Members to Unassigned Pool
* Deleting a house with 25 members prompts *"Return 25 members to unassigned pool?"*; on confirm, those 25 records get `houseName: null` and are re-allocatable, never orphaned or lost.

### TC-ADM-032: House Standings / Medal Tally
* Once house-representation matches complete, the Houses tab renders a Gold/Silver/Bronze medal table with ties broken by gold-medal count.

### TC-ADM-033: Export House Roster to CSV
* Downloads a CSV with Member UID, Name, House Name, Assigned Sports; output is sanitized against formula-injection (no cell may start with `=`, `+`, `-`, `@` unescaped).

## A6. Venue & Ground Setup — *(gap-filled; both prior docs under-covered this)*

### TC-ADM-034: Add Multiple Venues to One Season
* Adding "Gachibowli Indoor Sports Complex" and "Cyberabad Cricket Ground" both toggled ON, each with its own address, contact, and map pin, coexist independently in the same season.

### TC-ADM-035: Add Multiple Courts/Grounds Under One Venue
* Adding "Badminton Court 1" and "Badminton Court 2" under Gachibowli creates two independently bookable resources the scheduler can assign in parallel.

### TC-ADM-036: Set Per-Venue Operating Hours
* Gachibowli set to 08:00–20:00 (12h) and Cyberabad set to 09:00–18:00 (9h) are respected independently by the capacity engine; matches never get scheduled outside a venue's operating window.

### TC-ADM-037: Set Match Duration + Turnaround Gap Per Sport/Venue
* Badminton: 45-min matches + 15-min turnaround = 60-min slots. Cricket T20: 180-min matches + 30-min turnaround = 210-min slots. The capacity engine computes daily match capacity per court from these two numbers (e.g., 12h ÷ 1h × 2 courts = 24 badminton matches/day).

### TC-ADM-038: Assign a Fixture to a Specific Ground/Court Manually
* From the schedule grid, an organizer can hand-pick which court a given fixture uses, overriding the auto-scheduler's choice, subject to the double-booking guard (A4/TC-ADM-020).

### TC-ADM-039: Ground Capacity Warning When Entrants Exceed Available Slots
* If registered team/entrant count would require more daily match slots than the configured venues can provide, the schedule builder surfaces a warning banner *before* generation: *"Cricket needs 9 match-slots but venues only provide 6/day — extend dates or add a ground."*

### TC-ADM-040: Retire/Deactivate a Venue Mid-Season
* Toggling a venue OFF after fixtures exist blocks the toggle with an error until every fixture assigned to that venue's courts is reassigned or the event is cancelled — prevents silently orphaning scheduled matches.

### TC-ADM-041: Venue-Filtered Schedule View & Export
* Filtering the schedule grid to a single venue shows only that venue's courts/columns; PDF/CSV export respects the active filter so a ground manager can print a venue-specific noticeboard.

## A7. Officials & Umpire Assignment

### TC-ADM-042: Add a Verified Official From Registry
* Searching and adding "Kalyan Varma" pulls in his certified sports and verification badge from the public officials registry.

### TC-ADM-043: Add an External Official by Hand (Not on PlaySphere)
* Manually entering name + phone + certified sport for an official with no PlaySphere account tags them `handEntered: true` and an "External" chip, still assignable to matches.

### TC-ADM-044: Neutrality Constraint — Block Partisan Umpire Assignment
* Attempting to assign "Official Vikram" (affiliated with PS Visitors Club) to a match where PS Visitors Club is playing is rejected client + server side: *"Neutrality Violation: Official affiliated with competing club."*

### TC-ADM-045: Neutrality Override With Mandatory Justification (Emergency Only)
* When only one umpire is available, checking "Override Neutrality Constraint" requires a reason ("Mutual agreement by both captains") and stamps the match with a visible amber "Partisan (Override)" chip plus an audit-log entry naming who overrode it and why — both clubs can see the override happened.

### TC-ADM-046: Bulk Neutral Auto-Assignment
* "Run Neutral Assignment" staffs every unofficiated match across the season respecting neutrality + rest gaps in one pass, reporting `"10 matches staffed; 0 neutrality conflicts."`

### TC-ADM-047: Unstaffed-Match Alert
* Organizer Desk surfaces a standing amber card counting matches within 24h that still have no umpire, deep-linking to the fix.

### TC-ADM-048: Swap an Official on Matchday (Sick Leave)
* Replacing an assigned umpire updates the fixture doc and pushes an assignment notification to the new umpire.

### TC-ADM-049: Remove an Official With Active Assignments
* Deleting an official who still has assigned matches prompts *"Unassign from 3 matches first?"* before allowing removal — those matches revert to unstaffed rather than silently losing their umpire reference.

## A8. Access-Based Role System (Owner / Admin / Umpire / Co-ordinator) — *(gap-filled)*

### TC-ADM-050: Owner Grants Co-ordinator Role to a Member
* Owner adds "Manage Competitions" capability scoped as `coordinator` to a member; that member now sees Organizer Desk but **not** the club-ownership-transfer or financial-ledger screens.

### TC-ADM-051: Owner Grants Admin Role to a Member
* Same flow but scoped `admin`: the member gets everything a coordinator gets **plus** the ability to grant/revoke other coordinators/admins — but still cannot transfer club ownership (owner-exclusive).

### TC-ADM-052: Co-ordinator Cannot Delegate Further
* Logged in as a coordinator, the "Grant Rights to Another Member" action is hidden/disabled — only owner and admin roles can extend access.

### TC-ADM-053: Umpire Role Is Scoped to Assigned Matches Only
* An account with only the `umpire` role can open the scoring console for matches they're assigned to, but cannot see Organizer Desk, cannot edit season settings, cannot see the financial ledger, and cannot approve/reject registrations. Attempting a direct URL to any of those routes shows the lock-gate screen.

### TC-ADM-054: Umpire *Can* Make In-Match Roster Changes; Cannot Edit Draws
* An assigned umpire can perform an emergency substitution on the match they're officiating (see A12) but has no access to "Build Draw" or "Edit Event" for that competition.

### TC-ADM-055: Revoke Any Delegated Role Takes Effect Immediately
* Removing a capability from a coordinator/admin/umpire hides the corresponding controls from their app on next refresh/security-claim check — no stale access window beyond token refresh.

### TC-ADM-056: Role Boundary Regression — Admin Cannot Impersonate Owner-Only Actions
* Logged in as `admin`, attempting the club-ownership-transfer flow (even via direct route) is blocked server-side by security rules, not just hidden client-side.

## A9. Sending Invitations Directly From the Season Page — *(gap-filled)*

### TC-ADM-057: Compose and Send an Invite to a Specific Club
* From the season page, tap **Invite a Club** → search/select "PS Visitors Club" → pick which sports are offered to them (subset of the season's sports is allowed) → write/confirm the invite letter (auto-filled with dates/venue, editable) → tap **Send Invitation**.
* **Expected:** An invite doc is created scoped to that club; the visiting club owner (and admins) get the push/inbox notification tested in Suite B4; the season page's "Invited Clubs" list shows the club as `pending`.

### TC-ADM-058: Bulk-Invite Multiple Clubs at Once
* Selecting 5 clubs from a multi-select picker and sending in one action creates 5 independent invite docs; each club's acceptance/decline is tracked separately and doesn't affect the others.

### TC-ADM-059: Withdraw a Sent Invite Before Acceptance
* Tapping "Withdraw Invite" on a still-pending invite flips it to `revoked`; the target club's invitation card updates to "Invitation Withdrawn by Host" and their Accept/Decline buttons disable.

### TC-ADM-060: Re-Invite a Club That Previously Declined
* A club that declined can be re-invited (e.g., after a date change); this creates a fresh invite doc rather than trying to mutate the declined one, so history is preserved.

### TC-ADM-061: Invite Restricted to Sports the Season Actually Has
* The sport-selection step in the invite composer only lists sports already added to the season (Suite A2) — an admin cannot invite a club to a sport that hasn't been configured yet.

## A10. Registration Review & Acceptance

### TC-ADM-062: Review and Approve a Pending Solo Entry
* Inspecting a solo entrant's profile (age, verified-member status) before tapping **Accept** moves them to `approved` and fires a push notification.

### TC-ADM-063: Review and Approve a Pending Team Entry
* "Inspect Squad" shows all 11 players before **Accept**; approving a team approves the whole squad atomically, not player-by-player.

### TC-ADM-064: Decline an Entry With Mandatory Reason
* Declining picks/enters a reason ("Squad incomplete — requires 11 players"); the slot frees up in category capacity and the club is notified with the stated reason.

### TC-ADM-065: Automatic Waitlist Promotion on Cancellation
* A full category (16/16) with one cancellation auto-promotes the next waitlisted entrant to `approved` and notifies them.

### TC-ADM-066: Approve Some, Reject Others From the Same Multi-Team Club Submission
* When a club submits 3 teams in one batch, the host can accept 2 and reject 1 independently — rejection of one team doesn't touch the other two.

## A11. Player Credential Checks (Age ≥ 21 at Match Time)

### TC-ADM-067: Set a Minimum-Age Rule on an Event
* Enabling "Enforce Age Bounds" with Minimum Age 21 stores `minAge: 21`, `dimensions: ["age"]` on the competition doc.

### TC-ADM-068: Age Is Evaluated as of Season Start Date, Not Registration Date
* A player who is 20 at the time they register but will turn 21 before the season's start date is still rejected if 21 is not reached **by season start** — the eligibility clock is the competition's reference date, not "today."
* **Edge:** A player who turns 21 exactly on the season start date is eligible (inclusive boundary) — verify both the day-before-rejected and day-of-accepted cases explicitly.

### TC-ADM-069: Age Check Re-Validated at Match Time, Not Just at Registration
* Because rosters can change post-approval (emergency subs, A12), the age gate must re-run on the *substituted-in* player at the moment they're added to a live match lineup, not only when the original squad was submitted — an admin/umpire cannot slot in an underage reserve to dodge the original check.

### TC-ADM-070: Timezone-Correct Age Calculation (Asia/Kolkata)
* Age math is evaluated in IST, not UTC, so a player born late in the evening IST doesn't get miscounted by a UTC date-boundary shift.

## A12. Umpire/Admin Can Make Team Changes Mid-Match

### TC-ADM-071: Emergency Substitution by Umpire Before Toss/Kickoff
* Umpire taps the injured player → **Substitute/Replace Player** → picks an eligible reserve → enters a mandatory reason → confirms. Lineup updates immediately; an immutable timeline entry logs `[time] Official substituted X with Y (Reason: ...)`.

### TC-ADM-072: Emergency Substitution by Admin (Not Assigned as Umpire)
* A host admin who is *not* the match's assigned umpire can also perform this substitution (season-level authority), and the audit log records the admin's UID distinctly from an umpire-performed substitution.

### TC-ADM-073: Substitution Rejected if Replacement Fails Eligibility (Age/Duplicate)
* Attempting to sub in a reserve who is underage for the event, or who is already active in another squad for the same sport, is blocked with the same eligibility errors as initial registration (A11/B11) — emergency subs don't bypass the anti-cheat and age gates.

### TC-ADM-074: Post-Draw Roster Change Audit Trail
* Every addition/removal to a squad after the draw is built is visible in a per-team audit timeline with exact timestamp + author UID, regardless of whether the actor was umpire, admin, or coordinator.

## A13. Leaderboards & Match Stats — *(gap-filled: dedicated stats case added)*

### TC-ADM-075: Season/House Leaderboard Aggregation
* The standings tab correctly sums points across all completed matches (house or club), breaking ties by gold-medal count (houses) or head-to-head (clubs), matching the season's configured tiebreak chain.

### TC-ADM-076: Dedicated Match Stats View Per Completed Match
* Opening a completed match's "Stats" tab (separate from the live scorecard) shows the sport-appropriate aggregated stats — e.g., batting/bowling figures for cricket, points-on-serve for badminton — sourced from the match's event log, not hand-entered, and matches what the live scorecard showed at match end.

### TC-ADM-077: Player Career/Season Stats Roll-Up Visible on Organizer Desk
* Organizer Desk shows a "Top Performers" panel (top scorers/wicket-takers/etc. depending on sport mix) computed from this season's matches only, refreshing as results are signed off.

## A14. Visibility Gating — Clubs/Players Can't See Admin-Only Detail Until Published

### TC-ADM-078: Draft Schedule Is Fully Invisible to Everyone Outside the Host Club
* Before **Publish Schedule**, a participating club's Schedule tab shows an explicit empty state (*"Schedule not published yet"*) with zero matches, courts, or times leaked — not just a hidden button, an actual empty data response.

### TC-ADM-079: Publishing the Schedule Flips Visibility Instantly for Everyone
* The moment `isSchedulePublished` flips true, every invited/registered club's Schedule tab populates with full fixtures, sport filters, and courts — no separate per-club unlock needed.

### TC-ADM-080: Unpublish Rolls Visibility Back
* "Unpublish Schedule" (for major rework) hides fixtures from all non-admins again immediately; organizer still sees full draft state.

### TC-ADM-081: Pending Entrant Lists Are Admin/Owner-Only Until Approved
* A visiting club can see their *own* submitted entry's status but cannot see other clubs' pending or rejected entries — only the host admin's Pending Entries card shows the full cross-club list.

### TC-ADM-082: Financial Ledger Is Owner/Admin-Only, Hidden From Coordinators and Umpires
* The Organizer Desk "Finances" card (gross collections, gateway fees, net payout) is invisible to `coordinator` and `umpire` roles even though they can see the rest of Organizer Desk.

### TC-ADM-083: "View as Spectator" Preview Toggle
* Admin can toggle a preview mode that hides every organizer-only affordance and renders exactly what a visiting parent/spectator would see, then toggle back without losing their admin session.

## A15. Sports-Wise Tabs & Multi/Single-Player Scheduling

### TC-ADM-084: Independent Sport Tabs With Independent State
* Each sport tab (Cricket, Badminton, Chess, ...) carries its own draw status, entrant count, and publish state — closing entries on Badminton has zero effect on Cricket's entries.

### TC-ADM-085: Sport Tab Auto-Removal When Empty
* Deleting the last remaining event under a sport removes that sport's tab from the nav bar entirely (no dangling empty tabs).

### TC-ADM-086: Multi-Player Sport Scheduling Books at Team Granularity
* Scheduling a Cricket/Football match reserves the slot for the *whole team* — the overlap engine checks all 11/7 rostered players against that single slot, not just the captain.

### TC-ADM-087: Single-Player Sport Scheduling Books at Individual Granularity
* Scheduling a Badminton Singles/Chess match reserves the slot only for the two named individuals, allowing the venue's other courts to run fully independently in parallel.

---

# PART B — PARTICIPATING CLUBS & PLAYERS SIDE

## B1. Internal Club Members Joining Houses — *(gap-filled: player-side view added)*

### TC-CLUB-001: Player Sees Their Assigned House After Admin Allocation
* After the admin runs bulk house allocation (TC-ADM-027), a host club member opens the season and sees a "My House: Kakatiya Dynamos" banner with the house color, without needing to be told out-of-band.

### TC-CLUB-002: Player Registers Into an Internal-Season Event as a House Athlete
* A member of the host club registering for a house-season Badminton Singles category automatically carries their house tag onto the registration record, so house standings can attribute their result correctly.

### TC-CLUB-003: Player Requests a House Transfer (If Enabled by Organizer)
* If the organizer allows self-service transfer requests, a player can request to move houses; the request lands on the admin's queue rather than applying instantly (admin retains final control per TC-ADM-029).

## B2. Register for Single Sport / Multi-Sport (Internal Season)

### TC-CLUB-004: Member Registers for One Sport Only
* Registering only for Chess Rapid inside a multi-sport house season doesn't force registration into any other sport.

### TC-CLUB-005: Member Registers for Multiple Sports in the Same Internal Season
* The same member can independently register for Badminton Singles AND Table Tennis Singles in the same house season; the schedule engine (TC-ADM-018/019) then guarantees no overlap between the two.

## B3. Leaderboards, Match Schedules, Live Scoring (Player View)

### TC-CLUB-006: Player Views House/Club Leaderboard
* The Standings tab is readable by any participant (not just admins) and reflects the same numbers the admin sees in TC-ADM-075, read-only.

### TC-CLUB-007: Player Views Published Match Schedule Filtered to "My Matches"
* A "My Matches" filter on the schedule screen shows only fixtures the logged-in player/team is part of, across all sports they're registered in.

### TC-CLUB-008: Player Views Live Score With Real-Time Updates
* Opening a live match shows ball-by-ball/point-by-point updates streaming without manual refresh.

### TC-CLUB-009: Player Gets a Pre-Match Reminder Notification
* A push notification fires ~30 minutes before the player's scheduled match with court/venue info.

## B4. External Club Invite Reception — Owner-Only

### TC-CLUB-010: Only the Club Owner (and Delegated Admins) See the Invite
* The invite from TC-ADM-057 appears on the visiting club **owner's** Invitations screen with full letter + Accept/Decline actions. A delegated visiting-club admin (`Capability.manageCompetitions`) also sees and can act on it. A regular member of the same visiting club sees an empty state: *"No pending invitations for you."*

### TC-CLUB-011: Decline an Invitation With Feedback Reason
* Declining prompts a reason ("Scheduling conflict"); the card grays out; a 24-hour undo window is offered before the decline is final.

### TC-CLUB-012: Accept an Invitation → Land in Entry Builder
* "Accept & Build Entry" flips invite status to `accepted` and routes straight into the squad/roster builder for the offered sports.

### TC-CLUB-013: Invitation Expiry / Withdrawal Reflected Live
* If the deadline passes or the host withdraws the invite (TC-ADM-059), the visiting club's card updates to the corresponding locked state and Accept disables.

## B5. RSVP Creation & Team-Building From RSVP

### TC-CLUB-014: Club Owner Creates an RSVP Targeting All Members
* Posting an availability poll to "All Club Members" for a given sport publishes an announcement everyone in the club sees on their feed.

### TC-CLUB-015: Club Owner Creates an RSVP Targeting Only a Specific Sub-Group — *(explicit "ask only specific people" scenario)*
* Instead of polling everyone, the owner picks "Cricket Squad Members (25)" — or any other named sub-group — as the audience; only those 25 get the notification and see the poll card, not the other 75 club members.

### TC-CLUB-016: RSVP Can Be Created Per-Sport Independently
* A club running both a Cricket entry and a Badminton entry for the same season creates two separate RSVP polls, one per sport, each with its own deadline and audience.

### TC-CLUB-017: Member Taps In / Out / Tentative
* Each of the three response states updates instantly with a distinct visual state and increments the correct real-time counter on the owner's side.

### TC-CLUB-018: Member Changes Their Response Before Deadline
* Switching from "In" to "Out" decrements the "Available" count and removes them from the captain's auto-add pool.

### TC-CLUB-019: Responses Lock at Deadline
* After the deadline, response buttons disable for members and the server rejects late write attempts; the finalized headcount is preserved.

### TC-CLUB-020: Owner/Captain Views Full Response Roster
* A roster sheet lists everyone who responded "In" with contact/rating info and a quick-call action, for actually reaching them.

## B6. Hybrid Roster Building — Partial Pick + RSVP Completion (5 Direct + 6 via RSVP)

### TC-CLUB-021: Directly Pick Some Players First
* Manually checking 5 confirmed players updates the counter to "5/11 selected (6 needed)."

### TC-CLUB-022: One-Tap Pull Remaining Slots From RSVP Respondents
* A dynamic button — "Add the 6 who said In from RSVP" — appears once there are enough "In" responses to fill the gap; tapping it opens a sheet of respondents with the top N pre-checked, adjustable before confirming.

### TC-CLUB-023: Squad Completes to Required Size and Submit Unlocks
* Confirming the RSVP pull brings the squad to 11/11; "Submit Squad for Registration" only enables once the minimum is met.

### TC-CLUB-024: Add Reserves Beyond the Starting XI
* Reserves can be added up to the sport's max squad size (e.g., 15 for cricket); adding a 16th is blocked with a clear cap message.

### TC-CLUB-025: Assign Captain / Wicket-Keeper / Role Chips
* Role assignment (Captain, WK, etc.) is per-player, editable, and reflected on the squad card.

### TC-CLUB-026: Remove/Clear Selections Mid-Build
* Removing one player decrements the counter and re-disables Submit until refilled; "Clear All" resets the whole draft with a confirmation.

## B7. RSVP for Individual Sports

### TC-CLUB-027: RSVP Poll for a Single-Player Sport Event
* An owner can still post an RSVP for something like Badminton Singles to gauge interest before individually registering members — the RSVP mechanism isn't team-sport-exclusive, even though solo sports don't need a "squad" afterward, just a shortlist of who to individually register.

## B8. Multiple Teams, Same Club, Same Season

### TC-CLUB-028: Register a Second Team for the Same Sport
* After submitting "PS Visitors Lions," tapping **+ Register Another Team for Cricket** opens a fresh squad builder for "Squad #2" with zero player overlap allowed against Squad #1.

### TC-CLUB-029: Register a Third Team (Club A Enters 3 Teams Into Club B's Season)
* Repeating the flow for "PS Visitors Eagles" results in 3 fully independent team registrations from the same visiting club in the same season/sport, each with its own captain, roster, and seed.

### TC-CLUB-030: Duplicate Team Name Within Same Club Blocked
* Naming Squad #2 identically to Squad #1 ("PS Visitors Lions" again) is rejected with a clear uniqueness error.

### TC-CLUB-031: Per-Team Fee Calculation
* Pay-per-event mode itemizes `3 teams × ₹2,500 = ₹7,500`; whole-season mode instead shows a flat club pass covering all teams the club enters.

### TC-CLUB-032: Host Approves/Rejects Each Team Independently
* The host can accept Lions and Tigers while rejecting Eagles (e.g., capacity) without affecting the two accepted teams.

## B9. No Invite Received → Discover & Request Registration

### TC-CLUB-033: Find an Open Season via Explore/Discovery
* An uninvited club owner finds a season marked "Open" through search/browse (filterable by sport/city).

### TC-CLUB-034: Submit a Club Registration Request on an Open Season
* Tapping **Request Club Registration**, selecting desired sports, and submitting creates a request the host reviews — distinct from the direct-invite flow, and shows up on the host's Pending Requests queue.

### TC-CLUB-035: Host Approves an Uninvited Club's Request
* Approval unlocks the requesting club to build/submit entries exactly as an invited club would.

### TC-CLUB-036: Host Declines an Uninvited Club's Request With Reason
* Decline is logged with a reason and notified to the requester; re-submission may be rate-limited (e.g., no resubmission for N days) per organizer policy.

## B10. Invite-Only Strict Enforcement

### TC-CLUB-037: Invite-Only Season Hides All Public Entry Points
* When `accessMode == "inviteOnly"`, an uninvited club sees **no** "Request Registration" button at all — not disabled, not hidden-behind-a-tooltip, fully absent — replaced by a lock banner: *"By Invitation Only."*

### TC-CLUB-038: Direct URL to Invite-Only Season's Registration Route Is Blocked Server-Side
* Even bypassing the UI via a direct route/deep link, the write is rejected by security rules for a club that has no invite/approved-request record.

## B11. Duplicate Player / Same-Sport, Same-Season Guard

### TC-CLUB-039: Same Player Cannot Be Selected Into a Second Squad for the Same Sport
* Attempting to check "Player Ravi" (already in Lions/Cricket) into Tigers/Cricket is refused client-side with an inline error naming the conflicting team.

### TC-CLUB-040: Server-Side Duplicate Guard Survives a Bypassed Client
* Even if a malicious/buggy client submits a batch containing the same UID twice in one competition's registrations, the write transaction fails atomically server-side.

### TC-CLUB-041: Cross-Club Duplicate Flag (Same Player, Two Different Clubs, Same Sport)
* If the same person is somehow registered for Cricket by both Club A and Club B in the same season, the host's Pending Entries view surfaces an explicit warning banner naming the player and both clubs, forcing a manual resolution rather than silently allowing both.

### TC-CLUB-042: Multi-Sport Participation Is Allowed (Not a Duplicate)
* The same player registering for Cricket AND Badminton AND Chess in the same season is valid — the duplicate guard is scoped per-sport, not per-player-per-season.

### TC-CLUB-043: Duplicate Guard Also Applies to Late Roster Substitutions
* Swapping in a reserve who's already active on another squad for the same sport is blocked with the same duplicate error as initial registration.

## B12. Multiplayer Sport Cannot Register as a Single Member

### TC-CLUB-044: Team-Sport Event Page Has No "Register Myself" for Individuals
* Opening Football 7s or Cricket 11s as a lone individual shows no solo-registration affordance at all — only an informational card: *"Team sport — must be registered by a club team,"* with a "Contact Club Owner" action.

### TC-CLUB-045: Teams for Multiplayer Sports Must Be Built Inside the Club (Not Ad-Hoc)
* A multiplayer-sport squad can only be assembled from a club's own member roster via the Squad Builder (B6) — there's no path to cobble together a team from unaffiliated individuals outside a club context.

### TC-CLUB-046: Single-Player Sport Explicitly Allows Direct Solo Entry
* Badminton Singles/Chess/Table Tennis Singles show a prominent **Register Myself** button for any eligible individual — contrast case to TC-CLUB-044.

## B13. Cross-Club Direct Join for Single-Player Sports

### TC-CLUB-047: Member of Club A Directly Joins Club B's Open Single-Sport Tournament
* A member of the host club can open a *different* club's publicly-open Badminton Singles tournament and tap **Register Myself** successfully — because it's a single-player sport, club affiliation is irrelevant to eligibility; only the season's own `accessMode` (open vs invite-only) gates it.

### TC-CLUB-048: The Same Cross-Club Direct Join Is Blocked if That Season Is Invite-Only
* If Club B's single-sport tournament is `inviteOnly`, the same individual cannot direct-join even though it's a solo sport — invite-only status overrides the "any individual can join a solo sport" rule (B10 applies on top of B13).

### TC-CLUB-049: Doubles Partner Nomination Flow (Two Individuals, Still Cross-Club-Eligible)
* Registering for Badminton Doubles lets a solo player nominate a partner (who must confirm); the entry stays `pending_partner` until accepted, and this works regardless of whether the partner is from the same club.

## B14. 100-Player Scale — Using the Same Pool as Both Internal and External Registrants

### TC-CLUB-050: 100 Host-Club Members Split Between an Internal House Season and an External Team Entry
* The same 100-member host-club roster is used two ways in parallel: (a) allocated across 4 houses for the club's internal season (TC-ADM-027), and (b) a subset of those same members is simultaneously assembled into 3 external-facing teams (Lions/Tigers/Eagles) entered into a *different* club's tournament as a visiting club. Verify a player can legitimately appear in their own club's house roster **and** in an externally-submitted team for a different season without the duplicate guard (B11) misfiring — because B11's guard is scoped to one competition/sport/season, not globally across unrelated tournaments.
* **Expected:** House allocation writes are scoped to the internal season's document tree; external team registrations are scoped to the visiting tournament's document tree; no cross-contamination or false-positive duplicate flags between the two unrelated contexts.

### TC-CLUB-051: 100-Member Roster Renders Without Jank in Squad Builder / House Allocator
* Scrolling a 100-entry member list in either the squad builder or the house allocator stays smooth (lazy-loaded), with all avatars/badges correct at the bottom of the list, not just the top.

### TC-CLUB-052: 50 Concurrent RSVP Taps Resolve to an Accurate Headcount
* Fifty members tapping "In" at effectively the same moment all land correctly — the real-time counter converges to exactly 50, with no lost writes from transaction contention.

---

## Appendix: How to Use This Document

1. Run **Part A** end-to-end first on a throwaway test season — it validates the organizer's entire authoring surface before any club is invited.
2. Run **Part B** with at least 4 devices/accounts (host owner, host member, dual-club member, visiting owner) so the cross-club and cross-role assertions (B4, B10, B11, B13) are actually exercised, not just simulated by one tester switching hats.
3. Treat **Section 0** as a standing punch-list: A6 (venues), A8 (role matrix), A9 (send-invite), A13 (match stats), and B1 (player-side house view) were the specific holes found in your two prior documents — verify these five areas get real attention in the next test pass, since they're the ones most likely to have been skipped in actual QA if the docs were used as a checklist up to now.
