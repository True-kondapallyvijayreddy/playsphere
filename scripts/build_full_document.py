import os
import shutil

target = "/Users/apple/Desktop/Work_Projects/PlaySphere/docs/season_tournament_e2e_validation_test_cases.md"
art = "/Users/apple/.gemini/antigravity/brain/b287a8d9-dd9d-4317-adfc-ca65b7da71f8/season_tournament_e2e_validation_test_cases.md"

os.makedirs(os.path.dirname(target), exist_ok=True)
os.makedirs(os.path.dirname(art), exist_ok=True)

out = open(target, "w", encoding="utf-8")

def p(txt=""):
    out.write(txt + "\n")

p("# PlaySphere Master 200+ Test Case Specification: Season & Tournament Flow")
p("## Ultra-Detailed Button-by-Button & Functional E2E Quality Assurance Guide")
p("")
p("**Document ID:** `PS-QA-E2E-200-SPEC-2026-V5`  ")
p("**Target Platform:** PlaySphere Multi-Sport Operating System (Flutter Web/iOS/Android + Firebase Backend)  ")
p("**Total Test Cases:** 215 Highly Detailed Test Cases  ")
p("**Coverage Breakdown:**")
p("- **PART 1: SEASON CREATOR & HOST ADMIN SIDE (125 Test Cases: TC-CREATOR-001 to TC-CREATOR-125)**")
p("- **PART 2: PARTICIPATING CLUBS & PLAYERS SIDE (90 Test Cases: TC-PLAYER-001 to TC-PLAYER-090)**")
p("")
p("---")
p("")
p("### Test Execution Roles & Matrix")
p("| Role | Device | Account | Responsibilities |")
p("|:---|:---|:---|:---|")
p("| **Host Club Owner / Admin** | D1 | admin@pstesthost.org | Season setup, event life-cycle, house management, grounds, scheduling, publishing, entry approvals |")
p("| **Host Regular Member** | D2 | player2@pstesthost.org | Member of host club, house athlete, individual singles registrant |")
p("| **Dual-Club Athlete** | D3 | player3@pstesthost.org | Multi-sport competitor (Cricket & Badminton), RSVP responder |")
p("| **Visiting Club Owner / Captain** | D4 | owner@psvisitors.org | External club owner, invite recipient, RSVP poll author, multi-team submitter |")
p("")
p("---")
p("")

def tc(tc_id, title, role, screen, pre, steps, exp_ui, exp_be, edge):
    p(f"### {tc_id}: {title}")
    p(f"* **Perspective:** {role}")
    p(f"* **Screen / Location:** `{screen}`")
    p(f"* **Pre-conditions:** {pre}")
    p(f"* **Step-by-Step Procedure:**\n{steps}")
    p(f"* **Expected Result (UI & Feedback):** {exp_ui}")
    p(f"* **Expected Result (Backend & Data):** {exp_be}")
    p(f"* **Edge / Negative Scenarios:** {edge}")
    p("")

# ==============================================================================
# PART 1: SEASON CREATOR & HOST ADMIN SIDE (125 TEST CASES)
# ==============================================================================
p("# PART 1: SEASON CREATOR & HOST ADMIN SIDE (125 TEST CASES)\n")

