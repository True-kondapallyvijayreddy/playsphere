# PlaySphere — Complete Product, Functional, UX, Architecture, Data & QA Specification

**Document type:** Master Product Requirements + Functional Specification + UX/UI Specification + Domain Model + Technical Architecture + Statistics Architecture + QA/Test Strategy  
**Product:** PlaySphere  
**Audience:** Product, Founders, UI/UX, Flutter/mobile developers, backend developers, Firebase engineers, data engineers, DevOps, QA, automation QA, sports operations, tournament administrators, club administrators, support and analytics teams  
**Status:** Master working specification  
**Version:** 1.0  
**Date:** 11 August 2026  
**Primary design reference:** The PlaySphere UI reference supplied by the product owner in the current product discussion

---

# 1. Executive Summary

PlaySphere is intended to become a **multi-sport sports operating system**, not merely a tournament registration application.

The platform must support the complete lifecycle of sports participation:

- A person who has just installed the app and does not belong to any club.
- A person who wants to discover sports people nearby.
- A person who wants to discover and join a club.
- A person who wants to discover a team.
- A person who wants to participate individually.
- A group of friends who want to create a team without belonging to a club.
- A club owner who manages a large membership.
- A club with many teams per sport.
- A club that creates temporary teams for a specific competition.
- A tournament organizer.
- A multi-sport season organizer.
- A team manager.
- A captain.
- A scorer.
- An umpire/referee/official.
- A player.
- A casual community organizer.
- A user who simply wants to find a match nearby and play.

The system must connect all of these experiences through a common Match and Scorecard architecture.

The most important architectural principle is:

> **Identity, organization, participation, competition and match execution are separate concepts.**

A person is not a team.

A team is not necessarily a club.

A club is not a competition.

A competition is not a match.

An activity is not automatically a match.

A match is the actual sporting execution unit.

A scorecard is the canonical record of what happened in a match.

Statistics are derived from finalized match events.

---

# 2. Core Product Philosophy

PlaySphere must solve two very different sports problems.

## 2.1 Formal sports

Examples:

- Multi-sport seasons
- Cricket tournaments
- Football tournaments
- School competitions
- Corporate sports leagues
- Club championships
- Inter-club competitions
- Knockout tournaments
- League competitions

These require:

- Registration
- Eligibility
- Teams
- Rosters
- Formats
- Fixtures
- Officials
- Scheduling
- Scorecards
- Results
- Leaderboards
- Statistics

## 2.2 Informal/community sports

Examples:

> "Who is free Sunday at 2:30 for cricket?"

Today this often happens in:

- WhatsApp groups
- Telegram groups
- Phone calls
- Informal spreadsheets

PlaySphere should convert this into:

```text
Create Activity
        ↓
Post to Club / Community
        ↓
Members respond
YES / MAYBE / NO
        ↓
Organizer sees availability
        ↓
Participants confirmed
        ↓
Teams formed
        ↓
Match created
        ↓
Scorecard
        ↓
Player statistics
```

These two worlds must coexist.

---

# 3. The Central PlaySphere Model

The platform should be understood as seven layers.

```text
LAYER 1 — IDENTITY
Users / Players

LAYER 2 — ORGANIZATION
Clubs / Communities / Teams

LAYER 3 — DISCOVERY
Sports / Nearby Clubs / Nearby Players / Activities

LAYER 4 — PARTICIPATION
Individual / Team / Event Team / Pair / Club

LAYER 5 — COMPETITION & ACTIVITIES
Season / Tournament / Challenge / Club Activity

LAYER 6 — MATCH EXECUTION
Match / Officials / Scorecard / Events

LAYER 7 — RECORDS
Statistics / Rankings / Leaderboards / History
```

The dependency is:

```text
IDENTITY
   ↓
ORGANIZATION
   ↓
PARTICIPATION
   ↓
COMPETITION / ACTIVITY
   ↓
MATCH
   ↓
SCORECARD
   ↓
EVENTS
   ↓
STATISTICS
   ↓
LEADERBOARDS / CAREER
```

---

# 4. Fundamental Architectural Rules

These rules should be treated as product-level invariants.

## Rule 1 — User identity is permanent

A user must have a stable User ID.

## Rule 2 — Player identity is separate from user identity

A User may become a Player.

A Player may have sports-specific profiles.

## Rule 3 — Club membership is not the same as player identity

A player may belong to:

- zero clubs
- one club
- multiple clubs, if product policy allows

## Rule 4 — Team is independent of club

A team may:

- belong to a club
- have no club
- be permanent
- exist only for a competition

## Rule 5 — Club is optional for participation

A player must not be forced to join a club before participating in an eligible competition.

## Rule 6 — Competition defines participation rules

A competition determines whether participation is:

- Individual
- Pair
- Team
- Event Team
- Club/team registration

## Rule 7 — Event Team is supported

An event team can be created for one season/tournament/activity without becoming a permanent team.

## Rule 8 — Activity is separate from Match

A Club Activity coordinates people.

A Match records actual sporting competition.

## Rule 9 — Match is the atomic execution entity

Every actual game that produces a score/result must have a Match entity.

## Rule 10 — Every Match has an independent lifecycle

Starting Match A must never start Match B.

## Rule 11 — Multiple matches can run simultaneously

Example:

```text
Cricket Match A = LIVE
Cricket Match B = LIVE
Badminton Match C = LIVE
Football Match D = LIVE
```

## Rule 12 — Scorecard is canonical

The scorecard/event stream is the source for match statistics.

## Rule 13 — Statistics are derived

Do not manually maintain career counters from random UI operations.

## Rule 14 — Finalization is the official boundary

Live statistics can be provisional.

Finalized statistics become official.

## Rule 15 — Player history is persistent

A player's eligible performance should remain connected to their permanent Player ID regardless of whether the match came from:

- Season
- Tournament
- Challenge
- Club activity
- Standalone match

## Rule 16 — Historical records are traceable

Every statistic must be traceable:

```text
Career statistic
→ competition statistic
→ match statistic
→ scorecard
→ event
```

---

# 5. Primary Entities

The system must define these entities independently.

## 5.1 User

Authenticated PlaySphere account.

Responsibilities:

- Login
- Profile
- Permissions
- Notifications
- Settings
- Membership
- Role assignments

## 5.2 Player

Persistent sporting identity.

Attributes may include:

- Player ID
- Display name
- Profile photo
- Sports
- Preferred positions/roles
- Skill information
- Location/area
- Availability preferences
- Discoverability
- Verification

## 5.3 Club

Organization/group.

A club can contain:

- Members
- Administrators
- Teams
- Sports
- Activities
- Matches
- Competitions
- Statistics

## 5.4 Community

A lighter social/sports group that may not have the formal organizational structure of a club.

Example:

> Bangalore Sunday Cricket Community

A community can publish activities and connect players.

## 5.5 Team

A group that participates as a team.

Team types:

- Permanent
- Event
- Activity

## 5.6 Pair

Required for sports such as:

- Badminton doubles
- Tennis doubles
- Table tennis doubles

## 5.7 Sport

Examples:

- Cricket
- Badminton
- Football
- Volleyball
- Basketball
- Tennis
- Table Tennis
- Kabaddi
- Chess
- Carrom
- Kho-Kho

## 5.8 Competition

Generic competition container.

Subtypes:

- Season competition
- Tournament
- League
- Cup
- Custom competition

## 5.9 Season

A high-level multi-sport or multi-competition container.

Example:

> Hyderabad Sports Season 2026

## 5.10 Tournament

Normally a single-sport competition.

Example:

> Hyderabad Champions Cup 2026 — Cricket

## 5.11 Activity

A social/community coordination event.

Example:

> Sunday Cricket — 16 Aug — 2:30 PM

## 5.12 Challenge

A proposal between teams/players to play a match.

## 5.13 Match

Actual sporting execution.

## 5.14 Scorecard

Canonical match scoring record.

## 5.15 Match Event

Atomic scoring event.

## 5.16 Official

