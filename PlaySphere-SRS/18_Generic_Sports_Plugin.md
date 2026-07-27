# Generic Sports Plugin SRS

## 1. Overview
The Generic Sports Plugin serves as the fallback module in PlaySphere for any sport not explicitly supported by native plugins (e.g., Table Tennis, Athletics, Swimming, Ultimate Frisbee). It provides maximum configurability so admins can adapt it to point-based, set-based, or goal-based scoring schemas.

## 2. Match Structure & Configuration
- **Configurable Properties**: 
  - `sport_name`: Text field (e.g., "Table Tennis").
  - `scoring_type`: Enum (`points`, `sets`, `goals`, `time`).
  - `match_structure`: Enum (`continuous`, `halves`, `quarters`, `sets`).
  - `periods_count`: Number of periods/sets (e.g., 2 for halves, 5 for Table Tennis sets).

## 3. Scoring Rules & Win Conditions
- **Win Conditions**: 
  - `highest_score`: Team with the most points/goals wins.
  - `lowest_time`: Entity with the lowest time wins (Athletics/Swimming).
  - `sets_won`: Entity that wins the majority of sets wins.
- Admins configure custom win triggers, such as "First to 11 points wins set, must win by 2".

## 4. Match Events
| Event Type | Description | Data Payload |
| --- | --- | --- |
| `score_increment` | Adds generic points/goals. | `team_id`, `increment_value` |
| `period_end` | Marks the end of a half/quarter/set. | `period_index` |
| `custom_penalty` | Generic foul or penalty tracker. | `player_id`, `penalty_name` |
| `match_end` | Finalizes the match. | `winning_team_id` |

## 5. Standings & Tie-breakers
- **Points Allocation**: Configurable (e.g., W=3, D=1, L=0 or W=2, L=0).
- **Tie-breakers**:
  1. Points/Goals/Score Difference.
  2. Total Points/Goals Scored.
  3. Head-to-Head.

## 6. ELO & Ranking Adjustments
- ELO engine applies generic calculation: `Expected(A) = 1/(1+10^((RB-RA)/400))`.
- Base K-factor is used since sport-specific margin-of-victory rules do not apply.

## 7. Data Models
```json
{
  "match_id": "uuid",
  "sport_name": "Table Tennis",
  "scoring_schema": "sets",
  "generic_events": [
    {"type": "score_increment", "team_id": "A", "value": 1, "timestamp": "2023-10-10T10:00:00Z"}
  ]
}
```

## 8. State Management (Riverpod)
- `GenericMatchNotifier`: Dynamic state manager that adjusts its behavior based on the injected `scoring_type` config.
- Flexible UI state binding for generic score increments.

## 9. UI/UX Considerations
- **Dynamic Scoreboard**: UI adapts automatically. If `scoring_type` is `sets`, it renders a set-by-set table. If `goals`, it renders a single large number per team.
- **Admin Configuration Flow**: Easy-to-use wizard for admins to map out the rules of their unsupported sport.
