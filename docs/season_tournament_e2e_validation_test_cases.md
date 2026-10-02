# PlaySphere Master 200+ Test Case Specification: Season & Tournament Flow
## Ultra-Detailed Button-by-Button & Functional QA Guide

**Document ID:** `PS-QA-E2E-200-SPEC-2026-V5`  
**Target Environment:** PlaySphere Multi-Sport OS (Flutter Web/iOS/Android + Firebase Cloud Functions + Firestore Security Rules)  
**Total Test Cases:** 215 Granular Test Cases  
**Scope:** Exhaustive button-by-button, scenario-by-scenario verification across Season Creator (Admin) and Participating Clubs & Players.

---

### Role Matrix & Personas
| Persona | Device | Suggested Account | Capabilities / Roles |
|---|---|---|---|
| **Host Owner / Admin** | D1 | `admin@pstesthost.org` | Full Creator, Competition Manager, Grounds & Officials Manager |
| **Host Regular Player** | D2 | `player2@pstesthost.org` | Host Club Member, House Athlete, Singles Entrant |
| **Dual-Club Player** | D3 | `player3@pstesthost.org` | Member of Host Club AND Visiting Club, Multi-Sport Athlete |
| **Visiting Club Owner** | D4 | `owner@psvisitors.org` | Visiting Club Owner, Captain, Team Entry Submitter |

---

# PART 1: SEASON CREATOR & HOST CLUB ADMIN SIDE (125 TEST CASES)

## Suite 1.1: Season Container Wizard & Creation Controls (TC-ADM-001 to TC-ADM-015)

### TC-ADM-001: Floating Action Button '+ Create Season' Visibility for Admin
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `ActiveSeasonsScreen > Bottom-right FAB`
* **Pre-conditions:** User logged in on D1 with manageCompetitions capability.
* **Step-by-Step Execution:**
1. Navigate to More > Tournaments/Seasons.
2. Observe bottom-right corner.
* **Expected Result (UI):** Green extended FAB labeled '+ Create Season' is displayed with primary elevation.
* **Expected Result (Backend/Data):** Route guard allows access; no permission errors.
* **Edge / Negative Scenario:** Non-admin (D2) navigates to same screen; FAB is completely hidden.

### TC-ADM-002: FAB '+ Create Season' Debounce & Tap Rapid Protection
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `ActiveSeasonsScreen > FAB`
* **Pre-conditions:** On Tournaments screen.
* **Step-by-Step Execution:**
1. Rapidly double-tap or triple-tap '+ Create Season'.
* **Expected Result (UI):** Single navigation push to CreateSeasonScreen occurs. No screen duplication.
* **Expected Result (Backend/Data):** Router stack has exactly one instance of CreateSeasonScreen.
* **Edge / Negative Scenario:** Slow network or lagging device does not open multiple stacked wizards.

### TC-ADM-003: Container Name Input Field - Valid Entry
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `CreateSeasonScreen > Season Name field`
* **Pre-conditions:** CreateSeasonScreen open.
* **Step-by-Step Execution:**
1. Tap 'Season Name' field.
2. Type 'Telangana State Championship 2026'.
* **Expected Result (UI):** Text appears smoothly; character counter increments; border highlights in Ps.primary.
* **Expected Result (Backend/Data):** Local TextEditingController holds 'Telangana State Championship 2026'.
* **Edge / Negative Scenario:** Special characters like hyphens, ampersands, and numbers are accepted.

### TC-ADM-004: Container Name Input Field - Empty Validation on Submit
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `CreateSeasonScreen > Name Field`
* **Pre-conditions:** CreateSeasonScreen open with blank name.
* **Step-by-Step Execution:**
1. Leave Season Name empty.
2. Tap 'Create & Save Draft' button.
* **Expected Result (UI):** Red error text appears below field: 'Please enter a season name'. Form does not submit.
* **Expected Result (Backend/Data):** Zero network writes; Firestore document is not created.
* **Edge / Negative Scenario:** Whitespace-only strings ('   ') trigger the same validation error.

### TC-ADM-005: Container Name - Duplicate Name in Same Club Check
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `CreateSeasonScreen > Name Field`
* **Pre-conditions:** A season named 'Telangana State Championship 2026' already exists in PS Test Academy.
* **Step-by-Step Execution:**
1. Enter duplicate name 'Telangana State Championship 2026'.
2. Tap 'Create & Save Draft'.
* **Expected Result (UI):** Error dialog pops up: 'A season with this name already exists in this club'.
* **Expected Result (Backend/Data):** Repository SeasonName.isAvailable returns false; write rejected.
* **Edge / Negative Scenario:** Adding 'v2' or '2027' passes validation.

### TC-ADM-006: Segmented Switch 'Kind': Select 'Season (Multi-Sport)'
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `CreateSeasonScreen > Kind Segment`
* **Pre-conditions:** CreateSeasonScreen open.
* **Step-by-Step Execution:**
1. Tap segment 'Season (Multi-Sport)'.
* **Expected Result (UI):** Segment turns solid primary color; multi-sport categories section becomes visible.
* **Expected Result (Backend/Data):** State variable _kind set to SeasonKind.season.
* **Edge / Negative Scenario:** Allows adding disparate sports (Cricket, Badminton, Chess) into the container.

### TC-ADM-007: Segmented Switch 'Kind': Select 'Tournament (Single-Sport)'
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `CreateSeasonScreen > Kind Segment`
* **Pre-conditions:** CreateSeasonScreen open.
* **Step-by-Step Execution:**
1. Tap segment 'Tournament (Single-Sport)'.
* **Expected Result (UI):** Primary Sport dropdown appears immediately; multi-sport picker hides.
* **Expected Result (Backend/Data):** State variable _kind set to SeasonKind.tournament.
* **Edge / Negative Scenario:** Restricts category additions to sub-events of the selected primary sport.

### TC-ADM-008: Primary Sport Dropdown Selection (Cricket)
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `CreateSeasonScreen > Primary Sport Dropdown`
* **Pre-conditions:** Kind is set to 'Tournament'.
* **Step-by-Step Execution:**
1. Tap Primary Sport dropdown.
2. Select 'Cricket'.
* **Expected Result (UI):** Dropdown closes showing Cricket icon and title.
* **Expected Result (Backend/Data):** State variable _primarySportId set to 'cricket'.
* **Edge / Negative Scenario:** Only sports certified in the catalog appear in the dropdown.

### TC-ADM-009: Tournament Grade Dropdown Selection (District)
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `CreateSeasonScreen > Grade Dropdown`
* **Pre-conditions:** CreateSeasonScreen open.
* **Step-by-Step Execution:**
1. Tap Grade dropdown.
2. Select 'District' (Weight: 3).
* **Expected Result (UI):** Dropdown reflects 'District' with 3-star grade indicator.
* **Expected Result (Backend/Data):** State variable _grade set to TournamentGrade.district.
* **Edge / Negative Scenario:** Grade weights calibrate Glicko-2 skill rating adjustments upon match completion.

### TC-ADM-010: Date Range Picker - Selecting Future Window
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `CreateSeasonScreen > Dates Field`
* **Pre-conditions:** CreateSeasonScreen open.
* **Step-by-Step Execution:**
1. Tap 'Season Dates' field.
2. Select Start: 10 Oct 2026, End: 25 Oct 2026.
3. Tap 'Save'.
* **Expected Result (UI):** Modal dismisses; field displays '10 Oct 2026 – 25 Oct 2026 (16 days)'.
* **Expected Result (Backend/Data):** _startDate and _endDate stored as Indian Standard Time midnight timestamps.
* **Edge / Negative Scenario:** Past dates are grayed out and unselectable.

### TC-ADM-011: Date Range Picker - Single Day Event Selection
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `CreateSeasonScreen > Dates Field`
* **Pre-conditions:** CreateSeasonScreen open.
* **Step-by-Step Execution:**
1. Tap Dates field.
2. Tap 12 Oct 2026 twice (start and end on same day).
3. Save.
* **Expected Result (UI):** Field displays '12 Oct 2026 (1 day)'.
* **Expected Result (Backend/Data):** _startDate and _endDate have same calendar date.
* **Edge / Negative Scenario:** Timetable bounds restrict all match slots to 12 Oct 2026.

### TC-ADM-012: Fee Mode Radio: Select 'One fee for the whole season'
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `CreateSeasonScreen > Fee Mode`
* **Pre-conditions:** CreateSeasonScreen open.
* **Step-by-Step Execution:**
1. Select radio 'One fee for the whole season'.
2. In fee input, type '1500'.
* **Expected Result (UI):** Fee field accepts ₹1500; individual event fee fields are disabled/locked to ₹0.
* **Expected Result (Backend/Data):** Stored as feeMode: 'season', entryFeeRupees: 1500.
* **Edge / Negative Scenario:** Entrants pay once at season checkout and gain free access to all included events.

### TC-ADM-013: Fee Mode Radio: Select 'Pay per event / category'
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `CreateSeasonScreen > Fee Mode`
* **Pre-conditions:** CreateSeasonScreen open.
* **Step-by-Step Execution:**
1. Select radio 'Pay per event / category'.
* **Expected Result (UI):** Top fee input hides; helper note confirms event-level pricing will apply.
* **Expected Result (Backend/Data):** Stored as feeMode: 'per_event'.
* **Edge / Negative Scenario:** Allows charging ₹300 for Badminton Singles and ₹2500 for Cricket Team.

### TC-ADM-014: Description Field - Multiline Text Entry
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `CreateSeasonScreen > Description Box`
* **Pre-conditions:** CreateSeasonScreen open.
* **Step-by-Step Execution:**
1. Tap Description box.
2. Enter 3 paragraphs of rules, prizes, and venue guidelines.
* **Expected Result (UI):** Text wraps properly; scrollable inside box; character counter up to 2000 chars.
* **Expected Result (Backend/Data):** _description holds full string with newline characters preserved.
* **Edge / Negative Scenario:** Leaving description blank is permitted as optional field.

### TC-ADM-015: Button 'Create & Save Draft' - Success State & Navigation
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `CreateSeasonScreen > Bottom Action Bar`
* **Pre-conditions:** All mandatory fields filled.
* **Step-by-Step Execution:**
1. Tap 'Create & Save Draft'.
* **Expected Result (UI):** Button displays white spinner; screen navigates to TournamentDetailScreen with green toast.
* **Expected Result (Backend/Data):** Firestore creates orgs/org_host_01/tournaments/{id} with status: 'draft', acceptsEntries: false.
* **Edge / Negative Scenario:** Draft season is completely hidden from public visitors and external clubs.
## Suite 1.2: Sports Catalog, Side Formats & Equipment Specs (TC-CREATOR-016 to 028)