Person assigned to officiate or score a match.

## 5.17 Registration

A participant's request/registration to participate in a competition.

## 5.18 Roster

The players associated with a team for a particular context.

## 5.19 Statistics Record

Derived performance data.

## 5.20 Leaderboard

Ranking projection for a defined scope.

---

# 6. User Types and Personas

## 6.1 New user with no sports network

Scenario:

> User relocated to Bangalore and knows nobody.

Needs:

- Nearby clubs
- Nearby communities
- Nearby teams
- Nearby activities
- People who play selected sports
- Ability to join without an existing club

## 6.2 Individual player

Participates in:

- Singles
- Doubles
- Team competitions
- Challenges
- Activities
- Standalone matches

## 6.3 Club owner

Manages:

- Club
- Members
- Teams
- Activities
- Competitions
- Club statistics
- Permissions

## 6.4 Club admin

Operational management.

## 6.5 Team manager

Manages:

- Roster
- Team registration
- Match participation

## 6.6 Captain

Match/team leadership.

## 6.7 Scorer

Records match events.

## 6.8 Official

Verifies/controls match according to sport.

## 6.9 Organizer

Creates and administers competitions.

## 6.10 Casual activity organizer

Creates a Sunday game or community activity.

---

# 7. Role-Based Access Control

Membership and roles must be separate.

A person may simultaneously be:

```text
Rahul
├── Club Member
├── Cricket Player
├── Team Captain
└── Tournament Scorer
```

Another user:

```text
Vijay
├── Club Owner
├── Tournament Organizer
└── Team Manager
```

Recommended roles:

| Role | Club | Team | Competition | Match | Scoring | Statistics |
|---|---|---|---|---|---|---|
| Platform Admin | Full | Full | Full | Full | Full | Full |
| Club Owner | Full | Full | Manage | Manage | Configure | Full |
| Club Admin | Full | Full | Manage | Manage | Configure | Full |
| Team Manager | View | Full | Register | Manage | Limited | Team |
| Captain | View | Manage | Participate | View | Limited | Team |
| Member | View | View | Participate | View | No | Personal |
| Player | View | View | Participate | Play | No | Personal |
| Scorer | Assigned | Assigned | Assigned | Assigned | Full | Match |
| Official | View | View | Assigned | Assigned | Verify | Match |
| Viewer | Public | Public | Public | View | No | Public |

---

# 8. New User Onboarding

The first-time experience must not assume club membership.

## 8.1 Welcome

```text
Welcome to PlaySphere

All Sports. One Space.
```

Actions:

- Create account
- Login

## 8.2 Sports selection

```text
What sports do you play?

☐ Cricket
☐ Badminton
☐ Football
☐ Volleyball
☐ Basketball
☐ Tennis
☐ Table Tennis
☐ Kabaddi
☐ Chess
...
```

Allow multiple selections.

## 8.3 Location

```text
Where do you play?

[ Use my current location ]

OR

[ Enter city / area ]
```

Location is optional but strongly useful for discovery.

## 8.4 Intent

Ask:

```text
What are you looking for?

☑ Play sports
☑ Find people
☑ Join a club
☐ Join a team
☐ Create a team
☐ Organize matches
☐ Organize tournaments
```

## 8.5 Personalized home

The app should immediately show:

- Nearby clubs
- Nearby communities
- Nearby teams
- Nearby activities
- Live matches
- Upcoming sports activities

---

# 9. Location and Discovery

## 9.1 Location principle

PlaySphere should use location to improve discovery, not to expose precise user locations publicly.

Never display a user's exact home location.

Use:

- Area
- Neighborhood
- City
- Approximate distance

Examples:

```text
1.8 km away
Koramangala
Bangalore
```

## 9.2 Location permission

```text
Find sports near you

PlaySphere uses your location to find
clubs, teams and activities nearby.

[ Allow Location ]

[ Enter Location Manually ]
```

## 9.3 Permission denied

Allow manual location.

Do not block the app.

---

# 10. Join Club / Find Club

The "Join Club" experience must provide multiple entry points.

```text
JOIN A CLUB

Already know your club?
[ Search Club ]

[ Enter Club Code ]

OR

📍 Find Clubs Around Me

[ Find Nearby Clubs ]

OR

🔎 Browse Clubs
```

---

# 11. Nearby Clubs

## 11.1 List view

Each club card:

- Club logo
- Club name
- Sports
- Approximate distance
- Area
- Member count
- Verification status
- Join status

Example:

```text
Bangalore Strikers
Cricket • Football
1.8 km away
86 members

[ View Club ]
```

## 11.2 Map view

Show approximate club locations.

Tap marker → preview card.

## 11.3 Filters

- Sport
- Distance
- Club type
- Open membership
- Verified
- Activity frequency
- Age category
- Gender/category where relevant and lawful

---

# 12. Nearby Teams

A user with no club may discover:

```text
Bangalore Strikers
8 members
Cricket
Looking for 2 players
2.3 km
```

Actions:

- View team
- Request to join
- Contact through platform mechanisms
- View upcoming activities

---

# 13. Nearby Players

This feature must be privacy-controlled.

Search by:

- Sport
- Area
- Approximate distance
- Skill level
- Availability
- Looking for team
- Looking for players

Never expose exact location without explicit consent.

---

# 14. Nearby Activities

This is a key discovery surface.

Example:

```text
Sunday Cricket
Sunday 2:30 PM
2.4 km
14 going
```

Actions:

- View
- Interested
- Join
- Request participation

---

# 15. Club Model

A club is an organization, not a single team.

Example:

```text
Hyderabad Warriors Club

Cricket
├── Warriors A
├── Warriors B
├── Warriors U19
└── Warriors Veterans

Football
├── Warriors FC A
├── Warriors FC B
└── Warriors U19

Badminton
├── Senior
└── Junior
```

A club may have any number of teams subject to product/business limits.

---

# 16. Club Creation

Fields:

- Club name
- Logo
- Cover image
- Description
- Primary location
- Sports
- Membership type
- Public/private
- Contact
- Rules
- Verification documents where required

Membership types:

- Open
- Approval required
- Invite only
- Private

---

# 17. Club Membership

Membership lifecycle:

```text
NOT_MEMBER
 ↓
REQUESTED
 ↓
PENDING
 ↓
APPROVED
 ↓
ACTIVE_MEMBER
```

Other states:

```text
REJECTED
LEFT
REMOVED
SUSPENDED
```

## 17.1 Invite member

Club admin:

```text
Members
 ↓
Invite
 ↓
Search player
 ↓
Send invitation
```

## 17.2 Join request

Player:

```text
Club
 ↓
Request to Join
 ↓
Pending
```

Club owner/admin:

```text
Request
 ↓
View player
 ↓
Approve / Reject
```

---

# 18. Club Member Profile

Club administrators may see:

- Player name
- Sports
- Membership status
- Teams
- Role
- Participation history
- Relevant club statistics

Privacy settings determine what is visible.

---

# 19. Permanent Team

A permanent team exists beyond one competition.

Example:

```text
Warriors Cricket Team
```

Can participate in:

- Tournament A
- Tournament B
- Season
- Challenge
- Club activity
- Friendly match

Team attributes:

- Team ID
- Name
- Sport
- Club ID optional
- Captain
- Manager
- Roster
- Status

---

# 20. Independent Team

A team does not require a club.

Example:

```text
Hyderabad Strikers
```

Members:

- Rahul
- Karthik
- Vikram
- Suresh

It can participate directly in tournaments.

---

# 21. Event Team

Event team solves the registration problem for clubs.

Example:

Club has 64 cricket members.

Tournament allows 18 players/team.

Owner can:

```text
Register Team
 ↓
Create Team for this Competition
 ↓
Select available members
 ↓
Create Warriors A
 ↓
Submit registration
```

The event team is linked to:

- Competition
- Optional club
- Selected players
- Sport

It need not become a permanent team.

---

# 22. Permanent Team vs Event Team

## Permanent

