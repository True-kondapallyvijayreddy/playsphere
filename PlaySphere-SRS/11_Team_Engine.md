# 11 Team Engine

## Purpose
The Team Engine is a core module in PlaySphere responsible for grouping players into competitive units. It handles the lifecycle, formation, and tracking of two distinct types of teams: transient **Ad-hoc** teams formed specifically for a single competition run, and persistent **Franchise** teams that persist across seasons with distinct ownership and brand identities. The module provides multiple pluggable strategies for team formation, ranging from simple random assignment to complex, ELO-based AI balancing and real-time franchise auctions.

## Business Requirements
- **Support Two Kinds of Teams**:
  1. **Ad-hoc**: Formed fresh for a specific competition, dissolved afterward. Not reused across seasons.
  2. **Franchise**: Persists across seasons. Has an owner, brand identity (logo), and league association. Roster changes are managed via retentions, drafts, or auctions.
- **Pluggable Formation Strategies**: The system must support diverse ways to form teams without hardcoded `if/else` logic, using a pluggable architecture.
- **AI-Balanced Teams**: Ensure fair competition by using per-sport ELO ratings to distribute talent evenly via snake drafts.
- **Franchise Building**: Enable franchises to acquire players via mock auctions or drafts, mimicking professional leagues (e.g., IPL, NBA).
- **Organization-Based Teams**: Allow grouping based on tags (e.g., school houses, corporate departments).
- **Idempotency**: Running automated team formation (random, AI balanced) with the same inputs and fixed seed must yield the exact same roster output.

## Functional Requirements
- **Team Entity Management**: Create, update, and read Team profiles including ID, organization ID, team kind, name, logo, league (for franchises), owner, and active status.
- **Team Membership Tracking**: Manage players assigned to teams scoped to one `sportCompetitionId`, noting roles like captaincy.
- **Formation Strategy Execution**:
  1. **Random**: Shuffle players into N equal-sized groups.
  2. **Manual**: Allow administrators to drag-and-drop players into teams.
  3. **AIBalanced**: Sort players by sport-specific ELO rating descending. Use a greedy snake draft pattern (0..N-1, N-1..0) to distribute talent evenly.
  4. **Auction**: Facilitate live bidding by franchises on players (manage base prices in paise, track lot status, and record final prices).
  5. **Draft**: Execute a turn-based draft system for franchises with configurable order logic (e.g., worst-record-first or random).
  6. **HouseWise/DepartmentWise**: Group players based on their `OrganizationMembership.membershipTag`.
- **Franchise Roster Management**: Maintain historical records of franchise rosters including retention status, acquisition type, and price.

## Non-Functional Requirements
- **Scalability**: The auction and draft systems must support real-time concurrent updates without race conditions.
- **Performance**: AI balancing algorithm must process thousands of players within milliseconds.
- **Extensibility**: New team formation strategies must be implementable via plugins/interfaces without modifying core logic.
- **Reliability**: Auction transactions (bids) must be ACID compliant.
- **Idempotency**: Algorithms requiring randomness must support seed injection for testing and reproducibility.

## User Stories
- As a **Tournament Admin**, I want to automatically balance teams using AI based on player ELO ratings, so the competition is fair and exciting.
- As a **Tournament Admin**, I want to organize a player auction, so franchise owners can bid on local talent.
- As a **Franchise Owner**, I want to retain my best players from last season and bid on new players, so I can build a winning brand.
- As a **School Sports Coordinator**, I want to form teams strictly by school houses (tags), so we can conduct inter-house tournaments.
- As a **Player**, I want to see which team drafted me and who my captain is, so I can connect with my teammates.

## User Flow
1. **Ad-hoc Team Formation**:
   - Admin creates a new SportCompetition.
   - Admin selects the pool of registered players.
   - Admin chooses a formation strategy (Random, AIBalanced, HouseWise).
   - System previews the generated teams.
   - Admin finalizes the teams (Ad-hoc teams are generated and memberships are scoped to the competition).
2. **Franchise Auction Flow**:
   - League Admin initiates a new season.
   - Franchises declare retained players (stored in `FranchiseRosterEntryEntity`).
   - Remaining players form the auction pool.
   - Admin launches the Live Auction screen.
   - Admin presents `AuctionLotEntity` one by one.
   - Franchise Owners place bids; highest bid wins the player.
   - System finalizes `AuctionLotEntity` (winningTeamId, finalPrice) and creates a `FranchiseRosterEntryEntity` (acquisitionType: auction).

## UI Screens
- **Team Formation Dashboard**: A drag-and-drop interface showing unassigned players and team buckets. Includes a dropdown to run auto-formation algorithms.
- **Live Auction Console**:
  - *Admin View*: Current player on the block, starting price, timer, and controls to accept bids or mark unsold.
  - *Franchise View*: Budget remaining, current player stats, current highest bid, and a "Place Bid" button.
- **Franchise Roster Management**: A view for franchise owners to select which players to retain for the upcoming season, with associated retention costs.
- **Team Roster View (Public)**: Displays the list of players for a team, highlighting the captain and their acquisition method (if franchise).

## Database Design

### `Team`
| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | UUID | Primary Key | Unique identifier |
| `orgId` | UUID | Foreign Key | The organization this team belongs to |
| `teamKind` | Enum | `AD_HOC` or `FRANCHISE` | The persistence model of the team |
| `name` | String | Not Null | Display name |
| `logoUrl` | String | Nullable | URL to team logo |
| `leagueId` | UUID | Nullable (Req for Franchise) | Associated league for franchises |
| `ownerUserId` | UUID | Nullable (Req for Franchise) | User ID of the franchise owner |
| `isActive` | Boolean | Default `true` | Whether the team is currently active |

