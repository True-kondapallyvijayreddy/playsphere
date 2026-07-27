# Football Module SRS

## 1. Overview
The Football (Soccer) module handles goal-based scoring for PlaySphere. It scales to accommodate everything from standard 90-minute 11-a-side matches to smaller-sided 5-a-side community games, tracking goals, cards, and substitutions.

## 2. Match Structure & Configuration
- **Match Structure**: Two halves.
- **Configurable Settings**: 
  - Half duration (default 45 mins, scalable to 20/30 mins for community/youth).
  - Extra time availability (default 15 mins per half).
  - Penalty shootouts (for knockout stages).

## 3. Scoring Rules & Win Conditions
- **Goals**: Team with the most goals at the end of regulation (and extra time, if applicable) wins.
- **Ties**: Regular season matches can end in a draw. Knockout matches proceed to Extra Time and Penalties.

## 4. Match Events
| Event Type | Description | Data Payload |
| --- | --- | --- |
| `goal` | Regular goal scored. | `player_id`, `assist_player_id`, `time` |
| `own_goal` | Goal scored in own net. | `player_id`, `time` |
| `penalty` | Goal scored via penalty. | `player_id`, `time` |
| `yellow_card` | Booking. | `player_id`, `reason`, `time` |
| `red_card` | Dismissal. | `player_id`, `reason`, `time` |
| `substitution` | Player change. | `player_in_id`, `player_out_id`, `time` |

## 5. Standings & Tie-breakers
- **Points Allocation**: Win = 3, Draw = 1, Loss = 0.
- **Tie-breakers**: 
  1. Goal Difference (Goals For - Goals Against).
  2. Goals Scored (Total Goals For).
  3. Head-to-Head.

## 6. ELO & Ranking Adjustments
- Standard Elo applied: `Expected(A) = 1/(1+10^((RB-RA)/400))`.
- Margin of victory multiplier is applied to the base delta depending on the goal difference to reward dominant wins.

## 7. Data Models
```json
{
  "match_id": "uuid",
  "sport": "football",
  "score": {"team_A": 2, "team_B": 1},
  "clock_status": "running",
  "current_time_seconds": 2450,
  "events": []
}
```

## 8. State Management (Riverpod)
- `FootballMatchNotifier`: Tracks running clock, score, and aggregates card data.
- `MatchClockProvider`: Specialized provider to handle start, pause, and stoppage time calculations.

## 9. UI/UX Considerations
- **Match Clock**: Prominent timer, showing stoppage time clearly (e.g. 45:00 + 2:10).
- **Timeline View**: Visual representation of when goals and cards occurred along a match timeline axis.
- **Roster Management**: Drag-and-drop interface for substitutions during live scoring.
