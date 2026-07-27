# 07 User Profile (Portable Player Identity)

## 1. Overview
PlaySphere provides a **Portable Player Identity** system that ensures a user has one global `PlayerProfile` across all organizations in the platform (from community clubs to state leagues). The profile serves as an automatically updating resume, tracking their per-sport ELO ratings, match history, and achievements over their entire career. It acts as the definitive source of truth for a player’s skill level and participation history across the ecosystem.

## 2. Functional Requirements

### 2.1 Profile Creation & Initialization
*   **Auto-creation:** A `PlayerProfile` is automatically generated when a `User` account is created. 
*   **Global Identifier:** The profile is assigned a unique slug `/{slug}` used for public or semi-public sharing.
*   **Cross-Tenant Access:** Organizations do not "own" player profiles. They create `OrganizationMembership` records that link to the global `PlayerProfile`.

### 2.2 Per-Sport ELO Rating System
*   **Seed Rating:** All players start with a baseline ELO of **1200** for each new sport they participate in.
*   **Provisional Status:** The first **10 matches** in a sport are marked as *provisional*. Provisional ratings have higher K-factors for rapid adjustment and may be hidden or marked visually (e.g., `1200?`) until the 10-match threshold is passed.
*   **Expected Score Formula:** `Expected(A) = 1 / (1 + 10 ^ ((Rating_B - Rating_A) / 400))`
*   **Rating Adjustments:** Post-match, ELO is updated based on actual result vs. expected result. 

### 2.3 Achievement & Career Timeline
*   **Automated Timeline:** As a player competes, their timeline automatically populates with milestones (e.g., "Registered for Summer League", "Won District Final", "Reached 1500 ELO in Chess").
*   **Season Completion Hook:** When an organization marks a `Season` or `SportCompetition` as completed, the system auto-generates achievement badges for winners/runners-up and appends them to the respective profiles.
*   **Career Page View:** Accessible at `/p/{slug}`, presenting a structured resume containing top ELOs, recent form, win rates, and trophy cabinet.

### 2.4 Talent Discovery & Scouting
*   **Search Engine:** Authorized scouts and organization admins can search for talent across the public platform.
*   **Filters:** Search by `Sport`, `Age Group` (derived from DOB securely), `Region / Distance`, and `ELO Range`.
*   **Privacy Consideration:** Players must opt-in to "Scout Visibility" unless they are part of a sanctioned elite tier that mandates public listing.

## 3. Data Models

### 3.1 PlayerProfile
| Field | Type | Description |
| :--- | :--- | :--- |
| `id` | UUID | Primary key |
| `userId` | UUID | Foreign key to User account |
| `slug` | String | Unique profile URL slug |
| `visibility` | Enum | `public`, `private`, `scout_only`, `guardian_locked` |
| `createdAt` | DateTime | Timestamp of creation |

### 3.2 SportRating (Ledger Summary)
| Field | Type | Description |
| :--- | :--- | :--- |
| `playerProfileId` | UUID | Foreign key to PlayerProfile |
| `sportType` | Enum | e.g., `cricket`, `chess`, `badminton` |
| `currentElo` | Integer | Current ELO rating (defaults to 1200) |
| `matchCount` | Integer | Total matches played (<= 10 is provisional) |
| `highestElo` | Integer | All-time highest ELO in this sport |

### 3.3 EloHistoryLedger
An append-only table to track rating changes for auditability and graph plotting.
| Field | Type | Description |
| :--- | :--- | :--- |
| `id` | UUID | Ledger entry ID |
| `playerProfileId` | UUID | Foreign key |
| `sportType` | Enum | Sport identifier |
| `fixtureId` | UUID | The match that caused the change |
| `previousElo` | Integer | Rating before the match |
| `newElo` | Integer | Rating after the match |
| `timestamp` | DateTime | When the change was applied |

## 4. Trust & Safety (Minor Protection)

*   **Under-18 Accounts:** Any profile with a Date of Birth indicating an age under 18 is flagged as a Minor account.
*   **Visibility Lock:** Minor profiles have their `visibility` hard-locked to `private` or `guardian_locked` by default. They cannot appear in Talent Discovery searches or public career pages.
*   **Guardian Link Verification:** A Minor profile can only have its visibility relaxed if linked to a verified Guardian account (KYC or phone verified) who explicitly consents to specific visibility toggles (e.g., allowing college scouts to view the profile).

## 5. User Interfaces (Flutter/Riverpod)
*   **My Profile Screen:** Tabbed view showing Summary, ELO Charts (using a plotting library), Match History, and Settings.
*   **Public Career Page:** Read-only web/app view fetched via `slug`. Hides sensitive PII (like exact DOB or phone number) while showcasing sports stats.
*   **Scout Dashboard:** Advanced data table view with multi-select filtering for region, age, and ELO.

## 6. Edge Cases & Considerations
*   **Account Merging:** Occasionally parents create an account for a child, and the child creates one later. Support for merging `PlayerProfile` data (moving match histories and recalculating ELO) must be available to Super Admins.
*   **ELO Deflation/Inflation:** Periodic season resets or inactivity decay may need to be introduced in the future to prevent ELO hoarding.
