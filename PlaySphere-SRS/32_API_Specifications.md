# 32 API Specifications

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
```\n