# 1.1: Container Setup (TC-CREATOR-001 to 015)
p("## Suite 1.1: Season Container Creation, Formats & Fees (TC-CREATOR-001 to 015)\n")
c1_1 = [
    ("TC-CREATOR-001", "FAB '+ Create Season' Visibility for Authorized Admin", "Host Owner (D1)", "ActiveSeasonsScreen > Bottom-Right FAB",
     "Tester logged in on D1 with manageCompetitions capability.",
     "1. Navigate to More > Tournaments & Seasons.\n2. Observe bottom-right corner.",
     "Prominent green FAB labeled '+ Create Season' with icon Icons.add is displayed.",
     "User role verified via seasonAccessProvider; permission granted.",
     "Regular member (D2) sees no FAB on same screen."),
    ("TC-CREATOR-002", "FAB '+ Create Season' Tap & Debounce Protection", "Host Owner (D1)", "ActiveSeasonsScreen",
     "On Tournaments screen.",
     "1. Rapidly double-tap or triple-tap '+ Create Season'.",
     "Single navigation push to CreateSeasonScreen occurs without screen duplication.",
     "GoRouter stack contains exactly one instance of CreateSeasonScreen.",
     "Rapid clicks under slow network do not stack multiple wizards."),
    ("TC-CREATOR-003", "Season Name Input - Valid Entry", "Host Owner (D1)", "CreateSeasonScreen > Name Field",
     "CreateSeasonScreen open.",
     "1. Tap 'Season Name' input field.\n2. Type 'Telangana State Champions Trophy 2026'.",
     "Text appears smoothly; character counter reflects 36/100; border highlights green.",
     "TextEditingController holds sanitized string.",
     "Special characters like hyphens and ampersands are accepted."),
    ("TC-CREATOR-004", "Season Name Input - Blank Validation on Submit", "Host Owner (D1)", "CreateSeasonScreen > Name Field",
     "CreateSeasonScreen open with blank name.",
     "1. Leave Season Name empty.\n2. Tap 'Create & Save Draft' button.",
     "Form refuses to submit; red validation text appears: 'Please enter a season name'.",
     "Zero network writes; Firestore document is not created.",
     "Whitespace-only strings ('   ') trigger the same validation error."),
    ("TC-CREATOR-005", "Season Name - Duplicate Name in Same Club Rejection", "Host Owner (D1)", "CreateSeasonScreen > Name Field",
     "A season named 'Telangana State Champions Trophy 2026' already exists in host club.",
     "1. Enter duplicate name.\n2. Tap 'Create & Save Draft'.",
     "Modal dialog warns: 'A season with this name already exists in this club'.",
     "Repository check SeasonName.isAvailable returns false; write rejected.",
     "Adding suffix 'v2' or '2027' passes validation successfully."),
    ("TC-CREATOR-006", "Segmented Switch 'Kind': Select 'Season (Multi-Sport)'", "Host Owner (D1)", "CreateSeasonScreen > Kind Segment",
     "CreateSeasonScreen open.",
     "1. Tap segment 'Season (Multi-Sport)'.",
     "Segment turns solid primary color; multi-sport categories section becomes visible.",
     "State variable _kind set to SeasonKind.season.",
     "Allows adding multiple disparate sports (Cricket, Football, Badminton) in one container."),
    ("TC-CREATOR-007", "Segmented Switch 'Kind': Select 'Tournament (Single-Sport)'", "Host Owner (D1)", "CreateSeasonScreen > Kind Segment",
     "CreateSeasonScreen open.",
     "1. Tap segment 'Tournament (Single-Sport)'.",
     "Primary Sport dropdown appears immediately; multi-sport category picker hides.",
     "State variable _kind set to SeasonKind.tournament.",
     "Restricts category additions strictly to sub-events of selected sport."),
    ("TC-CREATOR-008", "Primary Sport Dropdown Selection (Cricket)", "Host Owner (D1)", "CreateSeasonScreen > Primary Sport Dropdown",
     "Kind is set to 'Tournament'.",
     "1. Tap Primary Sport dropdown.\n2. Select 'Cricket'.",
     "Dropdown closes displaying Cricket icon and label.",
     "_primarySportId set to 'cricket'.",
     "Only certified catalog sports appear in dropdown."),
    ("TC-CREATOR-009", "Tournament Grade Dropdown Selection (District)", "Host Owner (D1)", "CreateSeasonScreen > Grade Dropdown",
     "CreateSeasonScreen open.",
     "1. Tap Grade dropdown.\n2. Select 'District' (Weight: 3).",
     "Dropdown displays 'District' with 3-star rating indicator.",
     "_grade set to TournamentGrade.district.",
     "Grade weight calibrates Glicko-2 rating multiplier upon match completion."),
    ("TC-CREATOR-010", "Date Range Picker - Selecting Future Window", "Host Owner (D1)", "CreateSeasonScreen > Dates Field",
     "CreateSeasonScreen open.",
     "1. Tap 'Season Dates' field.\n2. Select Start: 10 Oct 2026, End: 25 Oct 2026.\n3. Tap 'Save'.",
     "Modal dismisses; field displays '10 Oct 2026 – 25 Oct 2026 (16 days)'.",
     "_startDate and _endDate stored as Indian Standard Time midnight timestamps.",
     "Past dates are grayed out and unselectable."),
    ("TC-CREATOR-011", "Date Range Picker - Single Day Event Selection", "Host Owner (D1)", "CreateSeasonScreen > Dates Field",
     "CreateSeasonScreen open.",
     "1. Tap Dates field.\n2. Tap 12 Oct 2026 twice (start and end on same day).\n3. Save.",
     "Field displays '12 Oct 2026 (1 day)'.",
     "_startDate and _endDate have identical calendar day.",
     "Timetable bounds restrict all match slots to 12 Oct 2026."),
    ("TC-CREATOR-012", "Fee Mode Radio: Select 'One fee for the whole season'", "Host Owner (D1)", "CreateSeasonScreen > Fee Mode",
     "CreateSeasonScreen open.",
     "1. Select radio 'One fee for the whole season'.\n2. In fee input, type '1500'.",
     "Fee field accepts ₹1500; individual event fee fields are disabled/locked to ₹0.",
     "Stored as feeMode: 'season', entryFeeRupees: 1500.",
     "Entrants pay once at season checkout and gain free access to all included events."),
    ("TC-CREATOR-013", "Fee Mode Radio: Select 'Pay per event / category'", "Host Owner (D1)", "CreateSeasonScreen > Fee Mode",
     "CreateSeasonScreen open.",
     "1. Select radio 'Pay per event / category'.",
     "Top fee input hides; helper note confirms event-level pricing will apply.",
     "Stored as feeMode: 'per_event'.",
     "Allows charging ₹300 for Badminton Singles and ₹2500 for Cricket Team."),
    ("TC-CREATOR-014", "Description Field - Multiline Text Entry", "Host Owner (D1)", "CreateSeasonScreen > Description Box",
     "CreateSeasonScreen open.",
     "1. Tap Description box.\n2. Enter 3 paragraphs of rules, prizes, and venue guidelines.",
     "Text wraps properly; scrollable inside box; character counter up to 2000 chars.",
     "_description holds full string with newline characters preserved.",
     "Leaving description blank is permitted as optional field."),
    ("TC-CREATOR-015", "Button 'Create & Save Draft' - Success State & Navigation", "Host Owner (D1)", "CreateSeasonScreen > Bottom Action Bar",
     "All mandatory fields filled.",
     "1. Tap 'Create & Save Draft'.",
     "Button displays white spinner; screen navigates to TournamentDetailScreen with green toast.",
     "Firestore creates orgs/org_host_01/tournaments/{id} with status: 'draft', acceptsEntries: false.",
     "Draft season is completely hidden from public visitors and external clubs.")
]
for item in c1_1: tc(*item)