### TC-CREATOR-016: Bulk Category Selector Sheet - Open Modal
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Organizer Desk > Events`
* **Pre-conditions:** Season details open in draft.
* **Step-by-Step Procedure:**
1. Tap '+ Add Category / Event'.
* **Expected Result (UI & Feedback):** BulkCategorySelectorSheet slides up from bottom displaying sport catalog.
* **Expected Result (Backend & Data):** Catalogs loaded from SportCatalog registry.
* **Edge / Negative Scenarios:** Tapping scrim outside dismisses sheet cleanly.

### TC-CREATOR-017: Sport Catalog - Badminton Singles Selection
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `BulkCategorySelectorSheet`
* **Pre-conditions:** Sheet open.
* **Step-by-Step Procedure:**
1. Tap 'Badminton' sport chip.
2. Tap 'Singles' side format.
3. Check 'Men's Open'.
* **Expected Result (UI & Feedback):** Category row highlights with checkmark; button updates to 'Add 1 Category'.
* **Expected Result (Backend & Data):** DraftCategory instance created with sportId: 'badminton', sideFormat: SideFormat.singles.
* **Edge / Negative Scenarios:** Disables conflicting double entries.

### TC-CREATOR-018: Sport Catalog - Badminton Doubles Selection
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `BulkCategorySelectorSheet`
* **Pre-conditions:** Sheet open.
* **Step-by-Step Procedure:**
1. In Badminton, tap 'Doubles' side format.
2. Check 'Mixed Doubles'.
* **Expected Result (UI & Feedback):** Category added beside singles; counter displays '2 Categories'.
* **Expected Result (Backend & Data):** sideFormat set to SideFormat.doubles.
* **Edge / Negative Scenarios:** Enforces 2-player team composition at registration.

### TC-CREATOR-019: Sport Catalog - Cricket 11-a-side Selection
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `BulkCategorySelectorSheet`
* **Pre-conditions:** Sheet open.
* **Step-by-Step Procedure:**
1. Tap 'Cricket' sport chip.
2. Select '11-a-side'.
3. Check 'T20 Open'.
* **Expected Result (UI & Feedback):** Cricket T20 row selected; counter updates to '3 Categories'.
* **Expected Result (Backend & Data):** sideFormat set to SideFormat.eleven.
* **Edge / Negative Scenarios:** Enforces 11-player squad minimum at registration.

### TC-CREATOR-020: Sport Catalog - Football 7-a-side Selection
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `BulkCategorySelectorSheet`
* **Pre-conditions:** Sheet open.
* **Step-by-Step Procedure:**
1. Tap 'Football' sport chip.
2. Select '7-a-side'.
3. Check 'Corporate Cup'.
* **Expected Result (UI & Feedback):** Football 7s row checked; counter increments.
* **Expected Result (Backend & Data):** sideFormat set to SideFormat.seven.
* **Edge / Negative Scenarios:** Enforces 7 starters + reserves.

### TC-CREATOR-021: Sport Catalog - Table Tennis Singles Selection
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `BulkCategorySelectorSheet`
* **Pre-conditions:** Sheet open.
* **Step-by-Step Procedure:**
1. Tap 'Table Tennis' chip.
2. Select 'Singles'.
3. Check 'Open Blitz'.
* **Expected Result (UI & Feedback):** Row checked.
* **Expected Result (Backend & Data):** DraftCategory holds table_tennis.
* **Edge / Negative Scenarios:** Supports indoor table allocations.

### TC-CREATOR-022: Sport Catalog - Chess Solo Selection
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `BulkCategorySelectorSheet`
* **Pre-conditions:** Sheet open.
* **Step-by-Step Procedure:**
1. Tap 'Chess' chip.
2. Check 'Rapid 15+10'.
* **Expected Result (UI & Feedback):** Row checked.
* **Expected Result (Backend & Data):** sideFormat set to SideFormat.solo.
* **Edge / Negative Scenarios:** Uses Swiss pairing algorithm for draw generation.

### TC-CREATOR-023: Equipment Specification - Cricket Ball Type Picker
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `BulkCategorySelectorSheet > Category Options`
* **Pre-conditions:** Cricket T20 category selected.
* **Step-by-Step Procedure:**
1. Tap 'Equipment / Ball' dropdown.
2. Select 'Red Leather 4-Piece (SG Club)'.
* **Expected Result (UI & Feedback):** Selection reflected in equipment subtitle.
* **Expected Result (Backend & Data):** Stored in equipmentSpec field on category.
* **Edge / Negative Scenarios:** Informs visiting clubs of match ball regulations.

### TC-CREATOR-024: Equipment Specification - Shuttlecock Picker
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `BulkCategorySelectorSheet > Category Options`
* **Pre-conditions:** Badminton Singles selected.
* **Step-by-Step Procedure:**
1. Tap 'Shuttlecock' dropdown.
2. Select 'Feather (Yonex AS-30)'.
* **Expected Result (UI & Feedback):** Feather shuttle badge displayed.
* **Expected Result (Backend & Data):** Stored as equipment: 'feather_yonex_as30'.
* **Edge / Negative Scenarios:** Allows clubs to practice with identical shuttle grade.

### TC-CREATOR-025: Draw Format Selector - Knockout (Single Elimination)
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `BulkCategorySelectorSheet > Format`
* **Pre-conditions:** Badminton category selected.
* **Step-by-Step Procedure:**
1. In Format dropdown, select 'Single Elimination (Knockout)'.
* **Expected Result (UI & Feedback):** Knockout bracket icon displayed.
* **Expected Result (Backend & Data):** format set to CompetitionFormat.knockout.
* **Edge / Negative Scenarios:** Generates pairwise bracket with losers eliminated.

### TC-CREATOR-026: Draw Format Selector - Round Robin (League Table)
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `BulkCategorySelectorSheet > Format`
* **Pre-conditions:** Cricket category selected.
* **Step-by-Step Procedure:**
1. Select 'Round Robin'.
* **Expected Result (UI & Feedback):** League table grid icon displayed.
* **Expected Result (Backend & Data):** format set to CompetitionFormat.roundRobin.
* **Edge / Negative Scenarios:** Generates all-play-all schedule and standings table.

### TC-CREATOR-027: Draw Format Selector - Group Stage then Knockout
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `BulkCategorySelectorSheet > Format`
* **Pre-conditions:** Football category selected.
* **Step-by-Step Procedure:**
1. Select 'Groups then Knockout'.
2. Set Group Count: 2, Top per group advancing: 2.
* **Expected Result (UI & Feedback):** Group configuration preview renders.
* **Expected Result (Backend & Data):** drawConfig stores groups: 2, advancingPerGroup: 2.
* **Edge / Negative Scenarios:** Group winners advance to semifinals.

### TC-CREATOR-028: Button 'Add Selected Categories' - Batch Creation Execution
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `BulkCategorySelectorSheet > Bottom Bar`
* **Pre-conditions:** 6 categories selected across 5 sports.
* **Step-by-Step Procedure:**
1. Tap 'Add Selected Categories (6)'.
* **Expected Result (UI & Feedback):** Sheet dismisses; sports navigation bar displays 5 sport tabs with 6 event rows.
* **Expected Result (Backend & Data):** Batch write creates 6 competition docs under orgs/org_host_01/tournaments/{id}/competitions/.
* **Edge / Negative Scenarios:** Database rollback occurs if any category creation fails.

## Suite 1.3: Category Setup, Dimensions, Age Limits & Restrictions (TC-CREATOR-029 to 042)

### TC-CREATOR-029: Category Age Bound Checkbox - Enable Min/Max Fields
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `EditEventDialog > Age Restrictions`
* **Pre-conditions:** Event edit dialog open.
* **Step-by-Step Procedure:**
1. Tap checkbox 'Restrict by Age'.
* **Expected Result (UI & Feedback):** Minimum Age and Maximum Age number input boxes animate into view.
* **Expected Result (Backend & Data):** Internal state sets dimensions.contains('age') = true.
* **Edge / Negative Scenarios:** Unchecking hides fields and clears age limits.

### TC-CREATOR-030: Minimum Age Input - Set to 21 Years
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `EditEventDialog > Min Age`
* **Pre-conditions:** Age restrictions enabled.
* **Step-by-Step Procedure:**
1. Tap 'Minimum Age' field.
2. Enter '21'.
* **Expected Result (UI & Feedback):** Value 21 accepted; preview badge displays 'Age 21+'.
* **Expected Result (Backend & Data):** Competition.minAge set to 21.
* **Edge / Negative Scenarios:** Players under 21 rejected at registration.

### TC-CREATOR-031: Maximum Age Input - Sub-Junior Under-14 Event
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `EditEventDialog > Max Age`
* **Pre-conditions:** U-14 category selected.
* **Step-by-Step Procedure:**
1. Set 'Maximum Age' to 14.
2. Leave Min Age blank.
* **Expected Result (UI & Feedback):** Preview badge displays 'Under-14'.
* **Expected Result (Backend & Data):** Competition.maxAge set to 14.
* **Edge / Negative Scenarios:** Players turning 15 before season start rejected.

### TC-CREATOR-032: Age Boundary Check - Min Age Greater Than Max Age Validation
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `EditEventDialog`
* **Pre-conditions:** Age restrictions enabled.
* **Step-by-Step Procedure:**
1. Enter Min Age: 25.
2. Enter Max Age: 20.
3. Tap 'Save'.
* **Expected Result (UI & Feedback):** Form blocks submission; red error: 'Minimum age cannot exceed maximum age'.
* **Expected Result (Backend & Data):** Write prevented.
* **Edge / Negative Scenarios:** Clearing invalid values restores submit state.

### TC-CREATOR-033: Gender Restriction Dropdown - Male Only
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `EditEventDialog > Gender`
* **Pre-conditions:** Event edit dialog open.
* **Step-by-Step Procedure:**
1. Tap Gender dropdown.
2. Select 'Male'.
* **Expected Result (UI & Feedback):** Row displays 'Men / Boys' badge.
* **Expected Result (Backend & Data):** allowedGenders set to ['male'].
* **Edge / Negative Scenarios:** Female and unspecified gender profiles blocked.

### TC-CREATOR-034: Gender Restriction Dropdown - Female Only
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `EditEventDialog > Gender`
* **Pre-conditions:** Event edit dialog open.
* **Step-by-Step Procedure:**
1. Tap Gender dropdown.
2. Select 'Female'.
* **Expected Result (UI & Feedback):** Row displays 'Women / Girls' badge.
* **Expected Result (Backend & Data):** allowedGenders set to ['female'].
* **Edge / Negative Scenarios:** Male profiles blocked.

### TC-CREATOR-035: Gender Restriction Dropdown - Open / Mixed
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `EditEventDialog > Gender`
* **Pre-conditions:** Event edit dialog open.
* **Step-by-Step Procedure:**
1. Tap Gender dropdown.
2. Select 'Open to all'.
* **Expected Result (UI & Feedback):** Row displays 'Open' badge.
* **Expected Result (Backend & Data):** allowedGenders set to empty list.
* **Edge / Negative Scenarios:** Any registered participant can enter.

### TC-CREATOR-036: Match Duration Stepper - 45 Minutes Standard
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `EditEventDialog > Duration`
* **Pre-conditions:** Event edit dialog open.
* **Step-by-Step Procedure:**
1. Tap Match Duration stepper [+] until '45 mins'.
* **Expected Result (UI & Feedback):** Value displays 45 mins; schedule slot preview updates.
* **Expected Result (Backend & Data):** matchMinutes set to 45.
* **Edge / Negative Scenarios:** Used by scheduler for court interval calculation.

### TC-CREATOR-037: Match Duration Input - T20 Cricket 180 Minutes
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `EditEventDialog > Duration`
* **Pre-conditions:** Cricket T20 event.
* **Step-by-Step Procedure:**
1. In Match Duration field, type '180'.
* **Expected Result (UI & Feedback):** Value displays 180 mins (3.0 hours).
* **Expected Result (Backend & Data):** matchMinutes set to 180.
* **Edge / Negative Scenarios:** Capacity planner calculates 2 matches per turf pitch per day.

### TC-CREATOR-038: Maximum Participants / Squads Stepper (32 Entrants)
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `EditEventDialog > Max Entries`
* **Pre-conditions:** Badminton Singles event.
* **Step-by-Step Procedure:**
1. Tap Max Entries field; type '32'.
* **Expected Result (UI & Feedback):** Displays 'Max 32 entrants'.
* **Expected Result (Backend & Data):** maxParticipants set to 32.
* **Edge / Negative Scenarios:** Entry registration automatically waitlists after 32 confirmed.

### TC-CREATOR-039: Seeding Mode Toggle - Manual vs Ranking-Based
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `EditEventDialog > Seeding`
* **Pre-conditions:** Event edit dialog.
* **Step-by-Step Procedure:**
1. In Seeding dropdown, pick 'Seed by PlaySphere Glicko Rating'.
* **Expected Result (UI & Feedback):** Info note explains top rated players will occupy seeds 1 to 4.
* **Expected Result (Backend & Data):** seedingMode set to 'rating'.
* **Edge / Negative Scenarios:** Avoids early matchups between top players.

### TC-CREATOR-040: Prize Description Input Field
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `EditEventDialog > Prizes`
* **Pre-conditions:** Event edit dialog.
* **Step-by-Step Procedure:**
1. In Prize field, type 'Winner: ₹15,000 + Trophy; Runner: ₹8,000'.
* **Expected Result (UI & Feedback):** Formatted prize card renders in event overview.
* **Expected Result (Backend & Data):** prizesText stored on competition doc.
* **Edge / Negative Scenarios:** Visible to visiting clubs on brochure.

### TC-CREATOR-041: Rulebook URL Attachment Field
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `EditEventDialog > Rules`
* **Pre-conditions:** Event edit dialog.
* **Step-by-Step Procedure:**
1. In Rulebook URL, paste 'https://playsphere.app/rules/bWF0Y2g'.
* **Expected Result (UI & Feedback):** Clickable link icon appears on event card.
* **Expected Result (Backend & Data):** rulesUrl validated as valid HTTPS URL.
* **Edge / Negative Scenarios:** Invalid URLs trigger format warning.

### TC-CREATOR-042: Button 'Save Category Settings' - Persistence Check
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `EditEventDialog > Footer`
* **Pre-conditions:** All parameters configured.
* **Step-by-Step Procedure:**
1. Tap 'Save Changes'.
* **Expected Result (UI & Feedback):** Dialog closes; event row updates immediately with all active constraint badges.
* **Expected Result (Backend & Data):** Firestore competition document updated atomically.
* **Edge / Negative Scenarios:** Concurrent edits by another admin show conflict prompt.

## Suite 1.4: Dynamic Event Editing, Additions & Mid-Season Cancellations (TC-CREATOR-043 to 055)

### TC-CREATOR-043: Add New Sport Tab Mid-Season (Basketball 3x3)
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Season Details > Organizer Desk`
* **Pre-conditions:** Season is live with Cricket and Badminton.
* **Step-by-Step Procedure:**
1. Tap Organizer Desk > Add Category.
2. Pick Basketball > 3x3 > Open.
3. Save.
* **Expected Result (UI & Feedback):** Basketball tab appears dynamically in top sports bar.
* **Expected Result (Backend & Data):** Competitions collection receives basketball_3x3 document.
* **Edge / Negative Scenarios:** Does not disturb active cricket or badminton draws.

### TC-CREATOR-044: Add New Category under Existing Sport (Badminton U-17 Boys)
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Badminton Sport Panel`
* **Pre-conditions:** Badminton currently has only Men's Open.
* **Step-by-Step Procedure:**
1. In Badminton panel, tap '+ Add Category'.
2. Select 'Boys U-17 Singles'.
3. Save.
* **Expected Result (UI & Feedback):** Second draw row appears under Badminton panel.
* **Expected Result (Backend & Data):** Second competition doc created with sportId: 'badminton'.
* **Edge / Negative Scenarios:** Entries open independently for U-17.

### TC-CREATOR-045: Open Registrations Button for Single Category
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Event Row`
* **Pre-conditions:** Category status is 'draft'.
* **Step-by-Step Procedure:**
1. Tap 'Open Registrations' button on Badminton Men's Open.
* **Expected Result (UI & Feedback):** Status badge flips from gray 'Draft' to green 'Registration Open'.
* **Expected Result (Backend & Data):** Competition.acceptsEntries set to true.
* **Edge / Negative Scenarios:** Visiting clubs and players now see active 'Register' button.

### TC-CREATOR-046: Close Registrations Button for Single Category
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Event Row`
* **Pre-conditions:** Category is 'Registration Open' with 16 entrants.
* **Step-by-Step Procedure:**
1. Tap 'Close Entries' button.
* **Expected Result (UI & Feedback):** Status flips to amber 'Entries Closed'.
* **Expected Result (Backend & Data):** Competition.acceptsEntries set to false.
* **Edge / Negative Scenarios:** Public 'Register' button hides immediately; prevents late entries.

### TC-CREATOR-047: Cancel Category with Zero Entrants
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Event Row > Overflow Menu`
* **Pre-conditions:** Empty category.
* **Step-by-Step Procedure:**
1. Tap overflow menu ⋮ on event row.
2. Tap 'Cancel Event'.
3. Confirm dialog.
* **Expected Result (UI & Feedback):** Row marked with red 'Cancelled' chip.
* **Expected Result (Backend & Data):** Competition.status set to 'cancelled'.
* **Edge / Negative Scenarios:** Zero notifications sent since entrant list is empty.

### TC-CREATOR-048: Cancel Category with 8 Active Entrants - Reason Prompt
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Event Row > Overflow Menu`
* **Pre-conditions:** 8 registered players in Chess Rapid.
* **Step-by-Step Procedure:**
1. Tap ⋮ > 'Cancel Event'.
2. Dialog prompts for reason.
* **Expected Result (UI & Feedback):** Modal dialog with mandatory text box appears.
* **Expected Result (Backend & Data):** Action blocked if reason text box is blank.
* **Edge / Negative Scenarios:** Entering reason enables 'Confirm Cancellation' button.

### TC-CREATOR-049: Cancel Category - Cloud Function Notification Dispatch
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Cancel Dialog`
* **Pre-conditions:** Reason: 'Severe thunderstorm warning'.
* **Step-by-Step Procedure:**
1. Type reason.
2. Tap 'Confirm Cancellation'.
* **Expected Result (UI & Feedback):** Dialog closes; status badge turns red 'CANCELLED'.
* **Expected Result (Backend & Data):** Cloud Function onEventCancelled dispatches push notifications to all 8 entrants.
* **Edge / Negative Scenarios:** Inboxes updated with cancellation notice.

### TC-CREATOR-050: Cancel Category - Schedule Timetable Removal
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Schedule Screen`
* **Pre-conditions:** Fixtures previously scheduled for cancelled event.
* **Step-by-Step Procedure:**
1. Open TournamentScheduleScreen.
* **Expected Result (UI & Feedback):** Cancelled event fixtures removed from active timetable; court slots freed up.
* **Expected Result (Backend & Data):** Fixture statuses set to 'cancelled'.
* **Edge / Negative Scenarios:** Freed court slots become available for other sports.

### TC-CREATOR-051: Re-open Cancelled Event Protection
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Event Row`
* **Pre-conditions:** Event is marked cancelled.
* **Step-by-Step Procedure:**
1. Inspect event row controls.
* **Expected Result (UI & Feedback):** 'Open Registrations' and 'Build Draw' buttons are permanently disabled.
* **Expected Result (Backend & Data):** Status cannot be flipped back to open to avoid inconsistent state.
* **Edge / Negative Scenarios:** Organizer must create fresh category if event is reinstated.

### TC-CREATOR-052: Delete Draft Event Permanently
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Event Row > Overflow`
* **Pre-conditions:** Event in draft with 0 registrations.
* **Step-by-Step Procedure:**
1. Tap ⋮ > 'Delete Event'.
2. Confirm delete.
* **Expected Result (UI & Feedback):** Row completely vanishes from UI.
* **Expected Result (Backend & Data):** Document deleted from Firestore.
* **Edge / Negative Scenarios:** Only allowed when entrant count is 0.

### TC-CREATOR-053: Delete Guard - Active Registrations Block
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Event Row > Overflow`
* **Pre-conditions:** Event has 5 registrations.
* **Step-by-Step Procedure:**
1. Tap ⋮ > observe options.
* **Expected Result (UI & Feedback):** 'Delete Event' option is hidden or disabled; only 'Cancel Event' is offered.
* **Expected Result (Backend & Data):** Prevents accidental data deletion with registered users.
* **Edge / Negative Scenarios:** Audit trail preserved.

