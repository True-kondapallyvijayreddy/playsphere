# 14 Cricket Module

## Purpose
The Cricket Module provides a simplified, lightweight ("Cricket-lite") scoring and management system tailored for community, school, and corporate cricket matches within PlaySphere. Rather than a complex full professional (BCCI) ball-by-ball tracker with immense overhead, this module ensures an easy-to-use interface for limited-overs cricket. It integrates with PlaySphere's core sports infrastructure, handling custom match formats, simplified scoring events, and standings generation utilizing Net Run Rate (NRR) tiebreakers.

## Business Requirements
- Support limited overs formats like 5, 10, or 20 overs (T20) suitable for varying weekend or corporate tournament constraints.
- Provide a responsive scorecard accessible in real-time by players and administrators.
- Minimize input friction for volunteer scorers (umpires or team members) entering ball-by-ball outcomes.
- Automatically calculate match results, points, and update standings upon match completion.
- Configurable team sizes (e.g., 7-a-side, 11-a-side) dictating the maximum allowable wickets per innings.

## Functional Requirements
- **Match Format**: Support two-innings limited overs cricket. The number of overs and team size must be configurable at the tournament or match level.
- **Match State Management**: The system must track current innings, batting team, bowling team, current over, current ball within over, total runs, total wickets, target score (for the second innings), and an array of overs containing ball-by-ball data.
- **Scoring Events Tracker**: Must accept inputs for ball outcomes: `run_scored`, `wicket`, `wide`, `no_ball`, `bye`, `leg_bye`, `extras`, `end_of_over`, `end_of_innings`.
- **Automatic Calculations**: Wides and no-balls automatically add extra runs and mandate re-bowling the delivery. No-balls must trigger a "free hit" rule for the subsequent ball.
- **Result Derivation**: In the second innings, if the batting team's score exceeds the target, they win. If they are all out or exhaust overs below target, they lose. Equal scores result in a tie.
- **Standings Integration**: Automatic points allocation (Win = 3pts, Tie = 1pt, Loss = 0pts) with Net Run Rate (NRR) applied as a tiebreaker in tournament standings.

## Non-Functional Requirements
- **Performance**: High concurrency for match viewing; score updates should reflect on connected clients within 1-2 seconds.
- **Scalability**: Ability to handle thousands of concurrent weekend matches without locking the primary database tables.
- **Usability**: UI must be heavily optimized for mobile devices so umpires can use it smoothly in glaring outdoor sunlight.
- **Data Integrity**: An undo/redo mechanism for the last 5 balls is required in case of scoring errors.

## User Stories
- As a **Tournament Admin**, I want to set the match to 7-a-side and 10 overs so I can run a corporate quick tournament.
- As a **Scorer**, I want large, clear buttons for Runs, Wickets, and Extras so I can quickly record the outcome of each ball without missing the action.
- As a **Scorer**, I want the app to automatically remind me that the next ball is a Free Hit after a no-ball.
- As a **Player**, I want to view the live match scorecard on my phone showing batsmen strike rates and bowler economies.
- As a **Tournament Admin**, I want NRR to automatically resolve standings ties so I don't have to calculate it manually.

## User Flow
1. **Match Setup**: Admin/Captain selects playing XI (or VII), toss winner, and decision (bat or bowl).
2. **First Innings**: 
   - Scorer selects opening batsmen and the opening bowler.
   - For each delivery, the scorer records the outcome (runs, extras, wicket).
   - At the end of an over, the system prompts the scorer to select the next bowler.
   - Innings ends when overs are complete or maximum wickets are lost.
3. **Innings Break**: System calculates and displays the target score.
4. **Second Innings**: Scorer records ball-by-ball for the chasing team until the target is passed, wickets run out, or overs expire.
5. **Match Completion**: System finalizes the match, derives the result, updates ELO/Standings, and archives the scorecard.

## UI Screens
- **Pre-Match Setup**: Toss details, squad selection, captain/wicketkeeper assignment.
- **Live Scoring Dashboard**: Mobile-first screen with prominent current score/overs, striker/non-striker stats, current bowler stats, and quick-tap buttons for 0, 1, 2, 3, 4, 6, Wicket, Wide, NB, Byes.
- **Full Scorecard View**: Tabbed view displaying:
  - **Batting**: Batsman, Dismissal, Runs, Balls, 4s, 6s, Strike Rate (SR).
  - **Bowling**: Bowler, Overs, Maidens, Runs, Wickets, Economy.
  - **Extras**: Breakdowns of wides, no-balls, byes, leg-byes.
  - **Fall of Wickets (FOW)**: Score and over when each wicket fell.
- **Standings Board**: Group tables displaying P, W, L, T, Pts, and NRR.

