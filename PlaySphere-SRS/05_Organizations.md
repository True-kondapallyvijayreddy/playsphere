# 05 Organizations

## Purpose
The Organizations module is the foundational multi-tenant pillar of PlaySphere. It manages the structural hierarchy of sports administration, ranging from local Sunday community matches to state-level premier leagues. By nesting organizations safely and assigning robust feature flags, this module ensures every tenant gets precisely the tools they need while enabling upward mobility for players and teams.

## Business Requirements
* **Hierarchical Nesting:** Organizations must nest in a strictly defined tree structure (Country > State > District > City/School/Community). Graph structures with multiple parents are not permitted.
* **Granular Feature Gating:** Available tools (e.g., ticketing, franchise auctions, media production) must be gated by the organization's type.
* **Trust & Safety:** Higher-level organizations (District and above) require verification to unlock premium ecosystem features like scouting invites.
* **Independent Operations:** Each organization autonomously runs its own seasons. Participation in parent organization leagues must be explicitly opted-in via SeasonLinks (Phase 7), never implicitly inherited.
* **Data Retention:** Organizations can only be soft-deleted to preserve historical sports data, and deletion must be strictly blocked if active seasons are running.

## Functional Requirements
* **Organization Types:** Support strict enumeration: `residentialCommunity`, `school`, `corporate`, `cityClub`, `districtAssociation`, `stateCouncil`, `countryCouncil`.
* **Organization Creation:** On creation, automatically generate an `OrganizationMembershipEntity` for the `creatorUserId` with `role=owner` and `status=active`.
* **Cycle Prevention:** When assigning or updating a `parentOrgId`, the system must traverse the hierarchy to guarantee no cycles are introduced.
* **Feature Flag Management:** Support a `jsonb` field for flags like `franchiseLeagues`, `venueMarketplace`, `officiatingRegistry`, `ticketing`, `sponsorship`, and `mediaProduction`. Set defaults based on `orgType`.
* **Verification Workflow:** Allow organizations of type `districtAssociation`, `stateCouncil`, or `countryCouncil` to apply for verification.
* **Deletion Constraints:** Block soft-deletion if the organization has any active season (status NOT IN `completed`, `cancelled`).

## Non-Functional Requirements
* **Performance:** Tree traversal for checking cycles or loading breadcrumbs must execute in under 50ms, potentially utilizing Materialized Paths or L-Tree extensions in PostgreSQL.
* **Security:** Organization profiles set to `unlisted` must not appear in global search or public directories unless directly linked.
* **Scalability:** Must comfortably support tens of thousands of deeply nested sub-organizations within a single country tree.

## User Stories
* **As a community organizer**, I want to create a residential community org so I can host our weekend cricket tournaments.
* **As a district sports association admin**, I want to apply for verified status so I can send official scouting invites to promising players.
* **As a state council**, I want to see a directory of all registered districts and clubs operating under my geographic umbrella.
* **As a platform admin**, I want to prevent an organization from being deleted if a season is currently running, to ensure no data loss or disruption to players.

## User Flow
1. **Creation:** User registers an organization -> Selects `orgType` -> Auto-assigned `owner` role -> Default feature flags applied.
2. **Hierarchy Linking:** Organization requests to link to a `parentOrgId` -> Cycle check executes -> Parent organization approves (if required) -> Tree linked.
3. **Verification (District+):** Org uploads official documentation -> Status becomes `pending` -> Platform admin reviews -> Status becomes `verified`.
4. **Operations:** Org manages isolated seasons -> Explicitly uses SeasonLink to push top teams up to parent leagues.

## UI Screens
* **Org Registration Flow:** Multi-step wizard to define name, type, and optional parent linkage.
* **Admin Portal - Org Dashboard:** Central hub showing active seasons, sub-organizations, and verification status.
* **Admin Portal - Settings:** Toggles for `visibility`, `description`, and `logoUrl`. Read-only view of enabled Feature Flags.
* **Participant Portal - Public Profile:** Public-facing page showcasing the organization's current seasons, verified badge, and recent champions.

## Database Design