```text
CREATE
 ↓
ACTIVE
 ↓
MULTIPLE COMPETITIONS
 ↓
ONGOING
```

## Event

```text
CREATE FOR COMPETITION
 ↓
REGISTER
 ↓
APPROVED
 ↓
PARTICIPATE
 ↓
COMPETITION ENDS
 ↓
HISTORICAL
```

Historical data must remain available.

---

# 23. Competition Participation Models

Every competition must define allowed participant types.

Possible:

```text
INDIVIDUAL
TEAM
EVENT_TEAM
PAIR
CLUB
```

Examples:

### Cricket

```text
TEAM
EVENT_TEAM
```

### Badminton Singles

```text
INDIVIDUAL
```

### Badminton Doubles

```text
PAIR
```

### Football

```text
TEAM
EVENT_TEAM
```

### Chess

```text
INDIVIDUAL
```

---

# 24. Competition Registration

Introduce a dedicated `CompetitionRegistration` concept.

It records:

- Competition ID
- Participant type
- Participant ID
- Team ID
- Event team ID
- Club ID
- Registered by
- Registration status
- Approval status
- Registration timestamp
- Payment status if applicable

---

# 25. Tournament Registration UI

Example:

```text
REGISTER FOR
Hyderabad Champions Cup

Sport: Cricket

How do you want to participate?

[ Existing Team ]

[ Create Team for this Competition ]

[ Register through Club ]
```

The exact choices depend on tournament rules.

---

# 26. Club Registration

Club owner sees:

```text
REGISTER CLUB

Hyderabad Warriors

Existing Teams
○ Warriors Cricket Team

Create Event Teams
○ Create Warriors A
○ Create Warriors B
```

If tournament permits multiple teams:

```text
Maximum teams per club = 2
```

System must prevent a third registration.

---

# 27. Available Member Pool

The club owner should see:

```text
CRICKET MEMBERS

Total: 64

Available: 38
Already assigned: 14
Unavailable: 12
```

Availability can be competition-specific.

---

# 28. Player Assignment Rules

When selecting players, system must validate:

- Membership
- Sport
- Age category
- Gender/category where applicable
- Registration status
- Competition eligibility
- Existing assignment
- Transfer restrictions
- Maximum roster
- Minimum roster
- Suspensions
- Duplicate assignment

---

# 29. Duplicate Player Prevention

Example:

```text
Rahul
Already registered with Warriors A
```

Attempting to add Rahul to Warriors B should be rejected if the competition rule is:

> One player can participate for only one team.

If transfers are allowed, use a formal transfer/replacement workflow.

---

# 30. Club Activity

Club Activity is a first-class entity.

Purpose:

> Coordinate informal or internal sporting activities before creating a Match.

Examples:

- Sunday cricket
- Friday badminton
- Morning football
- Evening volleyball
- Practice game
- Friendly match
- Open play
- Training session

---

# 31. Club Activity Lifecycle

```text
DRAFT
 ↓
PUBLISHED
 ↓
RESPONSES_OPEN
 ↓
RESPONSES_CLOSED
 ↓
PARTICIPANTS_CONFIRMED
 ↓
MATCH_CREATED
 ↓
COMPLETED
```

An activity can also be:

```text
CANCELLED
POSTPONED
```

---

# 32. Create Club Activity

## Step 1 — Activity details

Fields:

- Sport
- Activity type
- Title
- Description

Examples:

```text
Sunday Cricket
```

Activity types:

- Match
- Friendly
- Practice
- Training
- Open Play
- Social Game

---

# 33. Activity Date and Time

Fields:

- Date
- Start time
- End time
- Response deadline
- Time zone

Example:

```text
Sunday, 16 Aug
2:30 PM – 5:30 PM
Responses close at 12:00 PM
```

---

# 34. Activity Venue

Fields:

- Venue
- Court/ground
- Address
- Map
- Venue status

Venue may initially be:

```text
To be decided
```

and updated later.

---

# 35. Activity Audience

Creator chooses:

```text
Entire Club
Sport Members
Specific Team
Selected Members
Community
```

Example:

```text
Post to:
Cricket Members
```

This avoids sending football members a cricket poll unnecessarily.

---

# 36. Activity Feed Card

Members see:

```text
🏏 Sunday Cricket

Hyderabad Warriors Club

Sunday, 16 Aug
2:30 PM – 5:30 PM
Green Field Ground

18 Yes
7 Maybe
22 No

Are you available?

[ YES ] [ MAYBE ] [ NO ]
```

---

# 37. Activity Response Model

Every invited member has:

```text
YES
MAYBE
NO
NO_RESPONSE
```

A response contains:

- User ID
- Player ID if applicable
- Activity ID
- Response
- Timestamp
- Last updated timestamp

---

# 38. Organizer Activity Dashboard

Show:

```text
YES              18
MAYBE             7
NO                22
NO RESPONSE      17
```

Also:

- Minimum required
- Maximum participants
- Current expected count
- Response deadline
- Participation trend

---

# 39. Participant Lists

Tabs:

```text
YES
MAYBE
NO
NO RESPONSE
```

Each participant can show:

- Name
- Sport
- Player profile
- Team
- Availability status
- Organizer notes if permitted

---

# 40. Activity to Match Conversion

When enough players are confirmed:

```text
Create Match
```

System creates:

```text
Match
sourceType = CLUB_ACTIVITY
sourceId = Activity ID
```

The Activity remains as the coordination history.

The Match becomes the sporting record.

---

# 41. Event Team Formation for Activities

For 18 players:

```text
Auto Balance Teams
```

or:

```text
Manual Team Formation
```

Possible:

```text
Warriors Red
Warriors Blue
```

These are event teams.

They do not need to become permanent club teams.

---

# 42. Activity Participation Confirmation

Before Match creation:

```text
CONFIRM PARTICIPANTS

18 confirmed

☑ Rahul
☑ Karthik
☑ Vikram
...

[ Create Match ]
```

Optional replacement:

```text
Replace Player
```

If a player changes from YES to NO after teams are formed, organizer should receive a warning.

---

# 43. Match Creation Sources

There are four primary paths.

## Path A — Season

```text
Season
 ↓
Competition
 ↓
Schedule
 ↓
Match
```

## Path B — Tournament

```text
Tournament
 ↓
Fixture
 ↓
Match
```

## Path C — Challenge

```text
Team/Player
 ↓
Challenge
 ↓
Accept
 ↓
Match
```

## Path D — Activity

```text
Club/Community
 ↓
Activity
 ↓
Availability
 ↓
Participants
 ↓
Event Teams
 ↓
Match
```

## Path E — Standalone

```text
Create Match
 ↓
Participants
 ↓
Match
```

---

# 44. Challenge Flow

```text
Find Team
 ↓
Challenge Team
 ↓
Propose date/time/venue/rules
 ↓
Opponent accepts/rejects/counter-offers
 ↓
Match created
```

Challenge can be:

- Team vs Team
- Player vs Player
- Pair vs Pair

depending on sport.

---

# 45. Match as Atomic Execution Unit

A Match contains:

- Match ID
- Sport
- Source
- Competition/activity
- Participants
- Schedule
- Venue
- Officials
- Ruleset
- Scoring engine
- Scorecard
- Events
- Result
- Status
- Audit trail

---

# 46. Match Lifecycle

Recommended:

```text
DRAFT
 ↓
SCHEDULED
 ↓
OFFICIALS_ASSIGNED
 ↓
READY
 ↓
LIVE
 ↓
PAUSED
 ↓
LIVE
 ↓
ENDED
 ↓
PENDING_VERIFICATION
 ↓
FINALIZED
```

Terminal states:

```text
CANCELLED
POSTPONED
ABANDONED
NO_RESULT
```

---

# 47. Match Day

Match Day is a collection of independent Matches.

Example:

```text
25 May 2026

CRICKET
M001 LIVE
M002 LIVE
M003 UPCOMING

BADMINTON
M004 LIVE
M005 LIVE
M006 COMPLETED
M007 LIVE

FOOTBALL
M008 LIVE
M009 UPCOMING
```

