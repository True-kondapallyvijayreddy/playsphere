# 40 Security and Compliance Specification

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
- **Role Enforcement:** Server-side capability table (`kRoleCapabilityMatrix`) validation on all state mutations.\n