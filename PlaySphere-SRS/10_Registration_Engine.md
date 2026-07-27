# 10 Registration Engine

## 1. Overview
The **Registration Engine** handles the enrollment of participants into a `SportCompetition`. It acts as the bridge between a `PlayerProfile` (or a `Team` of profiles) and an Event. It supports dynamic waitlists, capacity constraints, payment hooks, and skill-level declarations to ensure smooth and fair tournament entry.

## 2. Functional Requirements

### 2.1 Enrollment Modalities
*   **Individual Registration:** A player registers themselves using their `PlayerProfile`.
*   **Team Registration:** A team captain or admin registers a team entity, linking multiple `PlayerProfile` members as the roster.
*   **Guardian Registration:** A verified guardian registers a minor under their purview.
*   **Bulk Upload:** Admins can upload CSVs (containing Name, Email, Phone, DOB) to mass-register school/corporate rosters. System auto-matches or provisions shadow profiles.
*   **QR Registration:** On-site players can scan a competition QR code to instantly open the registration flow in the PlaySphere app.

### 2.2 Registration Lifecycle & Waiting List
*   **Status Progression:** Registrations flow through states: `pending` -> `confirmed` / `waitlisted` -> `withdrawn`.
*   **Auto-Promote:** If a competition reaches its `maxCapacity`, subsequent registrations are marked `waitlisted`. If a `confirmed` player withdraws, the first `waitlisted` entry is automatically promoted to `confirmed` (and notified).

### 2.3 Payment Integration Hook
*   **Paywall Support:** If a competition has an entry fee, the registration is placed in a `pending_payment` state.
*   **Gateway Interface:** The engine abstracts the payment gateway (e.g., Stripe, Razorpay). Upon receiving a successful webhook, the registration transitions to `confirmed`.

### 2.4 Self-Declared Skill Level
*   **Unrated Players:** If a player has a provisional ELO (<= 10 matches) or no rating in the sport, the registration flow prompts for a self-declared skill level (e.g., "Beginner", "Intermediate", "Advanced", "Club Professional").
*   **Seeding Impact:** This self-declaration assists the admin during manual draws or snake drafts to ensure balanced pools, functioning as a heuristic until a true ELO is established.

## 3. Data Models

### 3.1 RegistrationEntity
| Field | Type | Description |
| :--- | :--- | :--- |
| `id` | UUID | Primary key |
| `sportCompetitionId` | UUID | Foreign key to the event |
| `entrantId` | UUID | Polymorphic: `PlayerProfile.id` OR `Team.id` |
| `entrantType` | Enum | `individual`, `team` |
| `registeredByUserId` | UUID | User who performed the action (Player, Admin, Guardian) |
| `status` | Enum | `pending`, `pending_payment`, `confirmed`, `waitlisted`, `withdrawn` |
| `selfDeclaredSkill`| Enum | `null`, `beginner`, `intermediate`, `advanced`, `pro` |
| `paymentRef` | String | External payment intent ID |
| `createdAt` | DateTime | Timestamp of entry (critical for waitlist order) |

## 4. API & Integration Points
*   **`POST /api/v1/competitions/{id}/register`**: Initiates registration. Checks capacity, checks eligibility (e.g., age limits), and returns the `RegistrationEntity` and optional payment intent client secret.
*   **`POST /api/v1/registrations/{id}/withdraw`**: Cancels a registration. Triggers waitlist auto-promotion logic.
*   **Webhook Listener:** Listens for `payment_intent.succeeded` to finalize `pending_payment` registrations.

## 5. Trust & Safety & Edge Cases
*   **Age Verification Hook:** The engine cross-references the event's age restrictions (e.g., "Under 15") with the `PlayerProfile` DOB. Registrations out of bounds are blocked.
*   **Concurrency / Race Conditions:** Registrations approaching max capacity utilize database row-level locking or atomic counters to prevent over-enrollment (e.g., two people clicking "Register" when only 1 spot is left).
*   **Refund Policy:** If a `confirmed` user withdraws, the engine alerts the finance module. Automatic refunds depend on the organization's configured refund cutoff window.
