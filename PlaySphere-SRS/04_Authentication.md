# 04 Authentication

## Purpose
This document defines the identity, authentication, and session management requirements for PlaySphere. It outlines the mechanisms for securely verifying users, handling minors, persisting sessions, and seamlessly routing authenticated users into their respective multi-tenant organizational contexts.

## Business Requirements
- **Frictionless Onboarding**: Provide diverse login methods (Email, Google SSO, Phone OTP) to maximize adoption across demographics.
- **Market Specificity**: Prioritize Phone OTP as the primary authentication method for the Indian market.
- **Demonstration Capability**: Support a "skip-login" mode for instant access to demo environments (e.g., `/org/maram-homes`) without credentials.
- **Child Protection**: Comply with minor safety regulations by enforcing read-only access for users under 18 until a verified guardian link is established.
- **Historical Integrity**: Ensure that deleted accounts retain their identity context for past sports matches and statistics (soft deletion).

## Functional Requirements
- **Auth Providers**: The system must support authentication via Email+Password, Google SSO (OAuth2), and Phone OTP.
- **Skip-Login Mode**: In development or demo environments, the app must optionally bypass the authentication screen and boot directly into a hardcoded organization route (`/org/maram-homes`) with a mock user session.
- **Minor Handling**: The system must compute age from the user's `dateOfBirth`. If the user is under 18, self-registration forces the account into a read-only state. Full write capabilities are unlocked only via the Guardian Link flow (Phase 6).
- **Session Management**: Authentication state must be maintained using JWT (JSON Web Tokens) with a short-lived access token and a long-lived refresh token. Sessions must persist across app restarts using secure on-device storage.
- **Multi-Org Routing**: Post-login, users must not enter a "global" logged-in state; instead, they must be presented with a list of their associated organizations. Selecting an organization loads the specific tenant context. User roles are tied to the OrganizationMembership, not the global user object.
- **Forgot Password**: The system must provide an email-based password reset workflow with a secure, single-use link that expires in 15 minutes.
- **Account Deletion**: Users must be able to delete their accounts. Deletion must be implemented as a "soft delete" (changing `accountStatus` to `deleted`), blocking all future logins and writes while preserving the user's historical match results and ELO ratings.

## Non-Functional Requirements
- **Security & Storage**: JWT refresh tokens and sensitive credentials must be stored in the device's secure enclave/keychain (e.g., `flutter_secure_storage`).
- **Performance**: Token refresh operations must occur transparently in the background without interrupting the user experience.
- **Scalability**: The authentication service must handle concurrent login spikes typical during large weekend sporting events.

## User Stories
- As a **casual user**, I want to log in using my phone number and an OTP so I don't have to remember a password.
- As a **developer/sales rep**, I want to bypass login so I can quickly demonstrate the app's features using a pre-configured organization.
- As a **player in multiple leagues**, I want to choose which organization I am interacting with right after I log in.
- As a **system administrator**, I want users to be locked out after multiple failed login attempts to prevent brute-force attacks.
- As a **parent**, I want my child's account to be restricted until I explicitly verify and link my guardian account to theirs.

## User Flow
1. **Launch**: App checks for an existing valid JWT in secure storage.
   - *If Valid*: User is navigated to the Organization Selection screen (or directly into the last visited org).
   - *If Invalid/Missing*: User is navigated to the Login screen.
   - *If Skip-Login Enabled*: App injects mock tokens and routes directly to `/org/maram-homes`.
2. **Login/Registration**: User selects Auth Provider (Phone OTP, Google SSO, or Email/Password).
3. **Age Verification**: Upon initial registration, the user provides a Date of Birth. If <18, the account is flagged for Guardian Linking.
4. **Org Selection**: After successful authentication, the API returns a list of the user's `OrganizationMembership` entries. The user selects an organization to enter the main app interface.

## UI Screens
| Screen Name | Description | Key Elements |
| :--- | :--- | :--- |
| **Login / Sign Up** | Primary entry point for unauthenticated users. | Phone input, Email input, "Continue with Google" button, "Forgot Password" link. |
| **OTP Verification** | Screen to input the 6-digit code sent via SMS. | 6-digit input field, Resend timer, "Change Phone Number" button. |
| **Profile Setup** | First-time registration details. | Full Name, Date of Birth (mandatory), Avatar upload. |
| **Organization Selector** | Post-login screen showing available tenants. | List of organization cards, "Create New Organization" button. |
| **Forgot Password** | Email input for password reset. | Email field, "Send Reset Link" button. |

## Database Design