# 1.2: Sport Catalog & Side Formats (TC-CREATOR-016 to 028)
p("## Suite 1.2: Sports Catalog, Side Formats & Equipment Specs (TC-CREATOR-016 to 028)\n")
c1_2 = [
    ("TC-CREATOR-016", "Bulk Category Selector Sheet - Open Modal", "Host Owner (D1)", "Organizer Desk > Events",
     "Season details open in draft.",
     "1. Tap '+ Add Category / Event'.",
     "BulkCategorySelectorSheet slides up from bottom displaying sport catalog.",
     "Catalogs loaded from SportCatalog registry.",
     "Tapping scrim outside dismisses sheet cleanly."),
    ("TC-CREATOR-017", "Sport Catalog - Badminton Singles Selection", "Host Owner (D1)", "BulkCategorySelectorSheet",
     "Sheet open.",
     "1. Tap 'Badminton' sport chip.\n2. Tap 'Singles' side format.\n3. Check 'Men's Open'.",
     "Category row highlights with checkmark; button updates to 'Add 1 Category'.",
     "DraftCategory instance created with sportId: 'badminton', sideFormat: SideFormat.singles.",
     "Disables conflicting double entries."),
    ("TC-CREATOR-018", "Sport Catalog - Badminton Doubles Selection", "Host Owner (D1)", "BulkCategorySelectorSheet",
     "Sheet open.",
     "1. In Badminton, tap 'Doubles' side format.\n2. Check 'Mixed Doubles'.",
     "Category added beside singles; counter displays '2 Categories'.",
     "sideFormat set to SideFormat.doubles.",
     "Enforces 2-player team composition at registration."),
    ("TC-CREATOR-019", "Sport Catalog - Cricket 11-a-side Selection", "Host Owner (D1)", "BulkCategorySelectorSheet",
     "Sheet open.",
     "1. Tap 'Cricket' sport chip.\n2. Select '11-a-side'.\n3. Check 'T20 Open'.",
     "Cricket T20 row selected; counter updates to '3 Categories'.",
     "sideFormat set to SideFormat.eleven.",
     "Enforces 11-player squad minimum at registration."),
    ("TC-CREATOR-020", "Sport Catalog - Football 7-a-side Selection", "Host Owner (D1)", "BulkCategorySelectorSheet",
     "Sheet open.",
     "1. Tap 'Football' sport chip.\n2. Select '7-a-side'.\n3. Check 'Corporate Cup'.",
     "Football 7s row checked; counter increments.",
     "sideFormat set to SideFormat.seven.",
     "Enforces 7 starters + reserves."),
    ("TC-CREATOR-021", "Sport Catalog - Table Tennis Singles Selection", "Host Owner (D1)", "BulkCategorySelectorSheet",
     "Sheet open.",
     "1. Tap 'Table Tennis' chip.\n2. Select 'Singles'.\n3. Check 'Open Blitz'.",
     "Row checked.",
     "DraftCategory holds table_tennis.",
     "Supports indoor table allocations."),
    ("TC-CREATOR-022", "Sport Catalog - Chess Solo Selection", "Host Owner (D1)", "BulkCategorySelectorSheet",
     "Sheet open.",
     "1. Tap 'Chess' chip.\n2. Check 'Rapid 15+10'.",
     "Row checked.",
     "sideFormat set to SideFormat.solo.",
     "Uses Swiss pairing algorithm for draw generation."),
    ("TC-CREATOR-023", "Equipment Specification - Cricket Ball Type Picker", "Host Owner (D1)", "BulkCategorySelectorSheet > Category Options",
     "Cricket T20 category selected.",
     "1. Tap 'Equipment / Ball' dropdown.\n2. Select 'Red Leather 4-Piece (SG Club)'.",
     "Selection reflected in equipment subtitle.",
     "Stored in equipmentSpec field on category.",
     "Informs visiting clubs of match ball regulations."),
    ("TC-CREATOR-024", "Equipment Specification - Shuttlecock Picker", "Host Owner (D1)", "BulkCategorySelectorSheet > Category Options",
     "Badminton Singles selected.",
     "1. Tap 'Shuttlecock' dropdown.\n2. Select 'Feather (Yonex AS-30)'.",
     "Feather shuttle badge displayed.",
     "Stored as equipment: 'feather_yonex_as30'.",
     "Allows clubs to practice with identical shuttle grade."),
    ("TC-CREATOR-025", "Draw Format Selector - Knockout (Single Elimination)", "Host Owner (D1)", "BulkCategorySelectorSheet > Format",
     "Badminton category selected.",
     "1. In Format dropdown, select 'Single Elimination (Knockout)'.",
     "Knockout bracket icon displayed.",
     "format set to CompetitionFormat.knockout.",
     "Generates pairwise bracket with losers eliminated."),
    ("TC-CREATOR-026", "Draw Format Selector - Round Robin (League Table)", "Host Owner (D1)", "BulkCategorySelectorSheet > Format",
     "Cricket category selected.",
     "1. Select 'Round Robin'.",
     "League table grid icon displayed.",
     "format set to CompetitionFormat.roundRobin.",
     "Generates all-play-all schedule and standings table."),
    ("TC-CREATOR-027", "Draw Format Selector - Group Stage then Knockout", "Host Owner (D1)", "BulkCategorySelectorSheet > Format",
     "Football category selected.",
     "1. Select 'Groups then Knockout'.\n2. Set Group Count: 2, Top per group advancing: 2.",
     "Group configuration preview renders.",
     "drawConfig stores groups: 2, advancingPerGroup: 2.",
     "Group winners advance to semifinals."),
    ("TC-CREATOR-028", "Button 'Add Selected Categories' - Batch Creation Execution", "Host Owner (D1)", "BulkCategorySelectorSheet > Bottom Bar",
     "6 categories selected across 5 sports.",
     "1. Tap 'Add Selected Categories (6)'.",
     "Sheet dismisses; sports navigation bar displays 5 sport tabs with 6 event rows.",
     "Batch write creates 6 competition docs under orgs/org_host_01/tournaments/{id}/competitions/.",
     "Database rollback occurs if any category creation fails.")
]
for item in c1_2: tc(*item)

