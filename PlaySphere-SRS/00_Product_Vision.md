# 00. Product Vision SRS

## 1. ONE-LINE PITCH
PlaySphere is the operating system for organized sport at every scale — from a Sunday society badminton match to a state premier league played like the IPL — unified by one live-scoring engine, one venue/team/season model, and one portable player identity.

## 2. PROBLEM STATEMENT
Currently, managing sports events relies on fragmented and disconnected tools across every layer of the sporting ecosystem. Tournaments are organized using WhatsApp groups, spreadsheet fixtures, and clipboard-based live scoring. As a result:
- **Talent is invisible:** Grassroots performance data is lost, making scouting nearly impossible.
- **History is lost:** Players have no verified record of their careers, achievements, or progression.
- **Management is chaotic:** Admins struggle with duplicative work across multiple platforms (payments, registrations, communication, scoring).
- **No Promotion Pipeline:** There is no structural link between community games and state-level federations to organically promote top talent.

## 3. SOLUTION
PlaySphere solves this by providing the **same engine at every scale**.
- **Federated Organization Hierarchy:** Nests organizations from Country > State > District > Community/School/Corporate.
- **Two Portals, One Codebase:** Seamless integration of Admin and Participant workflows natively separated by role inside the `OrganizationMembership`.
- **Portable Identity:** A single, persistent player profile that automatically builds a comprehensive sports resume across all participating leagues and tiers.
- **Unified Modeling:** Season > SportCompetition > Stage > Fixture hierarchy seamlessly supports any competition structure.

## 4. PURPOSE
The purpose of this document is to outline the overarching product vision and foundational specifications for PlaySphere. This SRS defines the functional capabilities, technical constraints, target users, and business rationale needed to architect a robust, multi-tenant Flutter application powered by Riverpod (state management) and GoRouter (navigation).

## 5. BUSINESS REQUIREMENTS
| ID | Requirement | Description |
|---|---|---|
| **BR-01** | **Multi-Tenancy** | The system must support unlimited organizations nesting hierarchically (National > State > District > Community) in a single database. |
| **BR-02** | **Freemium Monetization** | Free tier for basic community groups, Premium for advanced features (AI drafts, district/state portals), and Marketplace fees for venues and officiating. |
| **BR-03** | **Brand Whitelabeling** | State and National federations must be able to inject their branding (logos, colors) into the participant-facing UI dynamically. |
| **BR-04** | **Data Privacy & Compliance** | The platform must comply with data protection laws (e.g., DPDPA for India), especially around minor profiles, anonymization, and telemetry. |
| **BR-05** | **Scalability** | Must support peak load during massive state-level tournaments and concurrent live scoring across thousands of community fixtures on weekends. |

## 6. FUNCTIONAL REQUIREMENTS
### 6.1 Core Modules
| Module | Description |
|---|---|
| **Auth & Identity** | Secure login, portable global player profile, guardian accounts for minors. |
| **Organizations** | Multi-level hierarchical structures defining boundaries, roles, and seasons. |
| **Seasons & Competitions** | Grouping of events, multi-sport competition stages, knockouts/round-robins. |
| **Fixtures & Live Scoring** | Real-time score entry framework specific to rules (Cricket, Chess, Badminton, etc.). |
| **Team Formation** | AI-based house-wise grouping, snake drafts, manual overrides, and virtual franchise auctions. |
| **Rating Engine (ELO)** | Per-sport ELO calculations (`Expected(A) = 1/(1+10^((RB-RA)/400))`). |
| **Trust & Safety** | Linkage of minor profiles to verified guardian accounts; tier-based tournament verification. |
| **Talent Discovery** | Analytics dashboard to search players based on ELO, performance metrics, and age group. |

### 6.2 Sports Supported
- **Team Sports:** Cricket, Football, Volleyball, Basketball, Kabaddi
- **Racquet Sports:** Badminton, Table Tennis
- **Board/Strategy Sports:** Chess, Carrom
- **Custom/Generic:** Generic Plugin for unstructured or custom points-based games.

## 7. NON-FUNCTIONAL REQUIREMENTS
- **Performance:** App screens must render in < 2 seconds. API response time must be under 200ms.
- **Offline Capability:** Mobile app must support offline scoring capabilities with auto-sync when network is restored.
- **Real-Time Sync:** Fixture live scoring and ELO updates must push to connected clients via WebSockets/Server-Sent Events in real time.
- **Cross-Platform:** The Flutter application must deploy seamlessly to iOS, Android, and Web (Responsive Admin Portal & Participant Dashboards).
- **State Management:** Strict adherence to Riverpod for immutable state and GoRouter for deep linking.

## 8. USER STORIES
- **As a Player**, I want a unified profile that tracks my ELO rating and match history across different communities, so I can showcase my verifiable sports resume.
- **As a Community Admin**, I want to auto-generate a tournament schedule using an AI snake draft, so I can ensure balanced teams and save time.
- **As a Parent/Guardian**, I want to manage my child's profile and consent to their participation, so I can ensure their safety and track their progress.
- **As a State Federation Official**, I want to discover the top ELO-rated players from district competitions, so I can invite them to state trials.
- **As a Scorer**, I want an offline-capable, easy-to-use live scoring interface, so I can log runs/points even when cellular data drops at the venue.

