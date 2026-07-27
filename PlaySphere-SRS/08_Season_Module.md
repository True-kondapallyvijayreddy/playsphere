# 08 Season Module

## Purpose
The Season Module forms the backbone of competition organization within PlaySphere. It serves as the top-level container for organizing temporal, bounded sporting events such as tournaments, leagues, and annual games ("Monsoon Games 2026"). This module encapsulates independent sport competitions, persistent league identities, and season linking for multi-tier promotions.

## Business Requirements
1. **Bounded Timeframes:** Every season must have a distinct start and end date to bound its events in time.
2. **Multi-Sport Support:** A single season must be able to host multiple distinct sport competitions concurrently (e.g., Cricket, Chess, Badminton).
3. **Recurring Identities:** Support persistent recurring leagues to retain historical statistics, records, and "trophy cabinets" across multiple editions.
4. **Customizable Point Systems:** Provide flexible points configurations to cater to different sport-specific rules (e.g., win = 3, draw = 1, loss = 0).
5. **Promotion/Relegation Pipelines:** Support the linking of seasons between organizational tiers (e.g., Community winner advances to District).
6. **Managed Lifecycle:** Enforce strict state transitions from draft to completion to maintain data integrity and prevent unauthorized modifications.

## Functional Requirements
1. **Season Management:** Admins can create, update, cancel, and complete seasons.
2. **League Identity Linkage:** Seasons can optionally link to a parent League entity to inherit historical tracking.
3. **Sport Competition Configuration:** Admins can add multiple sport competitions to a season, defining entrant type (individual/team) and tournament format (round-robin, knockout, swiss, group-then-knockout, league table).
4. **Points Configuration:** Admins can assign and define custom points configurations for leagues/group stages, including dynamic tiebreaker arrays (`['points', 'score_diff', 'head_to_head', 'wins']`).
5. **State Transition Enforcement:** System strictly guides the season through defined lifecycle states (Draft -> Registration Open -> Registration Closed -> In Progress -> Completed).
6. **Season Linking (Phase 7):** Ability to configure progression feeds that automatically move top entrants from the current season into specified stages of a parent/higher-tier organization's season.

## Non-Functional Requirements
1. **Scalability:** Must support concurrent modifications across hundreds of active seasons and tens of thousands of participants globally.
2. **Data Consistency:** Heavy reliance on transactions when advancing season states to ensure all underlying competitions transition synchronously if required.
3. **Auditability:** All state changes (e.g., opening registrations, closing, completing) must be logged for audit trails.
4. **Performance:** Aggregating historical league data (trophy cabinets, all-time records) should use materialized views or caching to keep response times under 500ms.

## User Stories
* As an **Organization Admin**, I want to create a new "Summer Games" season with distinct start/end dates so that I can organize multiple sporting events under one banner.
* As an **Organization Admin**, I want to link this year's tournament to our "Annual Community League" so that historical records and trophy cabinets are preserved.
* As an **Admin**, I want to configure a Football competition within the season using a Round-Robin format, assigning 3 points for a win and 1 for a draw, so it matches standard FIFA rules.
* As a **State Level Organizer**, I want to link a District-level season to my State Premier League so that district champions are automatically promoted to my tournament.
* As a **Participant**, I want to view a season's details, available sports, and registration status so I can sign up for the events I'm interested in.

## User Flow
1. **Creation:** Admin accesses Organization Dashboard -> "Seasons" -> "Create New Season".
2. **Configuration:** Fills in name, dates, optional league linkage, and creates the Season in `Draft` status.
3. **Sport Addition:** Admin adds multiple Sport Competitions (e.g., Chess, Cricket), setting formats and points configs.
4. **Registration:** Admin changes status to `RegistrationOpen`. Participants view the season and register for specific sports.
5. **Closure & Execution:** Admin changes status to `RegistrationClosed`, forms teams (via snake draft/auction), and updates status to `InProgress`.
6. **Completion:** Matches are played. Once all sports conclude, Admin changes status to `Completed`. If season linking is active, top participants are pushed to the higher-tier season.

## UI Screens
1. **Season List Dashboard:** Table/grid view of all active, upcoming, and past seasons within an organization.
2. **Season Detail Page:** Displays dates, status, parent league info, and tabs for (1) Sport Competitions, (2) Participants, (3) Settings.
3. **Sport Competition Builder:** Form to add a sport, select entrant type, choose format, and configure point systems / tiebreakers.
4. **League History Portal:** Public-facing page showing the all-time trophy cabinet and historical records for a recurring league identity.

## Database Design

### `League` (Persistent Identity)
* `id` (UUID, PK)
* `orgId` (UUID, FK)
* `name` (String)
* `description` (Text)
* `foundedYear` (Integer)