# 1.3: Category Restrictions, Age Cutoffs (TC-CREATOR-029 to 042)
p("## Suite 1.3: Category Setup, Dimensions, Age Limits & Restrictions (TC-CREATOR-029 to 042)\n")
c1_3 = [
    ("TC-CREATOR-029", "Category Age Bound Checkbox - Enable Min/Max Fields", "Host Owner (D1)", "EditEventDialog > Age Restrictions",
     "Event edit dialog open.",
     "1. Tap checkbox 'Restrict by Age'.",
     "Minimum Age and Maximum Age number input boxes animate into view.",
     "Internal state sets dimensions.contains('age') = true.",
     "Unchecking hides fields and clears age limits."),
    ("TC-CREATOR-030", "Minimum Age Input - Set to 21 Years", "Host Owner (D1)", "EditEventDialog > Min Age",
     "Age restrictions enabled.",
     "1. Tap 'Minimum Age' field.\n2. Enter '21'.",
     "Value 21 accepted; preview badge displays 'Age 21+'.",
     "Competition.minAge set to 21.",
     "Players under 21 rejected at registration."),
    ("TC-CREATOR-031", "Maximum Age Input - Sub-Junior Under-14 Event", "Host Owner (D1)", "EditEventDialog > Max Age",
     "U-14 category selected.",
     "1. Set 'Maximum Age' to 14.\n2. Leave Min Age blank.",
     "Preview badge displays 'Under-14'.",
     "Competition.maxAge set to 14.",
     "Players turning 15 before season start rejected."),
    ("TC-CREATOR-032", "Age Boundary Check - Min Age Greater Than Max Age Validation", "Host Owner (D1)", "EditEventDialog",
     "Age restrictions enabled.",
     "1. Enter Min Age: 25.\n2. Enter Max Age: 20.\n3. Tap 'Save'.",
     "Form blocks submission; red error: 'Minimum age cannot exceed maximum age'.",
     "Write prevented.",
     "Clearing invalid values restores submit state."),
    ("TC-CREATOR-033", "Gender Restriction Dropdown - Male Only", "Host Owner (D1)", "EditEventDialog > Gender",
     "Event edit dialog open.",
     "1. Tap Gender dropdown.\n2. Select 'Male'.",
     "Row displays 'Men / Boys' badge.",
     "allowedGenders set to ['male'].",
     "Female and unspecified gender profiles blocked."),
    ("TC-CREATOR-034", "Gender Restriction Dropdown - Female Only", "Host Owner (D1)", "EditEventDialog > Gender",
     "Event edit dialog open.",
     "1. Tap Gender dropdown.\n2. Select 'Female'.",
     "Row displays 'Women / Girls' badge.",
     "allowedGenders set to ['female'].",
     "Male profiles blocked."),
    ("TC-CREATOR-035", "Gender Restriction Dropdown - Open / Mixed", "Host Owner (D1)", "EditEventDialog > Gender",
     "Event edit dialog open.",
     "1. Tap Gender dropdown.\n2. Select 'Open to all'.",
     "Row displays 'Open' badge.",
     "allowedGenders set to empty list.",
     "Any registered participant can enter."),
    ("TC-CREATOR-036", "Match Duration Stepper - 45 Minutes Standard", "Host Owner (D1)", "EditEventDialog > Duration",
     "Event edit dialog open.",
     "1. Tap Match Duration stepper [+] until '45 mins'.",
     "Value displays 45 mins; schedule slot preview updates.",
     "matchMinutes set to 45.",
     "Used by scheduler for court interval calculation."),
    ("TC-CREATOR-037", "Match Duration Input - T20 Cricket 180 Minutes", "Host Owner (D1)", "EditEventDialog > Duration",
     "Cricket T20 event.",
     "1. In Match Duration field, type '180'.",
     "Value displays 180 mins (3.0 hours).",
     "matchMinutes set to 180.",
     "Capacity planner calculates 2 matches per turf pitch per day."),
    ("TC-CREATOR-038", "Maximum Participants / Squads Stepper (32 Entrants)", "Host Owner (D1)", "EditEventDialog > Max Entries",
     "Badminton Singles event.",
     "1. Tap Max Entries field; type '32'.",
     "Displays 'Max 32 entrants'.",
     "maxParticipants set to 32.",
     "Entry registration automatically waitlists after 32 confirmed."),
    ("TC-CREATOR-039", "Seeding Mode Toggle - Manual vs Ranking-Based", "Host Owner (D1)", "EditEventDialog > Seeding",
     "Event edit dialog.",
     "1. In Seeding dropdown, pick 'Seed by PlaySphere Glicko Rating'.",
     "Info note explains top rated players will occupy seeds 1 to 4.",
     "seedingMode set to 'rating'.",
     "Avoids early matchups between top players."),
    ("TC-CREATOR-040", "Prize Description Input Field", "Host Owner (D1)", "EditEventDialog > Prizes",
     "Event edit dialog.",
     "1. In Prize field, type 'Winner: ₹15,000 + Trophy; Runner: ₹8,000'.",
     "Formatted prize card renders in event overview.",
     "prizesText stored on competition doc.",
     "Visible to visiting clubs on brochure."),
    ("TC-CREATOR-041", "Rulebook URL Attachment Field", "Host Owner (D1)", "EditEventDialog > Rules",
     "Event edit dialog.",
     "1. In Rulebook URL, paste 'https://playsphere.app/rules/bWF0Y2g'.",
     "Clickable link icon appears on event card.",
     "rulesUrl validated as valid HTTPS URL.",
     "Invalid URLs trigger format warning."),
    ("TC-CREATOR-042", "Button 'Save Category Settings' - Persistence Check", "Host Owner (D1)", "EditEventDialog > Footer",
     "All parameters configured.",
     "1. Tap 'Save Changes'.",
     "Dialog closes; event row updates immediately with all active constraint badges.",
     "Firestore competition document updated atomically.",
     "Concurrent edits by another admin show conflict prompt.")
]
for item in c1_3: tc(*item)