There is no single "current match."

---

# 48. Match Day UI

Header:

```text
MATCH DAY
25 MAY 2026
```

Sport filters:

```text
All
Cricket
Badminton
Football
Volleyball
Basketball
```

Status filters:

```text
All
Live
Upcoming
Completed
Postponed
Cancelled
```

Every Match Card opens its own Match Center.

---

# 49. Concurrent Match Requirement

This is a critical requirement.

If:

```text
Cricket Match A = LIVE
Cricket Match B = LIVE
Badminton Match C = LIVE
Football Match D = LIVE
```

the system must allow independent scoring.

Updating Match A must not:

- Change Match B
- Change Match C
- Change Match D
- Start other matches
- Finalize other matches

---

# 50. Match Center

Tabs:

```text
Overview
Teams / Players
Officials
Scorecard
Commentary
Stats
Info
```

Header:

- Participants
- Competition/activity
- Sport
- Match ID
- Date/time
- Venue
- Status

---

# 51. Officials

Official roles depend on sport.

Cricket:

- Umpire
- Scorer
- Additional official

Football:

- Referee
- Assistant referee
- Fourth official
- Scorer

Badminton:

- Umpire
- Service judge
- Line judge
- Scorer

---

# 52. Assign Officials Flow

```text
Match Center
 ↓
Assign Officials
 ↓
Select Role
 ↓
Search official
 ↓
Check availability
 ↓
Assign
 ↓
Official accepts
 ↓
Confirmed
```

Do not allow scheduling conflicts unless the official explicitly supports multiple simultaneous assignments.

---

# 53. Match Ready

Show:

```text
Warriors A
vs
Titans

Officials
Umpire: Suresh
Scorer: Harish

Venue
Ground 1

Rules
20 Overs
```

Button:

```text
START MATCH
```

---

# 54. Start Match

Only this Match becomes:

```text
LIVE
```

Other matches retain their states.

---

# 55. Universal Scorecard

The Scorecard has a common shell and sport-specific engine.

Common:

- Live score
- Participants
- Match state
- Events
- Commentary
- Officials
- Stats
- Result

Sport-specific:

- Event types
- Rules
- Aggregations
- Result logic

---

# 56. Cricket Scoring

Core event types:

- Dot ball
- 1
- 2
- 3
- 4
- 6
- Wide
- No-ball
- Bye
- Leg bye
- Wicket
- Run out
- Stumping
- Catch
- Bowled
- LBW
- Retired hurt
- Review where supported
- Over completion
- Innings completion

Store:

- Batter
- Non-striker
- Bowler
- Runs
- Extras
- Wicket
- Dismissed player
- Fielder
- Over
- Ball
- Timestamp
- Scorer
- Sequence number

---

# 57. Cricket Derived Statistics

Examples:

Batting:

- Runs
- Balls
- Strike rate
- Fours
- Sixes
- Dots
- Boundaries

Bowling:

- Overs
- Runs conceded
- Wickets
- Economy
- Maidens
- Dot balls

Fielding:

- Catches
- Run outs
- Stumpings

Team:

- Runs
- Wickets
- Overs
- Run rate
- Required run rate
- Target
- Result
- NRR contribution

---

# 58. Badminton Scoring

Event:

```text
Rally winner
```

Derived:

- Points
- Games
- Match result
- Point differential
- Game differential
- Win rate

Rules must support configurable scoring formats.

---

# 59. Football Scoring

Events:

- Goal
- Assist
- Own goal
- Yellow card
- Red card
- Substitution
- Penalty
- Missed penalty
- Foul
- Offside
- Period start/end
- Extra time

Derived:

- Goals
- Assists
- Cards
- Minutes
- Result
- Goal difference

---

# 60. Sport Engine Architecture

Each sport should implement a standard interface.

```text
Sport
 ↓
Ruleset
 ↓
Scoring Engine
 ↓
Statistics Engine
 ↓
Leaderboard Engine
```

Example:

```text
Cricket
→ Cricket Rules
→ Cricket Scoring Engine
→ Cricket Statistics Engine
→ Cricket Leaderboard
```

The common Match Engine owns lifecycle and permissions.

---

# 61. Score Event Validation

Every event must be validated.

Examples:

Cricket:

- No ball after innings complete.
- Invalid wicket rejected.
- Invalid over transition rejected.

Badminton:

- No points after match finalization.
- Game transition follows rules.

Football:

- Player must be part of match squad.
- Event timestamp must be valid.
- Match must be live.

---

# 62. Undo and Corrections

Never silently erase an official history.

Maintain:

```text
Original event
Correction event
User
Timestamp
Reason
```

Example:

```text
Event 103 = 4 runs
Correction = 6 runs
```

The system recalculates downstream projections.

---

# 63. Offline Scoring

Scorer may lose network connectivity.

Required:

```text
Local Event Queue
 ↓
Persistent Local Storage
 ↓
Network Restored
 ↓
Sync
 ↓
Server Validation
 ↓
Acknowledgement
```

UI states:

- Synced
- Syncing
- Offline
- Failed
- Conflict

Never lose a scoring event because of temporary connectivity loss.

---

# 64. Concurrency and Idempotency

If scorer taps twice due to latency, the backend must not create unintended duplicate events.

Use:

- Client event ID
- Sequence number
- Idempotency key
- Server acknowledgement

Finalization must also be idempotent.

---

# 65. Match End

Flow:

```text
END MATCH
 ↓
Calculate final result
 ↓
Show summary
 ↓
Submit
```

Example:

```text
Warriors CC 178/6
Titans SC 164/9

Warriors won by 14 runs.
```

---

# 66. Verification

If configured:

```text
Scorer submits
 ↓
Official reviews
 ↓
Approve
```

Possible:

- Approve
- Request correction
- Reject

---

# 67. Finalization

Finalization must:

1. Freeze scoring.
2. Freeze official result.
3. Calculate match statistics.
4. Calculate player statistics.
5. Calculate team statistics.
6. Update competition statistics.
7. Update season statistics.
8. Update club statistics.
9. Update player career statistics.
10. Update leaderboards.
11. Write audit record.
12. Publish final scorecard.

---

# 68. Statistics Architecture

```text
MATCH EVENTS
      ↓
EVENT VALIDATION
      ↓
MATCH AGGREGATION
      ↓
PLAYER MATCH STATS
      ↓
TEAM MATCH STATS
      ↓
COMPETITION STATS
      ↓
SEASON STATS
      ↓
CAREER STATS
```

Canonical source:

```text
Match Events
```

Derived projections:

```text
Stats
Leaderboards
Profiles
```

---

# 69. Player Statistics Scopes

Player statistics must support:

- Match
- Activity
- Tournament
- Season
- Club
- Sport
- Career

Example:

```text
Rahul Sharma

Career
128 matches
8,241 runs
184 wickets

Season 2026
24 matches
1,824 runs

HCC 2026
8 matches
642 runs

Last match
74 runs
2 wickets
```

---

# 70. Eligibility for Career Statistics

The platform must distinguish:

- Official competitive
- Friendly
- Practice
- Challenge
- Club activity
- Exhibition

A rules/configuration system determines whether each match category contributes to official career metrics.

Recommended separate views:

```text
Career Official
Career All Matches
Competitive
Friendly
```

---

# 71. Player History

Every Match should appear in appropriate player history.

Example:

```text
Tournament
74 runs
WIN

Season
51 runs
WIN

Challenge
42 runs
WIN

Club Activity
32 runs
LOSS
```

Each item links to the permanent Match record.

---

# 72. Team Statistics

Team statistics have context.

For permanent team:

```text
All-time
Season
Tournament
Recent
```

For event team:

```text
Competition only
```

Event-team statistics should not automatically contaminate permanent team statistics.

---

# 73. Club Statistics

Club can aggregate eligible results from:

- Permanent teams
- Event teams
- Individual members where applicable