### TC-CREATOR-054: Sport Tab Auto-Removal when All Categories Removed
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Organizer Desk`
* **Pre-conditions:** Basketball has only 1 event, which is deleted.
* **Step-by-Step Procedure:**
1. Delete last Basketball event.
* **Expected Result (UI & Feedback):** Basketball tab disappears from sports navigation bar.
* **Expected Result (Backend & Data):** tournament.sportCount decrements by 1.
* **Edge / Negative Scenarios:** Clean UI with no empty sport tabs.

### TC-CREATOR-055: Event List Re-ordering by Drag and Drop
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Organizer Desk > Events`
* **Pre-conditions:** 3 categories listed.
* **Step-by-Step Procedure:**
1. Long press drag handle on Event 3.
2. Drag to top position.
* **Expected Result (UI & Feedback):** Event 3 snaps to position 1; smooth reorder animation.
* **Expected Result (Backend & Data):** displayOrder index updated in database.
* **Edge / Negative Scenarios:** Order preserved across all devices.

## Suite 1.5: House Management, Custom Roster, Templates & Batch Allocations (TC-CREATOR-056 to 070)

### TC-CREATOR-056: Houses Card Visibility on Internal Club Season
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Organizer Desk > Houses Card`
* **Pre-conditions:** Internal season created for PS Test Academy.
* **Step-by-Step Procedure:**
1. Open season overview.
2. Tap Organizer Desk.
* **Expected Result (UI & Feedback):** Houses & Batches card is visible showing '0 Houses Configured'.
* **Expected Result (Backend & Data):** Reads tournament.presetHouses array.
* **Edge / Negative Scenarios:** External-only tournament does not display houses card.

### TC-CREATOR-057: Author Custom House Name 'Kakatiya Dynamos'
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Houses & Batches Editor`
* **Pre-conditions:** Houses card open.
* **Step-by-Step Procedure:**
1. Tap '+ Add House'.
2. Enter name 'Kakatiya Dynamos'.
* **Expected Result (UI & Feedback):** New row created; name reflected with orange avatar.
* **Expected Result (Backend & Data):** HouseDraft.fresh created in memory.
* **Edge / Negative Scenarios:** Whitespace is trimmed automatically.

### TC-CREATOR-058: Author Custom House Color with Palette Picker
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `House Row > Color Picker`
* **Pre-conditions:** House row active.
* **Step-by-Step Procedure:**
1. Tap circular color chip.
2. Pick #FF5722 (Deep Orange).
3. Save.
* **Expected Result (UI & Feedback):** House badge and avatar display deep orange tint.
* **Expected Result (Backend & Data):** Hex color stored with house definition.
* **Edge / Negative Scenarios:** Ensures color contrast against white and dark themes.

### TC-CREATOR-059: Pre-built House Template - School 4 Colors
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Houses Editor > Templates`
* **Pre-conditions:** Empty house list.
* **Step-by-Step Procedure:**
1. Tap 'Use Template' dropdown.
2. Select 'Classic 4 Colors (Red, Blue, Green, Yellow)'.
* **Expected Result (UI & Feedback):** 4 house rows populated instantly with corresponding brand colors.
* **Expected Result (Backend & Data):** HouseTemplates.classic populates list.
* **Edge / Negative Scenarios:** Overwrites empty list without confirmation; warns if existing houses present.

### TC-CREATOR-060: Pre-built House Template - College Departments
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Houses Editor > Templates`
* **Pre-conditions:** Empty house list.
* **Step-by-Step Procedure:**
1. Tap 'Use Template'.
2. Select 'Engineering Depts (CSE, ECE, MECH, CIVIL)'.
* **Expected Result (UI & Feedback):** 4 department rows created with custom abbreviations.
* **Expected Result (Backend & Data):** HouseTemplates.departments applied.
* **Edge / Negative Scenarios:** Saves typing on mobile keyboards.

### TC-CREATOR-061: Pre-built House Template - School Classes (8-A to 8-D)
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Houses Editor > Templates`
* **Pre-conditions:** Intra-school meet.
* **Step-by-Step Procedure:**
1. Tap 'Use Template' > 'Classes (A to D)'.
* **Expected Result (UI & Feedback):** Generates 4 class sections.
* **Expected Result (Backend & Data):** HouseTemplates.sections applied.
* **Edge / Negative Scenarios:** Organizers can rename sections to 9-A, 10-A.

### TC-CREATOR-062: Bulk Allocation Modal - Load 100 Members
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Houses Card > Allocate Members`
* **Pre-conditions:** 100 members approved in host club; 4 houses saved.
* **Step-by-Step Procedure:**
1. Tap button 'Allocate Members'.
* **Expected Result (UI & Feedback):** Modal opens showing '100 Approved Club Members Available for Allocation'.
* **Expected Result (Backend & Data):** Stream reads all verified members of org_host_01.
* **Edge / Negative Scenarios:** Unverified members or banned accounts are excluded.

### TC-CREATOR-063: Bulk Allocation - Auto-Distribute Evenly Across 4 Houses
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `House Allocation Modal`
* **Pre-conditions:** 100 members available.
* **Step-by-Step Procedure:**
1. Select 'Auto-Distribute Evenly'.
2. Tap 'Preview Distribution'.
* **Expected Result (UI & Feedback):** Preview table displays exactly 25 members per house with 0 unassigned.
* **Expected Result (Backend & Data):** Algorithm splits 100 / 4 = 25 evenly.
* **Edge / Negative Scenarios:** Odd remainders (e.g. 101 members) distribute sequentially (+1 to House 1).

### TC-CREATOR-064: Bulk Allocation - Gender & Rating Balancing Check
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `House Allocation Modal`
* **Pre-conditions:** 100 members with varying skill ratings.
* **Step-by-Step Procedure:**
1. Toggle 'Balance Skill & Gender' to ON.
2. Tap 'Preview Distribution'.
* **Expected Result (UI & Feedback):** Each house shows balanced average rating (within +/- 15 Glicko points).
* **Expected Result (Backend & Data):** Snake draft algorithm distributes players based on skill tier.
* **Edge / Negative Scenarios:** Prevents stacking all top athletes in one house.

### TC-CREATOR-065: Bulk Allocation - Confirm & Apply Execution
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `House Allocation Modal > Footer`
* **Pre-conditions:** Preview reviewed.
* **Step-by-Step Procedure:**
1. Tap 'Confirm & Apply Allocation'.
* **Expected Result (UI & Feedback):** Loading indicator displays progress; returns to house overview with green success banner.
* **Expected Result (Backend & Data):** Firestore batch write updates 100 registration records with houseName.
* **Edge / Negative Scenarios:** Atomic commit ensures zero partial allocation on failure.

### TC-CREATOR-066: Manual Member Transfer Between Houses
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `House Member Roster`
* **Pre-conditions:** Player A in Kakatiya; Player B in Nizam.
* **Step-by-Step Procedure:**
1. Open Kakatiya roster.
2. Tap 'Transfer' on Player A.
3. Pick 'Nizam Strikers'.
* **Expected Result (UI & Feedback):** Player A moves to Nizam; Kakatiya count = 24, Nizam count = 26.
* **Expected Result (Backend & Data):** Registration.houseName updated to 'Nizam Strikers'.
* **Edge / Negative Scenarios:** Immediate UI update across all connected clients.

### TC-CREATOR-067: House Rename with Member Migration Map
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Houses Editor`
* **Pre-conditions:** Nizam Strikers has 26 members.
* **Step-by-Step Procedure:**
1. Tap Edit on Nizam Strikers.
2. Rename to 'Charminar Strikers'.
3. Tap 'Save'.
* **Expected Result (UI & Feedback):** Confirmation alert warns 26 members will migrate; tap 'Confirm'.
* **Expected Result (Backend & Data):** HouseRosterPlan replays rename across 26 registration docs.
* **Edge / Negative Scenarios:** Zero stranded members in unassigned pool.

### TC-CREATOR-068: House Deletion - Orphaned Members Revert to Pool
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Houses Editor`
* **Pre-conditions:** Chalukya Warriors has 25 members.
* **Step-by-Step Procedure:**
1. Tap delete icon on Chalukya Warriors.
2. Confirmation prompts: 'Return 25 members to unassigned pool?'.
3. Confirm.
* **Expected Result (UI & Feedback):** House deleted; unassigned pool badge increments by +25.
* **Expected Result (Backend & Data):** Registration records have houseName reset to null.
* **Edge / Negative Scenarios:** Members can be re-allocated into other houses.

### TC-CREATOR-069: House Standing & Medal Points Tally Display
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Houses Tab`
* **Pre-conditions:** Matches completed with house representations.
* **Step-by-Step Procedure:**
1. Open Houses tab.
* **Expected Result (UI & Feedback):** Leaderboard table displays Gold, Silver, Bronze medals and total points per house.
* **Expected Result (Backend & Data):** Points aggregated from all house match results.
* **Edge / Negative Scenarios:** Ties resolved by gold medal count.

### TC-CREATOR-070: Export House Roster to CSV
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Houses Desk > Header Actions`
* **Pre-conditions:** All 100 members allocated.
* **Step-by-Step Procedure:**
1. Tap 'Export CSV' button.
* **Expected Result (UI & Feedback):** Browser downloads 'PS_House_Games_2026_Rosters.csv'.
* **Expected Result (Backend & Data):** CSV contains Member UID, Name, House Name, Assigned Sports.
* **Edge / Negative Scenarios:** Sanitized against formula injection.

## Suite 1.6: Venue Planning, Ground Calendars, Court Turnarounds & Capacities (TC-CREATOR-071 to 085)

### TC-CREATOR-056: Houses Card Visibility on Internal Club Season
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Organizer Desk > Houses Card`
* **Pre-conditions:** Internal season created for PS Test Academy.
* **Step-by-Step Procedure:**
1. Open season overview.
2. Tap Organizer Desk.
* **Expected Result (UI & Feedback):** Houses & Batches card is visible showing '0 Houses Configured'.
* **Expected Result (Backend & Data):** Reads tournament.presetHouses array.
* **Edge / Negative Scenarios:** External-only tournament does not display houses card.

### TC-CREATOR-057: Author Custom House Name 'Kakatiya Dynamos'
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Houses & Batches Editor`
* **Pre-conditions:** Houses card open.
* **Step-by-Step Procedure:**
1. Tap '+ Add House'.
2. Enter name 'Kakatiya Dynamos'.
* **Expected Result (UI & Feedback):** New row created; name reflected with orange avatar.
* **Expected Result (Backend & Data):** HouseDraft.fresh created in memory.
* **Edge / Negative Scenarios:** Whitespace is trimmed automatically.

### TC-CREATOR-058: Author Custom House Color with Palette Picker
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `House Row > Color Picker`
* **Pre-conditions:** House row active.
* **Step-by-Step Procedure:**
1. Tap circular color chip.
2. Pick #FF5722 (Deep Orange).
3. Save.
* **Expected Result (UI & Feedback):** House badge and avatar display deep orange tint.
* **Expected Result (Backend & Data):** Hex color stored with house definition.
* **Edge / Negative Scenarios:** Ensures color contrast against white and dark themes.

### TC-CREATOR-059: Pre-built House Template - School 4 Colors
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Houses Editor > Templates`
* **Pre-conditions:** Empty house list.
* **Step-by-Step Procedure:**
1. Tap 'Use Template' dropdown.
2. Select 'Classic 4 Colors (Red, Blue, Green, Yellow)'.
* **Expected Result (UI & Feedback):** 4 house rows populated instantly with corresponding brand colors.
* **Expected Result (Backend & Data):** HouseTemplates.classic populates list.
* **Edge / Negative Scenarios:** Overwrites empty list without confirmation; warns if existing houses present.

### TC-CREATOR-060: Pre-built House Template - College Departments
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Houses Editor > Templates`
* **Pre-conditions:** Empty house list.
* **Step-by-Step Procedure:**
1. Tap 'Use Template'.
2. Select 'Engineering Depts (CSE, ECE, MECH, CIVIL)'.
* **Expected Result (UI & Feedback):** 4 department rows created with custom abbreviations.
* **Expected Result (Backend & Data):** HouseTemplates.departments applied.
* **Edge / Negative Scenarios:** Saves typing on mobile keyboards.

### TC-CREATOR-061: Pre-built House Template - School Classes (8-A to 8-D)
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Houses Editor > Templates`
* **Pre-conditions:** Intra-school meet.
* **Step-by-Step Procedure:**
1. Tap 'Use Template' > 'Classes (A to D)'.
* **Expected Result (UI & Feedback):** Generates 4 class sections.
* **Expected Result (Backend & Data):** HouseTemplates.sections applied.
* **Edge / Negative Scenarios:** Organizers can rename sections to 9-A, 10-A.

### TC-CREATOR-062: Bulk Allocation Modal - Load 100 Members
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Houses Card > Allocate Members`
* **Pre-conditions:** 100 members approved in host club; 4 houses saved.
* **Step-by-Step Procedure:**
1. Tap button 'Allocate Members'.
* **Expected Result (UI & Feedback):** Modal opens showing '100 Approved Club Members Available for Allocation'.
* **Expected Result (Backend & Data):** Stream reads all verified members of org_host_01.
* **Edge / Negative Scenarios:** Unverified members or banned accounts are excluded.

### TC-CREATOR-063: Bulk Allocation - Auto-Distribute Evenly Across 4 Houses
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `House Allocation Modal`
* **Pre-conditions:** 100 members available.
* **Step-by-Step Procedure:**
1. Select 'Auto-Distribute Evenly'.
2. Tap 'Preview Distribution'.
* **Expected Result (UI & Feedback):** Preview table displays exactly 25 members per house with 0 unassigned.
* **Expected Result (Backend & Data):** Algorithm splits 100 / 4 = 25 evenly.
* **Edge / Negative Scenarios:** Odd remainders (e.g. 101 members) distribute sequentially (+1 to House 1).

### TC-CREATOR-064: Bulk Allocation - Gender & Rating Balancing Check
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `House Allocation Modal`
* **Pre-conditions:** 100 members with varying skill ratings.
* **Step-by-Step Procedure:**
1. Toggle 'Balance Skill & Gender' to ON.
2. Tap 'Preview Distribution'.
* **Expected Result (UI & Feedback):** Each house shows balanced average rating (within +/- 15 Glicko points).
* **Expected Result (Backend & Data):** Snake draft algorithm distributes players based on skill tier.
* **Edge / Negative Scenarios:** Prevents stacking all top athletes in one house.

### TC-CREATOR-065: Bulk Allocation - Confirm & Apply Execution
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `House Allocation Modal > Footer`
* **Pre-conditions:** Preview reviewed.
* **Step-by-Step Procedure:**
1. Tap 'Confirm & Apply Allocation'.
* **Expected Result (UI & Feedback):** Loading indicator displays progress; returns to house overview with green success banner.
* **Expected Result (Backend & Data):** Firestore batch write updates 100 registration records with houseName.
* **Edge / Negative Scenarios:** Atomic commit ensures zero partial allocation on failure.

### TC-CREATOR-066: Manual Member Transfer Between Houses
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `House Member Roster`
* **Pre-conditions:** Player A in Kakatiya; Player B in Nizam.
* **Step-by-Step Procedure:**
1. Open Kakatiya roster.
2. Tap 'Transfer' on Player A.
3. Pick 'Nizam Strikers'.
* **Expected Result (UI & Feedback):** Player A moves to Nizam; Kakatiya count = 24, Nizam count = 26.
* **Expected Result (Backend & Data):** Registration.houseName updated to 'Nizam Strikers'.
* **Edge / Negative Scenarios:** Immediate UI update across all connected clients.