### `organizations` Table
| Column Name | Type | Constraints | Description |
| :--- | :--- | :--- | :--- |
| `id` | UUID | Primary Key | Unique identifier |
| `name` | VARCHAR | NOT NULL | Display name |
| `slug` | VARCHAR | UNIQUE, NOT NULL | URL-safe identifier |
| `orgType` | ENUM | NOT NULL | e.g., `school`, `stateCouncil` |
| `parentOrgId` | UUID | Foreign Key | References `organizations(id)` |
| `logoUrl` | VARCHAR | NULL | S3 bucket URL |
| `description` | TEXT | NULL | Markdown supported |
| `visibility` | ENUM | DEFAULT `public` | `public` or `unlisted` |
| `creatorUserId` | UUID | Foreign Key | User who created the org |
| `featureFlags` | JSONB | NOT NULL | Gated features mapping |
| `orgVerificationStatus`| ENUM | DEFAULT `unverified`| `unverified`, `pending`, `verified`, `rejected` |
| `deletedAt` | TIMESTAMP| NULL | Soft deletion flag |

### `organization_memberships` Table
| Column Name | Type | Constraints | Description |
| :--- | :--- | :--- | :--- |
| `id` | UUID | Primary Key | Unique identifier |
| `userId` | UUID | Foreign Key | User reference |
| `orgId` | UUID | Foreign Key | Organization reference |
| `role` | ENUM | NOT NULL | `owner`, `admin`, `member` |
| `status` | ENUM | DEFAULT `active` | `active`, `suspended`, `left` |

## API Endpoints
* **`POST /api/v1/organizations`**: Create a new organization.
* **`GET /api/v1/organizations/:slug`**: Fetch public details of an organization.
* **`PATCH /api/v1/organizations/:id`**: Update settings, parent link, or feature flags.
* **`DELETE /api/v1/organizations/:id`**: Soft-delete (validates active seasons).
* **`POST /api/v1/organizations/:id/verify`**: Submit verification documents.
* **`GET /api/v1/organizations/:id/hierarchy`**: Fetch parent and child organization tree.

## Validation Rules
* `slug` must be globally unique, lowercase alphanumeric with hyphens only.
* `parentOrgId` cannot equal `id` (self-referencing block).
* Submitting a `parentOrgId` must trigger a recursive check ensuring the new parent is not currently a descendant of the target organization.
* Only orgs with `orgType` IN (`districtAssociation`, `stateCouncil`, `countryCouncil`) can have `orgVerificationStatus` modified to anything other than `unverified`.

## Permissions
* **System Admin:** Full read/write access, can manually override verification status and feature flags.
* **Org Owner:** Can edit all org settings, delete org, and manage memberships.
* **Org Admin:** Can edit basic settings and create seasons, but cannot delete the org or alter feature flags.
* **Public:** Can read public profiles and view public seasons.

## Notifications
* **Welcome Email:** Triggered on organization creation.
* **Verification Status Update:** Push and email notifications to `owner` and `admin` roles when status changes to `verified` or `rejected`.
* **Child Linking Request:** Notification sent to parent organization when a child organization requests to nest beneath them.

## Error Handling
* `400 Bad Request: CYCLE_DETECTED`: Returned if setting a parent introduces a circular hierarchy.
* `409 Conflict: ACTIVE_SEASON_EXISTS`: Returned on deletion attempt if the organization has running seasons.
* `403 Forbidden: VERIFICATION_UNSUPPORTED`: Returned if a community/school org attempts to apply for verification.

## Edge Cases
* **Changing Parent Orgs:** If an organization moves to a different parent, existing historical SeasonLinks remain intact, but future ones default to the new parent tree.
* **Simultaneous Operations:** Two admins attempting to change the parent to different target orgs simultaneously. Must be handled via optimistic locking or transactional constraints.
* **Orphaned Sub-Orgs:** If a parent org is soft-deleted, child organizations either move up a level (inherit the grandparent) or become top-level organizations.

## Acceptance Criteria
1. An organization can be created and the creator is automatically made the `owner`.
2. Feature flags correctly reflect default values based on the chosen `orgType`.
3. An attempt to create a hierarchical cycle (e.g., A -> B -> C -> A) fails gracefully with an explicit error.
4. Soft deletion is successful only when all associated seasons are either `completed` or `cancelled`.
5. Only `districtAssociation`, `stateCouncil`, and `countryCouncil` can successfully trigger the verification endpoint.

## Future Enhancements
* **Geospatial Fencing:** Restrict child organizations based on the geographical boundaries of the parent (e.g., a city club must be physically located within its parent district).
* **Automated Feature Unlocking:** Integration with Stripe to unlock premium feature flags via subscription instead of relying solely on `orgType` defaults.
* **Cross-Org Player Analytics:** Roll up player ELO and statistics through the hierarchy for state/national leaderboards.