But aggregation rules must be explicit.

---

# 74. Season Leaderboard

Multi-sport season should have Olympics-style views.

Example:

```text
Overall
Cricket
Football
Badminton
Volleyball
Basketball
```

Overall may include:

```text
Club
Gold
Silver
Bronze
Points
```

The exact medal/points rules are configurable.

---

# 75. Sport-wise Season Leaderboard

Example:

```text
CRICKET

Teams
Players
Batting
Bowling
Records
```

Badminton:

```text
Singles
Doubles
Players
Rankings
```

---

# 76. Tournament Leaderboard

Single-sport tournament can use an IPL-style structure.

Cricket:

- Points Table
- Batting
- Bowling
- All-rounders
- Fielding
- Team rankings
- Player rankings
- Records

---

# 77. Live vs Official Statistics

During live play:

```text
PROVISIONAL
```

After finalization:

```text
OFFICIAL
```

UI must clearly distinguish the two.

---

# 78. Recalculation and Reconciliation

Backend must support recalculation from canonical events.

Example:

```text
Recalculate Match
Recalculate Player
Recalculate Tournament
Recalculate Season
Rebuild Leaderboard
```

This allows correction without manual database edits.

---

# 79. Competition Formats

Support:

- League
- Round Robin
- Knockout
- League + Knockout
- Double Elimination
- Group Stage
- Custom

Configuration includes:

- Teams per group
- Matches per team
- Qualification
- Knockout rounds
- Points
- Tiebreakers

---

# 80. Schedule Generation

Inputs:

- Teams
- Players
- Format
- Dates
- Times
- Venue
- Courts/grounds
- Match duration
- Rest period
- Official availability

Validation:

- Team conflict
- Player conflict
- Venue conflict
- Official conflict
- Insufficient rest
- Court conflict
- Date boundary
- Competition window

---

# 81. Tournament Creation Flow

Six-step baseline:

```text
1. Details
2. Teams
3. Format
4. Schedule
5. Settings
6. Review
```

## Details

- Name
- Sport
- Logo
- Banner
- Dates
- Registration deadline
- Organizer
- Location
- Category
- Eligibility
- Fees
- Description

## Teams

- Existing team
- Create event team
- Club registration
- Independent team
- Approval

## Format

- League
- Knockout
- Groups
- Qualification
- Tiebreakers

## Schedule

- Match dates
- Times
- Venue
- Courts/grounds
- Officials
- Conflicts

## Settings

- Live scoring
- Result approval
- Rules
- Registration
- Eligibility
- Statistics
- Ranking

## Review

Complete summary before publishing.

---

# 82. Multi-Sport Season Creation

```text
1. Season Details
2. Sports
3. Competitions
4. Teams/Players
5. Venues
6. Schedule
7. Rules
8. Registration
9. Review
10. Publish
```

Multiple sports may operate simultaneously.

---

# 83. Season Example

```text
Hyderabad Sports Season 2026

Cricket
├── Warriors A
├── Warriors B
└── Titans

Football
├── Warriors FC
└── Titans FC

Badminton
├── Singles
├── Doubles

Chess
├── Individuals
```

All can have matches on the same day.

---

# 84. Match Day Architecture for Season

Example:

```text
25 MAY

Cricket
M001 LIVE
M002 LIVE
M003 LIVE

Badminton
M004 LIVE
M005 LIVE
M006 LIVE
M007 LIVE

Football
M008 LIVE
M009 UPCOMING
```

Each Match is independent.

---

# 85. Club Activity vs Tournament vs Challenge

## Club Activity

Purpose:

```text
Find who is available
```

Flow:

```text
Post
 ↓
YES/MAYBE/NO
 ↓
Participants
 ↓
Teams
 ↓
Match
```

## Tournament

Purpose:

```text
Organized competition
```

Flow:

```text
Registration
 ↓
Format
 ↓
Fixtures
 ↓
Matches
 ↓
Leaderboard
```

## Challenge

Purpose:

```text
Team/player proposes a match to another
```

Flow:

```text
Challenge
 ↓
Accept
 ↓
Match
```

---

# 86. Discovery-to-Participation Loop

A major PlaySphere growth loop:

```text
New User
 ↓
Select Sport
 ↓
Location
 ↓
Nearby Clubs
 ↓
Nearby Teams
 ↓
Nearby Activities
 ↓
Join / Interested
 ↓
Participate
 ↓
Match
 ↓
Scorecard
 ↓
Player Statistics
 ↓
Player discovers more activities
 ↓
Becomes active member
```

---

# 87. New Bangalore User Example

User relocates to Bangalore.

No club.

No team.

No friends.

Flow:

```text
Install
 ↓
Profile
 ↓
Select Cricket
 ↓
Location = Bangalore
 ↓
Find Nearby
 ↓
Nearby Clubs
 ↓
Nearby Teams
 ↓
Nearby Players
 ↓
Sunday Cricket Activity
 ↓
I'm Interested
 ↓
Organizer approves
 ↓
Player joins event
 ↓
Event team
 ↓
Match
 ↓
Scorecard
 ↓
Career statistics
```

This is one of PlaySphere's most important acquisition/use cases.

---

# 88. "Looking for Players"

Teams can publish:

```text
Bangalore Strikers
Looking for 2 cricket players

Preferred:
Bowler
All-rounder

Match:
Sunday 2:30 PM

Area:
Koramangala
```

A new user can:

```text
View
 ↓
Request to Join
 ↓
Team reviews profile
 ↓
Accept
 ↓
Player joins match/activity
```

---

# 89. Community Discovery

Communities are lighter than clubs.

Example:

```text
Bangalore Sunday Cricket
```

A community can:

- Publish activities
- Find players
- Host matches
- Build membership
- Create event teams
- Develop into a club if desired

---

# 90. Privacy and Discovery

Users must control:

- Whether discoverable
- Whether searchable
- Approximate area visibility
- Sports visibility
- Skill visibility
- Availability visibility
- Profile visibility

Do not expose:

- Exact home address
- Exact real-time location
- Sensitive personal information

---

# 91. Club Owner Dashboard

Main sections:

```text
Club Dashboard
├── Overview
├── Members
├── Teams
├── Sports
├── Activities
├── Matches
├── Competitions
├── Statistics
├── Notifications
└── Settings
```

---

# 92. Club Member Dashboard

Member sees:

```text
My Club
├── Feed
├── Activities
├── Teams
├── Matches
├── Members
└── Stats
```

A member can see activities and respond without having management rights.

---

# 93. Activity Feed

Club feed can contain:

- Activity posts
- Match results
- Upcoming matches
- Announcements
- Tournament registration
- Team announcements
- New member notices
- Achievement posts

---

# 94. Notifications

Examples:

### Club

- Join request
- Membership approved
- New activity
- Match scheduled
- Activity response deadline
- Tournament registration

### Player

- Team invitation
- Match selection
- Activity invitation
- Match reminder
- Result
- Ranking change

### Scorer

- Assignment
- Match starting soon
- Match changed

### Official

- Assignment
- Acceptance
- Match reminder
- Correction request

---

# 95. Match Notifications

Potential:

```text
Match starts in 1 hour
Match starts in 15 minutes
Match is live
Match paused
Match completed
Result finalized
```

Notification preferences must be configurable.

---

# 96. Data Model — Conceptual

Recommended core entities:

```text
users
players
playerSports
clubs
clubMembers
communities
communityMembers
teams
teamMembers
teamSports
sports
seasons
tournaments
competitions
competitionParticipants
competitionRegistrations
eventTeams
eventTeamMembers
pairs
activities
activityInvites
activityResponses
challenges
venues
matches
matchParticipants
matchOfficials
scorecards
matchEvents
matchResults
playerMatchStats
teamMatchStats
competitionStats
seasonStats
clubStats
playerCareerStats
leaderboards
notifications
auditLogs
```

---

# 97. User Entity

Conceptual:

```text
User {
  id
  name
  email/phone
  profilePhoto
  locationPreference
  privacySettings
  notificationSettings
  createdAt
  updatedAt
}
```