### TC-CREATOR-067: House Rename with Member Migration Map
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Houses Editor`
* **Pre-conditions:** Nizam Strikers has 26 members.
* **Step-by-Step Procedure:**
1. Tap Edit on Nizam Strikers.
2. Rename to 'Charminar Strikers'.
3. Tap 'Save'.
* **Expected Result (UI & Feedback):** Confirmation alert warns 26 members will migrate; tap 'Confirm'.
* **Expected Result (Backend & Data):** HouseRosterPlan replays rename across 26 registration docs.
* **Edge / Negative Scenarios:** Zero stranded members in unassigned pool.

### TC-CREATOR-068: House Deletion - Orphaned Members Revert to Pool
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Houses Editor`
* **Pre-conditions:** Chalukya Warriors has 25 members.
* **Step-by-Step Procedure:**
1. Tap delete icon on Chalukya Warriors.
2. Confirmation prompts: 'Return 25 members to unassigned pool?'.
3. Confirm.
* **Expected Result (UI & Feedback):** House deleted; unassigned pool badge increments by +25.
* **Expected Result (Backend & Data):** Registration records have houseName reset to null.
* **Edge / Negative Scenarios:** Members can be re-allocated into other houses.

### TC-CREATOR-069: House Standing & Medal Points Tally Display
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Houses Tab`
* **Pre-conditions:** Matches completed with house representations.
* **Step-by-Step Procedure:**
1. Open Houses tab.
* **Expected Result (UI & Feedback):** Leaderboard table displays Gold, Silver, Bronze medals and total points per house.
* **Expected Result (Backend & Data):** Points aggregated from all house match results.
* **Edge / Negative Scenarios:** Ties resolved by gold medal count.

### TC-CREATOR-070: Export House Roster to CSV
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Houses Desk > Header Actions`
* **Pre-conditions:** All 100 members allocated.
* **Step-by-Step Procedure:**
1. Tap 'Export CSV' button.
* **Expected Result (UI & Feedback):** Browser downloads 'PS_House_Games_2026_Rosters.csv'.
* **Expected Result (Backend & Data):** CSV contains Member UID, Name, House Name, Assigned Sports.
* **Edge / Negative Scenarios:** Sanitized against formula injection.

## Suite 1.7: Smart Draw Generation, Seeds, Groups & Anti-Overlap Scheduler (TC-CREATOR-086 to 102)

### TC-CREATOR-086: Draw Generation Button for Knockout Event (Badminton)
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Event Row`
* **Pre-conditions:** 16 confirmed entrants in Badminton Singles.
* **Step-by-Step Procedure:**
1. Tap 'Build Draw' on Badminton Singles row.
* **Expected Result (UI & Feedback):** Draw generation wizard opens showing 16 slots.
* **Expected Result (Backend & Data):** DrawConfig loaded with type knockout.
* **Edge / Negative Scenarios:** Generates Round of 16 bracket layout.

### TC-CREATOR-087: Seeding Placement - Top 4 Seeds Positioned at Bracket Extremes
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Draw Preview`
* **Pre-conditions:** Seeding mode set to rating.
* **Step-by-Step Procedure:**
1. Review generated bracket.
* **Expected Result (UI & Feedback):** Seed 1 at Top (Slot 1), Seed 2 at Bottom (Slot 16), Seeds 3 & 4 in opposite halves.
* **Expected Result (Backend & Data):** Standard tennis/badminton seeding distribution applied.
* **Edge / Negative Scenarios:** Prevents top seeds meeting before semifinals.

### TC-CREATOR-088: Draw Generation - Round Robin League Table (Cricket T20)
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Event Row`
* **Pre-conditions:** 6 cricket teams registered.
* **Step-by-Step Procedure:**
1. Tap 'Build Draw' on Cricket T20.
2. Confirm Round Robin.
* **Expected Result (UI & Feedback):** Generates 15 matches (n*(n-1)/2); league table renders with 6 rows (0 P, 0 W, 0 L, 0 Pts).
* **Expected Result (Backend & Data):** Fixture collection created with round-robin matrix.
* **Edge / Negative Scenarios:** Home/Away alternates evenly between teams.

### TC-CREATOR-089: Draw Generation - Groups then Knockout (Football 7s)
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Event Row`
* **Pre-conditions:** 8 teams entered; 2 groups of 4.
* **Step-by-Step Procedure:**
1. Tap 'Build Draw' > Confirm Groups then Knockout.
* **Expected Result (UI & Feedback):** Renders Group A (4 teams, 6 matches) and Group B (4 teams, 6 matches), followed by Semis.
* **Expected Result (Backend & Data):** Fixtures tagged with isGroupStage: true / false.
* **Edge / Negative Scenarios:** Group winners feed Semifinal 1 and Semifinal 2.

### TC-CREATOR-090: Scheduler Button 'Auto-Generate Master Timetable'
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Schedule Screen Top Bar`
* **Pre-conditions:** All draws generated; venues configured.
* **Step-by-Step Procedure:**
1. Tap 'Auto-Generate Master Timetable'.
* **Expected Result (UI & Feedback):** Progress overlay renders with animated progress bar.
* **Expected Result (Backend & Data):** TournamentScheduler.schedule execution starts.
* **Edge / Negative Scenarios:** Button disabled while solver runs.

### TC-CREATOR-091: Anti-Overlap - Single Player in Two Sports Collision Guard
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Schedule View`
* **Pre-conditions:** Player Arjun in Badminton (09:00 - 09:45) and Cricket.
* **Step-by-Step Procedure:**
1. Inspect scheduler placement for Arjun's Cricket match.
* **Expected Result (UI & Feedback):** Cricket match placed at 11:15 AM (after 45m match + 20m rest + 45m travel buffer).
* **Expected Result (Backend & Data):** ScheduleWindow.overlaps evaluated false.
* **Edge / Negative Scenarios:** Zero concurrent scheduling for same player.

### TC-CREATOR-092: Anti-Overlap - Same Court Double Booking Defense
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Schedule View`
* **Pre-conditions:** Court 1 has match 09:00 - 09:45 with 15m turnaround.
* **Step-by-Step Procedure:**
1. Inspect next match on Court 1.
* **Expected Result (UI & Feedback):** Next match starts strictly at 10:00 AM or later.
* **Expected Result (Backend & Data):** CourtCalendar ensures slot separation.
* **Edge / Negative Scenarios:** Prevents two matches being called to same court.

### TC-CREATOR-093: Manual Match Drag-and-Drop Placement Override
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Graphical Schedule Grid`
* **Pre-conditions:** Match placed on Court 1 at 14:00.
* **Step-by-Step Procedure:**
1. Long press match card.
2. Drag horizontally to Court 2 at 15:00.
3. Release.
* **Expected Result (UI & Feedback):** Match card snaps to Court 2 at 15:00; time updates immediately.
* **Expected Result (Backend & Data):** Fixture document updated with courtId: 'c2', startTime: 15:00.
* **Edge / Negative Scenarios:** If clash created, card glows red with conflict warning.

### TC-CREATOR-094: Clash Detector Alert Banner on Manual Conflict
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Schedule Screen`
* **Pre-conditions:** Admin drags match into another match's window.
* **Step-by-Step Procedure:**
1. Drag Match A onto occupied slot.
* **Expected Result (UI & Feedback):** Snack bar and top banner alert: '1 Conflict: Court 1 double-booked at 10:00'.
* **Expected Result (Backend & Data):** TournamentSchedule.isComplete returns false.
* **Edge / Negative Scenarios:** Banner highlights conflicting match cards in red outline.

### TC-CREATOR-095: Filter Schedule by Sport Tab (Cricket Only)
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Schedule Screen Tabs`
* **Pre-conditions:** Multi-sport timetable.
* **Step-by-Step Procedure:**
1. Tap 'Cricket' filter chip.
* **Expected Result (UI & Feedback):** Only Cricket matches shown on timetable; Badminton and Football hidden.
* **Expected Result (Backend & Data):** UI filtering query where('sportId', '==', 'cricket').
* **Edge / Negative Scenarios:** Export button adapts to export only Cricket matches.

### TC-CREATOR-096: Filter Schedule by Venue (Gachibowli Only)
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Schedule Screen Tabs`
* **Pre-conditions:** Two venues in season.
* **Step-by-Step Procedure:**
1. Tap Venue dropdown > pick 'Gachibowli Indoor'.
* **Expected Result (UI & Feedback):** Grid renders only Court 1 and Court 2 columns.
* **Expected Result (Backend & Data):** Filters by venueId == 'v_gachibowli'.
* **Edge / Negative Scenarios:** Allows ground manager to print venue-specific noticeboard.

### TC-CREATOR-097: Date Shifting Tool - Move Entire Day by +1 Day
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Schedule > Shift Timetable`
* **Pre-conditions:** Rain delay on 12 Oct.
* **Step-by-Step Procedure:**
1. Tap 'Shift Timetable'.
2. Select date: 12 Oct.
3. Shift: +1 Day.
4. Apply.
* **Expected Result (UI & Feedback):** All matches on 12 Oct move to 13 Oct with identical court and time slots.
* **Expected Result (Backend & Data):** SeasonDateShift batch updates fixture timestamps.
* **Edge / Negative Scenarios:** Push notification sent: 'Timetable shifted due to weather'.

### TC-CREATOR-098: Schedule Download Button - PDF Timetable Generation
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Schedule Screen Header`
* **Pre-conditions:** Published timetable.
* **Step-by-Step Procedure:**
1. Tap 'Download PDF' icon.
* **Expected Result (UI & Feedback):** System generates formatted, printable PDF with club logo, courts, and times.
* **Expected Result (Backend & Data):** ScheduleDownloadButton renders PDF.
* **Edge / Negative Scenarios:** Includes QR code deep-linking to live scores.

### TC-CREATOR-099: Schedule Download Button - CSV Export
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Schedule Screen Header`
* **Pre-conditions:** Published timetable.
* **Step-by-Step Procedure:**
1. Tap 'Export CSV'.
* **Expected Result (UI & Feedback):** Downloads 'Season_Timetable.csv' with match indices, courts, sides, officials.
* **Expected Result (Backend & Data):** CSV formatted for spreadsheet analysis.
* **Edge / Negative Scenarios:** Clean formatting with no missing cells.

### TC-CREATOR-100: Toggle Button 'Publish Schedule' Execution
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Schedule Top Bar`
* **Pre-conditions:** Draft schedule verified with 0 clashes.
* **Step-by-Step Procedure:**
1. Tap 'Publish Schedule'.
2. Confirm dialog.
* **Expected Result (UI & Feedback):** Badge turns green 'PUBLISHED'; banner updates to 'Schedule Live'.
* **Expected Result (Backend & Data):** tournament.isSchedulePublished set to true.
* **Edge / Negative Scenarios:** Visiting clubs and players immediately see fixtures.

### TC-CREATOR-101: Toggle Button 'Unpublish Schedule' Protection
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Schedule Top Bar`
* **Pre-conditions:** Published schedule needs major rework.
* **Step-by-Step Procedure:**
1. Tap 'Unpublish Schedule'.
2. Warning dialog explains fixtures will be hidden from public.
3. Confirm.
* **Expected Result (UI & Feedback):** Status returns to draft; fixtures hidden from spectators.
* **Expected Result (Backend & Data):** tournament.isSchedulePublished set to false.
* **Edge / Negative Scenarios:** Prevents public seeing unstable schedule edits.

### TC-CREATOR-102: Running Late Notice Card & Delay Broadcaster
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Tournament Overview`
* **Pre-conditions:** Match running 30 mins late.
* **Step-by-Step Procedure:**
1. On running match row, tap 'Running Late'.
2. Select '+30 mins'.
3. Tap 'Broadcast'.
* **Expected Result (UI & Feedback):** RunningLateCard appears on season home; following matches on court show '+30m delay'.
* **Expected Result (Backend & Data):** Fixture.estimatedDelayMinutes set to 30.
* **Edge / Negative Scenarios:** Alerts upcoming players to rest longer before heading to court.

## Suite 1.8: Officials Desk, Umpire Assignment & Neutrality Constraints (TC-CREATOR-103 to 112)

### TC-CREATOR-103: Officials Screen Access Gate
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Organizer Desk > Officials`
* **Pre-conditions:** Season open.
* **Step-by-Step Procedure:**
1. Tap 'Officials Desk' button.
* **Expected Result (UI & Feedback):** OfficialsScreen opens displaying Coverage report and Roster.
* **Expected Result (Backend & Data):** SeasonOrganizerGate permits access.
* **Edge / Negative Scenarios:** Non-admin accessing URL sees lock screen.

### TC-CREATOR-104: Add Official Sheet - Search Open Registry
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `OfficialsScreen > Add Official`
* **Pre-conditions:** Add Official sheet open.
* **Step-by-Step Procedure:**
1. In search box, type 'Kalyan'.
2. Select verified umpire 'Kalyan Varma'.
* **Expected Result (UI & Feedback):** Profile loaded with certified sports (Cricket, Badminton).
* **Expected Result (Backend & Data):** Reads public officials registry.
* **Edge / Negative Scenarios:** Displays verification badge.

### TC-CREATOR-105: Add Official Sheet - Manual Entry with Phone Number
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `OfficialsScreen > Add Official`
* **Pre-conditions:** Umpire not registered on PlaySphere.
* **Step-by-Step Procedure:**
1. Tap 'Add by Hand'.
2. Enter Name: 'Ramesh Babu', Phone: '+919876543210', Sport: 'Football'.
* **Expected Result (UI & Feedback):** Ramesh Babu added to season panel with 'External' chip.
* **Expected Result (Backend & Data):** TournamentOfficial doc created with handEntered: true.
* **Edge / Negative Scenarios:** Allows staffing external neutral referees.

### TC-CREATOR-106: Declare Official Club Affiliation Tag
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Official Details`
* **Pre-conditions:** Official belongs to PS Visitors Club.
* **Step-by-Step Procedure:**
1. In Affiliation dropdown, pick 'PS Visitors Club'.
2. Save.
* **Expected Result (UI & Feedback):** Affiliation badge displays 'Affiliated: PS Visitors Club'.
* **Expected Result (Backend & Data):** TournamentOfficial.clubId set to 'org_visiting_04'.
* **Edge / Negative Scenarios:** Crucial for neutrality engine checks.

### TC-CREATOR-107: Neutrality Constraint Check - Partisan Umpire Assignment Block
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Officials Desk > Match Row`
* **Pre-conditions:** Match 101: PS Test Academy vs PS Visitors Club.
* **Step-by-Step Procedure:**
1. Tap 'Assign Official' on Match 101.
2. Attempt to select Official Vikram (affiliated with PS Visitors Club).
* **Expected Result (UI & Feedback):** Selection rejected with alert: 'Neutrality Violation: Official affiliated with competing club'.
* **Expected Result (Backend & Data):** neutralityCheck returns false.
* **Edge / Negative Scenarios:** Assignment prevented; only neutral officials can be selected.

### TC-CREATOR-108: Neutrality Override with Explicit Organizer Justification
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Officials Desk`
* **Pre-conditions:** Emergency: only 1 umpire available.
* **Step-by-Step Procedure:**
1. Check 'Override Neutrality Constraint'.
2. Enter reason: 'Mutual agreement by both captains'.
3. Assign.
* **Expected Result (UI & Feedback):** Official assigned with amber warning chip: 'Partisan (Override)'.
* **Expected Result (Backend & Data):** Audit log records override reason and author UID.
* **Edge / Negative Scenarios:** Full transparency to both clubs.

### TC-CREATOR-109: Run Neutral Bulk Auto-Assignment Algorithm
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Officials Desk Top Bar`
* **Pre-conditions:** 10 unofficiated matches; 4 neutral umpires on panel.
* **Step-by-Step Procedure:**
1. Tap 'Run Neutral Assignment'.
* **Expected Result (UI & Feedback):** Solver runs; assigns neutral umpires across all 10 matches respecting availability and rest.
* **Expected Result (Backend & Data):** assignOfficialsAcrossTournament executes.
* **Edge / Negative Scenarios:** Reports '10 matches staffed; 0 neutrality conflicts'.

