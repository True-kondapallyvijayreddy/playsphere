# 13 Scoreboard Framework (Plugin Architecture)

## 1. Overview
The **Scoreboard Framework** handles live match scoring across a diverse range of sports. Because a chess match is scored vastly differently than a cricket match, PlaySphere employs a **Plugin Architecture**. Each sport utilizes a dedicated scoring plugin that interprets atomic events, updates the match state, and determines the final result, while the core framework manages persistence, live web-sockets, and undo operations.

## 2. Framework Architecture

### 2.1 The `ScoringPlugin` Interface
Every sport scoring logic implements a unified interface/contract in the backend and frontend:
*   **`key`**: Unique identifier (e.g., `cricket_t20`, `badminton_standard`).
*   **`initialState()`**: Returns the JSON structure representing a 0-0 start.
*   **`applyEvent(currentState, event)`**: A pure function that takes the current state, applies an event payload (e.g., "Goal Scored", "Wicket"), and returns the new state.
*   **`isMatchComplete(state)`**: Evaluates if the win condition is met (e.g., 2 sets won, time expired).
*   **`deriveResult(state)`**: Extracts the final outcome (Winner, Loser, Scoreline) for ELO processing.
*   **`renderSummary(state)`**: Generates a human-readable summary (e.g., "Team A won by 4 wickets", "6-4, 6-2").

### 2.2 Built-in Plugins
1.  **`simple_win_loss`**: (Chess, Carrom, Table Tennis) - Tracks basic points or direct win/loss declarations.
2.  **`set_based`**: (Badminton, Volleyball, Tennis) - Tracks points within sets, manages serve possession, and handles deuces/tie-breaks.
3.  **`run_based`**: (Cricket) - Complex state tracking balls, overs, runs, wickets, extras, and strike rotation.
4.  **`goal_based`**: (Football, Basketball, Kabaddi) - Tracks time, goals/points, halves/quarters, and fouls.

### 2.3 Event-Sourcing & Undo Mechanism
*   **Append-Only Events:** Instead of mutating the score directly in the database, the framework saves atomic `MatchEvent` records (e.g., `{"type": "point_won", "team": "A"}`).
*   **State Reconstruction:** The current match state is the `initialState` folded over all `MatchEvent`s using the plugin's `applyEvent`.
*   **Undo Functionality:** "Undo" is handled natively by deleting (or soft-deleting) the most recent `MatchEvent` and replaying the remaining events through the plugin to derive the corrected state.

### 2.4 Live Web-Sockets
*   Scorers use the PlaySphere admin app (Flutter). Tapping a scoring button emits a `MatchEvent`.
*   The backend validates the event via the plugin, saves it, calculates the new state, and broadcasts the new state over a Web-Socket channel (e.g., `/topic/fixture/{id}`).
*   Spectators on the participant portal subscribe to this channel for sub-second live score updates.

## 3. Data Models

### 3.1 Fixture
| Field | Type | Description |
| :--- | :--- | :--- |
| `id` | UUID | Primary key |
| `sportCompetitionId` | UUID | Parent competition |
| `pluginKey` | String | e.g., `badminton_standard` |
| `entrantA_Id` | UUID | Player/Team A |
| `entrantB_Id` | UUID | Player/Team B |
| `status` | Enum | `scheduled`, `live`, `completed` |
| `currentState` | JSON | Denormalized snapshot for fast reads |

### 3.2 MatchEvent
| Field | Type | Description |
| :--- | :--- | :--- |
| `id` | UUID | Primary key |
| `fixtureId` | UUID | Match being scored |
| `sequence` | Integer | Order of the event (1, 2, 3...) |
| `payload` | JSON | Event data specific to plugin |
| `timestamp` | DateTime | When the event occurred |

## 4. Post-Match Hooks (ELO Integration)
When `isMatchComplete()` returns `true`:
1.  The scorer confirms the result.
2.  Fixture status moves to `completed`.
3.  `deriveResult()` outputs the winner.
4.  The **Event Engine** updates the competition standings/brackets.
5.  The **User Profile Engine** calculates and applies the ELO rating adjustments to both entrants' ledgers.

## 5. Edge Cases & Considerations
*   **Offline Scoring:** If a scorer loses internet connection, the Flutter app queues `MatchEvent`s locally. Upon reconnection, it syncs the queue in sequence to the backend to reconstruct the state.
*   **Manual Overrides:** Sometimes the pure event stream gets irreparably messed up by human error. Plugins must expose a "Manual Correction Event" payload that acts as a hard state-override, allowing admins to manually type in "Score is 15-14" bypassing standard rules.
