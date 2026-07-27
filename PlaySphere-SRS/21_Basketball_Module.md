# 21 Basketball Module

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
- Shot clock integration and detailed shot chart mapping.\n