### TC-CREATOR-110: Unstaffed Match Alert Card in Organizer Desk
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Organizer Desk`
* **Pre-conditions:** 2 matches tomorrow have no umpire.
* **Step-by-Step Procedure:**
1. Open Organizer Desk.
* **Expected Result (UI & Feedback):** Prominent amber card alerts: '2 matches unstaffed tomorrow'.
* **Expected Result (Backend & Data):** officiatingDemand calculation identifies staffing gap.
* **Edge / Negative Scenarios:** Tapping card deep-links to unstaffed matches on Officials Desk.

### TC-CREATOR-111: Change Assigned Official on Matchday
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Match Row`
* **Pre-conditions:** Assigned umpire took sick leave.
* **Step-by-Step Procedure:**
1. Tap 'Change Official' on match row.
2. Select standby neutral umpire.
3. Save.
* **Expected Result (UI & Feedback):** Umpire replaced on scorecard.
* **Expected Result (Backend & Data):** Fixture.officials updated in Firestore.
* **Edge / Negative Scenarios:** New umpire receives push notification with match assignment.

### TC-CREATOR-112: Remove Official from Season Panel
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Officials Panel List`
* **Pre-conditions:** Official no longer participating.
* **Step-by-Step Procedure:**
1. Tap delete icon on official card.
2. System checks if official has active matches.
* **Expected Result (UI & Feedback):** If official has assigned matches, prompts: 'Unassign from 3 matches first?'; confirm removal.
* **Expected Result (Backend & Data):** Official removed from panel; assigned matches revert to unstaffed.
* **Edge / Negative Scenarios:** Maintains scheduling integrity.

## Suite 1.9: Organizer Desk, Role-Based Access & Staffing (TC-CREATOR-113 to 120)

### TC-CREATOR-113: Organizer Desk Button Visibility (Admin Exclusive)
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Tournament Details Top Bar`
* **Pre-conditions:** Logged in as Host Owner.
* **Step-by-Step Procedure:**
1. Open season overview.
* **Expected Result (UI & Feedback):** 'Organizer Desk' action button is prominently visible.
* **Expected Result (Backend & Data):** SeasonAccess.isOrganizer evaluates true.
* **Edge / Negative Scenarios:** Regular player (D2) sees no Organizer Desk button.

### TC-CREATOR-114: Deep Link Guard to Organizer Desk by Non-Admin
* **Perspective:** Regular Player (D2)
* **Screen / Location:** `URL Direct Navigation`
* **Pre-conditions:** D2 attempts opening /org/org_host_01/tournaments/seas_101/desk.
* **Step-by-Step Procedure:**
1. Navigate to desk URL.
* **Expected Result (UI & Feedback):** SeasonOrganizerGate intercepts; shows lock icon and 'For season organizers' message.
* **Expected Result (Backend & Data):** Firestore security rules block read of desk metadata.
* **Edge / Negative Scenarios:** Primary button offers 'Go to the season'.

### TC-CREATOR-115: Grant Coordinator Rights to Another Member
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Club Settings > Members`
* **Pre-conditions:** Member Suresh to manage tournament.
* **Step-by-Step Procedure:**
1. Open Suresh's member profile.
2. Add capability: 'Manage Competitions'.
3. Save.
* **Expected Result (UI & Feedback):** Suresh now sees 'Organizer Desk' on season.
* **Expected Result (Backend & Data):** Capability.manageCompetitions granted.
* **Edge / Negative Scenarios:** Allows delegating tournament management without transferring club ownership.

### TC-CREATOR-116: Revoke Coordinator Rights
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Club Settings > Members`
* **Pre-conditions:** Suresh tournament role finished.
* **Step-by-Step Procedure:**
1. Remove 'Manage Competitions' capability from Suresh.
* **Expected Result (UI & Feedback):** Organizer controls vanish from Suresh's app upon next refresh.
* **Expected Result (Backend & Data):** Permissions revoked in Firestore claims.
* **Edge / Negative Scenarios:** Immediate security enforcement.

### TC-CREATOR-117: Organizer Desk - Staffing Headcount Counters
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Organizer Desk`
* **Pre-conditions:** Season has 5 officials, 12 volunteers.
* **Step-by-Step Procedure:**
1. Inspect Staffing card on desk.
* **Expected Result (UI & Feedback):** Displays: '5 Officials Appointed · 12 Volunteers Active · 2 Staffing Gaps'.
* **Expected Result (Backend & Data):** Aggregates staffing records.
* **Edge / Negative Scenarios:** Provides at-a-glance operational readiness.

### TC-CREATOR-118: Organizer Desk - Financial Ledger Summary
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Organizer Desk > Finances`
* **Pre-conditions:** Flat fee season with 20 paid entries at ₹1,500.
* **Step-by-Step Procedure:**
1. Tap 'Finances' card.
* **Expected Result (UI & Feedback):** Displays: 'Gross Collections: ₹30,000 · Gateway Fees: ₹600 · Net Payout: ₹29,400'.
* **Expected Result (Backend & Data):** Aggregates payment transactions.
* **Edge / Negative Scenarios:** Visible only to club owner and financial admins; hidden from umpires.

### TC-CREATOR-119: Spectator View Toggle (Preview Public Page)
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Organizer Desk > Actions`
* **Pre-conditions:** Admin wants to verify public experience.
* **Step-by-Step Procedure:**
1. Tap 'View as Spectator' toggle.
* **Expected Result (UI & Feedback):** Administrative cards and edit handles hide; page displays exactly as a visiting parent sees it.
* **Expected Result (Backend & Data):** SeasonAccess temporarily mocks Spectator role in memory.
* **Edge / Negative Scenarios:** Tap 'Return to Admin View' restores organizer controls.

### TC-CREATOR-120: Export Complete Tournament Dossier (PDF)
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Organizer Desk > Export`
* **Pre-conditions:** Season concluded.
* **Step-by-Step Procedure:**
1. Tap 'Export Complete Season Report'.
* **Expected Result (UI & Feedback):** Generates multi-page PDF with draws, match scorecards, medal tallies, and financial receipts.
* **Expected Result (Backend & Data):** Dossier generator aggregates all subcollections.
* **Edge / Negative Scenarios:** Archival copy for club records.

## Suite 1.10: Entry Approvals, Rejections, Waitlists & Emergency Roster Overrides (TC-CREATOR-121 to 125)

### TC-CREATOR-121: Pending Entries Card - Accept Team Submission
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Tournament Overview > Pending Card`
* **Pre-conditions:** PS Visitors Lions submitted for Cricket.
* **Step-by-Step Procedure:**
1. Tap 'Accept' button on team row.
* **Expected Result (UI & Feedback):** Row fades out with green checkmark; counter decrements.
* **Expected Result (Backend & Data):** Registration.status set to 'approved'.
* **Edge / Negative Scenarios:** Visiting club receives approval notification.

### TC-CREATOR-122: Pending Entries Card - Decline Team Submission with Reason
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Pending Card`
* **Pre-conditions:** Incomplete squad submitted.
* **Step-by-Step Procedure:**
1. Tap 'Decline' on team row.
2. Pick reason: 'Squad incomplete (requires 11 players)'.
3. Confirm.
* **Expected Result (UI & Feedback):** Row removed from pending card.
* **Expected Result (Backend & Data):** Registration.status set to 'rejected' with reason.
* **Edge / Negative Scenarios:** Slot freed up in category capacity.

### TC-CREATOR-123: Waitlist Promotion - Automatic Move on Cancellation
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Category Entrants`
* **Pre-conditions:** Category full (16/16); 1 player cancels; 1 on waitlist.
* **Step-by-Step Procedure:**
1. Approve cancellation of Player X.
* **Expected Result (UI & Feedback):** Waitlisted Player Y automatically promoted to confirmed entrant; status turns 'approved'.
* **Expected Result (Backend & Data):** EntrantPromoter handles waitlist promotion.
* **Edge / Negative Scenarios:** Player Y receives push: 'You have been promoted from waitlist to confirmed entrant'.

### TC-CREATOR-124: Matchday Emergency Lineup Substitution (Injury Before Toss)
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Match Center > Lineup`
* **Pre-conditions:** Player twisted ankle in warmups.
* **Step-by-Step Procedure:**
1. Tap player on lineup > 'Substitute'.
2. Pick eligible reserve.
3. Enter reason.
4. Save.
* **Expected Result (UI & Feedback):** Scorecard lineup updates; reserve active; replaced player benched.
* **Expected Result (Backend & Data):** Match document records audit log entry with timestamp and official UID.
* **Edge / Negative Scenarios:** Immutable record prevents disputed scores.