## Database Design

### `CricketMatchState` (JSON/NoSQL Document or structured relation)
- `match_id` (UUID, FK)
- `current_innings` (Integer: 1 or 2)
- `batting_team_id` (UUID)
- `bowling_team_id` (UUID)
- `target_score` (Integer, nullable)
- `toss_winner_id` (UUID)
- `toss_decision` (String: BAT/BOWL)

### `CricketInnings`
- `innings_id` (UUID, PK)
- `match_id` (UUID)
- `team_id` (UUID)
- `total_runs` (Integer)
- `total_wickets` (Integer)
- `overs_played` (Decimal, e.g., 19.4)
- `extras_wides`, `extras_noballs`, `extras_byes`, `extras_legbyes` (Integers)

### `CricketBallEvent`
- `event_id` (UUID, PK)
- `innings_id` (UUID, FK)
- `over_number` (Integer)
- `ball_number` (Integer)
- `bowler_id` (UUID)
- `striker_id` (UUID)
- `non_striker_id` (UUID)
- `runs` (Integer: 0-6)
- `extras_type` (Enum: NONE, WIDE, NO_BALL, BYE, LEG_BYE)
- `is_wicket` (Boolean)
- `wicket_type` (Enum: BOWLED, CAUGHT, LBW, RUN_OUT, STUMPED, HIT_WICKET)
- `dismissed_player_id` (UUID, nullable)

## API Endpoints
- `POST /api/cricket/match/{match_id}/toss`: Submit toss results.
- `POST /api/cricket/match/{match_id}/ball`: Record a single ball event.
- `DELETE /api/cricket/match/{match_id}/ball/{event_id}`: Undo a specific ball (restricted to latest).
- `GET /api/cricket/match/{match_id}/scorecard`: Retrieve the fully formatted scorecard.
- `POST /api/cricket/match/{match_id}/innings/end`: Manually trigger innings end (e.g., declaration).

## Validation Rules
- **Overs**: Cannot exceed the tournament-defined max overs.
- **Wickets**: Cannot exceed `team_size - 1` (e.g., 6 wickets for 7-a-side).
- **Bowler Over Limit**: A single bowler cannot bowl more than 20% of the total match overs (e.g., max 4 overs in a T20).
- **Legitimate Delivery Check**: Wides and no-balls do not increment the `ball_number` of the current over (over remains incomplete until 6 legal deliveries).

## Permissions
- **System Admin**: Can edit all match data post-game.
- **Scorer / Official**: Can submit ball-by-ball events during the live match.
- **Captain**: Can declare an innings or forfeit the match, but cannot score unless designated as Scorer.
- **Participant/Viewer**: Read-only access to live scorecards.

## Notifications
- **Match Start**: "Match has started! Team A won the toss and elected to bat."
- **Milestones**: "Player X has reached a Half-Century (50 runs)!"
- **Innings Break**: "End of Innings. Team B needs 156 runs to win."
- **Match Result**: "Team B won by 4 wickets. View the full scorecard."

## Error Handling
- **Network Interruptions**: Offline support in the app caching ball-by-ball actions, syncing sequentially once connection is restored.
- **Invalid State Action**: Scoring a ball when innings is already completed returns `400 Bad Request`.
- **Concurrent Scoring**: Reject inputs with stale sequence IDs to prevent two scorers from messing up the same over.

## Edge Cases
- **Retired Hurt / Retired Out**: Allow a batsman to be replaced without counting as a bowler's wicket, adjusting the scorecard accordingly.
- **Mankad / Non-striker run out**: Requires capturing the dismissed player distinctly from the striker.
- **Penalty Runs**: Supporting umpires awarding 5 penalty runs (e.g., ball hitting helmet behind keeper) which are added to total but not credited to a batsman.
- **Rain Delays (DLS)**: For v1, manual target score override provided to Admins instead of automated DLS calculation.

## Acceptance Criteria
- [ ] A 10-over match can be fully simulated via API and UI without critical failure.
- [ ] No-balls correctly trigger a "Free Hit" UI indicator for the next delivery.
- [ ] A wide ball automatically adds 1 extra run and prevents the ball count in the over from incrementing.
- [ ] At the end of a match, standings update correctly with 3 points for a win and updated NRR.
- [ ] Scorecard mathematically balances: `Sum of Batsmen Runs + Extras = Total Runs`.

## Future Enhancements
- Automated Duckworth-Lewis-Stern (DLS) calculator for rain-affected matches.
- Wagon wheels and pitch maps for advanced player statistics.
- Live video streaming overlay integration showing the scorecard.
- Support for Test Match (multi-day, 4-innings) formats.