---

# 98. Player Entity

```text
Player {
  id
  userId
  displayName
  photo
  sports[]
  discoverability
  area
  verificationStatus
  createdAt
}
```

---

# 99. Club Entity

```text
Club {
  id
  name
  logo
  coverImage
  description
  location
  sports[]
  membershipMode
  visibility
  ownerId
  status
  verificationStatus
  createdAt
}
```

---

# 100. Team Entity

```text
Team {
  id
  name
  sportId
  clubId?
  type
  captainId?
  managerId?
  status
  createdAt
}
```

Team type:

```text
PERMANENT
INDEPENDENT
EVENT
```

---

# 101. Event Team Entity

```text
EventTeam {
  id
  competitionId?
  activityId?
  sportId
  clubId?
  baseTeamId?
  name
  captainId?
  roster[]
  status
}
```

---

# 102. Competition Registration

```text
CompetitionRegistration {
  id
  competitionId
  participantType
  participantId
  teamId?
  eventTeamId?
  clubId?
  registeredBy
  status
  submittedAt
  approvedAt?
}
```

---

# 103. Activity Entity

```text
Activity {
  id
  ownerId
  containerType
  containerId
  sportId
  activityType
  title
  description
  startTime
  endTime
  responseDeadline
  venueId?
  audienceType
  status
  createdAt
}
```

Container types:

```text
CLUB
COMMUNITY
TEAM
```

---

# 104. Activity Response

```text
ActivityResponse {
  id
  activityId
  userId
  playerId?
  response
  createdAt
  updatedAt
}
```

Response:

```text
YES
MAYBE
NO
NO_RESPONSE
```

---

# 105. Match Entity

```text
Match {
  id
  sportId
  sourceType
  sourceId
  competitionId?
  seasonId?
  tournamentId?
  activityId?
  challengeId?
  participants[]
  scheduledStart
  scheduledEnd
  actualStart?
  actualEnd?
  venueId?
  courtOrGroundId?
  status
  rulesetId
  scoringEngineId
  scorecardId
  resultId?
  createdBy
  createdAt
  updatedAt
}
```

---

# 106. Match Event

```text
MatchEvent {
  id
  matchId
  sequenceNumber
  eventType
  eventPayload
  actorUserId
  clientEventId
  clientTimestamp
  serverTimestamp
  version
  status
  correctionOfEventId?
}
```

---

# 107. Scorecard

```text
Scorecard {
  id
  matchId
  sportId
  state
  currentScore
  periodState
  eventCount
  version
  lastEventSequence
  finalizedAt?
  finalizedBy?
}
```

---

# 108. Official Assignment

```text
MatchOfficial {
  id
  matchId
  userId
  role
  status
  assignedBy
  assignedAt
  acceptedAt?
}
```

---

# 109. Statistics Data Model

Match-level:

```text
PlayerMatchStats
TeamMatchStats
```

Competition-level:

```text
CompetitionPlayerStats
CompetitionTeamStats
```

Season-level:

```text
SeasonPlayerStats
SeasonTeamStats
SeasonClubStats
```

Career:

```text
PlayerCareerStats
```

---

# 110. Firebase/Flutter Architecture

Assuming the existing PlaySphere stack uses Flutter/Firebase:

## Flutter

Responsible for:

- UI
- Navigation
- Form validation
- Local activity state
- Local score queue
- Real-time listeners
- Offline handling
- User interactions

## Firebase Authentication

- Identity
- Sessions
- Account security

## Firestore

- Users
- Players
- Clubs
- Teams
- Activities
- Competitions
- Matches
- Metadata
- Read projections

## Cloud Functions/backend

- Match finalization
- Statistics
- Leaderboards
- Notifications
- Reconciliation
- Validation
- Scheduled processing

## Storage

- Logos
- Banners
- Player photos
- Documents

---

# 111. Real-Time Architecture

Scoring flow:

```text
Scorer
 ↓
Local Event
 ↓
Backend
 ↓
Canonical Event
 ↓
Live Match Projection
 ↓
Viewers
```

Statistics:

```text
Finalization
 ↓
Statistics Processing
 ↓
Leaderboard Projection
```

---

# 112. Read Models

For high-traffic screens, maintain read-optimized projections:

- Live Match Summary
- Match Day Summary
- Leaderboard
- Player Summary
- Team Summary
- Club Summary

Canonical events remain authoritative.

---

# 113. Audit Trail

Audit every important operation.

Examples:

- Club created
- Member approved
- Team created
- Event team created
- Registration submitted
- Match scheduled
- Official assigned
- Score event entered
- Score corrected
- Match ended
- Result approved
- Match finalized
- Statistics recalculated
- Leaderboard rebuilt
- Membership removed

Audit fields:

```text
who
what
when
entity
entityId
before
after
reason
source
```

---

# 114. Security

Test/protect:

- Unauthorized score modification
- Unauthorized finalization
- Unauthorized member approval
- Unauthorized team roster modification
- Unauthorized competition editing
- Role escalation
- Cross-club data access
- Suspended account access
- Token expiry
- Deleted account access

---

# 115. Privacy

Default principle:

> Show the minimum information necessary for the sports experience.

Sensitive information must not be exposed to:

- Random club members
- Sponsors
- Other players
- Public users

unless appropriate consent/authorization exists.

Location is approximate.

---

# 116. QA Strategy

QA must cover:

1. UI
2. Functional
3. API
4. Integration
5. Data
6. Statistics
7. Concurrency
8. Security
9. Offline
10. Performance
11. Regression
12. Accessibility

---

# 117. Onboarding QA

Test:

- New user
- Existing user
- No sports selected
- Multiple sports
- Location allowed
- Location denied
- Manual location
- No nearby clubs
- Many nearby clubs
- Nearby team
- Nearby activity
- Privacy settings

---

# 118. Club QA

Test:

- Club creation
- Owner assignment
- Admin assignment
- Join request
- Approval
- Rejection
- Invite
- Removal
- Suspension
- Multiple sports
- Multiple teams
- Multiple event teams

---

# 119. Team QA

Test:

- Permanent team
- Independent team
- Event team
- Add player
- Remove player
- Captain
- Manager
- Duplicate player
- Player already in another event team
- Roster limits
- Eligibility

---

# 120. Activity QA

Test:

- Create activity
- Publish
- Invite audience
- YES
- MAYBE
- NO
- Change response
- Deadline
- Close responses
- Minimum players
- Maximum players
- Participant confirmation
- Team formation
- Match creation
- Cancellation
- Postponement

---

# 121. Competition Registration QA

Test:

- Individual registration
- Team registration
- Independent team
- Event team
- Club registration
- Pair registration
- Multiple club teams
- Maximum teams
- Duplicate registration
- Player duplication
- Eligibility
- Approval
- Withdrawal
- Replacement

---

# 122. Tournament QA

Test:

- All six wizard steps
- Save draft
- Resume draft
- Back navigation
- Format validation
- Team count
- Schedule
- Venue conflicts
- Official conflicts
- Publish
- Registration
- Fixture generation

---

# 123. Season QA

Test:

- Multiple sports
- Multiple competitions
- Multiple matches per sport
- Same-day scheduling
- Concurrent matches
- Sport-specific leaderboard
- Overall leaderboard
- Club points
- Medal/point rules
- Cross-sport participation

---

# 124. Match Day QA

Test:

```text
1 match
5 matches
10 matches
50 matches
100+ matches
```

Simultaneously:

```text
Cricket LIVE
Badminton LIVE
Football LIVE
Volleyball LIVE
```

Verify complete isolation.

---

# 125. Scorecard QA

For each sport:

- Start
- Score
- Undo
- Correction
- Pause
- Resume
- End
- Verify
- Finalize
- Reopen if allowed

---

# 126. Statistics QA

For every finalized Match:

```text
Match Score
=
Scorecard Aggregate
```

```text
Player Match Stats
=
Match Events
```