### TC-CREATOR-125: Dispute Resolution & Score Correction Sign-Off
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Match Result Review`
* **Pre-conditions:** Scoring dispute logged by team captain within 1-hour protest window.
* **Step-by-Step Procedure:**
1. Open Protest Review sheet.
2. Review ball-by-ball video/pad logs.
3. Adjust final score.
4. Sign off.
* **Expected Result (UI & Feedback):** Match status moves from 'provisional' to 'official'; dispute marked resolved.
* **Expected Result (Backend & Data):** Leaderboard and Glicko ratings recalculate with corrected score.
* **Edge / Negative Scenarios:** Protest window closes permanently.

# PART 2: PARTICIPATING CLUBS & PLAYERS SIDE (90 TEST CASES)

## Suite 2.1: Club-to-Club Invitation Delivery, Notifications & Permissions (TC-PLAYER-001 to 010)

### TC-PLAYER-001: In-App Push Notification for Tournament Invitation
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `OS Notification Bar`
* **Pre-conditions:** Host club sent invitation to PS Visitors Club.
* **Step-by-Step Procedure:**
1. Observe D4 device lockscreen / notifications.
* **Expected Result (UI & Feedback):** Push notification received: 'PS Test Academy invited your club to Telangana State Champions Trophy 2026'.
* **Expected Result (Backend & Data):** FCM push dispatched via Cloud Function to visiting club owner UID.
* **Edge / Negative Scenarios:** Tapping notification launches app directly to invitation card.

### TC-PLAYER-002: Club Owner Exclusive Invitation Card Visibility
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `Invitations Tab`
* **Pre-conditions:** Logged in as Owner of PS Visitors Club.
* **Step-by-Step Procedure:**
1. Navigate to More > Invitations.
* **Expected Result (UI & Feedback):** Official invitation card displayed with host badge, sports list, dates, and action buttons.
* **Expected Result (Backend & Data):** Security rules permit read of org_visiting_04/invites for club owners.
* **Edge / Negative Scenarios:** Regular member (D2/D3) navigating to same route sees empty state.

### TC-PLAYER-003: Invitation Letter Inspection - Sports & Venues Check
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `Invitation Card`
* **Pre-conditions:** Invitation card open.
* **Step-by-Step Procedure:**
1. Tap 'Read Full Invitation Letter'.
* **Expected Result (UI & Feedback):** Letter expands showing host club name, sports offered (Cricket, Badminton), dates, and venue address.
* **Expected Result (Backend & Data):** Letter generated via InvitationLetter.compose.
* **Edge / Negative Scenarios:** Verified that no placeholder or null fields are displayed.

### TC-PLAYER-004: Button 'Decline Invitation' Flow with Feedback Prompt
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `Invitation Card`
* **Pre-conditions:** Active invitation.
* **Step-by-Step Procedure:**
1. Tap 'Decline' button.
2. In reason prompt, select 'Scheduling conflict with state league'.
3. Confirm.
* **Expected Result (UI & Feedback):** Card updates to gray status 'Declined'; action buttons vanish.
* **Expected Result (Backend & Data):** Invite status updated to 'declined'; host club informed.
* **Edge / Negative Scenarios:** Option to reverse decline available for 24 hours.

### TC-PLAYER-005: Button 'Accept & Build Entry' - Navigation to Roster Builder
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `Invitation Card`
* **Pre-conditions:** Active invitation.
* **Step-by-Step Procedure:**
1. Tap green button 'Accept & Build Entry'.
* **Expected Result (UI & Feedback):** Button shows spinner; navigates to BuildEntryScreen with sport category cards.
* **Expected Result (Backend & Data):** Invite status updated to 'accepted'.
* **Edge / Negative Scenarios:** Creates draft entry container under visiting club workspace.

### TC-PLAYER-006: Visiting Club Admin (Non-Owner) Access to Invitation
* **Perspective:** Visiting Admin (D4b)
* **Screen / Location:** `Invitations Tab`
* **Pre-conditions:** User holds Capability.manageCompetitions in visiting club.
* **Step-by-Step Procedure:**
1. Open Invitations tab.
* **Expected Result (UI & Feedback):** Invitation card visible with 'Accept & Build Entry' enabled.
* **Expected Result (Backend & Data):** Capability check allows club admins to act on invites.
* **Edge / Negative Scenarios:** Provides redundancy if club owner is travelling.

### TC-PLAYER-007: Regular Player Access Denial to Club Invitations
* **Perspective:** Regular Player (D3)
* **Screen / Location:** `Invitations Screen`
* **Pre-conditions:** Regular member of PS Visitors Club.
* **Step-by-Step Procedure:**
1. Navigate to More > Invitations.
* **Expected Result (UI & Feedback):** Empty state displays: 'No personal invitations pending'.
* **Expected Result (Backend & Data):** Club-level invitations collection query blocked for non-admins.
* **Edge / Negative Scenarios:** Players cannot accept or decline invites on behalf of club.

### TC-PLAYER-008: Deep Link Invitation Acceptance via Web URL
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `Mobile Browser / Web`
* **Pre-conditions:** Invitation link shared via WhatsApp.
* **Step-by-Step Procedure:**
1. Tap invitation URL in WhatsApp on phone.
* **Expected Result (UI & Feedback):** App opens via Android App Links / iOS Universal Links directly to invitation review sheet.
* **Expected Result (Backend & Data):** GoRouter parses deepLinkRoute and parameters orgId and tournamentId.
* **Edge / Negative Scenarios:** Prompts Google Sign-In if unauthenticated.

### TC-PLAYER-009: Expired Invitation State Handling
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `Invitations Screen`
* **Pre-conditions:** Registration deadline passed.
* **Step-by-Step Procedure:**
1. Open invitation card.
* **Expected Result (UI & Feedback):** Card displays amber badge: 'Registration Closed on 05 Oct 2026'; 'Accept' button disabled.
* **Expected Result (Backend & Data):** tournament.acceptsEntries evaluates false.
* **Edge / Negative Scenarios:** Prevents submitting entries to closed tournaments.

### TC-PLAYER-010: Host Club Revoked Invitation Handling
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `Invitations Screen`
* **Pre-conditions:** Host club cancelled invitation.
* **Step-by-Step Procedure:**
1. Open Invitations screen.
* **Expected Result (UI & Feedback):** Card reflects status: 'Invitation Withdrawn by Host'.
* **Expected Result (Backend & Data):** Invite record status set to 'revoked'.
* **Edge / Negative Scenarios:** Entry creation disabled.

## Suite 2.2: Squad RSVP Availability Polling, Member Taps & Headcounts (TC-PLAYER-011 to 022)

### TC-PLAYER-011: Button 'Ask who's free (RSVP)' on Event Card
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `BuildEntryScreen > Cricket Card`
* **Pre-conditions:** Season invite accepted.
* **Step-by-Step Procedure:**
1. On Cricket card, tap 'Ask who's free (RSVP)'.
* **Expected Result (UI & Feedback):** CreateSquadRsvpSheet opens pre-populated with match dates and sport.
* **Expected Result (Backend & Data):** FixtureCallTarget instantiated with tournament ID and sport ID.
* **Edge / Negative Scenarios:** Button disabled if RSVP call already active for this draw.

### TC-PLAYER-012: RSVP Target Audience Selector - All Club Members
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `CreateSquadRsvpSheet`
* **Pre-conditions:** Sheet open.
* **Step-by-Step Procedure:**
1. In Audience dropdown, pick 'All Club Members (100 players)'.
* **Expected Result (UI & Feedback):** Headcount badge displays '100 recipients'.
* **Expected Result (Backend & Data):** targetFilter set to 'all_members'.
* **Edge / Negative Scenarios:** Poll will appear on main club board.

### TC-PLAYER-013: RSVP Target Audience Selector - Cricket Squad Only
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `CreateSquadRsvpSheet`
* **Pre-conditions:** Sheet open.
* **Step-by-Step Procedure:**
1. In Audience dropdown, pick 'Cricket Squad (25 players)'.
* **Expected Result (UI & Feedback):** Badge displays '25 recipients'.
* **Expected Result (Backend & Data):** targetFilter set to 'squad_cricket'.
* **Edge / Negative Scenarios:** Filters out members not playing cricket.

### TC-PLAYER-014: RSVP Deadline Picker Configuration
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `CreateSquadRsvpSheet`
* **Pre-conditions:** Sheet open.
* **Step-by-Step Procedure:**
1. Tap 'RSVP Deadline' field.
2. Pick 05 Oct 2026, 18:00.
* **Expected Result (UI & Feedback):** Displays 'Responses close in 4 days (05 Oct, 18:00)'.
* **Expected Result (Backend & Data):** deadline timestamp stored on announcement doc.
* **Edge / Negative Scenarios:** Responses locked after deadline.

### TC-PLAYER-015: Button 'Post RSVP to Club Board' Execution
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `CreateSquadRsvpSheet > Bottom Bar`
* **Pre-conditions:** Parameters configured.
* **Step-by-Step Procedure:**
1. Tap 'Post RSVP to Club Board'.
* **Expected Result (UI & Feedback):** Sheet closes; toast confirms 'Availability poll published to club feed'.
* **Expected Result (Backend & Data):** Announcement doc created in orgs/org_visiting_04/announcements/{id}.
* **Edge / Negative Scenarios:** Push notification sent to targeted members.

### TC-PLAYER-016: Member Sees RSVP Card on Club Feed
* **Perspective:** Player (D3)
* **Screen / Location:** `PS Visitors Club Feed`
* **Pre-conditions:** Poll published.
* **Step-by-Step Procedure:**
1. Open Club Feed on D3.
* **Expected Result (UI & Feedback):** Top card displays '[RSVP: Cricket - Telangana Champions] Are you available to play on 10 Oct?'.
* **Expected Result (Backend & Data):** MatchRsvpCard rendered in feed stream.
* **Edge / Negative Scenarios:** Displays action buttons: 'In', 'Out', 'Tentative'.

### TC-PLAYER-017: Member Taps 'In' Button on RSVP Card
* **Perspective:** Player (D3)
* **Screen / Location:** `MatchRsvpCard`
* **Pre-conditions:** Poll open.
* **Step-by-Step Procedure:**
1. Tap '[ 👍 In ]' button.
* **Expected Result (UI & Feedback):** Button highlights solid green; light haptic feedback; counter increments to 'Available: 1'.
* **Expected Result (Backend & Data):** Subcollection response written: announcements/{id}/responses/{uid} with status: 'in'.
* **Edge / Negative Scenarios:** Captain's live headcount increments in real time.

### TC-PLAYER-018: Member Taps 'Out' Button on RSVP Card
* **Perspective:** Player (D2)
* **Screen / Location:** `MatchRsvpCard`
* **Pre-conditions:** Poll open.
* **Step-by-Step Procedure:**
1. Tap '[ 👎 Out ]' button.
* **Expected Result (UI & Feedback):** Button highlights red; counter increments to 'Unavailable: 1'.
* **Expected Result (Backend & Data):** response doc written with status: 'out'.
* **Edge / Negative Scenarios:** Captain sees player marked unavailable.

### TC-PLAYER-019: Member Taps 'Tentative' Button on RSVP Card
* **Perspective:** Player (D3)
* **Screen / Location:** `MatchRsvpCard`
* **Pre-conditions:** Poll open.
* **Step-by-Step Procedure:**
1. Tap '[ ❓ Tentative ]' button.
* **Expected Result (UI & Feedback):** Button highlights amber; counter updates 'Tentative: 1'.
* **Expected Result (Backend & Data):** status: 'tentative' stored.
* **Edge / Negative Scenarios:** Player remains in standby pool for captain.

### TC-PLAYER-020: Changing RSVP Response from 'In' to 'Out'
* **Perspective:** Player (D3)
* **Screen / Location:** `MatchRsvpCard`
* **Pre-conditions:** D3 previously tapped 'In'.
* **Step-by-Step Procedure:**
1. Tap '[ 👎 Out ]' button.
* **Expected Result (UI & Feedback):** Green button reverts to outlined; red button fills solid; Available count decrements.
* **Expected Result (Backend & Data):** Firestore response doc updated to status: 'out'.
* **Edge / Negative Scenarios:** Removes player from captain's auto-add RSVP list.

### TC-PLAYER-021: RSVP Responses Closed After Deadline
* **Perspective:** Player (D3)
* **Screen / Location:** `MatchRsvpCard`
* **Pre-conditions:** Deadline expired.
* **Step-by-Step Procedure:**
1. View RSVP card.
* **Expected Result (UI & Feedback):** Buttons replaced by message: 'Responses closed on 05 Oct 18:00'.
* **Expected Result (Backend & Data):** Client disables response buttons; server rules reject writes.
* **Edge / Negative Scenarios:** Preserves finalized availability state.

### TC-PLAYER-022: Captain Views RSVP Response Roster Sheet
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `Club Board > RSVP Details`
* **Pre-conditions:** 12 members responded 'In', 4 'Out', 2 'Tentative'.
* **Step-by-Step Procedure:**
1. Tap 'View Responses' on RSVP card.
* **Expected Result (UI & Feedback):** Sheet opens listing 12 members in 'Available' section with player photos, ratings, and phone numbers.
* **Expected Result (Backend & Data):** Reads responses subcollection joined with member profiles.
* **Edge / Negative Scenarios:** Quick-call button next to each player.

## Suite 2.3: Hybrid Roster Building (Direct Picks + RSVP Remainder) (TC-PLAYER-023 to 035)

### TC-PLAYER-023: Open Squad Builder Sheet for Cricket 11s
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `BuildEntryScreen > Cricket`
* **Pre-conditions:** Accepted season invite.
* **Step-by-Step Procedure:**
1. Tap 'Build Squad' on Cricket T20 card.
* **Expected Result (UI & Feedback):** Squad builder sheet opens displaying member roster with checkboxes; counter '0 / 11 selected'.
* **Expected Result (Backend & Data):** Initializes DraftSquad instance.
* **Edge / Negative Scenarios:** Submit button disabled until 11 players selected.

### TC-PLAYER-024: Directly Check 5 Confirmed Players
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `Squad Builder`
* **Pre-conditions:** Roster of 100 members.
* **Step-by-Step Procedure:**
1. Tap checkboxes for Player 1, Player 2, Player 3, Player 4, Player 5.
* **Expected Result (UI & Feedback):** 5 checkboxes check green; counter updates: '5 / 11 selected (6 needed)'.
* **Expected Result (Backend & Data):** Selected player UIDs appended to active squad list.
* **Edge / Negative Scenarios:** Remaining count calculated dynamically: 11 - 5 = 6.

### TC-PLAYER-025: Dynamic Button 'Add the 6 who said In from RSVP' Appearance
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `Squad Builder Footer`
* **Pre-conditions:** 5 players selected directly; 8 members responded 'In' to RSVP.
* **Step-by-Step Procedure:**
1. Inspect footer action bar.
* **Expected Result (UI & Feedback):** Button labeled 'Add the 6 who said In from RSVP' appears prominently.
* **Expected Result (Backend & Data):** SquadRsvpActions detects matching poll and calculates 6 required slots.
* **Edge / Negative Scenarios:** Button only appears when active RSVP responses exist.

### TC-PLAYER-026: Button 'Add the 6 who said In' Tap Execution
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `Squad Builder`
* **Pre-conditions:** Footer button visible.
* **Step-by-Step Procedure:**
1. Tap 'Add the 6 who said In from RSVP'.
* **Expected Result (UI & Feedback):** Selection modal opens showing the 8 members who tapped 'In', top 6 pre-checked.
* **Expected Result (Backend & Data):** Filters responses where status == 'in' and not in existing 5 picks.
* **Edge / Negative Scenarios:** Captain can toggle individual picks before confirming.

### TC-PLAYER-027: Confirm RSVP Pull - Squad Completion to 11 Players
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `RSVP Picker Modal`
* **Pre-conditions:** 6 players checked.
* **Step-by-Step Procedure:**
1. Tap 'Confirm Selection'.
* **Expected Result (UI & Feedback):** Modal closes; squad roster populates all 11 players; counter displays green '11 / 11 selected (Complete)'.
* **Expected Result (Backend & Data):** 11 player UIDs staged in DraftSquad.members.
* **Edge / Negative Scenarios:** Primary button 'Submit Squad for Registration' enables immediately.

### TC-PLAYER-028: Add Reserve Players Stepper (3 Reserves)
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `Squad Builder > Reserves`
* **Pre-conditions:** 11 starters selected.
* **Step-by-Step Procedure:**
1. Tap '+ Add Reserve' 3 times.
2. Pick 3 reserve members.
* **Expected Result (UI & Feedback):** Reserves section shows 3 players with 'Reserve' chip; total squad size = 14.
* **Expected Result (Backend & Data):** DraftSquad.reserves contains 3 UIDs.
* **Edge / Negative Scenarios:** Reserves eligible for emergency matchday substitutions.

### TC-PLAYER-029: Assign Team Captain Chip (C)
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `Squad Member Row`
* **Pre-conditions:** 11 players selected.
* **Step-by-Step Procedure:**
1. Tap player row > tap 'Make Captain'.
* **Expected Result (UI & Feedback):** Gold (C) badge appears next to player name.
* **Expected Result (Backend & Data):** squadEntry.isCaptain set to true.
* **Edge / Negative Scenarios:** Captain authorized to attend coin toss and sign scorecards.

### TC-PLAYER-030: Assign Team Wicket-Keeper Chip (WK)
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `Squad Member Row`
* **Pre-conditions:** Cricket squad.
* **Step-by-Step Procedure:**
1. Tap player row > tap 'Make Wicket Keeper'.
* **Expected Result (UI & Feedback):** Blue (WK) badge displayed.
* **Expected Result (Backend & Data):** squadEntry.role set to 'wicket_keeper'.
* **Edge / Negative Scenarios:** Enforces wicket-keeper equipment and fielding positions.

### TC-PLAYER-031: Remove Selected Player from Squad List
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `Squad Member Row`
* **Pre-conditions:** Player mistakenly selected.
* **Step-by-Step Procedure:**
1. Tap 'X' icon on Player 3 row.
* **Expected Result (UI & Feedback):** Player removed; counter decrements to '10 / 11 selected'; submit button disables.
* **Expected Result (Backend & Data):** UID removed from DraftSquad.members.
* **Edge / Negative Scenarios:** RSVP button dynamically updates to 'Add 1 from RSVP'.

### TC-PLAYER-032: Clear All Selections Button
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `Squad Builder Header`
* **Pre-conditions:** Partial squad staged.
* **Step-by-Step Procedure:**
1. Tap 'Clear All'.
2. Confirm alert dialog.
* **Expected Result (UI & Feedback):** All checkboxes uncheck; counter resets to '0 / 11 selected'.
* **Expected Result (Backend & Data):** DraftSquad.members emptied.
* **Edge / Negative Scenarios:** Fresh state.

### TC-PLAYER-033: Squad Validation Check - Under-manned Squad Rejection
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `Squad Builder`
* **Pre-conditions:** Only 9 players selected (11 required).
* **Step-by-Step Procedure:**
1. Attempt tapping 'Submit Squad' (if forced via dev console).
* **Expected Result (UI & Feedback):** Snack bar error: 'Cricket squad requires minimum 11 players (currently 9)'.
* **Expected Result (Backend & Data):** Client validation guards write.
* **Edge / Negative Scenarios:** Prevents submitting forfeit-prone squads.

### TC-PLAYER-034: Squad Validation Check - Max Squad Size Cap (15 Players)
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `Squad Builder`
* **Pre-conditions:** 11 starters + 4 reserves = 15 players selected.
* **Step-by-Step Procedure:**
1. Attempt adding 16th player.
* **Expected Result (UI & Feedback):** '+ Add Reserve' button disables; toast: 'Maximum squad size of 15 reached'.
* **Expected Result (Backend & Data):** Prevents oversized squads.
* **Edge / Negative Scenarios:** Maintains fair tournament limits.

### TC-PLAYER-035: Button 'Submit Squad for Registration' - Persistence
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `Squad Builder Bottom Bar`
* **Pre-conditions:** 11 starters + 3 reserves configured.
* **Step-by-Step Procedure:**
1. Tap 'Submit Squad for Registration'.
* **Expected Result (UI & Feedback):** Spinner displays; returns to BuildEntryScreen with green checkmark on Cricket card.
* **Expected Result (Backend & Data):** Team registration document created with status: 'submitted'.
* **Edge / Negative Scenarios:** Pending entry appears on host club Organizer Desk.

## Suite 2.4: Multi-Team Club Registration (Lions, Tigers, Eagles) (TC-PLAYER-036 to 048)

### TC-PLAYER-036: First Squad Naming - 'PS Visitors Lions'
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `Squad 1 Header`
* **Pre-conditions:** Cricket squad 1 assembled.
* **Step-by-Step Procedure:**
1. In Team Name field, type 'PS Visitors Lions'.
2. Save.
* **Expected Result (UI & Feedback):** Header displays 'PS Visitors Lions (11 players)'.
* **Expected Result (Backend & Data):** Registration.teamName set to 'PS Visitors Lions'.
* **Edge / Negative Scenarios:** First seed staged.

### TC-PLAYER-037: Button '+ Register Another Team for Cricket'
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `Cricket Section Footer`
* **Pre-conditions:** Squad 1 submitted.
* **Step-by-Step Procedure:**
1. Tap '+ Register Another Team for Cricket'.
* **Expected Result (UI & Feedback):** Second squad card animates into view: 'Cricket — Squad #2'.
* **Expected Result (Backend & Data):** Initializes second DraftSquad in memory.
* **Edge / Negative Scenarios:** Allows entering multiple club teams.

### TC-PLAYER-038: Second Squad Naming - 'PS Visitors Tigers'
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `Squad 2 Header`
* **Pre-conditions:** Squad 2 card open.
* **Step-by-Step Procedure:**
1. In Team Name, type 'PS Visitors Tigers'.
* **Expected Result (UI & Feedback):** Header reflects 'PS Visitors Tigers'.
* **Expected Result (Backend & Data):** teamName set to 'PS Visitors Tigers'.
* **Edge / Negative Scenarios:** Distinct team identity.

### TC-PLAYER-039: Second Squad Roster Selection (11 Different Members)
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `Squad 2 Builder`
* **Pre-conditions:** Roster list.
* **Step-by-Step Procedure:**
1. Select 11 club members not in Lions.
* **Expected Result (UI & Feedback):** 11 checkboxes tick green; counter shows '11 / 11 selected'.
* **Expected Result (Backend & Data):** DraftSquad 2 holds 11 distinct UIDs.
* **Edge / Negative Scenarios:** Lions players grayed out.

### TC-PLAYER-040: Third Squad Naming & Selection - 'PS Visitors Eagles'
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `Cricket Section`
* **Pre-conditions:** Squads 1 & 2 saved.
* **Step-by-Step Procedure:**
1. Tap '+ Register Another Team'.
2. Name 'PS Visitors Eagles'.
3. Select 11 more members.
* **Expected Result (UI & Feedback):** Squad 3 complete with 11 players; summary reflects 3 squads (33 players total).
* **Expected Result (Backend & Data):** 3 distinct team records prepared.
* **Edge / Negative Scenarios:** Demonstrates large-club multi-team participation.

### TC-PLAYER-041: Duplicate Team Name within Same Club Rejection
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `Squad Name Field`
* **Pre-conditions:** Lions already exists.
* **Step-by-Step Procedure:**
1. Name Squad 2 'PS Visitors Lions'.
2. Tap Save.
* **Expected Result (UI & Feedback):** Validation error: 'Team name already used in this season entry'.
* **Expected Result (Backend & Data):** Rejects duplicate team names from same club.
* **Edge / Negative Scenarios:** Forces unique naming for bracket clarity.

### TC-PLAYER-042: Independent Captain Assignment per Squad
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `Squad Builders`
* **Pre-conditions:** 3 squads assembled.
* **Step-by-Step Procedure:**
1. Assign Captain A for Lions.
2. Assign Captain B for Tigers.
3. Assign Captain C for Eagles.
* **Expected Result (UI & Feedback):** Each squad card displays its respective captain badge.
* **Expected Result (Backend & Data):** Each team registration has distinct captainUid.
* **Edge / Negative Scenarios:** Allows independent matchday leadership.

### TC-PLAYER-043: Multi-Team Entry Fee Calculation (Pay per Event Mode)
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `Checkout Sheet`
* **Pre-conditions:** Fee is ₹2,500 per cricket team.
* **Step-by-Step Procedure:**
1. Review checkout breakdown.
* **Expected Result (UI & Feedback):** Itemized total displays: '3 Cricket Teams x ₹2,500 = ₹7,500'.
* **Expected Result (Backend & Data):** Fee calculated dynamically: entryFee * squadCount.
* **Edge / Negative Scenarios:** Correct billing for multiple squads.

### TC-PLAYER-044: Multi-Team Entry Fee (Whole Season Pass Mode)
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `Checkout Sheet`
* **Pre-conditions:** Whole season fee is ₹1,500 flat.
* **Step-by-Step Procedure:**
1. Review checkout.
* **Expected Result (UI & Feedback):** Total displays: 'Club Flat Season Pass: ₹1,500 (3 Teams Included)'.
* **Expected Result (Backend & Data):** feeMode == 'season' waives additional team fees.
* **Edge / Negative Scenarios:** Cost-effective for multi-team clubs.

### TC-PLAYER-045: Submit All 3 Teams Batch Execution
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `BuildEntryScreen Bottom Bar`
* **Pre-conditions:** 3 squads ready.
* **Step-by-Step Procedure:**
1. Tap 'Submit 3 Teams for Registration'.
* **Expected Result (UI & Feedback):** Loading spinner; toast confirms '3 team entries submitted successfully'.
* **Expected Result (Backend & Data):** Firestore commits 3 registration documents under competitions/{compId}/registrations/.
* **Edge / Negative Scenarios:** Host Organizer Desk receives 3 entries.

### TC-PLAYER-046: Host Organizer Desk Displays 3 Distinct Pending Entries
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Pending Entries Card`
* **Pre-conditions:** 3 teams submitted.
* **Step-by-Step Procedure:**
1. Open Organizer Desk on D1.
* **Expected Result (UI & Feedback):** Pending card shows 3 rows: 'PS Visitors Lions', 'PS Visitors Tigers', 'PS Visitors Eagles'.
* **Expected Result (Backend & Data):** Each row shows independent squad size (11 players).
* **Edge / Negative Scenarios:** Host admin can accept or reject each team independently.

