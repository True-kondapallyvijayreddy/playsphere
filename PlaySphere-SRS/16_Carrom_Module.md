# PlaySphere Software Requirements Specification
## 16. Carrom Module

### 1. Introduction
This document outlines the requirements for the Carrom Module within PlaySphere. The module provides scoring, event tracking, and match logic tailored for both competitive and casual carrom matches.

### 2. Core Scoring & Match Logic
Carrom matches are set-based and track specific in-game events relevant to the sport.

#### 2.1 Match Format
- **Sets/Boards:** Matches are played as a series of boards.
  - Typical configurations: Best-of-3 or Best-of-5 boards.
- **Formats Supported:**
  - **Singles:** 1v1 (Individual entrant)
  - **Doubles:** 2v2 (Team entrant)

#### 2.2 In-Game Events
The PlaySphere scorer will track the following events during a carrom match:
- `board_won`: Emitted when a board concludes.
  - **Parameters:** `winner_id` (participant or team), `points_scored` (calculated based on opponent's remaining pieces + queen points if applicable).
- `queen_pocketed`: Tracks which player pocketed the Queen.
- `cover_given`: Tracks if the Queen was successfully covered.

#### 2.3 Board Winning Logic
- A board is won when a player/team is the first to pocket all their designated pieces (White or Black).
- **Queen Rule:** The Queen must be pocketed and successfully covered by the same player/team before they can win the board. If the cover fails, the Queen is returned to the center.

### 3. Tournament Formats & Standings
The Carrom Module supports standard PlaySphere tournament structures (Round Robin, Knockout, Groups).

#### 3.1 Standings & Points
- **Match Points (League/Group Stage):**
  - Win = 3 points
  - Draw = 1 point (if applicable in specific tournament rules)
  - Loss = 0 points
- **Tiebreakers:**
  - **Primary:** Board difference (Boards won minus Boards lost).
  - **Secondary:** Total points scored across all boards.
  - **Tertiary:** Direct encounter (Head-to-head).

### 4. Data Models (Extensions)

#### 4.1 CarromMatchState
| Field | Type | Description |
|-------|------|-------------|
| `format` | Enum | `singles`, `doubles` |
| `boards_config` | Integer | Total boards to win (e.g., 3 for best-of-5) |
| `current_board` | Integer | The board currently being played |
| `board_scores` | Array | History of scores and winners for each completed board |
| `queen_status` | Enum | `on_board`, `pocketed`, `covered` |

### 5. User Interface Requirements
- **Participant Portal:** Match score entry interface allowing users to log who won the board, the points scored, and who secured the Queen.
- **Admin Portal:** Live scoring dashboard, ability to correct board scores, and standings view with tiebreaker details (board difference).

### 6. Future Enhancements (v2+)
- Break/Strike tracking (who takes the first strike per board).
- Foul tracking (e.g., pocketing the striker).
- Detailed points calculation engine based on exact pieces remaining.