### `TeamMembership`
| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | UUID | Primary Key | Unique identifier |
| `teamId` | UUID | Foreign Key | The team being joined |
| `sportCompetitionId` | UUID | Foreign Key | Scopes the membership to one run |
| `playerProfileId` | UUID | Foreign Key | The player joining the team |
| `isCaptain` | Boolean | Default `false` | Whether the player is the team captain |

### `AuctionLotEntity`
| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | UUID | Primary Key | Unique identifier |
| `competitionId` | UUID | Foreign Key | The auction event context |
| `playerProfileId` | UUID | Foreign Key | The player being auctioned |
| `basePricePaise`| Integer | Not Null | Starting bid in paise |
| `status` | Enum | `UPCOMING`, `LIVE`, `SOLD`, `UNSOLD` | Current lot state |
| `winningTeamId` | UUID | Nullable | The team that won the bid |
| `finalPricePaise`| Integer | Nullable | The winning bid amount |

### `FranchiseRosterEntryEntity`
| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | UUID | Primary Key | Unique identifier |
| `teamId` | UUID | Foreign Key | The franchise team |
| `seasonId` | UUID | Foreign Key | The season this roster applies to |
| `playerProfileId` | UUID | Foreign Key | The player on the roster |
| `acquisitionType`| Enum | `RETAINED`, `AUCTION`, `DRAFT`, `FREE_SIGNING` | How the player was acquired |
| `acquisitionPrice`| Integer | Nullable | Price paid/retained in paise |

## API Endpoints

- `POST /api/v1/teams/generate`
  - Body: `competitionId`, `playerIds[]`, `strategy` (RANDOM, AI_BALANCED, HOUSE_WISE), `seed` (optional)
  - Returns generated team compositions (preview).
- `POST /api/v1/teams/commit`
  - Body: Team structures mapped to players.
  - Creates Ad-hoc `Team` and `TeamMembership` records.
- `POST /api/v1/auctions/lots/{lotId}/bid`
  - Body: `teamId`, `bidAmountPaise`
  - Submits a bid for a live auction lot.
- `PATCH /api/v1/auctions/lots/{lotId}/status`
  - Body: `status`, `winningTeamId`, `finalPricePaise`
  - Updates lot state (Admin only).
- `POST /api/v1/franchises/{teamId}/roster`
  - Body: `seasonId`, `playerProfileId`, `acquisitionType`, `acquisitionPrice`
  - Adds a player to a franchise roster.

## Validation Rules
- `teamKind` constraints: If `teamKind == FRANCHISE`, both `leagueId` and `ownerUserId` MUST be provided. Ad-hoc teams must NOT have an owner.
- AI Balanced Sorting: Player ELO must be fetched for the specific sport of the competition.
- Auction Bids: `bidAmountPaise` must be strictly greater than the current highest bid or `basePricePaise` (if no bids).
- Retentions: A franchise cannot retain more players than the league's maximum retention limit per season.
- Roster Uniqueness: A player (`playerProfileId`) can only have one active `TeamMembership` per `sportCompetitionId`.

## Permissions
- **Admin**: Full control. Can trigger any team formation strategy, modify team details, and control auction states.
- **Franchise Owner**: Can update their own franchise logo/name, submit retentions, and place bids during live auctions for their team.
- **Player**: Read-only access to their team assignment and team members.

## Notifications
- **Player Drafted/Auctioned**: Push notification sent to player when acquired by a franchise. ("You have been drafted by [Team Name] for ₹X!")
- **Team Formed**: Push notification to players when ad-hoc teams are finalized. ("Your team for the upcoming [Competition] has been formed! Meet your captain.")
- **Auction Outbid**: Real-time websocket event sent to a franchise owner when they are outbid on a live lot.

## Error Handling
- `400 Bad Request`: When trying to run `HouseWise` strategy on players lacking an `OrganizationMembership.membershipTag`.
- `409 Conflict`: If an auction bid arrives after a lot is marked `SOLD`.
- `422 Unprocessable Entity`: If creating a Franchise without an owner or league.

## Edge Cases
- **Insufficient Players for AI Draft**: If player count is not a clean multiple of team count, the snake draft must handle the remainder (e.g., teams at the end of the snake get one fewer player, or dummy profiles are used).
- **Network Drops during Auction**: Bids rely on accurate timestamps. The auction system should utilize a countdown that resets on valid bids, giving users time to reconnect.
- **Missing ELO Ratings**: For `AIBalanced` drafts, new players without match history get the default ELO (e.g., 1200) for sorting.

## Acceptance Criteria
- Verify ad-hoc teams dissolve/are scoped exclusively to the requested `sportCompetitionId`.
- Verify franchise teams persist and can link to a new season's `FranchiseRosterEntryEntity`.
- Verify `AIBalanced` strategy groups players via greedy snake draft sorted by exact ELO desc.
- Verify `random` formation with a specific seed consistently outputs the exact same team structure.
- Verify franchises can only bid if `ownerUserId` matches the authenticated user and lot is `LIVE`.

## Future Enhancements
- **Salary Caps**: Hard limits on the sum of `acquisitionPrice` per franchise for a season.
- **Trade Engine**: Mid-season player trades between franchises with approval workflows.
- **Multi-sport ELO Weights**: If forming a multi-sport decathlon team, use a blended ELO rating.
- **Advanced Draft Order**: Support lottery-weighted drafts similar to NBA for more dynamic franchise building.
