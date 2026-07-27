import os

srs_dir = "/Users/apple/Desktop/Work_Projects/PlaySphere/PlaySphere-SRS"

docs = {
    "21_Basketball_Module.md": """# 21 Basketball Module

## Purpose
The Basketball Module enables organization admins and scorers to schedule, manage, and live-score basketball games across various formats (5v5 standard, 3x3 streetball). It handles quarter-by-quarter scoring, fouls, timeouts, field goals (2-pointers and 3-pointers), free throws, and overtime.

## Business Requirements
- Support 5v5 full-court and 3x3 half-court competition formats.
- Enable real-time score updates per quarter for spectators and participants.
- Provide automated team standings based on win-loss records and point differentials.

## Functional Requirements
- **Quarter & Game Control:** Configurable 4-quarter structure (e.g., 10 or 12 minutes per quarter) with overtime periods for tied games.
- **Scoring Event Logging:**
  - 2-point Field Goal Made
  - 3-point Field Goal Made
  - Free Throw Made (1 point)
  - Missed Shot / Missed Free Throw
- **Fouls & Penalties:** Personal fouls, technical fouls, unsportsmanlike fouls, and team bonus foul tracking.
- **Timeouts:** Track remaining timeouts per team per half.

## Non-Functional Requirements
- Score updates fan out to connected clients via WebSockets with <500ms latency.
- State mutation must be event-sourced so any mis-scored event can be undone cleanly.

## User Stories
- As a Basketball Scorer, I want to tap +2, +3, or +1 buttons during live play so that the scoreboard updates instantly.
- As a Fan, I want to see the live box score and quarter breakdown on my mobile device.

## User Flow
1. Scorer opens match on Live Dashboard.
2. Selects active quarter (Q1, Q2, Q3, Q4, OT).
3. Taps event button (+2 Pts, +3 Pts, Free Throw, Foul) and assigns player.
4. Engine recalculates match score and updates standings upon match completion.

## UI Screens
- Live Box Score & Quarter Breakdown Screen.
- Scorer Panel with fast-action score buttons.

## Database Design
- Uses `MatchEventEntity` with payload: `{"points": 2|3|1, "player_id": "...", "quarter": 1|2|3|4}`.

## API Endpoints
- `POST /api/v1/fixtures/{fixtureId}/events` - Post basketball scoring event.
- `GET /api/v1/fixtures/{fixtureId}/scorecard` - Fetch full basketball box score.

## Validation Rules
- Points added must be strictly 1, 2, or 3.
- Quarter cannot advance beyond 4 without a tie condition requiring Overtime.

## Permissions
- `enterLiveScores` capability required to submit scoring events.

## Notifications
- Push notification sent to event subscribers when a close game enters Overtime or finishes.

## Error Handling
- Undo last event rewinds team score and player box score accurately.

## Edge Cases
- Game tied at end of Q4 enters 5-minute Overtime automatically.
- Technical fouls resulting in free throws and possession reset.

## Acceptance Criteria
- Given a tied game at the end of Q4, when the clock expires, then the match state automatically shifts to Overtime (OT1).
- Given a +3 event submitted, when processed, then team total score increases by 3 points.

## Future Enhancements
- Shot clock integration and detailed shot chart mapping.
""",

    "22_Kabaddi_Module.md": """# 22 Kabaddi Module

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
- Video review integration for contested raids.
""",

    "30_Mobile_App.md": """# 30 Mobile App Specification

## Purpose
The PlaySphere Mobile App provides a native cross-platform (iOS & Android) experience built using Flutter. It caters to players, admins, guardians, and spectators, enabling on-the-go registration, match check-in, live score viewing, and profile management.

## Business Requirements
- Deliver 100% feature parity for mobile users across iOS and Android.
- Support smooth 60 FPS performance on mid-tier mobile devices.
- Enable offline score entry for scorers operating in venues with intermittent connectivity.

## Functional Requirements
- **Authentication & Role Switching:** OTP/Email login, biometric login, and dynamic role switcher between Admin and Participant modes.
- **Event & Match Discovery:** Browse upcoming seasons, view interactive brackets, and follow live match updates.
- **QR Code Scanner:** Embedded camera QR scanner for quick player check-in at tournament venues.
- **Push Notifications:** Instant alerts for match schedules, live scoring milestones, and team assignments.
- **Offline Caching:** Local caching using Hive/SharedPreferences for offline viewing of downloaded fixtures and profiles.

## Non-Functional Requirements
- App cold boot time < 2.0 seconds.
- Responsive layout adapting to various mobile screen sizes and orientations.

## User Stories
- As a Player, I want to scan my QR code at the venue check-in desk so that my attendance is recorded instantly.
- As a Scorer, I want to record scores offline during a match so that my data syncs automatically when signal is restored.

## UI Screens & Architecture
- Built using Flutter with Riverpod state management and Material 3 design system.
- Bottom Navigation Bar with Home, Events, Live Ops, Profile, and Settings tabs.

## Database & Caching
- Local Hive key-value store for offline persistence.
- Automatic sync queue engine for pending offline HTTP requests.

## Security & Compliance
- Secure storage (iOS Keychain / Android Keystore) for JWT auth tokens.
- Biometric authentication support (Face ID / Fingerprint).

## Acceptance Criteria
- App compiles cleanly for Android (APK/AAB) and iOS (IPA).
- QR scanner successfully decodes player ticket payload within 300ms.
""",

    "31_Web_Admin_Portal.md": """# 31 Web Admin Portal Specification

## Purpose
The PlaySphere Web Admin Portal is an optimized web application designed for Desktop and Tablet browsers. It empowers organization owners, sports coordinators, and tournament managers to administer complex multi-sport seasons, manage registrations, trigger AI team shuffles, and oversee live scoring control rooms.

## Business Requirements
- Provide a comprehensive command center for managing single-day community games up to state-wide leagues.
- Enable multi-tenant dashboard switching for users managing multiple sports organizations.
- Export registration rosters, standings tables, and financial statements to CSV/PDF formats.

## Functional Requirements
- **Organization Management:** Configure organization profile, parent-child links, branding, and feature flags.
- **Season & Event Builder:** Multi-step wizard to create seasons, add sport competitions, configure points/tiebreaker rules, and publish schedules.
- **AI Team Formation Control Room:** Configure team strategy (AI Balanced ELO, Random, House-wise, Auction) and execute idempotent team shuffles with real-time preview.
- **Live Scoring Command Center:** Multi-field live scoring dashboard allowing central monitoring of simultaneous matches.
- **User & Membership Management:** Roles & permissions matrix manager, guardian consent review queue, and member directory.

## Non-Functional Requirements
- Responsive web design optimized for 1920x1080 desktop and tablet viewport sizes.
- Keyboard shortcuts for rapid live scoring entry.

## User Stories
- As an Org Admin, I want to run an AI-balanced team shuffle so that all teams have an equal average ELO rating.
- As a Tournament Director, I want to monitor 4 ongoing badminton courts from one central web screen.

## UI Screens
- Dashboard Home with KPI summary cards.
- Season & Competition Management Hub.
- Bracket & Fixture Generator Interface.
- Live Operations Control Room.

## Acceptance Criteria
- Web portal builds into optimized web bundle (`flutter build web`).
- Responsive layout smoothly scales across 1024px to 4K display viewports.
""",

    "32_API_Specifications.md": """# 32 API Specifications

## Purpose
This document defines the RESTful HTTP and WebSocket API contracts for the PlaySphere backend services, connecting Flutter client apps to core services.

## Base URL
`https://api.playsphere.org/v1`

## Core Endpoints

### 1. Authentication
- `POST /auth/login` - Authenticate via email/password or OTP. Returns JWT token pair.
- `POST /auth/refresh` - Refresh access token.
- `GET /auth/me` - Fetch authenticated user profile & memberships.

### 2. Organizations
- `GET /orgs` - List user accessible organizations.
- `POST /orgs` - Create a new organization.
- `GET /orgs/{orgId}` - Get organization details & feature flags.
- `PUT /orgs/{orgId}/memberships/{userId}` - Update membership role.

### 3. Seasons & Competitions
- `GET /orgs/{orgId}/seasons` - List seasons for an org.
- `POST /orgs/{orgId}/seasons` - Create a new season.
- `POST /seasons/{seasonId}/competitions` - Add a sport competition to a season.

### 4. Fixtures & Live Scoring
- `GET /competitions/{competitionId}/fixtures` - Fetch fixture list & standings.
- `POST /fixtures/{fixtureId}/events` - Append match event (score, wicket, goal, etc.).
- `POST /fixtures/{fixtureId}/complete` - Mark fixture completed & trigger standings/ELO recompute.

### 5. Player Profiles & Ratings
- `GET /profiles/{profileId}` - Fetch global player profile & career timeline.
- `GET /profiles/{profileId}/ratings` - Fetch per-sport ELO rating history.

## WebSocket Channels
- `wss://realtime.playsphere.org/v1/fixtures/{fixtureId}` - Live score fan-out broadcast channel.

## Error Format
```json
{
  "error": {
    "code": "INVALID_STATE_TRANSITION",
    "message": "Cannot transition season from completed to draft",
    "status": 400
  }
}
```
""",

    "33_Database_Schema.md": """# 33 Database Schema Specification

## Purpose
The PlaySphere database schema is built on PostgreSQL (hosted via Supabase) utilizing multi-tenant Row Level Security (RLS), JSONB feature flags, and foreign key relationships across 10 core domain phases.

## Schema Overview

### 1. Identity & Auth (`public` schema)
- `users` (id UUID PRIMARY KEY, full_name TEXT, email TEXT UNIQUE, phone TEXT, date_of_birth DATE, auth_provider TEXT, account_status TEXT, created_at TIMESTAMPTZ)
- `organizations` (id UUID PRIMARY KEY, name TEXT, slug TEXT UNIQUE, org_type TEXT, parent_org_id UUID REFERENCES organizations(id), feature_flags JSONB, created_at TIMESTAMPTZ)
- `organization_memberships` (id UUID PRIMARY KEY, org_id UUID REFERENCES organizations(id), user_id UUID REFERENCES users(id), role TEXT, status TEXT, membership_tag TEXT, UNIQUE(org_id, user_id))
- `player_profiles` (id UUID PRIMARY KEY, user_id UUID REFERENCES users(id) UNIQUE, display_name TEXT, primary_sport_ids TEXT[], visibility_default TEXT, career_page_slug TEXT UNIQUE)

### 2. Seasons & Competitions
- `seasons` (id UUID PRIMARY KEY, org_id UUID REFERENCES organizations(id), name TEXT, status TEXT, start_date DATE, end_date DATE)
- `sport_competitions` (id UUID PRIMARY KEY, season_id UUID REFERENCES seasons(id), sport_id TEXT, name TEXT, entrant_type TEXT, format TEXT, status TEXT)

### 3. Teams & Fixtures
- `teams` (id UUID PRIMARY KEY, org_id UUID REFERENCES organizations(id), team_kind TEXT, name TEXT, is_active BOOLEAN)
- `stages` (id UUID PRIMARY KEY, sport_competition_id UUID REFERENCES sport_competitions(id), name TEXT, stage_order INT, stage_format TEXT, status TEXT)
- `fixtures` (id UUID PRIMARY KEY, stage_id UUID REFERENCES stages(id), entrant_a_id UUID, entrant_b_id UUID, status TEXT, result_entrant_id UUID, is_draw BOOLEAN, verification_tier TEXT)
- `match_events` (id UUID PRIMARY KEY, fixture_id UUID REFERENCES fixtures(id), event_type TEXT, payload JSONB, sequence_no INT, entered_by_user_id UUID, created_at TIMESTAMPTZ)

### 4. Ratings & Achievements
- `rating_records` (id UUID PRIMARY KEY, player_profile_id UUID REFERENCES player_profiles(id), sport_id TEXT, current_rating FLOAT, rating_status TEXT, matches_played INT, UNIQUE(player_profile_id, sport_id))
- `rating_history_entries` (id UUID PRIMARY KEY, rating_record_id UUID REFERENCES rating_records(id), rating_before FLOAT, rating_after FLOAT, expected_score FLOAT, actual_score FLOAT, k_factor_used FLOAT)
- `achievements` (id UUID PRIMARY KEY, player_profile_id UUID REFERENCES player_profiles(id), sport_id TEXT, description TEXT, verification_tier TEXT)

## Indexes & Performance
- `CREATE INDEX idx_match_events_fixture_seq ON match_events(fixture_id, sequence_no);`
- `CREATE INDEX idx_fixtures_stage ON fixtures(stage_id);`
- `CREATE INDEX idx_org_memberships_user ON organization_memberships(user_id);`

## Row Level Security (RLS)
- Organization members can read data belonging to their `org_id`.
- Admins/Owners have write permissions within their `org_id`.
""",

    "34_UI_UX_Wireframes.md": """# 34 UI/UX Wireframes Specification

## Purpose
This document details the UI/UX design system, visual aesthetics, color palettes, typography, and layout wireframes for the PlaySphere cross-platform applications.

## Design Aesthetics & Tokens
- **Theme Mode:** Dual support for sleek Dark Mode (default for live scoring & command center) and modern Light Mode.
- **Color Palette:**
  - Primary Brand: Electric Indigo `#6366F1`
  - Accent / Energy: Vibrant Emerald `#10B981` & Amber `#F59E0B`
  - Background Dark: Deep Slate `#0F172A`
  - Surface Dark: Slate Card `#1E293B`
- **Typography:** Modern sans-serif font stack (Inter / Outfit) with clear hierarchy from Display Small to Body Small.
- **Visual Styles:** Glassmorphism, smooth subtle gradients, elevated card elevations (2dp-8dp), and micro-animations for interactions.

## Key Screen Wireframe Layouts

### 1. Organization Home Dashboard (`/org/:orgId`)
- Top Bar: Org Name, Logo, Role Switcher Badge (Admin / Participant).
- KPI Cards Row: Active Seasons, Total Participants, Upcoming Fixtures, Quick Actions.
- Main Section: Featured Active Competition Banner & Live Scoring Feed.

### 2. Live Operations Dashboard (`/org/:orgId/events/:eventId/live`)
- Header: Match Status, Scoreboard Display, Live Clock.
- Action Grid (Scorer Mode): Large, high-contrast event logging buttons.
- Feed Column: Real-time event log stream with undo capability.

### 3. Portable Player Profile (`/org/:orgId/members/:memberId`)
- Hero Banner: Avatar, Verified Badge, Global Portable ID, Per-Sport ELO Chips.
- ELO Progress Chart: Interactive `fl_chart` Line chart showing rating history over time.
- Achievement Timeline: List of verified tournament finishes, trophies, and milestones.

## Responsive Layout Breakpoints
- Mobile Compact: `< 600px` (Single column, bottom navigation)
- Tablet Medium: `600px - 1024px` (Two column, navigation rail)
- Desktop Expanded: `> 1024px` (Multi-column dashboard, permanent sidebar)
""",

    "35_User_Stories.md": """# 35 User Stories Specification

## Epics Overview
PlaySphere features are organized into core user epics spanning all user roles: Org Owners, Admins, Scorers, Players, Guardians, and Scouts.

## User Stories by Epic

### Epic 1: Organization & Identity
- **US1.1:** As a Community Resident, I want to create a PlaySphere organization for my housing society so that we can host annual sports events.
- **US1.2:** As an Org Owner, I want to invite event managers and assign them `admin` roles so that they can manage competitions.
- **US1.3:** As a User with multiple memberships, I want to switch my organization context in one tap without re-logging in.

### Epic 2: Season & Event Management
- **US2.1:** As an Admin, I want to create a season ("Monsoon Cup 2026") and configure Table Tennis and Cricket competitions under it.
- **US2.2:** As an Admin, I want to set points rules (3 pts for win, 1 for tie) and tiebreakers (Net Run Rate) for a league.

### Epic 3: AI Team Formation
- **US3.1:** As an Admin, I want to trigger an AI-balanced team shuffle so that player skill ratings are evenly distributed across teams.
- **US3.2:** As a Franchise Owner, I want to participate in a live player auction to build my team roster.

### Epic 4: Live Scoring & Fixtures
- **US4.1:** As a Judge/Scorer, I want to record live match events on my mobile device so that the scoreboard updates in real time.
- **US4.2:** As a Spectator, I want to view live score updates and standings tables on the web or app.

### Epic 5: Portable Profile & Talent Discovery
- **US5.1:** As a Player, I want my tournament achievements and ELO ratings to be saved to my portable profile so that I keep my history across communities.
- **US5.2:** As a State Scout, I want to search for top-rated table tennis players by age category and ELO rating.

### Epic 6: Trust & Safety for Minors
- **US6.1:** As a Guardian, I want to link my account to my minor child's profile and control whether their profile is public or private.
""",

    "36_Acceptance_Criteria.md": """# 36 Acceptance Criteria Specification

## Overview
This document specifies standard Gherkin-formatted (Given-When-Then) acceptance criteria for PlaySphere's core technical workflows.

## Feature 1: Multi-Tenant Role Authorization
```gherkin
Scenario: Admin views admin actions on organization dashboard
  Given a user signed in with an active membership in "Maram Homes" having role "admin"
  When the user navigates to "/org/maram-homes"
  Then the Admin Portal controls (Create Season, Add Member, Manage Roles) are visible
  And the role badge displays "ADMIN".

Scenario: Member views participant view on organization dashboard
  Given a user signed in with an active membership in "Maram Homes" having role "member"
  When the user navigates to "/org/maram-homes"
  Then the Admin Portal creation tools are hidden
  And the Participant view (Browse Events, My Registrations) is displayed.
```

## Feature 2: AI-Balanced Team Shuffle
```gherkin
Scenario: Executing AI team shuffle on 16 registered players into 4 teams
  Given 16 player registrations with per-sport ELO ratings ranging from 1000 to 1800
  When the Admin selects strategy "aiBalanced" with team count 4 and executes shuffle
  Then 4 teams of 4 players each are generated
  And the total rating variance between the highest and lowest average team rating is < 5%.
```

## Feature 3: ELO Rating Update on Fixture Completion
```gherkin
Scenario: Player A (1400 ELO) defeats Player B (1200 ELO) in a casual match
  Given Player A has current ELO 1400 and Player B has current ELO 1200
  When a Table Tennis fixture between Player A and B is completed with Player A winning
  Then Player A's new ELO increases by approximately +6 points (K=20)
  And Player B's new ELO decreases by -6 points
  And a new append-only RatingHistoryEntry is created for both players.
```

## Feature 4: Minor Protection Visibility Hard-Lock
```gherkin
Scenario: Minor profile without verified guardian remains hard-locked to private
  Given a user profile where dateOfBirth indicates age < 18
  And no verified GuardianLink exists for the user
  When any external user attempts to search or view the profile
  Then the system restricts profile visibility to "private" regardless of stored defaults.
```
""",

    "37_Test_Plan.md": """# 37 Test Plan Specification

## Purpose
The PlaySphere Test Plan outlines the testing strategy, automation framework, unit test requirements, UI widget tests, and integration test flows required to ensure high quality across Web and Mobile targets.

## Test Strategy & Coverage Targets
- **Unit Tests:** > 80% coverage on Domain Entities, Services (Rating Calculation, Team Formation, Standings Recompute), and State Stores.
- **Widget Tests:** Test all critical UI screens (`OrganizationHomeScreen`, `LiveDashboardScreen`, `MemberProfileScreen`, `TalentDiscoveryScreen`).
- **Integration Tests:** End-to-end user navigation flows using `flutter_test` and `integration_test`.

## Unit Test Matrix
1. **Rating Calculation Engine (`rating_service_test.dart`):**
   - Verify `expectedScore` formula matches `1 / (1 + 10^((RB-RA)/400))`.
   - Verify K-factor calculation based on `RatingStatus` and `VerificationTier`.
   - Test draw handling (`actualScore = 0.5`).
2. **Team Formation Engine (`team_formation_service_test.dart`):**
   - Test `random` shuffle bucket distribution.
   - Test `aiBalanced` greedy snake draft for rating variance minimization.
   - Test `houseWise` and `departmentWise` tag grouping.
3. **Scoring Plugins (`scoring_plugins_test.dart`):**
   - Test event replay immutability and undo capability for Cricket, Chess, Badminton, and Football.

## Automated Command Execution
- Run unit and widget tests: `flutter test`
- Run static code analysis: `flutter analyze`
- Run integration tests: `flutter test integration_test/app_test.dart`

## Acceptance Benchmarks
- Zero analyzer errors or warnings (`flutter analyze` passes clean).
- All unit and widget test suites execute with 100% pass rate.
""",

    "38_Deployment_Architecture.md": """# 38 Deployment Architecture Specification

## Purpose
This document details the production cloud deployment architecture, infrastructure topology, containerization, and scaling strategies for PlaySphere.

## Infrastructure Topology

```
                   +------------------------+
                   |  Cloudflare CDN / DNS  |
                   +-----------+------------+
                               |
               +---------------+---------------+
               |                               |
       +-------v-------+               +-------v-------+
       | Flutter Web   |               | REST API / WS |
       | Static (S3)   |               | Kubernetes K8s|
       +---------------+               +-------+-------+
                                               |
                                       +-------v-------+
                                       | Supabase DB   |
                                       | PostgreSQL    |
                                       +---------------+
```

## Hosting & CDN Strategy
- **Flutter Web Client:** Static web build (`flutter build web --release`) hosted on AWS S3 / Cloudflare Pages behind global Cloudflare CDN with SSL/TLS edge termination.
- **Mobile Clients:** Distributed via Apple App Store (iOS IPA) and Google Play Store (Android APK/AAB).
- **Backend API & WebSockets:** Containerized Node.js/Go services deployed on Kubernetes (EKS/GKE) with Auto-scaling (HPA) based on CPU and concurrent WebSocket connection metrics.
- **Database Layer:** Managed Supabase / PostgreSQL instance with Primary-Replica read scaling and automated daily WAL backups.

## Containerization (Docker)
```dockerfile
# Multi-stage build for Flutter Web
FROM plugfox/flutter:3.22.0 AS build
WORKDIR /app
COPY . .
RUN flutter pub get
RUN flutter build web --release

FROM nginx:alpine
COPY --from=build /app/build/web /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```
""",

    "39_CICD_Pipeline.md": """# 39 CI/CD Pipeline Specification

## Purpose
The Continuous Integration and Continuous Deployment (CI/CD) pipeline automates linting, testing, building, and deploying PlaySphere across Web, iOS, and Android platforms.

## CI/CD Workflow Stack
- **Platform:** GitHub Actions
- **Triggers:** Push to `main`, Pull Requests to `main` or `develop`.

## Pipeline Jobs

### Job 1: Static Analysis & Testing (`lint_and_test`)
- Setup Flutter SDK environment.
- Run `flutter pub get`.
- Run `flutter analyze` (fail on any error).
- Run `flutter test --coverage`.
- Upload coverage reports.

### Job 2: Web Build & Deployment (`deploy_web`)
- Depends on `lint_and_test`.
- Run `flutter build web --release --base-href "/"`.
- Deploy `/build/web` directory to AWS S3 / Cloudflare Pages.
- Purge CDN cache.

### Job 3: Android Build (`build_android`)
- Depends on `lint_and_test`.
- Setup Java 17 JDK & Android SDK.
- Run `flutter build appbundle --release`.
- Upload AAB artifact to Google Play Console Internal Track.

### Job 4: iOS Build (`build_ios`)
- Runs on macOS runner.
- Setup CocoaPods & Apple Developer Certificates.
- Run `flutter build ipa --release`.
- Upload IPA to TestFlight via Fastlane.

## GitHub Actions Workflow YAML Template
Located at `.github/workflows/main.yml` in the repository root.
""",

    "40_Security_and_Compliance.md": """# 40 Security and Compliance Specification

## Purpose
This specification outlines security protocols, data protection standards, data privacy compliance (India DPDPA & GDPR), and minor safety enforcement for the PlaySphere ecosystem.

## Data Privacy Compliance (DPDPA & GDPR)
- **Data Minimization:** Collect only essential user data required for sports operations (Name, DOB, Email/Phone).
- **Right to Erasure (Soft Delete):** Account deletion soft-deletes user PII while preserving anonymized game history and scores.
- **Data Encryption:**
  - In Transit: Mandatory TLS 1.3 for HTTPS and WSS connections.
  - At Rest: AES-256 encryption for database storage, S3 media buckets, and sensitive membership data (`medicalNotes`).

## Minor Protection & Safety Controls (Phase 6)
- **Age Verification:** Automatic calculation of minor status (`age < 18`) from `dateOfBirth`.
- **Guardian Consent Gate:** Minors cannot participate in public listings or receive scouting invites without a verified `GuardianLinkEntity`.
- **Visibility Hard-Lock:** Unverified minor profiles are strictly forced to `ProfileVisibility.private`.

## Application & API Security
- **Authentication:** OAuth 2.0 / JWT tokens with 15-minute access token lifespan and secure refresh tokens.
- **Rate Limiting:** API Gateway rate limiting (100 req/min per IP, 5 OTP attempts/hour) to prevent brute-force attacks.
- **Input Sanitization:** XSS and SQL injection prevention via parameterized ORM/Supabase queries.
- **Role Enforcement:** Server-side capability table (`kRoleCapabilityMatrix`) validation on all state mutations.
""",

    "41_Audit_Logging.md": """# 41 Audit Logging Specification

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
- Logs retained for a minimum of 7 years for compliance and dispute resolution.
""",

    "42_Reporting_and_Exports.md": """# 42 Reporting and Exports Specification

## Purpose
The Reporting and Exports module provides automated generation of tournament certificates, PDF standings summaries, CSV member rosters, and financial export reports.

## Export Capabilities

### 1. Automated PDF Certificate Generation
- **Certificate Types:** Winner, Runner-Up, Certificate of Participation, Best Player Award.
- **Template Engine:** HTML/Canvas template styled with organization logo, tournament name, signature, and QR code.
- **QR Verification:** Each certificate includes a scanned link `https://playsphere.org/verify/cert/{certId}` confirming authenticity.

### 2. Standings & Roster CSV/Excel Exports
- **Leaderboard Export:** Export tournament standings (Rank, Team, Played, Won, Lost, Tied, Points, Net Run Rate / Goal Diff) to `.csv` or `.xlsx`.
- **Registration Roster Export:** Export participant lists with contact overrides and check-in status for venue marshals.

### 3. Financial & Monetization Reports
- **Revenue Summary:** Breakdown of registration fees collected, coupon discounts applied, and payout reports per season.

## API Endpoints
- `GET /api/v1/seasons/{seasonId}/export/standings?format=pdf|csv`
- `GET /api/v1/registrations/{regId}/certificate`
""",

    "43_Integrations.md": """# 43 Integrations Specification

## Purpose
This document specifies external third-party integrations connecting PlaySphere to payment gateways, messaging networks, media storage, and authentication providers.

## Key Third-Party Integrations

### 1. Payment Gateways (Razorpay & Stripe)
- **Use Case:** Event registration fees, season passes, franchise auction deposits.
- **Currency Support:** Primary INR (Paise representation `int`), secondary USD/EUR.
- **Webhook Handlers:** Asynchronous payment confirmation (`payment.captured`) triggering automatic registration status update (`pending -> confirmed`).

### 2. Push Notifications & SMS (Firebase FCM & Twilio)
- **Use Case:** Push notifications for live score alerts, match schedule changes, OTP delivery.
- **Fallback:** SMS/WhatsApp OTP fallback when push notification delivery fails.

### 3. Cloud Media Storage (AWS S3 & Cloudflare R2)
- **Use Case:** Image uploads (organization logos, user avatars, match gallery photos) and PDF certificate hosting.
- **Optimization:** Pre-signed upload URLs and automatic WebP image compression.

### 4. WhatsApp Business API
- **Use Case:** Automated match schedule reminders and digital tournament pass delivery directly to participant WhatsApp numbers.
""",

    "44_Roadmap.md": """# 44 Product Roadmap Specification

## Vision Summary
PlaySphere evolves from a local community game engine into the nationwide operating system for organized sports across 4 strategic phases.

## Phase Timeline & Milestones

```
+------------------+-------------------+--------------------+------------------+
| Phase 1: MVP Core| Phase 2: Scale    | Phase 3: Marketplace| Phase 4: National|
| (Months 1 - 3)   | (Months 4 - 6)    | (Months 7 - 9)     | (Months 10 - 12) |
+------------------+-------------------+--------------------+------------------+
| • Auth & Identity| • Franchise League| • Venue Booking    | • National Talent|
| • Org Hierarchy  | • AI Team Shuffle | • Officiating Hub  |   Scouting Graph |
| • Seasons & Events| • Minor Protection| • Ticketing & Fees | • AI Video Recaps|
| • Live Scoring   | • ELO Rating Engine| • WhatsApp Bot    | • Federation API |
+------------------+-------------------+--------------------+------------------+
```

## Milestone Details

### Phase 1: MVP Core (Current Base)
- Multi-tenant Organization hierarchy.
- Season & Competition management.
- Live Scoring Engine (Cricket, Chess, Carrom, Badminton, Football, Basketball, Kabaddi, Volleyball).
- Basic Player Profiles and Standings Tables.

### Phase 2: Advanced Leagues & Ratings (Q3 2026)
- AI-Balanced Team Shuffle engine (ELO greedy snake draft).
- Per-sport ELO Rating calculation & append-only history.
- Minor Protection Guardian consent workflow (Phase 6).
- Portable Career Resume auto-generator (`/p/{slug}`).

### Phase 3: Venue & Officiating Marketplace (Q4 2026)
- Venue booking engine with ground availability conflict detection.
- Certified Referee/Umpire marketplace and assignment system.
- Ticketing & Sponsorship monetization modules.

### Phase 4: National Talent Graph & Federation Network (2027)
- State & National sports federation API links.
- AI automated match video highlighting and computer vision scoring.
""",

    "45_Backlog.md": """# 45 Product Backlog Specification

## Purpose
Categorized backlog of features, enhancements, and technical debt items prioritized by impact (P0 = Critical MVP, P1 = High, P2 = Medium/Nice-to-have).

## Prioritized Feature Backlog

### P0 (Critical MVP Items - Completed / In Progress)
- [x] Multi-tenant organization routing (`/org/:orgId`).
- [x] Dual portal view (Admin vs Participant) based on `OrganizationMembershipEntity.role`.
- [x] Central store (`PlaySphereStore`) seeding sample org ("Maram Garlapati Homes") and events.
- [x] Live Scoring Dashboard for real-time score entry and display.
- [x] Portable Player Profile with ELO progression chart.
- [x] Talent Discovery screen with sport category and ELO rating filter.

### P1 (High Priority Next Items)
- [ ] Add explicit `usePathUrlStrategy()` configuration for Flutter Web URL routing.
- [ ] Implement Razorpay payment gateway integration for paid registrations.
- [ ] Add Push Notification triggers via Firebase Messaging for score updates.
- [ ] Implement automated PDF certificate generator with QR verification link.
- [ ] Implement Hive local storage caching for offline scoring support.

### P2 (Enhancements & Future Capabilities)
- [ ] Add Dark Mode toggle switch in main app navigation bar.
- [ ] Implement Computer Vision ball tracking for automated cricket/tennis scoring.
- [ ] Support WhatsApp API bot for receiving match updates via chat.
- [ ] Export standings to Excel (`.xlsx`) format.

## Technical Debt & Maintenance
- Refactor all `withOpacity` calls to `.withValues()` to eliminate Flutter 3.22 deprecation warnings.
- Increase unit test coverage on `PlaySphereTeamFormationEngine` to 95%.
"""
}

for filename, content in docs.items():
    filepath = os.path.join(srs_dir, filename)
    with open(filepath, "w", encoding="utf-8") as f:
        f.write(content.strip() + "\\n")
    print(f"Wrote {filename} ({len(content)} bytes)")
