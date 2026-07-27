# PlaySphere — Domain Model (per Technical Build Specification v1.0)

## What this is

`lib/domain/` is a fresh, hand-written domain-entity layer that mirrors
every object in `PlaySphere — Technical Build Specification v1.0`
field-for-field, across all 10 phases plus the two design-sketch
phases (9 and 10).

Import everything with:

```dart
import 'package:playsphere/domain/domain.dart';
```

## File map

| File | Spec section | Contents |
|---|---|---|
| `enums.dart` | throughout | every enum used by every entity, grouped by phase |
| `shared/audit_log_entity.dart` | §0 conventions | `AuditLogEntry`, `TimestampedSoftDeletable` mixin, `Paise` money type |
| `phase1_identity.dart` | §1 | `UserEntity`, `OrganizationEntity`, `FeatureFlags`, `OrganizationMembershipEntity`, role-capability matrix, `PlayerProfileEntity` |
| `phase2_season_competition.dart` | §2 | `SeasonEntity` (+ state machine), `SportCompetitionEntity`, `SportEntity`, `RegistrationEntity`, `EntrantEntity`, `LeagueEntity`, `PointsConfigEntity` |
| `phase3_team_formation.dart` | §3 | `TeamEntity`, `TeamMembershipEntity`, `TeamFormationStrategyEntity` (+ strategy interface), `FranchiseRosterEntryEntity`, `AuctionLotEntity` |
| `phase4_fixtures_scoring.dart` | §4 | `StageEntity`, `FixtureEntity`, `MatchEventEntity` (+ `ScoringPlugin` interface), `StandingEntity` |
| `phase5_rating_achievement.dart` | §5 | `RatingRecordEntity`, `RatingHistoryEntryEntity` (+ `RatingCalculationService` contract), `AchievementEntity`, `FlaggedRatingEventEntity` |
| `phase6_trust_safety.dart` | §6 | `GuardianLinkEntity`, `VisibilityResolver` contract, `ScoutingInviteEntity` |
| `phase7_promotion.dart` | §7 | `SeasonLinkEntity` |
| `phase8_discovery.dart` | §8 | `CareerPageView`, `TalentSearchIndexEntry` (read-model shapes) |
| `phase9_venue_officiating.dart` | §9 (design sketch) | `VenueEntity`, `VenueBookingEntity`, `OfficialRegistryEntity`, `OfficialAssignmentEntity` |
| `phase10_governance_monetization.dart` | §10 (design sketch) | `EligibilityRuleEntity`, `AntiDopingFlagEntity`, `SponsorshipDealEntity`, `TicketProductEntity`, `TicketOrderEntity`, `SubscriptionPlanEntity`, `HighlightReelEntity` |

## What's implemented vs. stubbed — read this before using in anger

**Implemented:** every field, type, and relationship from the spec,
as plain immutable Dart classes (`Equatable`, no code generation
needed — no `build_runner` step required to use these). Legal-state
tables that are pure data (e.g. `Season.kLegalTransitions`, the
role→capability matrix `kRoleCapabilityMatrix`) are implemented as
data, since they're lookups, not behavior.

**Stubbed as `TODO` comments, not implemented:** every *business
rule* that requires a database, a transaction, or a service to
enforce — uniqueness constraints, permission checks, the audit log
actually being written, standings/rating recompute jobs, the Elo
calculation, the dispute-window state machine, the minor
visibility-lock resolver, idempotent team-formation, etc. Each one is
called out with a `// TODO(...)` comment on the entity or interface it
belongs to, quoting the exact rule from the spec, so nothing gets
silently lost. Search the domain files for `TODO(business-rules` /
`TODO(scheduled-job` / `TODO(implementation` to get the full list.

None of this business logic runs today. The classes just carry data.

## What was intentionally left untouched

The existing `lib/features/**/domain/entities/*.dart` files (from the
prior "Blueprint" spec — `event_entity.dart`, `member_entity.dart`,
etc.) were **not modified or deleted**. They don't match the new
spec's object model (e.g. there's no single `EventEntity` anymore —
it's replaced by `Season` → `SportCompetition` → `Stage` → `Fixture`),
and the app's existing presentation/data/router layers still depend
on them to compile. Rewiring the app to actually use `lib/domain/`
(new repositories, providers, screens per phase) was explicitly
out of scope for this pass — see the two options below for how to
proceed.

## Next steps (not done yet, by design)

1. **Where should the business rules run?** Decide backend
   (Node/Postgres implementing the spec's rules, Flutter as a client)
   vs. local-only (SQLite + repository classes enforcing rules
   client-side for now).
2. **Wire `lib/domain/` into the app.** Replace the old
   `lib/features/**/domain/entities` and their repositories/providers
   with ones built on top of `lib/domain/`, phase by phase.
3. **Implement the stubbed rules**, starting with Phase 1–2 (identity,
   org, season/competition), since every later phase depends on them.
