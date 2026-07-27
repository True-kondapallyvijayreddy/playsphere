# 06 Roles And Permissions

## Purpose
The primary purpose of the Roles and Permissions module is to manage multi-tenant access control across PlaySphere's hierarchical organizations (Country > State > District > Community/School/Corporate). The core principle is that **Roles live on OrganizationMembership, NOT on the global User entity.** This allows the same physical person to have radically different permissions in different contexts—for example, being an `owner` of a Sunday League community club while being a standard `member` in the State Premier League. 

## Business Requirements
1. **Multi-Tenant Contextual Authorization**: Access controls must be strictly bounded to the specific organization context. 
2. **Dual-Portal Architecture**: The system must seamlessly route users to either the Admin Portal or the Participant Portal based on their highest role within the active organization.
3. **Data Privacy & Trust**: Sensitive organizational data like encrypted medical notes must be accessible only to highly privileged roles (`admin`, `owner`).
4. **Accountability & Compliance**: Every role change must generate an immutable audit log for administrative tracing.
5. **Organizational Integrity**: Organizations cannot be left orphaned. There must always be at least one active `owner`.

## Functional Requirements
- **Role Assignment**: Authorized roles can assign, elevate, or demote members within their organization up to their own permission level.
- **Membership Status Lifecycle**: Memberships must transition between `invited`, `active`, and `removed` statuses. 
- **Historical Retention**: Removing a member transitions their status to `removed` to retain match/roster history but immediately revokes write and portal access.
- **Context Switching**: The UI must provide a clear mechanism for a user to switch their active organization, instantly reloading the correct portal and permissions.
- **Audit Logging**: Any update to the `role` field on a membership must append an `AuditLogEntry` capturing the actor, target, previous role, and new role.

## Non-Functional Requirements
- **Performance**: Authorization checks must be sub-50ms since they wrap almost every API request. Role lookups should be cached or embedded in JWT tokens (scoped to active org).
- **Security**: `medicalNotes` must be AES-256 encrypted at rest, decrypted only when explicitly requested by an `owner` or `admin`.
- **Scalability**: The roles architecture must support a single user having hundreds of active `OrganizationMembership` records without degrading login performance.

## User Stories
- **As a casual user**, I want to be a `member` of multiple local clubs so I can view my schedules and register for events without seeing admin clutter.
- **As a state organizer**, I want to be an `owner` of the state org to oversee all `admins` and `eventManagers`.
- **As a referee (`judgeScorer`)**, I want to log into the Participant portal and quickly access the live scoring plugin for my assigned fixtures.
- **As an admin**, I want to remove a player who left the club without breaking historical season statistics.

## User Flow
1. **Org Switching**: User logs into PlaySphere -> Views list of their memberships -> Selects an org -> System checks role -> Routes to Admin Portal (if `owner`/`admin`/`eventManager`) OR Participant Portal (if `judgeScorer`/`member`).
2. **Inviting a Member**: `admin` opens Org Settings -> Enters email + selects role -> System creates `OrganizationMembership` (status: `invited`) -> User accepts -> Status becomes `active`.
3. **Role Change**: `owner` navigates to Members list -> Selects `eventManager` -> Changes role to `admin` -> `AuditLogEntry` created -> User session is updated.

## UI Screens
- **Portal Switcher Dialog**: A visual drawer allowing users to switch active context.
- **Admin Portal - Members Tab**: A data table showing members, roles, statuses, and contact overrides.
- **Member Detail Sheet**: A side sheet in the Admin Portal to edit roles, view encrypted medical notes, and manage tags.
- **Participant Portal - Profile**: A stripped-down view where a user can view their own role and update their own medical notes/contact details.

## Database Design

### Table: `OrganizationMembership`
| Column Name | Type | Constraints / Notes |
| --- | --- | --- |
| `id` | UUID | Primary Key |
| `orgId` | UUID | Foreign Key -> `Organization`, Indexed |
| `userId` | UUID | Foreign Key -> `User`, Indexed |
| `role` | Enum | `owner`, `admin`, `eventManager`, `judgeScorer`, `member` |
| `status` | Enum | `invited`, `active`, `removed` |
| `joinedAt` | Timestamp | Set when status becomes `active` |
| `contactDetailsOverride` | JSONB | Org-specific contact info (e.g. club email vs personal) |
| `medicalNotes` | String | Encrypted at rest |
| `invitedByUserId` | UUID | Foreign Key -> `User` |
| `membershipTag` | String | e.g. "U18", "Varsity", "Alumni" |