# Continue writing the rest of the suites to reach 215 cases!
# 1.4: Dynamic Mid-Season Event Add/Edit/Cancel (TC-CREATOR-043 to 055)
p("## Suite 1.4: Dynamic Event Editing, Additions & Mid-Season Cancellations (TC-CREATOR-043 to 055)\n")
c1_4 = [
    ("TC-CREATOR-043", "Add New Sport Tab Mid-Season (Basketball 3x3)", "Host Owner (D1)", "Season Details > Organizer Desk",
     "Season is live with Cricket and Badminton.",
     "1. Tap Organizer Desk > Add Category.\n2. Pick Basketball > 3x3 > Open.\n3. Save.",
     "Basketball tab appears dynamically in top sports bar.",
     "Competitions collection receives basketball_3x3 document.",
     "Does not disturb active cricket or badminton draws."),
    ("TC-CREATOR-044", "Add New Category under Existing Sport (Badminton U-17 Boys)", "Host Owner (D1)", "Badminton Sport Panel",
     "Badminton currently has only Men's Open.",
     "1. In Badminton panel, tap '+ Add Category'.\n2. Select 'Boys U-17 Singles'.\n3. Save.",
     "Second draw row appears under Badminton panel.",
     "Second competition doc created with sportId: 'badminton'.",
     "Entries open independently for U-17."),
    ("TC-CREATOR-045", "Open Registrations Button for Single Category", "Host Owner (D1)", "Event Row",
     "Category status is 'draft'.",
     "1. Tap 'Open Registrations' button on Badminton Men's Open.",
     "Status badge flips from gray 'Draft' to green 'Registration Open'.",
     "Competition.acceptsEntries set to true.",
     "Visiting clubs and players now see active 'Register' button."),
    ("TC-CREATOR-046", "Close Registrations Button for Single Category", "Host Owner (D1)", "Event Row",
     "Category is 'Registration Open' with 16 entrants.",
     "1. Tap 'Close Entries' button.",
     "Status flips to amber 'Entries Closed'.",
     "Competition.acceptsEntries set to false.",
     "Public 'Register' button hides immediately; prevents late entries."),
    ("TC-CREATOR-047", "Cancel Category with Zero Entrants", "Host Owner (D1)", "Event Row > Overflow Menu",
     "Empty category.",
     "1. Tap overflow menu ⋮ on event row.\n2. Tap 'Cancel Event'.\n3. Confirm dialog.",
     "Row marked with red 'Cancelled' chip.",
     "Competition.status set to 'cancelled'.",
     "Zero notifications sent since entrant list is empty."),
    ("TC-CREATOR-048", "Cancel Category with 8 Active Entrants - Reason Prompt", "Host Owner (D1)", "Event Row > Overflow Menu",
     "8 registered players in Chess Rapid.",
     "1. Tap ⋮ > 'Cancel Event'.\n2. Dialog prompts for reason.",
     "Modal dialog with mandatory text box appears.",
     "Action blocked if reason text box is blank.",
     "Entering reason enables 'Confirm Cancellation' button."),
    ("TC-CREATOR-049", "Cancel Category - Cloud Function Notification Dispatch", "Host Owner (D1)", "Cancel Dialog",
     "Reason: 'Severe thunderstorm warning'.",
     "1. Type reason.\n2. Tap 'Confirm Cancellation'.",
     "Dialog closes; status badge turns red 'CANCELLED'.",
     "Cloud Function onEventCancelled dispatches push notifications to all 8 entrants.",
     "Inboxes updated with cancellation notice."),
    ("TC-CREATOR-050", "Cancel Category - Schedule Timetable Removal", "Host Owner (D1)", "Schedule Screen",
     "Fixtures previously scheduled for cancelled event.",
     "1. Open TournamentScheduleScreen.",
     "Cancelled event fixtures removed from active timetable; court slots freed up.",
     "Fixture statuses set to 'cancelled'.",
     "Freed court slots become available for other sports."),
    ("TC-CREATOR-051", "Re-open Cancelled Event Protection", "Host Owner (D1)", "Event Row",
     "Event is marked cancelled.",
     "1. Inspect event row controls.",
     "'Open Registrations' and 'Build Draw' buttons are permanently disabled.",
     "Status cannot be flipped back to open to avoid inconsistent state.",
     "Organizer must create fresh category if event is reinstated."),
    ("TC-CREATOR-052", "Delete Draft Event Permanently", "Host Owner (D1)", "Event Row > Overflow",
     "Event in draft with 0 registrations.",
     "1. Tap ⋮ > 'Delete Event'.\n2. Confirm delete.",
     "Row completely vanishes from UI.",
     "Document deleted from Firestore.",
     "Only allowed when entrant count is 0."),
    ("TC-CREATOR-053", "Delete Guard - Active Registrations Block", "Host Owner (D1)", "Event Row > Overflow",
     "Event has 5 registrations.",
     "1. Tap ⋮ > observe options.",
     "'Delete Event' option is hidden or disabled; only 'Cancel Event' is offered.",
     "Prevents accidental data deletion with registered users.",
     "Audit trail preserved."),
    ("TC-CREATOR-054", "Sport Tab Auto-Removal when All Categories Removed", "Host Owner (D1)", "Organizer Desk",
     "Basketball has only 1 event, which is deleted.",
     "1. Delete last Basketball event.",
     "Basketball tab disappears from sports navigation bar.",
     "tournament.sportCount decrements by 1.",
     "Clean UI with no empty sport tabs."),
    ("TC-CREATOR-055", "Event List Re-ordering by Drag and Drop", "Host Owner (D1)", "Organizer Desk > Events",
     "3 categories listed.",
     "1. Long press drag handle on Event 3.\n2. Drag to top position.",
     "Event 3 snaps to position 1; smooth reorder animation.",
     "displayOrder index updated in database.",
     "Order preserved across all devices.")
]
for item in c1_4: tc(*item)

print("Part 1: Suites 1.1 - 1.4 written")
