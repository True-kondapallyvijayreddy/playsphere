# 41 Audit Logging Specification

## Purpose
The Audit Logging system provides an immutable, append-only record of administrative actions, membership role modifications, match result overrides, score dispute resolutions, and financial transactions.

## Audit Log Schema (`AuditLogEntryEntity`)
- `id` (UUID) - Unique log entry ID.
- `orgId` (UUID) - Hosting organization ID.
- `actorUserId` (UUID) - User who performed the action.
- `actionType` (Enum) - `ROLE_CHANGED`, `FIXTURE_REOPENED`, `RESULT_MUTATED`, `SEASON_CANCELLED`, `GUARDIAN_LINKED`.
- `targetEntityId` (UUID) - ID of affected entity.
- `changes` (JSONB) - Delta map `{"before": {...}, "after": {...}}`.
- `ipAddress` (String) - Client IP address.
- `timestamp` (TIMESTAMPTZ) - Immutable server timestamp.

## Mandatory Audit Triggers
1. **Role Modifications:** Any edit to `OrganizationMembershipEntity.role`.
2. **Dispute Window Re-opens:** Reopening a completed fixture (`status -> disputed`) after initial closure.
3. **Rating Overrides:** Admin manual correction of ELO ratings or verification tiers.
4. **Guardian Consent Overrides:** Admin attestation of minor guardian relationships.

## Retention Policy
- Audit log records are immutable (INSERT only, NO UPDATE/DELETE allowed).
- Logs retained for a minimum of 7 years for compliance and dispute resolution.\n