```text
Tournament Stats
=
Eligible Tournament Matches
```

```text
Season Stats
=
Eligible Season Matches
```

```text
Career Stats
=
Eligible Career Matches
```

---

# 127. Cross-Source Player QA

Create Rahul.

Have Rahul participate in:

```text
Tournament Match
Season Match
Challenge
Club Activity
Standalone Match
```

Finalize all.

Verify eligible career aggregation.

Then add an excluded practice match.

Verify career official statistics do not change if practice matches are excluded.

---

# 128. Concurrency QA

Use different scorers on:

```text
Match A
Match B
Match C
Match D
```

Verify:

- No cross-contamination
- No duplicate events
- No lost events
- Correct event sequence
- Correct statistics
- Correct leaderboards

---

# 129. Offline QA

```text
Online
 ↓
Score
 ↓
Network lost
 ↓
Score
 ↓
Network restored
 ↓
Sync
```

Verify exact final state.

---

# 130. Idempotency QA

Submit same event twice.

Expected:

```text
One canonical event
```

Submit finalize twice.

Expected:

```text
One finalization
No double statistics
No double points
```

---

# 131. Correction QA

Original:

```text
Rahul = 4
```

Correction:

```text
Rahul = 6
```

Verify all affected:

- Match
- Player match stats
- Tournament
- Season
- Career
- Leaderboard

---

# 132. Security QA

Test role escalation:

```text
Member → tries to become Admin
Scorer → tries to finalize
Viewer → tries to score
Team manager → edits unrelated team
Club admin → accesses another private club
```

All must be correctly blocked.

---

# 133. Performance QA

Load test:

- Hundreds of matches
- Thousands of players
- Large clubs
- Large member pools
- Large leaderboards
- Concurrent live scoring
- Large event streams

Measure:

- Screen latency
- Event write latency
- Live update latency
- Finalization time
- Statistics processing time
- Leaderboard update time

---

# 134. Error States

Every major screen must have:

- Loading
- Empty
- Error
- Offline
- Permission denied
- Not found
- Conflict
- Finalized/locked

Examples:

```text
No nearby clubs found.
```

```text
You don't have permission to score this match.
```

```text
This match has already been finalized.
```

```text
This player is already registered with another team.
```

---

# 135. Development Phases

## Phase 1

Foundation:

- Auth
- User
- Player
- Sports
- Discovery
- Location

## Phase 2

Organizations:

- Club
- Community
- Membership
- Roles
- Teams
- Event teams

## Phase 3

Activities:

- Club activity
- Availability
- YES/MAYBE/NO
- Participant confirmation
- Event team formation

## Phase 4

Competitions:

- Tournament
- Season
- Registration
- Format
- Scheduling

## Phase 5

Match Engine:

- Match
- Officials
- Lifecycle
- Match Center

## Phase 6

Cricket scoring:

- Live scorecard
- Events
- Corrections
- Finalization

## Phase 7

Statistics:

- Match
- Player
- Team
- Club
- Tournament
- Season
- Career

## Phase 8

Leaderboards.

## Phase 9

Additional sport engines.

---

# 136. Recommended First Vertical

Cricket should be the first complete end-to-end sport because it exercises:

- Event-level scoring
- Innings
- Overs
- Wickets
- Batting
- Bowling
- Fielding
- Extras
- Player roles
- Team statistics
- Points tables
- NRR
- Career records

Once this architecture is stable, other sports can implement the same common interfaces.

---

# 137. Definition of Done — Discovery

Complete when:

- New user can select sport.
- Location can be detected.
- Manual location works.
- Nearby clubs are displayed.
- Nearby teams are displayed.
- Nearby activities are displayed.
- Nearby players are discoverable according to privacy.
- User can request membership.
- User can request team participation.
- User can join an activity.

---

# 138. Definition of Done — Club

Complete when:

- Club can be created.
- Owner can be assigned.
- Members can join.
- Admins can manage members.
- Multiple sports can be configured.
- Multiple permanent teams can exist.
- Event teams can be created.
- Activities can be posted.
- Club statistics are available.

---

# 139. Definition of Done — Activity

Complete when:

- Activity can be created.
- Audience can be selected.
- Members receive it.
- YES/MAYBE/NO works.
- Organizer sees responses.
- Response deadline works.
- Participants can be confirmed.
- Teams can be formed.
- Match can be created.
- Activity remains historically linked.

---

# 140. Definition of Done — Tournament

Complete when:

- Tournament created.
- Sport configured.
- Participant type configured.
- Existing teams can register.
- Independent teams can register.
- Event teams can be created.
- Club can register multiple teams where allowed.
- Players can be selected.
- Duplicate players are prevented.
- Fixtures generated.
- Schedule released.
- Multiple matches can run.
- Leaderboard updates.

---

# 141. Definition of Done — Season

Complete when:

- Multiple sports selected.
- Multiple competitions created.
- Teams/players registered.
- Same-day multi-sport schedule supported.
- Multiple simultaneous matches supported.
- Sport-wise leaderboards work.
- Overall leaderboard works.
- Player statistics update.

---

# 142. Definition of Done — Match

Complete when:

- Match created from any supported source.
- Match independently scheduled.
- Officials assigned.
- Match started.
- Scorecard live.
- Events stored.
- Corrections work.
- Match ended.
- Verification works.
- Finalization works.
- Statistics update.
- Leaderboards update.
- Audit trail exists.

---

# 143. Definition of Done — Player

Complete when:

- Player has permanent ID.
- Player can participate without club.
- Player can join club.
- Player can join team.
- Player can form event team.
- Player can participate individually.
- Player can participate in doubles/pairs.
- Player can join activities.
- Player can play challenges.
- Player can see career statistics.
- Player can see all eligible match history.

---

# 144. Complete End-to-End Example

## Scenario

Rahul relocates to Bangalore.

He installs PlaySphere.

He knows nobody.

### Step 1

Creates account.

### Step 2

Selects:

```text
Cricket
Badminton
```

### Step 3

Allows location.

### Step 4

PlaySphere finds:

```text
12 cricket clubs
8 badminton clubs
17 teams
24 activities
```

### Step 5

Rahul sees:

```text
Sunday Cricket
2:30 PM
2.4 km
14 going
```

### Step 6

He taps:

```text
I'm Interested
```

### Step 7

Organizer reviews Rahul's profile.

### Step 8

Organizer accepts.

### Step 9

Rahul becomes participant.

### Step 10

Organizer forms:

```text
Red
Blue
```

### Step 11

PlaySphere creates Match.

### Step 12

Scorer opens scorecard.

### Step 13

Rahul scores 42 runs.

### Step 14

Match ends.

### Step 15

Result finalized.

### Step 16

Rahul's player profile updates.

```text
Club Activity
1 Match
42 Runs
```

### Step 17

Rahul sees another tournament.

He registers individually or joins a team.

His history continues from the same Player ID.

---

# 145. Formal Tournament Example

Club:

```text
Hyderabad Warriors
```

Members:

```text
64 Cricket Players
```

Tournament:

```text
Hyderabad Champions Cup
Maximum roster = 18
Maximum teams per club = 2
```

Club owner chooses:

```text
Create Event Team
```

Selects:

```text
Warriors A
18 players
```

Then:

```text
Create Event Team
Warriors B
18 players
```

The remaining 28 players stay available.

The tournament has:

```text
Warriors A
Warriors B
Titans
Rangers
Super Kings
```

Each team gets its own fixtures.

Every match is independent.

Every finalized match updates:

- Match statistics
- Event team statistics
- Tournament statistics
- Eligible player statistics
- Player career statistics

---

# 146. Multi-Sport Season Example

```text
Hyderabad Sports Season 2026
```

Cricket:

```text
Warriors A
Warriors B
Titans
```

Football:

```text
Warriors FC
Titans FC
```

Badminton:

```text
Rahul
Karthik
Rahul/Karthik
```

Chess:

```text
Rahul
Vikram
```

On the same date:

