# 12 Fixture Engine

## Purpose
The Fixture Engine manages the scheduling, progression, and outcome tracking of matches within sports competitions on the PlaySphere platform. It enables the configuration of complex tournament stages (e.g., Round Robin, Knockout, Swiss), automates fixture generation, ensures deterministic recalculation of standings based on match events, and coordinates with sport-specific scoring plugins to maintain accurate, immutable event streams. It incorporates trust and safety measures via a dispute window and verification tiers to accommodate casual to sanctioned play.

## Business Requirements
- Support progressive competition structures where entities progress sequentially through stages (e.g., group stages into knockouts).
- Handle multi-format scheduling, supporting Round Robin, Single/Double Elimination Knockout, and Swiss pairing systems.
- Reconstruct match states consistently through event sourcing, decoupled from sport-specific logic using standardized plugin interfaces.
- Guarantee idempotent standings generation: Standings must be recalculated entirely from ground truth (fixtures) rather than patched incrementally.
- Ensure match integrity with structured dispute windows after match completion, limiting unauthorized edits and keeping immutable audit trails.

## Functional Requirements
1. **Stage Management:** Admins must be able to define stages (Group, Knockout, Playoffs), chain stages sequentially where top `N` finishers advance, and set stage formats.
2. **Fixture Generation:** The system shall automatically generate fixtures based on the configured `stageFormat` and seeded entrants.
3. **Standings Calculation:** The system shall recalculate rankings, played, wins, losses, draws, points, and tiebreakers for a stage completely from source fixtures every time a match is marked completed.
4. **Scoring Plugin Interface:** Match events must be routed through a generic `ScoringPlugin` interface that evaluates pure functions to derive the match state and check if a match is complete.
5. **Match Event Stream:** The engine must store sequentially incrementing match events (e.g., points scored, fouls) and broadcast these events via WebSockets to participants and fans in real-time.
6. **Dispute Window Lifecycle:** When a fixture ends, a configurable dispute window (default 24h) begins. The system must restrict standard outcome edits after the window closes, requiring a special administrative audit flag.

## Non-Functional Requirements
- **Performance:** Idempotent standings recalculation must execute efficiently (under 200ms for up to 1000 entrants in a stage).
- **Scalability:** Real-time WebSockets fan-out for live matches must reliably broadcast match events to thousands of connected clients with low latency.
- **Reliability:** Match events must be strictly sequenced, preventing concurrent write anomalies (optimistic concurrency control on sequenceNo).
- **Auditability:** Any status change during a dispute window or administrative override must be fully logged.

## User Stories
- As a Tournament Admin, I want to automatically generate a round-robin schedule for a group stage so I don't have to pair teams manually.
- As a Player, I want to see my team's position on the leaderboard update immediately after our fixture is completed.
- As an Organizer, I want to lock match results automatically after 24 hours, so that players can no longer dispute the final scores.
- As an Official/Referee, I want to input point-by-point events for a match, so that the live score updates instantly for spectators viewing the app.

## User Flow
1. **Configuration:** Admin creates a `StageEntity` with a format (e.g., Knockout) and specifies how many advance (`advanceCount`) from the prior stage.
2. **Generation:** System populates `FixtureEntity` rows automatically based on the seeding and format.
3. **Execution:** At scheduled time, match status changes to `live`. An assigned official inputs match events.
4. **Real-time Events:** `MatchEventEntity` sequences are pushed, processed by the `ScoringPlugin`, and fanned out via WebSocket.
5. **Completion:** When the plugin determines the match is complete, status changes to `completed`, and the dispute window opens.
6. **Resolution:** Standings are idempotently recalculated for the stage. If no dispute is raised, the match permanently closes after the window.

## UI Screens
- **Stage Builder Dashboard:** Drag-and-drop interface to configure stages, linking feeders and configuring advance counts.
- **Fixture List/Calendar:** Chronological view of matches with filters by stage, status, venue, and team.
- **Live Match Terminal:** Screen for officials to record events (e.g., points, fouls) tailored dynamically by the active sport plugin.
- **Standings/Bracket View:** Automatically updated visual representation of Round Robin groups or Knockout brackets.
- **Dispute Resolution Console:** Admin interface to review disputed matches, alter results manually, and resolve issues.

## Database Design

### StageEntity
| Column | Type | Description |
|---|---|---|
| id | UUID | Primary Key |
| sportCompetitionId | UUID | Foreign Key to Competition |
| name | String | E.g., "Group Stage", "Finals" |
| stageOrder | Int | Defines sequence of stages |
| stageFormat | Enum | `roundRobin`, `knockout`, `swiss` |
| status | Enum | `pending`, `inProgress`, `completed` |
| feedsFromStageId | UUID | Link to previous stage |
| advanceCount | Int | Number of top finishers that advance |

