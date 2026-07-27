# 22 Kabaddi Module

## Purpose
The Kabaddi Module delivers dedicated scoring, raid tracking, and team management for Kabaddi tournaments—a prominent sport across India and South Asia. It supports standard 7-a-side mat and clay formats.

## Business Requirements
- Support traditional and Pro-Kabaddi style tournament rules.
- Track raid points, tackle points, bonus points, super raids, and All-Outs.
- Calculate league standings based on match wins, ties, and score differentials.

## Functional Requirements
- **Match Structure:** Two halves (typically 20 minutes each) with a 5-minute halftime interval.
- **Raid Event Tracking:**
  - Touch Points (1 point per defender touched)
  - Bonus Point (1 point when raiding past bonus line with trailing foot in air)
  - Super Raid (3+ points in a single raid)
  - Empty Raid / Do-or-Die Raid logic
- **Tackle Event Tracking:**
  - Standard Tackle (1 point)
  - Super Tackle (2 points awarded when 3 or fewer defenders successfully execute a tackle)
- **All-Out (Lona):** 2 bonus points awarded to the opposing team when all players of a side are revived/eliminated.

## Non-Functional Requirements
- Rapid tap input interface optimized for high-velocity raid actions.
- Real-time notification fan-out for Super Raids and All-Outs.

## User Stories
- As a Kabaddi Referee/Scorer, I want to record raid results (Touch, Bonus, Super Tackle, Out) within seconds of the raid completion.
- As a Player, I want my raid points and tackle points recorded on my Portable Player Profile.

## User Flow
1. Scorer starts match clock for Half 1.
2. Selects raiding team and raider player.
3. Records raid outcome (e.g., 2 Touch Points + Bonus).
4. System updates score, manages player revivals, and calculates current active court count.

## UI Screens
- Live Kabaddi Mat Dashboard (showing active players per side).
- Raider & Defender Summary Cards.

## Database Design
- `MatchEventEntity` payload: `{"event_type": "raid"|"tackle"|"all_out", "points": int, "raider_id": "...", "revived_count": int}`.

## API Endpoints
- `POST /api/v1/fixtures/{fixtureId}/kabaddi-event`
- `GET /api/v1/fixtures/{fixtureId}/kabaddi-scorecard`

## Validation Rules
- Touch points cannot exceed the number of active defenders on court.
- Super Tackle points (2) only valid when defending team has <= 3 active players.

## Permissions
- Requires `judgeScorer` or `admin` role in the hosting organization.

## Notifications
- High-priority push notifications triggered on "ALL OUT" or "SUPER RAID".

## Error Handling
- Complete raid rollback recalculates active player rosters for both teams.

## Edge Cases
- Simultaneous touch and tackle calls (reviewable by judge).
- Do-or-die raid timer expiration resulting in raider elimination.

## Acceptance Criteria
- Given 3 defenders on court, when a successful tackle is logged, then 2 Super Tackle points are awarded.
- Given a team loses its last active player, when logged, 2 All-Out points are awarded to the opponent and all 7 players are revived.

## Future Enhancements
- Video review integration for contested raids.\n