### Table: `AuditLogEntry`
| Column Name | Type | Notes |
| --- | --- | --- |
| `id` | UUID | Primary Key |
| `orgId` | UUID | Context |
| `actorUserId`| UUID | Who made the change |
| `targetUserId`| UUID | Who was changed |
| `actionType` | String | e.g., `ROLE_UPDATE`, `MEMBERSHIP_REMOVED` |
| `oldValue` | String | e.g., `member` |
| `newValue` | String | e.g., `eventManager` |

**Constraints**:
- Unique compound constraint on `(orgId, userId)`.
- Rule: An `Organization` must always have `count(role = 'owner' AND status = 'active') >= 1`.

## API Endpoints

| Method | Endpoint | Description | Required Role |
| --- | --- | --- | --- |
| `POST` | `/api/v1/orgs/{orgId}/members/invite` | Invites a new user or links existing | `admin`, `owner` |
| `PATCH` | `/api/v1/orgs/{orgId}/members/{userId}/role` | Updates role and logs audit | `admin` (up to admin), `owner` |
| `DELETE` | `/api/v1/orgs/{orgId}/members/{userId}` | Soft deletes (sets to `removed`) | `admin`, `owner` |
| `GET` | `/api/v1/orgs/{orgId}/members/{userId}/medical` | Retrieves and decrypts medical notes | `admin`, `owner` |

## Validation Rules
- **Unique Membership**: A user cannot have multiple membership records in the same org. Re-inviting a `removed` user should restore their existing row to `active` rather than creating a new one.
- **Owner Minimum**: The system must reject any `PATCH` (role downgrade) or `DELETE` (removal) or User Account Deletion request that would result in 0 active `owners` for an organization.
- **Role Elevation Limitations**: An `admin` cannot elevate another user to `owner`. Only an `owner` can transfer ownership or create new `owners`.

## Permissions

### Role Power Matrix (Ordered by Power)
| Feature / Action | Owner | Admin | EventManager | JudgeScorer | Member |
| --- | :---: | :---: | :---: | :---: | :---: |
| **Portal Access** | Admin | Admin | Admin | Participant | Participant |
| Delete Organization | ✅ | ❌ | ❌ | ❌ | ❌ |
| Transfer / Create Owner | ✅ | ❌ | ❌ | ❌ | ❌ |
| Manage Members/Roles | ✅ | ✅ | ❌ | ❌ | ❌ |
| View All Medical Notes | ✅ | ✅ | ❌ | ❌ | ❌ (Own Only) |
| Create/Edit Seasons | ✅ | ✅ | ✅ | ❌ | ❌ |
| Trigger Team Formation (Draft/Auction) | ✅ | ✅ | ✅ | ❌ | ❌ |
| Enter Live Scores | ✅ | ✅ | ✅ | ✅ | ❌ |
| Register Self For Events | ✅ | ✅ | ✅ | ✅ | ✅ |

## Notifications
- **Membership Invitation**: User receives push/email: "You have been invited to join [Org Name] as a [Role]."
- **Role Change**: User receives push/email: "Your role in [Org Name] has been updated to [Role]."
- **Removal**: No explicit notification to the user to prevent confrontation, but the org disappears from their active switcher.

## Error Handling
- **403 Forbidden**: Returned if a user attempts an action above their role (e.g. `eventManager` trying to delete the organization).
- **400 Bad Request (Owner Constraint)**: "Cannot remove the last owner. Please assign a new owner before leaving the organization."
- **409 Conflict**: "User is already a member of this organization."
- **404 Not Found**: Attempting to act on an organization that has been deleted or one the user is not a member of.

## Edge Cases
- **Last Owner Deleting Account**: If the last `owner` attempts to delete their global PlaySphere account, the system must prompt them to transfer ownership or explicitly disband/delete the organization first.
- **Same Email, Different Roles**: Handled natively since auth is global but roles are joined on `OrganizationMembership`.
- **Accepting Invite for Wrong Account**: Invite links should mandate a confirmation screen showing the currently logged-in account before creating the binding.

## Acceptance Criteria
- [ ] User can exist in Org A as `owner` and Org B as `member` without permission bleed.
- [ ] Attempting to remove the sole `owner` of an organization returns a validation error.
- [ ] Logging in correctly routes `owner`, `admin`, and `eventManager` to the Admin portal UI.
- [ ] Logging in correctly routes `judgeScorer` and `member` to the Participant portal UI.
- [ ] Updating a user's role creates a corresponding `AuditLogEntry` verifying who performed the action.
- [ ] Medical notes are visually masked and require explicit decryption via the API for authorized roles only.

## Future Enhancements
- **Custom Roles**: Allowing orgs to define granular RBAC templates (e.g., `treasurer` role that only has access to a future billing module).
- **Time-Bounded Roles**: Expiring roles automatically at the end of a season (e.g., temporary `judgeScorer` rights).
- **Hierarchical Permission Inheritance**: An `owner` of a State organization automatically inheriting `admin` rights on all child District organizations.