### `users` Table
| Column Name | Type | Constraints | Description |
| :--- | :--- | :--- | :--- |
| `id` | UUID | PRIMARY KEY | Unique identifier for the user. |
| `fullName` | VARCHAR(100) | NOT NULL | User's display name. |
| `email` | VARCHAR(255) | UNIQUE, LOWERCASED | Email address (used for login and communications). |
| `phone` | VARCHAR(20) | UNIQUE (if present) | Primary for Indian market OTP login. |
| `dateOfBirth` | DATE | NOT NULL | Used to compute age and trigger minor restrictions. |
| `authProvider` | ENUM | NOT NULL | `email`, `google`, `phone` |
| `passwordHash` | VARCHAR(255) | NULLABLE | Null if `authProvider` is not `email`. |
| `avatarUrl` | VARCHAR(500) | NULLABLE | URL to profile picture. |
| `accountStatus` | ENUM | DEFAULT 'active' | `active`, `suspended`, `deleted` |

### `organization_memberships` Table *(Reference Context)*
Roles and permissions are defined here rather than on the global user. Maps `userId` to `organizationId` with a specific `role` (e.g., `admin`, `participant`).

## API Endpoints
| Method | Endpoint | Description | Payload/Response |
| :--- | :--- | :--- | :--- |
| `POST` | `/api/v1/auth/register` | Register a new user | Body: `{ email, password, fullName, dob, phone }` |
| `POST` | `/api/v1/auth/login` | Authenticate with credentials | Body: `{ email, password }` or `{ phone, otp }` |
| `POST` | `/api/v1/auth/sso/google` | Authenticate via Google | Body: `{ idToken }` |
| `POST` | `/api/v1/auth/otp/send` | Send OTP to phone | Body: `{ phone }` |
| `POST` | `/api/v1/auth/refresh` | Refresh JWT session | Body: `{ refreshToken }` |
| `POST` | `/api/v1/auth/forgot-password` | Request reset link | Body: `{ email }` |
| `DELETE` | `/api/v1/users/me` | Soft delete account | Response: `204 No Content` |

## Validation Rules
- **Email**: Must conform to standard email regex and be converted to lowercase before insertion.
- **Phone**: Must include country code and validate against standard phone number lengths.
- **Password Complexity**: Minimum 8 characters, at least one uppercase letter, one number, and one special character.
- **Date of Birth**: Cannot be in the future.

## Permissions
- **Global**: A newly registered user has global read access to public organization directories but no write access anywhere until they join an organization.
- **Minors**: Users computed as <18 years old have their global write permissions revoked (read-only mode) until `guardianId` is successfully linked.
- **Deleted Accounts**: Accounts with `accountStatus = 'deleted'` immediately fail token validation at the API gateway layer.

## Notifications
- **Welcome Email/SMS**: Sent upon successful registration.
- **OTP Delivery**: SMS containing the 6-digit authentication code.
- **Password Reset**: Email containing the secure reset link.
- **Security Alert**: Email notification sent if a login occurs from a new device or unrecognized IP.

## Error Handling
- **Invalid Credentials**: Generic error message: "Invalid email/phone or password" to prevent user enumeration.
- **Rate Limited**: HTTP 429 Too Many Requests: "Too many attempts. Please try again in X minutes." (Max 5 OTP attempts/hour)
- **Account Locked**: "Your account has been temporarily locked due to 5 failed login attempts. Check your email to unlock."
- **Suspended/Deleted Account**: "This account has been deactivated. Contact support for assistance."

## Edge Cases
- **Phone Number Reassignment**: If a phone number is recycled by a telecom provider, the new owner cannot access the old user's data because they do not have the linked email or Google SSO fallback (requires manual support intervention for account recovery vs. creation).
- **Timezone Differences for DOB**: Age calculation must consider the server's UTC date against the user's registered local DOB.
- **Expired Refresh Token**: If the refresh token expires while the app is backgrounded, the user must be cleanly routed back to the login screen without crashing.

## Acceptance Criteria
- [ ] Users can successfully register and login via Email, Google, and Phone OTP.
- [ ] Attempting 5 incorrect OTPs or passwords locks the account or blocks the IP.
- [ ] Launching the app with skip-login enabled immediately loads `/org/maram-homes` with a mock session.
- [ ] Users under 18 can register but are blocked from creating teams, joining paid leagues, or sending messages until a guardian is verified.
- [ ] JWT tokens are securely stored and automatically refreshed.
- [ ] Deleting an account preserves the user's historical match data (ELO ratings, fixture appearances) but permanently disables login access.

## Future Enhancements
- **Biometric Login**: Support for FaceID / TouchID to unlock the app or authorize sensitive actions.
- **Passkeys**: Transition from password-based flows to WebAuthn/Passkeys for improved security.
- **Multi-Factor Authentication (MFA)**: Allow admins of high-tier organizations to enforce 2FA for their members.