```text
10:00 Cricket M1 LIVE
10:00 Cricket M2 LIVE
10:00 Badminton M3 LIVE
10:00 Badminton M4 LIVE
10:00 Football M5 LIVE
10:00 Chess M6 LIVE
```

The Match Engine handles each independently.

The Season engine aggregates appropriately.

---

# 147. Final Master Architecture

```text
                                      PLAYSPHERE
                                          │
              ┌───────────────────────────┼───────────────────────────┐
              │                           │                           │
           DISCOVERY                  ORGANIZATION                 COMPETITION
              │                           │                           │
       ┌──────┼──────┐            ┌───────┼───────┐          ┌────────┼────────┐
       │      │      │            │       │       │          │        │        │
     Clubs  Teams  Players      Clubs  Teams Activities    Season Tournament Challenge
       │      │      │
       └──────┼──────┘
              │
              ▼
        PARTICIPATION
              │
    ┌─────────┼───────────┐
    │         │           │
Individual  Team      Event Team
    │         │           │
    └─────────┼───────────┘
              │
              ▼
            MATCH
              │
       ┌──────┼──────┐
       │      │      │
   Officials Rules Venue
              │
              ▼
          SCORECARD
              │
              ▼
        MATCH EVENTS
              │
              ▼
       STATISTICS ENGINE
              │
      ┌───────┼────────┐
      │       │        │
    Player   Team     Club
      │       │        │
      └───────┼────────┘
              │
      ┌───────┼───────────┐
      │       │           │
   Career   Season    Tournament
      │       │           │
      └───────┼───────────┘
              ▼
         LEADERBOARDS
```

---

# 148. Master Page Map

```text
HOME
│
├── SPORTS
│   └── SPORT DETAILS
│
├── DISCOVER
│   ├── Nearby Clubs
│   ├── Nearby Teams
│   ├── Nearby Players
│   └── Nearby Activities
│
├── CLUBS
│   ├── Club Search
│   ├── Club Details
│   ├── Join Club
│   ├── Members
│   ├── Teams
│   ├── Activities
│   ├── Matches
│   └── Statistics
│
├── TEAMS
│   ├── Team Search
│   ├── Team Details
│   ├── Join Team
│   ├── Looking for Players
│   └── Team Statistics
│
├── PLAYERS
│   ├── Player Search
│   ├── Player Profile
│   ├── Career
│   ├── Sports
│   ├── Match History
│   └── Rankings
│
├── ACTIVITIES
│   ├── Create Activity
│   ├── Activity Details
│   ├── Responses
│   ├── Participants
│   ├── Team Formation
│   └── Create Match
│
├── SEASONS
│   ├── Create Season
│   ├── Dashboard
│   ├── Registration
│   ├── Competitions
│   ├── Schedule
│   ├── Match Day
│   ├── Leaderboard
│   └── Sport Leaderboards
│
├── TOURNAMENTS
│   ├── Create Tournament
│   │   ├── Details
│   │   ├── Teams
│   │   ├── Format
│   │   ├── Schedule
│   │   ├── Settings
│   │   └── Review
│   ├── Dashboard
│   ├── Registration
│   ├── Fixtures
│   ├── Match Day
│   └── Leaderboards
│
├── CHALLENGES
│   ├── Create Challenge
│   ├── Challenge Details
│   ├── Counter Offer
│   └── Match
│
└── MATCHES
    ├── Live
    ├── Upcoming
    ├── Match Day
    ├── Match Center
    ├── Officials
    ├── Scorecard
    ├── Commentary
    ├── Stats
    ├── Verification
    └── Final Result
```

---

# 149. Non-Negotiable Product Rules

1. A user does not need a club to use PlaySphere.
2. A player does not need a team to participate in individual sports.
3. A team does not need a club.
4. A club can have multiple teams.
5. A club can have multiple teams for the same sport.
6. A club can create event teams for specific competitions.
7. An event team does not need to become a permanent team.
8. A player can be selected into an event team from the club member pool.
9. A competition must define allowed participant types.
10. A Club Activity is not the same as a Match.
11. Club Activities support YES/MAYBE/NO.
12. Activity participants can later become Match participants.
13. Match is the canonical sporting execution entity.
14. Every actual scored match gets a Scorecard.
15. Every Match can run independently.
16. Multiple Matches can be live simultaneously.
17. Multiple sports can have live matches simultaneously.
18. Officials are assigned per Match.
19. Scorecards are sport-specific but share a common lifecycle.
20. Statistics are derived from match events.
21. Finalization creates official statistics.
22. Player identity remains persistent across competitions.
23. Challenge matches can use the same Match Engine.
24. Standalone matches can use the same Match Engine.
25. Club activities can create matches.
26. Tournament fixtures create matches.
27. Season fixtures create matches.
28. Every statistic must be traceable to a Match.
29. Corrections must propagate to all affected projections.
30. Finalization must be idempotent.
31. Historical records must not disappear because a team or club changes name.
32. Privacy controls must protect precise location and personal information.
33. Roles and membership must be separate.
34. Permissions must be enforced server-side.
35. Live statistics must be distinguishable from official statistics.

---

# 150. Final Product Definition

PlaySphere should allow a person to enter the sports ecosystem from **any point**.

A person can say:

> "I just moved to Bangalore."

PlaySphere responds:

```text
Find sports around you
        ↓
Find people
        ↓
Find teams
        ↓
Find clubs
        ↓
Find activities
        ↓
Join something
        ↓
Play
        ↓
Score
        ↓
Build sports history
```

A club can say:

> "We have 200 members and want to play cricket this Sunday."

PlaySphere responds:

```text
Create Activity
        ↓
Notify Cricket Members
        ↓
YES / MAYBE / NO
        ↓
Confirm Players
        ↓
Create Event Teams
        ↓
Create Match
        ↓
Score
        ↓
Finalize
        ↓
Update Player / Team / Club Statistics
```

A tournament organizer can say:

> "I want to conduct a cricket tournament."

PlaySphere responds:

```text
Create Tournament
        ↓
Teams / Event Teams / Independent Teams
        ↓
Registration
        ↓
Format
        ↓
Fixtures
        ↓
Schedule
        ↓
Match Day
        ↓
Multiple simultaneous matches
        ↓
Independent scorecards
        ↓
Results
        ↓
Tournament Leaderboard
        ↓
Player Statistics
```

A season organizer can say:

> "I want cricket, badminton, football and volleyball happening across the same season."

PlaySphere responds:

```text
Multi-Sport Season
        ↓
Multiple competitions
        ↓
Multiple sports
        ↓
Multiple venues
        ↓
Multiple simultaneous matches
        ↓
Independent scorecards
        ↓
Sport-specific leaderboards
        ↓
Overall season leaderboard
        ↓
Permanent player records
```

The final system is therefore:

```text
                     PLAYSPHERE
                         │
              DISCOVER SPORTS & PEOPLE
                         │
              ┌──────────┼──────────┐
              │          │          │
            CLUBS      TEAMS      PLAYERS
              │          │          │
              └──────────┼──────────┘
                         │
               ACTIVITIES / EVENTS
                         │
               PARTICIPATION
                         │
          ┌──────────────┼──────────────┐
          │              │              │
      INDIVIDUAL       TEAM        EVENT TEAM
          │              │              │
          └──────────────┼──────────────┘
                         │
              SEASON / TOURNAMENT
                         │
                      MATCH
                         │
                    SCORECARD
                         │
                  MATCH EVENTS
                         │
                STATISTICS ENGINE
                         │
          ┌──────────────┼──────────────┐
          │              │              │
       PLAYER          TEAM           CLUB
          │              │              │
          ▼              ▼              ▼
       CAREER        TEAM STATS     CLUB STATS
          │
     ┌────┴────┐
     ▼         ▼
  SEASON   TOURNAMENT
   STATS      STATS
     │         │
     └────┬────┘
          ▼
      LEADERBOARDS
```

**This is the master product model that the Development and QA teams should use as the baseline.**