### TC-PLAYER-047: Host Approves 2 Teams and Rejects 1 Team
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Pending Entries Card`
* **Pre-conditions:** 3 teams waiting.
* **Step-by-Step Procedure:**
1. Tap 'Accept' on Lions and Tigers.
2. Tap 'Decline' on Eagles (due to field capacity).
* **Expected Result (UI & Feedback):** Lions and Tigers approved; Eagles rejected with notification.
* **Expected Result (Backend & Data):** Lions & Tigers status: 'approved'; Eagles status: 'rejected'.
* **Edge / Negative Scenarios:** Draw generator seeds Lions and Tigers only.

### TC-PLAYER-048: Seeding Separation - Same Club Teams in Opposite Pools
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Draw Preview`
* **Pre-conditions:** Lions and Tigers approved in Group Stage tournament.
* **Step-by-Step Procedure:**
1. Build draw.
* **Expected Result (UI & Feedback):** Scheduler places Lions in Group A and Tigers in Group B.
* **Expected Result (Backend & Data):** drawConfig applies same-club pool separation constraint.
* **Edge / Negative Scenarios:** Prevents club sister teams playing in early group stages.

## Suite 2.5: Anti-Cheat: Duplicate Player In Same Sport & Multi-Sport (TC-PLAYER-049 to 058)

### TC-PLAYER-049: Duplicate Player Selection Attempt in Second Squad
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `Squad 2 Builder`
* **Pre-conditions:** Player Ravi is in Lions (Cricket).
* **Step-by-Step Procedure:**
1. Open Tigers squad sheet.
2. Find Player Ravi.
3. Attempt checking checkbox.
* **Expected Result (UI & Feedback):** Checkbox refuses to tick; red alert chip displays: 'Already selected in Lions for Cricket'.
* **Expected Result (Backend & Data):** Client team builder checks active squad UIDs.
* **Edge / Negative Scenarios:** Prevents accidental double booking.

### TC-PLAYER-050: Server-Side Duplicate Player Rejection Guard
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `Backend Trigger`
* **Pre-conditions:** Malicious client bypasses UI check to submit Ravi in both Lions and Tigers.
* **Step-by-Step Procedure:**
1. Send batch commit with duplicate UID in same competition.
* **Expected Result (UI & Feedback):** Firebase security rules / Cloud Function rejects transaction with error: 'Duplicate player in same draw'.
* **Expected Result (Backend & Data):** Transaction fails atomically.
* **Edge / Negative Scenarios:** Security integrity maintained at database level.

### TC-PLAYER-051: Cross-Club Duplicate Player Block (Player in Club A and Club B)
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Pending Entries Card`
* **Pre-conditions:** Player Vikram registered by Host Club and Visiting Club for Cricket.
* **Step-by-Step Procedure:**
1. Host admin reviews pending entries.
* **Expected Result (UI & Feedback):** Warning banner flags: 'Player Vikram is registered in 2 different clubs for Cricket'.
* **Expected Result (Backend & Data):** crossClubDuplicateChecker triggers.
* **Edge / Negative Scenarios:** Admin must contact player to confirm primary club affiliation.

### TC-PLAYER-052: Multi-Sport Allowed Scenario (Cricket + Badminton)
* **Perspective:** Dual Athlete (D3)
* **Screen / Location:** `Registration Sheet`
* **Pre-conditions:** Player Arjun is in Cricket squad.
* **Step-by-Step Procedure:**
1. Register Arjun in Badminton Singles Men's Open.
* **Expected Result (UI & Feedback):** Registration succeeds with green checkmark; tooltip confirms: 'Dual-sport participant'.
* **Expected Result (Backend & Data):** Different sport IDs allow multi-sport participation.
* **Edge / Negative Scenarios:** Scheduler will automatically de-conflict match times.

### TC-PLAYER-053: Multi-Sport Triple Event Participation (Cricket, Badminton, Chess)
* **Perspective:** Dual Athlete (D3)
* **Screen / Location:** `Registration Sheet`
* **Pre-conditions:** Arjun already in Cricket and Badminton.
* **Step-by-Step Procedure:**
1. Register Arjun in Chess Rapid.
* **Expected Result (UI & Feedback):** Registration confirms successfully; player profile displays 3 active tournament badges.
* **Expected Result (Backend & Data):** Valid multi-sport athlete.
* **Edge / Negative Scenarios:** Timetable enforces rest gaps between all 3 sports.

### TC-PLAYER-054: Maximum Events per Player Ceiling Enforcement (Max 3 Events)
* **Perspective:** Dual Athlete (D3)
* **Screen / Location:** `Registration Sheet`
* **Pre-conditions:** Season rule limits 3 events per player.
* **Step-by-Step Procedure:**
1. Attempt registering Arjun in 4th event (Football 7s).
* **Expected Result (UI & Feedback):** Registration blocks with error: 'Maximum event limit reached (3 events per athlete)'.
* **Expected Result (Backend & Data):** tournament.maxEventsPerAthlete enforced.
* **Edge / Negative Scenarios:** Prevents player exhaustion.

### TC-PLAYER-055: Duplicate Player Check on Late Roster Replacement
* **Perspective:** Visiting Owner (D4)
* **Screen / Location:** `Roster Edit`
* **Pre-conditions:** Team substituting player post-approval.
* **Step-by-Step Procedure:**
1. Attempt substituting in a player already active on another cricket squad.
* **Expected Result (UI & Feedback):** System rejects substitution: 'Player already active in competition'.
* **Expected Result (Backend & Data):** Dynamic roster edit checks duplicate pool.
* **Edge / Negative Scenarios:** Prevents illegal roster poaching.

### TC-PLAYER-056: Self-Playing Sybil Matchup Defense
* **Perspective:** Backend Rule
* **Screen / Location:** `Match Center`
* **Pre-conditions:** Fraudulent draw where Player A is on Side 1 and Side 2.
* **Step-by-Step Procedure:**
1. Finalize match result.
* **Expected Result (UI & Feedback):** Glicko-2 rating trigger halts with error: 'same_account_on_both_sides'.
* **Expected Result (Backend & Data):** Rating settlement withheld; security incident logged.
* **Edge / Negative Scenarios:** Protects global leaderboard integrity.

### TC-PLAYER-057: Disqualified Player Cross-Sport Suspension
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Disciplinary Panel`
* **Pre-conditions:** Player red-carded for violent conduct in Football.
* **Step-by-Step Procedure:**
1. Admin issues tournament-wide suspension.
* **Expected Result (UI & Feedback):** Player barred from upcoming Badminton and Cricket matches automatically.
* **Expected Result (Backend & Data):** userTournamentSuspension set to true.
* **Edge / Negative Scenarios:** Enforces multi-sport sportsmanship.