### `Season`
* `id` (UUID, PK)
* `orgId` (UUID, FK)
* `leagueId` (UUID, FK, Nullable)
* `name` (String) - e.g. "Monsoon Games 2026"
* `description` (Text)
* `startDate` (Timestamp)
* `endDate` (Timestamp)
* `status` (Enum: draft, registrationOpen, registrationClosed, inProgress, completed, cancelled)

### `PointsConfig`
* `id` (UUID, PK)
* `orgId` (UUID, FK)
* `winPoints` (Decimal, default 3)
* `drawPoints` (Decimal, default 1)
* `lossPoints` (Decimal, default 0)
* `tiebreakerOrder` (JSONB) - e.g. `['points', 'score_diff', 'head_to_head', 'wins']`

### `SportCompetition`
* `id` (UUID, PK)
* `seasonId` (UUID, FK)
* `sportId` (UUID, FK)
* `name` (String)
* `entrantType` (Enum: individual, team)
* `format` (Enum: roundRobin, knockout, swiss, groupThenKnockout, leagueTable)
* `pointsConfigId` (UUID, FK, Nullable)
* `status` (Enum: draft, open, locked, inProgress, completed)

### `SeasonLink` (Phase 7 Pipeline)
* `id` (UUID, PK)
* `sourceSeasonId` (UUID, FK)
* `targetSeasonId` (UUID, FK)
* `targetStage` (String)
* `qualifierCount` (Integer) - e.g., top 2 teams advance

## API Endpoints
* `POST /api/v1/seasons` - Create a new season.
* `GET /api/v1/seasons?orgId={id}` - List seasons for an org.
* `GET /api/v1/seasons/{id}` - Get full season details (with nested competitions).
* `PATCH /api/v1/seasons/{id}/status` - Advance season state machine.
* `POST /api/v1/seasons/{id}/competitions` - Add a sport competition to a season.
* `POST /api/v1/leagues` - Create a recurring league identity.

## Validation Rules
* **Dates:** `endDate` must be greater than or equal to `startDate`.
* **State Machine:** State transitions must follow the sequence: `draft -> registrationOpen -> registrationClosed -> inProgress -> completed`.
* **Cancellation:** Season can be moved to `cancelled` from any state *except* `completed`.
* **Completion Constraint:** A season cannot be marked `completed` unless all associated `SportCompetition` entities are marked `completed` or `cancelled`.
* **Points Config:** `winPoints` must generally be >= `drawPoints` >= `lossPoints`. Tiebreaker keys must map to valid calculable metrics.

## Permissions
* **Organization Admin:** Full CRUD on leagues, seasons, competitions, and points configurations.
* **Organization Member:** Can view active and upcoming seasons. Can register when status is `registrationOpen`.
* **Public/Guest:** Can view season details, league history, and standings if the Organization is set to public visibility.

## Notifications
* **Registration Opened:** Push/Email to all organization members when season transitions to `registrationOpen`.
* **Registration Closing Soon:** Automated reminder 48 hours before `registrationClosed` state triggers.
* **Season Started:** Notification when state hits `inProgress`.
* **Promotion Alert:** (Phase 7) Notification to teams/individuals when they qualify for a higher-tier target season.

## Error Handling
* `INVALID_STATE_TRANSITION`: Attempting to move from `draft` to `inProgress` directly.
* `COMPETITIONS_NOT_FINISHED`: Attempting to complete a season while active competitions remain.
* `DATE_CONFLICT`: Submitting an end date prior to the start date.
* `INVALID_TIEBREAKER_CONFIG`: Providing unsupported keys in the `tiebreakerOrder` array.

## Edge Cases
* **Indefinite Delays:** A season suspended midway. Solution: Admins can manually extend `endDate` or leave in `inProgress` indefinitely, though UI should flag long-stagnant seasons.
* **Format Switch Mid-Season:** Once a `SportCompetition` is `inProgress`, its format and `pointsConfigId` should be strictly locked to prevent score corruption.
* **No Registrations:** A season hits `registrationClosed` with 0 participants. UI should prompt admin to either cancel the season or extend registration.
* **Tied Standings After All Tiebreakers:** Tiebreaker array exhausts without breaking a tie. Final resolution defaults to coin-toss logic (random seed stored in DB) or manual admin override.

## Acceptance Criteria
1. Admins can successfully create a season with bounded dates and advance it linearly through all status states.
2. Admins can link a season to a persistent League entity, and historical endpoints accurately aggregate data across all linked seasons.
3. Multiple unique sport competitions can be created within a single season, each with independent formats and points configurations.
4. Attempting to mark a season as `completed` while an underlying competition is still `inProgress` returns a clear error.
5. Attempting an invalid state transition (e.g., `inProgress` back to `draft`) is rejected by the API.

## Future Enhancements
* **Season Analytics Dashboard:** Advanced participant engagement graphs and drop-off rates across seasons.
* **Dynamic Smart Scheduling:** Automatically generating match dates based on season bounding dates and facility availability.
* **Sponsorship Management:** Attaching sponsor banners and ad-placements specific to a season or league entity.