### FixtureEntity
| Column | Type | Description |
|---|---|---|
| id | UUID | Primary Key |
| stageId | UUID | Foreign Key to Stage |
| entrantAId | UUID | Team/Player A |
| entrantBId | UUID | Team/Player B |
| scheduledAt | DateTime | Scheduled start time |
| venueId | UUID | Location of the match |
| status | Enum | `scheduled`, `live`, `completed`, `walkover`, `abandoned`, `disputed` |
| resultEntrantId | UUID | Winner ID (null if draw) |
| isDraw | Boolean | True if drawn |
| officiatedByUserId | UUID | Referee/Scorer |
| disputeWindowClosesAt | DateTime | When the dispute period ends |
| verificationTier | Enum | `casual`, `sanctioned` |

### StandingEntity
| Column | Type | Description |
|---|---|---|
| id | UUID | Primary Key |
| stageId | UUID | Foreign Key to Stage |
| entrantId | UUID | Team/Player |
| played | Int | Total matches played |
| wins/draws/losses | Int | W/D/L record |
| points | Int | Aggregated points based on rules |
| tiebreakValues | JSONB | E.g., net run rate, goal difference |
| rank | Int | Calculated rank |

### MatchEventEntity
| Column | Type | Description |
|---|---|---|
| id | UUID | Primary Key |
| fixtureId | UUID | Foreign Key to Fixture |
| eventType | String | Plugin-defined event (e.g., "GOAL") |
| payload | JSONB | Event data |
| enteredByUserId | UUID | User who logged event |
| sequenceNo | Int | Strictly increasing event index |
| createdAt | DateTime | Timestamp of event |

## API Endpoints
- `POST /api/v1/stages` - Create a new stage configuration.
- `POST /api/v1/stages/:stageId/generate-fixtures` - Trigger generation of fixtures based on format.
- `PATCH /api/v1/fixtures/:fixtureId/status` - Update fixture status (e.g., to live, completed, disputed).
- `POST /api/v1/fixtures/:fixtureId/events` - Submit a new match event (sequence checked).
- `GET /api/v1/stages/:stageId/standings` - Retrieve current idempotent standings.
- `POST /api/v1/fixtures/:fixtureId/resolve-dispute` - Overwrite result and close dispute.

## Validation Rules
- `MatchEventEntity.sequenceNo` must be strictly increasing for a given `fixtureId`.
- Cannot change a fixture status from `completed` to `scheduled` or `live`.
- A stage cannot be transitioned to `completed` unless all associated fixtures are `completed`, `walkover`, or `abandoned`.
- `advanceCount` must not exceed the total number of entrants in a stage.

## Permissions
- **Admin/Organizer:** Full CRUD over Stages, Fixtures, and Dispute Resolutions. Can override results post-dispute window.
- **Official:** Can input match events, transition match to `live` and `completed`.
- **Participant:** Read-only access to standings, schedules, and live match websockets. Can flag a completed match for dispute during the active window.

## Notifications
- **Fixture Generation:** Sent to participants when schedule is published.
- **Match Start:** Push notification to followers and participants 15 minutes before `scheduledAt` and at `live`.
- **Dispute Alert:** Notifies organizers when a match result is disputed.
- **Result Finalized:** Alerts participants when the dispute window closes.

## Error Handling
- **Concurrent Events:** Return `409 Conflict` if event `sequenceNo` is out of order.
- **Locked Edits:** Return `403 Forbidden` if an official attempts to modify a match event after the `disputeWindowClosesAt` timestamp.
- **Invalid Stage Chain:** Return `422 Unprocessable Entity` if `advanceCount` logic conflicts with the target format.

## Edge Cases
- **Walkovers / Byes:** Generate dummy fixtures and instantly mark them complete; award standing points according to sport rules.
- **Tie-breakers:** When tiebreak fields are identical, resort to random coin-toss logic (logged via system event) or head-to-head performance depending on league rule configs.
- **Disputes extending beyond stage timeline:** A stage might be blocked from finishing if a critical match is in `disputed` status; handle admin alerts and manual forced progression.

## Acceptance Criteria
- Given a group of 4 teams, when the stage is set to `roundRobin`, 6 unique fixtures are automatically generated.
- Given a completed fixture, when the backend recalculates standings, the operation builds state identically whether processed once or sequentially rebuilt from scratch.
- Given a live match, when an official inputs a goal event, spectators on the WebSocket channel receive the payload in under 200ms.
- Given a completed match past its 24-hour dispute window, when an official tries to change the score, the API rejects the request.

## Future Enhancements
- Support for complex algorithmic formats like multi-stage repechage brackets.
- Machine Learning (AI) based dynamic rescheduling of fixtures due to weather or venue delays.
- Expand `ScoringPlugin` to allow third-party developers to upload WASM modules for custom niche sports.
