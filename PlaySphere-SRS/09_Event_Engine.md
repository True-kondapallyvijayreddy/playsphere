# 09 Event Engine

## 1. Overview
The **Event Engine** manages the hierarchical structure of sports events within an organization. It provides the framework for organizing matches, tournaments, and leagues. The hierarchy flows from **Season** down to **SportCompetition**, which in turn dictates the stages and actual fixtures.

## 2. Functional Requirements

### 2.1 Season Management
*   **Definition:** A Season represents a logical grouping of events over a time period (e.g., "Summer Championship 2026", "Corporate League Q3").
*   **Admin Controls:** Organization Admins can create a Season, set its start and end dates, and add multiple `SportCompetition` instances to it.

### 2.2 Sport Competition Configuration
*   **Definition:** An event within a Season focused on a specific sport (e.g., "Men's Under-19 Cricket", "Open Rapid Chess").
*   **Format Selection:** Admins can define the tournament structure:
    *   `roundRobin`: Everyone plays everyone.
    *   `knockout`: Single or double elimination.
    *   `swiss`: Swiss-system tournament (players paired with similar running scores).
    *   `leagueTable`: Long-running points-based league.
*   **Entrant Type:** 
    *   `individual`: Players compete as themselves (e.g., Tennis Singles).
    *   `team`: Players form or are drafted into rosters (e.g., Football).
*   **Points Configuration:** Define points awarded for Win, Loss, Draw, or No Result (e.g., Football: Win=3, Draw=1, Loss=0).

### 2.3 Status Lifecycle & State Machine
The competition follows a strict state progression:
1.  **Draft:** Configured by admin. Not visible to participants.
2.  **Open:** Visible. Registration window is active. Players/teams can enroll.
3.  **Locked:** Registration closed. Admin performs draws, snake drafts, or generates the fixture schedule.
4.  **InProgress:** Matches are actively being played and scored.
5.  **Completed:** All fixtures resolved. Final standings locked. Achievements dispatched.

### 2.4 Registration Window Management
*   **Timeboxing:** Competitions have `registrationOpensAt` and `registrationClosesAt` timestamps.
*   **Capacity Limits:** Admins can set maximum participant/team caps. 
*   **Transitioning:** The system automatically changes status from `Open` to `Locked` when the `registrationClosesAt` time is reached or capacity is maxed out (if auto-lock is configured).

## 3. Data Models

### 3.1 Season
| Field | Type | Description |
| :--- | :--- | :--- |
| `id` | UUID | Primary key |
| `organizationId` | UUID | Owning organization |
| `name` | String | e.g., "Winter League 2026" |
| `startDate` | DateTime | Season start |
| `endDate` | DateTime | Season end |

### 3.2 SportCompetition
| Field | Type | Description |
| :--- | :--- | :--- |
| `id` | UUID | Primary key |
| `seasonId` | UUID | Parent season |
| `sportType` | Enum | e.g., `football`, `badminton` |
| `name` | String | e.g., "Under-15 Boys Football" |
| `format` | Enum | `roundRobin`, `knockout`, `swiss`, `leagueTable` |
| `entrantType` | Enum | `individual`, `team` |
| `status` | Enum | `draft`, `open`, `locked`, `inProgress`, `completed` |
| `maxCapacity` | Integer | Max entrants allowed |
| `registrationStart` | DateTime | Reg open time |
| `registrationEnd` | DateTime | Reg close time |
| `pointsConfig` | JSON | E.g., `{"win": 3, "draw": 1, "loss": 0}` |

## 4. API & Integration Points
*   **Event Creation Hook:** When a competition status changes to `Open`, the Notification Engine broadcasts push notifications to eligible organization members.
*   **Draw Generation Hook:** When status shifts to `Locked`, the tournament generator (external service or background worker) calculates the bracket/schedule based on the `format`.
*   **Completion Hook:** Transitions to `Completed` trigger the ELO finalization, achievement awards (see User Profile), and promotion pipelines to higher-tier seasons.

## 5. Edge Cases & Considerations
*   **Manual Overrides:** Admins must have the ability to manually pause a competition (revert `inProgress` to `locked`) in case of disputes, extreme weather, or scheduling errors.
*   **Multi-Stage Tournaments:** Future iterations will support nested stages within a `SportCompetition` (e.g., Group Stage (Round Robin) followed by Playoffs (Knockout)). For MVP, these can be modeled as two separate linked competitions.