### TC-PLAYER-058: Audit Trail for Roster Changes Post-Draw Generation
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Draws View`
* **Pre-conditions:** Any roster modification after draw is built.
* **Step-by-Step Procedure:**
1. Inspect team roster history.
* **Expected Result (UI & Feedback):** Audit timeline shows every addition/removal with exact timestamp and author UID.
* **Expected Result (Backend & Data):** AuditLog subcollection preserves full history.
* **Edge / Negative Scenarios:** Prevents unrecorded lineup tampering.

## Suite 2.6: Solo Entry vs Team Sport Guardrails & Age 21+ Verification (TC-PLAYER-059 to 070)

### TC-PLAYER-059: Team Sport (Football 7s) Blocks Solo Registration
* **Perspective:** Solo Player (D2)
* **Screen / Location:** `Tournament Event Page`
* **Pre-conditions:** Solo player opens Football 7s.
* **Step-by-Step Procedure:**
1. Observe registration action area.
* **Expected Result (UI & Feedback):** No 'Register Myself' button; card states: 'Team sport: must be registered by a club team'.
* **Expected Result (Backend & Data):** sideFormat.isTeam checks true.
* **Edge / Negative Scenarios:** Provides 'Contact Club Owner' button.

### TC-PLAYER-060: Team Sport (Cricket T20) Blocks Solo Registration
* **Perspective:** Solo Player (D2)
* **Screen / Location:** `Tournament Event Page`
* **Pre-conditions:** Solo player opens Cricket T20.
* **Step-by-Step Procedure:**
1. Observe registration area.
* **Expected Result (UI & Feedback):** Single registration disabled; informational card explains 11-player squad requirement.
* **Expected Result (Backend & Data):** sideFormat == SideFormat.eleven.
* **Edge / Negative Scenarios:** Prevents single players cluttering team draws.

### TC-PLAYER-061: Single-Player Sport (Badminton Singles) Open Solo Entry
* **Perspective:** Solo Player (D2)
* **Screen / Location:** `Badminton Singles Page`
* **Pre-conditions:** Solo player opens Badminton Singles.
* **Step-by-Step Procedure:**
1. Observe action area.
* **Expected Result (UI & Feedback):** Prominent green button 'Register Myself' is active and enabled.
* **Expected Result (Backend & Data):** sideFormat == SideFormat.singles.
* **Edge / Negative Scenarios:** Solo entry permitted.

### TC-PLAYER-062: Solo Player 'Register Myself' Tap & Checkout
* **Perspective:** Solo Player (D2)
* **Screen / Location:** `Registration Sheet`
* **Pre-conditions:** Badminton Singles open.
* **Step-by-Step Procedure:**
1. Tap 'Register Myself'.
2. Review profile details.
3. Tap 'Confirm Entry'.
* **Expected Result (UI & Feedback):** Button animates to checkmark 'Registered'; toast confirms entry.
* **Expected Result (Backend & Data):** Registration doc created under competitions/{compId}/registrations/{uid}.
* **Edge / Negative Scenarios:** Player added to unseeded draw pool.

### TC-PLAYER-063: Age 21+ Verification - Ineligible Player (Age 20y 10m) Rejection
* **Perspective:** Captain (D4)
* **Screen / Location:** `BuildEntryScreen`
* **Pre-conditions:** Event requires Age 21+ on 10 Oct 2026; Player DOB: 15 Nov 2005.
* **Step-by-Step Procedure:**
1. Add Player to roster.
2. Tap 'Validate & Submit'.
* **Expected Result (UI & Feedback):** Modal dialog blocks: 'Player is 20 years old on 10/10/2026. Minimum required age is 21'.
* **Expected Result (Backend & Data):** checkTeamEligibility callable function returns eligible: false.
* **Edge / Negative Scenarios:** Player cannot be submitted in squad.

### TC-PLAYER-064: Age 21+ Verification - Eligible Player (Age 21y 1d) Acceptance
* **Perspective:** Captain (D4)
* **Screen / Location:** `BuildEntryScreen`
* **Pre-conditions:** Player DOB: 09 Oct 2005 (Turned 21 yesterday).
* **Step-by-Step Procedure:**
1. Add Player to roster.
2. Tap 'Validate & Submit'.
* **Expected Result (UI & Feedback):** Player accepted with green verified badge; no age warning.
* **Expected Result (Backend & Data):** ageOnDate calculation in Asia/Kolkata evaluates to 21.
* **Edge / Negative Scenarios:** Player successfully submitted.

### TC-PLAYER-065: Age Verification Privacy - Exact Birthdate Withheld from Captain
* **Perspective:** Captain (D4)
* **Screen / Location:** `Eligibility Error Sheet`
* **Pre-conditions:** Underage player rejected.
* **Step-by-Step Procedure:**
1. Inspect rejection notice.
* **Expected Result (UI & Feedback):** Notice displays player name, calculated age (20), and rule violation; exact DOB is NOT displayed.
* **Expected Result (Backend & Data):** Privacy guard protects minor and adult birthdates in compliance with data privacy.
* **Edge / Negative Scenarios:** Prevents exposing private credentials.

### TC-PLAYER-066: Timezone Integrity Check (Indian Standard Time Cutoff)
* **Perspective:** Captain (D4)
* **Screen / Location:** `Cloud Function`
* **Pre-conditions:** Player born on cutoff date at 23:30 UTC (05:00 IST next day).
* **Step-by-Step Procedure:**
1. System calculates age.
* **Expected Result (UI & Feedback):** Evaluated strictly in Asia/Kolkata timezone (calendarDay function).
* **Expected Result (Backend & Data):** Avoids UTC birthday shifting bug.
* **Edge / Negative Scenarios:** Ensures consistent eligibility across all devices.

### TC-PLAYER-067: Solo Player Direct Entry in Another Club's Open Singles
* **Perspective:** Solo Player (D2)
* **Screen / Location:** `Public Explore`
* **Pre-conditions:** PS Visitors Club hosting open Badminton tournament.
* **Step-by-Step Procedure:**
1. Member of PS Test Academy opens PS Visitors tournament.
2. Tap 'Register Myself'.
* **Expected Result (UI & Feedback):** Registration succeeds regardless of hosting club.
* **Expected Result (Backend & Data):** Open singles tournaments allow direct individual participation across clubs.
* **Edge / Negative Scenarios:** Encourages community engagement.

### TC-PLAYER-068: Doubles Partner Nomination Flow (Badminton Doubles)
* **Perspective:** Solo Player (D2)
* **Screen / Location:** `Doubles Registration Sheet`
* **Pre-conditions:** Badminton Doubles event.
* **Step-by-Step Procedure:**
1. Tap 'Register as Pair'.
2. Search and pick Partner UID.
3. Send partner invite.
* **Expected Result (UI & Feedback):** Entry marked 'Pending Partner Confirmation'; notification sent to partner.
* **Expected Result (Backend & Data):** Registration doc has status: 'pending_partner'.
* **Edge / Negative Scenarios:** Entry finalizes once partner confirms.

### TC-PLAYER-069: Doubles Partner Declines Nomination
* **Perspective:** Partner (D3)
* **Screen / Location:** `Partner Notifications`
* **Pre-conditions:** Partner receives doubles nomination.
* **Step-by-Step Procedure:**
1. Partner taps 'Decline'.
* **Expected Result (UI & Feedback):** Original player notified; entry marked 'Partner Declined - Pick Another'.
* **Expected Result (Backend & Data):** Registration status set to 'partner_declined'.
* **Edge / Negative Scenarios:** Slot not consumed until confirmed.

### TC-PLAYER-070: Solo Player Entry Fee Payment via Razorpay / UPI
* **Perspective:** Solo Player (D2)
* **Screen / Location:** `Payment Drawer`
* **Pre-conditions:** Singles fee ₹300.
* **Step-by-Step Procedure:**
1. Tap 'Pay & Register'.
2. Complete UPI mock payment.
* **Expected Result (UI & Feedback):** Receipt generated with GST invoice; badge updates to 'Confirmed & Paid'.
* **Expected Result (Backend & Data):** Payment record written; webhook verifies signature.
* **Edge / Negative Scenarios:** Automatic refund if tournament cancelled.

## Suite 2.7: Public Discovery, Request to Join vs Invite-Only Gate (TC-PLAYER-071 to 080)

### TC-PLAYER-071: Public Discovery - Find Season on Explore Page
* **Perspective:** Uninvited Club (D4)
* **Screen / Location:** `ExploreScreen`
* **Pre-conditions:** Open tournament published.
* **Step-by-Step Procedure:**
1. Open Explore > Tournaments.
2. Locate 'Telangana State Champions Trophy 2026'.
* **Expected Result (UI & Feedback):** Tournament card displays host logo, dates, sports chips, and 'Open Registration' badge.
* **Expected Result (Backend & Data):** Reads public active tournaments stream.
* **Edge / Negative Scenarios:** Search bar filters by sport and city.

### TC-PLAYER-072: Request Club Registration Button on Open Tournament
* **Perspective:** Uninvited Club (D4)
* **Screen / Location:** `Public Season Overview`
* **Pre-conditions:** Tournament is open.
* **Step-by-Step Procedure:**
1. Tap 'Request Club Registration' button.
* **Expected Result (UI & Feedback):** Application modal opens requesting club name, contact phone, and sports interested.
* **Expected Result (Backend & Data):** tournament.accessMode == 'open'.
* **Edge / Negative Scenarios:** Host receives entry request.

### TC-PLAYER-073: Submit Registration Request with Sports Selection
* **Perspective:** Uninvited Club (D4)
* **Screen / Location:** `Request Modal`
* **Pre-conditions:** Modal open.
* **Step-by-Step Procedure:**
1. Check 'Cricket' and 'Badminton'.
2. Type note: 'Premier club of Warangal'.
3. Submit.
* **Expected Result (UI & Feedback):** Toast confirms: 'Registration request submitted to host organizers'.
* **Expected Result (Backend & Data):** Request doc created in tournaments/{id}/requests/{reqId}.
* **Edge / Negative Scenarios:** Host Organizer Desk displays new request in Pending card.

### TC-PLAYER-074: Strict Lockout on Invite-Only Season (Public View)
* **Perspective:** Uninvited Club (D4)
* **Screen / Location:** `Public Season Overview`
* **Pre-conditions:** Tournament configured as accessMode: 'inviteOnly'.
* **Step-by-Step Procedure:**
1. Open tournament page.
* **Expected Result (UI & Feedback):** Register and Request buttons are completely hidden; private lock banner displayed.
* **Expected Result (Backend & Data):** accessMode == 'inviteOnly'.
* **Edge / Negative Scenarios:** Blocks unauthorized clubs from applying.

### TC-PLAYER-075: Host Approves Registration Request
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Pending Requests Card`
* **Pre-conditions:** Request waiting.
* **Step-by-Step Procedure:**
1. Tap 'Approve Request' on Warangal Club.
* **Expected Result (UI & Feedback):** Warangal Club receives notification: 'Your club registration request was approved'.
* **Expected Result (Backend & Data):** Warangal club owner unlocked to build and submit squad entries.
* **Edge / Negative Scenarios:** Seamless onboarding for open tournaments.

### TC-PLAYER-076: Host Declines Registration Request with Reason
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Pending Requests Card`
* **Pre-conditions:** Request from incompatible club.
* **Step-by-Step Procedure:**
1. Tap 'Decline Request' > enter 'All slots filled'.
* **Expected Result (UI & Feedback):** Request marked declined; notification sent to applicant.
* **Expected Result (Backend & Data):** request.status set to 'declined'.
* **Edge / Negative Scenarios:** Applicant barred from resubmitting for 7 days.

### TC-PLAYER-077: Search Tournaments by Sport Tag (Football Only)
* **Perspective:** Player (D2)
* **Screen / Location:** `ExploreScreen`
* **Pre-conditions:** Multiple tournaments active.
* **Step-by-Step Procedure:**
1. Tap 'Football' category filter pill.
* **Expected Result (UI & Feedback):** Only tournaments hosting Football competitions are shown.
* **Expected Result (Backend & Data):** Query where('sportIds', 'array-contains', 'football').
* **Edge / Negative Scenarios:** Fast discovery for athletes.

### TC-PLAYER-078: Search Tournaments by City (Hyderabad Only)
* **Perspective:** Player (D2)
* **Screen / Location:** `ExploreScreen`
* **Pre-conditions:** Active tournaments in various cities.
* **Step-by-Step Procedure:**
1. In City dropdown, pick 'Hyderabad'.
* **Expected Result (UI & Feedback):** Only Hyderabad venues and tournaments shown.
* **Expected Result (Backend & Data):** Query where('city', '==', 'Hyderabad').
* **Edge / Negative Scenarios:** Local community focus.

### TC-PLAYER-079: Share Tournament Link to External Contacts
* **Perspective:** Player (D2)
* **Screen / Location:** `Tournament Overview`
* **Pre-conditions:** Tournament open.
* **Step-by-Step Procedure:**
1. Tap Share icon in top bar.
* **Expected Result (UI & Feedback):** Native OS ShareSheet opens with tournament title and link.
* **Expected Result (Backend & Data):** Deep link https://playsphere.app/tournaments/{id} copied.
* **Edge / Negative Scenarios:** Promotes viral tournament discovery.

### TC-PLAYER-080: Bookmark / Favorite Tournament
* **Perspective:** Player (D2)
* **Screen / Location:** `Tournament Overview`
* **Pre-conditions:** Tournament open.
* **Step-by-Step Procedure:**
1. Tap bookmark star icon.
* **Expected Result (UI & Feedback):** Star turns solid yellow; toast confirms 'Saved to My Tournaments'.
* **Expected Result (Backend & Data):** userFavorites subcollection updated.
* **Edge / Negative Scenarios:** Fast access from 'My Clubs & Seasons' screen.

## Suite 2.8: Player Live Matchday Experience, Scores & Protests (TC-PLAYER-081 to 085)

### TC-PLAYER-081: View Live Scores with Ball-by-Ball Timeline
* **Perspective:** Player (D2)
* **Screen / Location:** `Match Center`
* **Pre-conditions:** Match currently in progress.
* **Step-by-Step Procedure:**
1. Open live match from 'Live Now' tab.
* **Expected Result (UI & Feedback):** Real-time score updates, live dot pulse, and ball-by-ball commentary stream smoothly.
* **Expected Result (Backend & Data):** Firestore onSnapshot listener updates without manual refresh.
* **Edge / Negative Scenarios:** Clean 60fps score rendering.

### TC-PLAYER-082: Push Notification on Player Upcoming Match Alert
* **Perspective:** Player (D2)
* **Screen / Location:** `OS Notifications`
* **Pre-conditions:** Match scheduled in 30 minutes.
* **Step-by-Step Procedure:**
1. Receive automated notification.
* **Expected Result (UI & Feedback):** Notification alerts: 'Your Badminton match on Court 1 starts in 30 minutes'.
* **Expected Result (Backend & Data):** Scheduled Cloud Function fires 30m before fixture startTime.
* **Edge / Negative Scenarios:** Ensures players report to court on time.

### TC-PLAYER-083: Spectator Cheer Button Execution (Clap / Flame)
* **Perspective:** Player (D2)
* **Screen / Location:** `Live Match Screen`
* **Pre-conditions:** Match live.
* **Step-by-Step Procedure:**
1. Tap '🔥 Fire' cheer button 3 times.
* **Expected Result (UI & Feedback):** Floating fire emoji animation floats up screen; cheer counter increments.
* **Expected Result (Backend & Data):** Cheer subcollection document bumped via FieldValue.increment.
* **Edge / Negative Scenarios:** Engages spectators and fans.

### TC-PLAYER-084: Submit Official Match Result Protest within 1 Hour
* **Perspective:** Captain (D4)
* **Screen / Location:** `Completed Match Card`
* **Pre-conditions:** Match finished 20 minutes ago with scoring discrepancy.
* **Step-by-Step Procedure:**
1. Tap 'Protest Result' button.
2. Enter explanation: 'Scorepad missed 2 boundary runs in 14th over'.
3. Submit.
* **Expected Result (UI & Feedback):** Match badge updates to 'Under Protest'; organizer alerted.
* **Expected Result (Backend & Data):** protestSubmittedAt timestamp recorded; must be <= 1 hour post-match.
* **Edge / Negative Scenarios:** Freezes rating settlement until resolved.

### TC-PLAYER-085: Protest Window Expiration Lock (After 1 Hour)
* **Perspective:** Captain (D4)
* **Screen / Location:** `Completed Match Card`
* **Pre-conditions:** Match finished 1 hour 15 minutes ago.
* **Step-by-Step Procedure:**
1. Inspect match card.
* **Expected Result (UI & Feedback):** 'Protest Result' button is disabled; status badge reads 'Final & Official'.
* **Expected Result (Backend & Data):** Protest window closed; results permanently locked.
* **Edge / Negative Scenarios:** Glicko-2 ratings settled permanently.

## Suite 2.9: 100-Player Scale, Concurrency & High-Density UI Stress (TC-PLAYER-086 to 090)

### TC-PLAYER-086: 100-Member Bulk Roster Rendering Performance
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Members Roster Sheet`
* **Pre-conditions:** 100 members approved in club.
* **Step-by-Step Procedure:**
1. Open member allocation list.
2. Rapidly fling scroll down to bottom.
* **Expected Result (UI & Feedback):** ListView.builder renders smoothly at 60fps; zero memory spikes or jank.
* **Expected Result (Backend & Data):** Lazy loading and view recycling maintain smooth performance.
* **Edge / Negative Scenarios:** All 100 member avatars and badges render correctly.

### TC-PLAYER-087: 50 Concurrent RSVP Responses Stress Test
* **Perspective:** System Stress
* **Screen / Location:** `Club Feed`
* **Pre-conditions:** 50 members tap 'In' simultaneously via automated test script.
* **Step-by-Step Procedure:**
1. Trigger 50 concurrent writes to RSVP response subcollection.
* **Expected Result (UI & Feedback):** Firestore handles concurrent transactions without write contention; live headcount updates to 50.
* **Expected Result (Backend & Data):** Firestore transaction retries absorb concurrency.
* **Edge / Negative Scenarios:** Real-time stream displays accurate tally.

### TC-PLAYER-088: 100-Player Multi-Sport Timetable Rendering
* **Perspective:** Player (D2)
* **Screen / Location:** `Graphical Schedule Grid`
* **Pre-conditions:** 60 cricket players + 20 badminton players + 20 football players scheduled.
* **Step-by-Step Procedure:**
1. Open Graphical Schedule Grid View on phone.
* **Expected Result (UI & Feedback):** Interactive matrix grid renders all court columns and time rows with fluid 2D pinch-to-zoom.
* **Expected Result (Backend & Data):** CustomPainter / InteractiveViewer renders efficiently.
* **Edge / Negative Scenarios:** Zooming and panning remain fluid.

### TC-PLAYER-089: Olympics Medal Tally Calculation Across 100 Athletes
* **Perspective:** Host Owner (D1)
* **Screen / Location:** `Tournament Standings Tab`
* **Pre-conditions:** All events completed across 4 houses and visiting clubs.
* **Step-by-Step Procedure:**
1. Open Season Leaderboard.
* **Expected Result (UI & Feedback):** Medal table aggregates Gold, Silver, Bronze tallies and points accurately across 100 players in < 1 second.
* **Expected Result (Backend & Data):** Leaderboard aggregator pipeline sums event placements.
* **Edge / Negative Scenarios:** Ties broken correctly by Gold medal count.

### TC-PLAYER-090: End-to-End Stress Run Verification & Zero Memory Leaks
* **Perspective:** QA Tester
* **Screen / Location:** `Memory Profiler`
* **Pre-conditions:** Continuous 2-hour full test run across all 215 test cases.
* **Step-by-Step Procedure:**
1. Inspect Flutter memory heap and Dart VM metrics.
* **Expected Result (UI & Feedback):** Total memory consumption remains stable (< 190 MB); zero uncollected streams or widget memory leaks.
* **Expected Result (Backend & Data):** Disposed controllers and cancelled stream subscriptions verified.
* **Edge / Negative Scenarios:** App remains crisp and fully responsive.

