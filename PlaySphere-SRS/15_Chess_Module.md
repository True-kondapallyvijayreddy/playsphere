# PlaySphere Software Requirements Specification
## 15. Chess Module

### 1. Introduction
This document outlines the requirements for the Chess Module within PlaySphere. The Chess Module provides a specialized scoring plugin and event tracking system tailored for chess tournaments and casual games. Version 1 focuses on match results without move-by-move tracking.

### 2. Core Scoring & Match Logic
The Chess Module uses a simple Win/Loss/Draw scoring system for individual matches.

#### 2.1 Match Result Processing
- **No Move-by-Move Tracking:** In v1, the module does not validate or store PGN (Portable Game Notation) or track individual moves.
- **Match Events:**
  - `game_result`: Finalizes the match.
    - **Parameters:**
      - `result`: `white_win`, `black_win`, `draw`
      - `method`: `checkmate`, `stalemate`, `resignation`, `timeout`, `agreement`

#### 2.2 Time Controls
Time controls dictate the pace of the game and are configurable at the fixture or tournament level.
- **Supported Pre-sets:**
  - **Rapid:** 15 minutes + 10 seconds increment (15+10)
  - **Blitz:** 5 minutes + 3 seconds increment (5+3)
  - **Classical:** 30 minutes + 0 seconds increment (30+0)
- **Custom Configuration:** Admins can define custom base time (minutes) and increment (seconds per move).

### 3. Tournament Formats & Pairing
The Chess Module supports common tournament structures.

#### 3.1 Pairing Systems
- **Swiss System:** Players are paired each round against opponents with a similar running score, without playing the same opponent twice.
- **Round Robin:** Every participant plays against every other participant.

#### 3.2 Standings & Points
- **Match Points:**
  - Win = 1 point
  - Draw = 0.5 points
  - Loss = 0 points
- **Tiebreakers:**
  - **Primary:** Buchholz (sum of opponents' scores).
  - **Secondary:** Direct encounter (head-to-head).

### 4. ELO Rating System
PlaySphere's core ELO rating engine is natively adapted for the Chess Module.

#### 4.1 Rating Calculations
- **Formula:** Expected(A) = 1 / (1 + 10^((RB - RA) / 400))
- **K-Factor Rules:**
  - `K=32`: For provisional players (e.g., fewer than 30 rated games).
  - `K=16`: For established players.

### 5. Data Models (Extensions)

#### 5.1 ChessMatchState
| Field | Type | Description |
|-------|------|-------------|
| `white_player_id` | UUID | User ID of the player with white pieces |
| `black_player_id` | UUID | User ID of the player with black pieces |
| `result` | Enum | `white_win`, `black_win`, `draw`, `pending` |
| `method` | Enum | The method of the result |
| `time_control` | String | E.g., "15+10" |

### 6. User Interface Requirements
- **Participant Portal:** Display side-by-side player profiles with colors (White/Black), current ratings, and match result submission forms.
- **Admin Portal:** Swiss pairing generation dashboard, overriding match results, adjusting time controls, and viewing ELO changes per round.

### 7. Future Enhancements (v2+)
- PGN upload and parsing.
- Real-time digital clock integration.
- Anti-cheat detection algorithms for online play.