## 9. USER FLOW (High-Level)
1. **Onboarding:** User downloads app -> Authenticates (OTP/OAuth) -> Completes Portable Profile.
2. **Discovery/Join:** User browses Organizations (or scans QR code) -> Joins Community Org.
3. **Registration:** Admin creates Season & SportCompetition -> User registers / pays entry fee.
4. **Drafting:** Admin runs AI Draft -> Teams are formed -> Fixtures generated.
5. **Match Day:** Scorer opens Fixture -> Logs points in real-time -> Live scoreboard updates for spectators.
6. **Post-Match:** Final whistle -> Stats aggregated -> ELO ratings recalculated -> Player profile updated automatically.

## 10. UI SCREENS (Core)
- **Global Dashboard:** Feed of live matches, upcoming fixtures, and organizational announcements.
- **Player Resume (Profile):** Displays global ELO ratings per sport, trophy cabinet, match history, and verified status.
- **Admin Workspace:** Web-optimized responsive view managing members, seasons, and registrations.
- **Live Scoring Hub:** Sport-specific UI (e.g., cricket wagon wheel, chess timer sync) optimized for fast tap entry.
- **Draft/Auction Room:** Real-time view for team owners to bid on players or view AI draft progression.

## 11. DATABASE DESIGN (High-Level Entities)
- **User:** ID, Phone, Name, DOB, Global ELO Matrix.
- **Organization:** ID, ParentOrgID (Nullable for root), Name, Tier (Community/District/State).
- **OrganizationMembership:** UserID, OrgID, Role (Admin, Scorer, Player), Status.
- **Season:** ID, OrgID, StartDate, EndDate, Status.
- **SportCompetition:** ID, SeasonID, SportType, Format, Ruleset.
- **Fixture:** ID, CompetitionID, TeamAID, TeamBID, StartTime, Venue, Status, FinalScore.
- **GuardianLink:** MinorUserID, GuardianUserID, VerifiedStatus.

## 12. API ENDPOINTS (Examples)
- `POST /api/v1/auth/verify-otp` - Authenticate user.
- `GET /api/v1/organizations/{id}/hierarchy` - Fetch nested structure.
- `POST /api/v1/competitions/{id}/draft/ai-snake` - Trigger AI team formation.
- `PUT /api/v1/fixtures/{id}/live-score` - Push real-time score updates.
- `GET /api/v1/players/{id}/resume` - Fetch aggregated career stats.

## 13. VALIDATION RULES
- **Minor Accounts:** Any user with DOB yielding age < 18 MUST have an active GuardianLink to participate in sanctioned tournaments.
- **ELO Integrity:** ELO recalculations can only occur if the fixture is marked as `COMPLETED` and approved by an Admin/Umpire.
- **Hierarchical Scoping:** District events can only invite participants who are registered in child Community organizations.

## 14. PERMISSIONS
| Role | Capabilities |
|---|---|
| **Platform Admin** | Manage global taxonomy, plugins, subscription tiers. |
| **Org Admin** | Create seasons, manage memberships, override drafts, edit fixtures. |
| **Umpire/Scorer** | Edit live scores, validate match results, submit injury reports. |
| **Player** | Register for events, edit personal profile, view leaderboards. |
| **Guardian** | Manage dependent profiles, approve registrations, view child's schedule. |

## 15. NOTIFICATIONS
- **Push:** "Your match starts in 15 minutes at Court 2."
- **In-App:** "You have been drafted to Team Spartans for the Summer League!"
- **Email:** End-of-season summary and ELO update reports.
- **Real-Time Pub/Sub:** "Wicket! Player X is out, caught by Y." (Sent to subscribers of the live match).

## 16. ERROR HANDLING & EDGE CASES
- **Network Drop during Live Scoring:** Data queued locally in Hive/Isar DB. UI shows "Syncing..." icon. Auto-retries on connection restore.
- **Abandoned Matches:** Admin must manually select "No Result" or "Awarded to X". ELO engine skips calculation.
- **Draft Ties / Not Enough Players:** AI draft algorithm prompts Admin to either reduce team sizes or inject dummy players (byes).
- **Disputed Scores:** Provides a "Flag Result" button for team captains to halt ELO updates until admin review.

## 17. ACCEPTANCE CRITERIA
- AC1: A user can create an Organization, nest it under a parent District, and successfully launch a Season.
- AC2: A Scorer can log points offline, and the system synchronizes seamlessly upon reconnection without data loss.
- AC3: The AI Draft successfully distributes players into balanced teams based on their global ELO ratings.
- AC4: The web Admin portal and mobile app share the same Riverpod state models for real-time consistency.
- AC5: All minor accounts are functionally restricted from event registration until a Guardian approves.

## 18. FUTURE ENHANCEMENTS
- **Video Highlights Integration:** Auto-clipping of live streams based on scoring event timestamps.
- **Wearable Integration:** Syncing heart rate and movement data for advanced player analytics.
- **Web3 Identity:** Decentralized storage of sports credentials and certificates.
- **Predictive AI:** Forecasting match outcomes based on historical ELO and team synergy scores.
