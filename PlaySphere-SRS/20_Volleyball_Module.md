# Volleyball Module SRS

## 1. Overview
The Volleyball module tracks set-based scoring for matches. It handles rapid point progression and set tracking, catering to indoor, beach, and community variants.

## 2. Match Structure & Configuration
- **Match Structure**: Best-of-5 sets (configurable to Best-of-3).
- **Configurable Settings**: 
  - Target score per set (default 25 points for sets 1-4, 15 points for set 5).
  - Must win by 2 points rule.
  - Score caps (if applicable by specific community rules).

## 3. Scoring Rules & Win Conditions
- **Rally Scoring**: A point is scored on every rally.
- **Set Win Condition**: First to 25 points (or 15 in the 5th set) and leading by at least 2 points.
- **Match Win Condition**: First team to win 3 sets (or 2 sets for Best-of-3).

## 4. Match Events
| Event Type | Description | Data Payload |
| --- | --- | --- |
| `point_won` | Point scored. | `team_id`, `scorer_id` |
| `set_won` | Set concluded. | `team_id`, `set_number` |
| `ace` | Point scored directly from serve. | `player_id` |
| `block` | Point scored via successful block. | `player_id` |
| `timeout` | Team requested timeout. | `team_id` |

*Note: Rotation tracking is optional for v1 and left out of mandatory event schemas.*

## 5. Standings & Tie-breakers
- **Points Allocation**: Win = 2 points, Loss = 0 points (or 3 points for 3-0/3-1 win, 2 points for 3-2 win, 1 point for 3-2 loss depending on league configuration).
- **Tie-breakers**:
  1. Set Ratio (Sets Won / Sets Lost).
  2. Point Ratio (Points Won / Points Lost).

## 6. ELO & Ranking Adjustments
- Elo Engine: `Expected(A) = 1/(1+10^((RB-RA)/400))`.
- Elo variations calculated based on the Set Margin (e.g., a 3-0 sweep yields a higher ELO delta than a 3-2 win).

## 7. Data Models
```json
{
  "match_id": "uuid",
  "sport": "volleyball",
  "sets": [
    {"set_number": 1, "score_team_A": 25, "score_team_B": 18},
    {"set_number": 2, "score_team_A": 23, "score_team_B": 25}
  ],
  "current_set": 3
}
```

## 8. State Management (Riverpod)
- `VolleyballMatchNotifier`: Manages points, validates set wins via 2-point lead logic, and triggers next set transitions.
- `VolleyballStatsProvider`: Aggregates aces and blocks per player.

## 9. UI/UX Considerations
- **Set History**: Display small indicators of past set scores underneath the large current set score.
- **Timeout Tracker**: Clear indicators showing remaining timeouts per team per set.
- **Rapid Input**: Oversized '+1' buttons as Volleyball points occur rapidly.
