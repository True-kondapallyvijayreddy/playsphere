# Badminton Module SRS

## 1. Overview
The Badminton module in PlaySphere is designed to handle set-based scoring (specifically games) for Singles, Doubles, and Mixed Doubles formats. It supports best-of-3 games, strictly adhering to the standard BWF (Badminton World Federation) rules up to 21 points with a cap at 30 points.

## 2. Match Structure & Configuration
- **Match Formats**: Singles (Men's, Women's, Boys', Girls'), Doubles, Mixed Doubles.
- **Match Structure**: Best-of-3 games.
- **Configurable Settings**: 
  - Number of games (default 3).
  - Target score per game (default 21).
  - Deuce requirement (default must win by 2 points).
  - Score cap (default 30).

## 3. Scoring Rules & Win Conditions
- **Rally Scoring System**: A point is scored on every serve regardless of who serves.
- **Game Win Condition**: First to 21 points. If the score becomes 20-all, the side which gains a two-point lead first wins that game.
- **Cap**: If the score becomes 29-all, the side scoring the 30th point wins the game.
- **Match Win Condition**: The first side to win 2 games wins the match.
- **Serve Rotation**: In doubles, serve rotates between partners based on the even/odd score.

## 4. Match Events
| Event Type | Description | Data Payload |
| --- | --- | --- |
| `point_won` | Awarded to either team. | `team_id`, `player_id` (scorer) |
| `game_won` | Triggered when a team reaches target score. | `team_id`, `game_number` |
| `fault` | Service fault, net fault, etc. | `player_id`, `fault_type` |
| `interval` | Break at 11 points and between games. | `timestamp`, `duration` |

## 5. Standings & Tie-breakers
- **Points Allocation**: Win = 2 points, Loss = 0 points.
- **Tie-breakers**: 
  1. Head-to-Head result.
  2. Games Difference (Games Won - Games Lost).
  3. Points Difference (Total Points Won - Total Points Lost).

## 6. ELO & Ranking Adjustments
- Singles match outcome recalculates ELO: `Expected(A) = 1/(1+10^((RB-RA)/400))`
- Doubles match outcome averages the ELO of the pair before calculation and applies the delta evenly.

## 7. Data Models
```json
{
  "match_id": "uuid",
  "sport": "badminton",
  "format": "singles",
  "games": [
    {"game_number": 1, "score_team_A": 21, "score_team_B": 19},
    {"game_number": 2, "score_team_A": 22, "score_team_B": 20}
  ],
  "current_server_id": "uuid"
}
```

## 8. State Management (Riverpod)
- `BadmintonMatchNotifier`: Manages real-time score updates, current game state, and serve rotation logic.
- `BadmintonEventProvider`: Handles live streaming of events for spectators.

## 9. UI/UX Considerations
- **Scoreboard**: Large, readable digits, indicating who is currently serving.
- **Serve Indicators**: Visual cue on the scoreboard showing which side and player is serving.
- **Quick Event Buttons**: Easy taps for "+1 Point" for each side to keep scoring fast for umpires.
