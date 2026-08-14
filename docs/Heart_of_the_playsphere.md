The most important design decision is that a Match is the atomic scoring entity, regardless of where that match came from.

A player may play in:

a Season
a Tournament
a League
a Single Match
a Challenge
a Club event
an independently created match

But every match must ultimately produce one common Scorecard, and that Scorecard must update the player's permanent career/profile statistics.

Think of it like CricHeroes-style match scoring + PlaySphere's larger multi-sport ecosystem.

1. THE CORE IDEA
                    PLAYSPHERE
                        │
              ┌─────────┴──────────┐
              │                    │
         COMPETITION              MATCH
              │                    │
       ┌──────┼──────┐             │
       │      │      │             │
     Season Tournament Challenge   │
       │      │      │             │
       └──────┼──────┘             │
              │                    │
              └──────────────► MATCH
                                  │
                                  ▼
                              SCORECARD
                                  │
                         ┌────────┴────────┐
                         │                 │
                   MATCH RESULT       PLAYER EVENTS
                         │                 │
                         ▼                 ▼
                  TEAM METRICS       PLAYER METRICS
                         │                 │
                         ▼                 ▼
                  COMPETITION        CAREER PROFILE
                   LEADERBOARD       / STATISTICS

The Match + Scorecard is the common denominator.

2. VERY IMPORTANT: SEASON ≠ TOURNAMENT ≠ MATCH

These should be three different entities.

Season

A season is a container of multiple competitions across multiple sports.

Example:

PLAYSPHERE HYDERABAD SPORTS SEASON 2026

        │
        ├── Cricket
        │    ├── Cricket Tournament A
        │    ├── Cricket Tournament B
        │    └── Cricket League
        │
        ├── Football
        │    ├── Football Tournament
        │    └── Football League
        │
        ├── Badminton
        │    ├── Singles
        │    └── Doubles
        │
        └── Volleyball
Tournament

One competition in one sport.

IPL-style Cricket Tournament

32 Teams
     ↓
Groups
     ↓
League
     ↓
Playoffs
     ↓
Final
Match

One actual sporting contest.

Warriors CC
      VS
Titans SC

25 May
6:00 PM
Green Field Ground
3. EVERY MATCH GETS ITS OWN MATCH ENTITY

This is critical.

Suppose a tournament has 36 matches.

You don't have:

Tournament → Score

Instead:

Tournament
│
├── Match 001
├── Match 002
├── Match 003
├── Match 004
├── ...
└── Match 036

Each match is independently accessible.

When the user taps:

Match 017

they should open the Match Center.

4. MATCH CENTER

This should become one of the most important screens in PlaySphere.

┌─────────────────────────────────────┐
│ ← Match Center                  ⋮   │
│                                     │
│ CRICKET                             │
│ Hyderabad Champions Cup             │
│                                     │
│ Warriors CC       VS     Titans SC  │
│                                     │
│ 25 May 2026 • 6:00 PM               │
│ Green Field Ground                  │
│                                     │
│ Status: UPCOMING                    │
├─────────────────────────────────────┤
│ Officials                           │
│                                     │
│ Umpire                              │
│ [ Assign Umpire ]                   │
│                                     │
│ Scorer                              │
│ [ Assign Scorer ]                   │
├─────────────────────────────────────┤
│ Match Configuration                 │
│                                     │
│ 20 Overs                            │
│ Standard Rules                      │
│ Live Scoring: ON                    │
├─────────────────────────────────────┤
│                                     │
│       [ START MATCH ]               │
│                                     │
└─────────────────────────────────────┘
5. ASSIGN UMPIRE

The organizer/authorized official selects an umpire.

Assign Umpire

Search Officials
[ Rahul ................. ]

Available Officials

○ Suresh Kumar
   Certified Umpire
   245 Matches

○ Prakash Rao
   Certified Umpire
   182 Matches

○ Anil Reddy
   Certified Umpire
   96 Matches

                 [ Assign ]

Once assigned:

Umpire

✓ Suresh Kumar
  Assigned
6. ASSIGN SCORER

You can have a separate scorer.

Scorer

○ Official Scorer
○ Team Scorer
○ Organizer
○ Auto/Remote Scorer

For smaller matches, you could allow:

Captain / Player as scorer

But for tournaments and official competitions, organizer-controlled scorer assignment should be available.

7. MATCH STATUS MACHINE

This should be explicitly designed.

SCHEDULED
    │
    ▼
OFFICIALS ASSIGNED
    │
    ▼
READY
    │
    ▼
LIVE
    │
    ▼
PAUSED
    │
    ▼
LIVE
    │
    ▼
MATCH ENDED
    │
    ▼
RESULT PENDING APPROVAL
    │
    ▼
FINALIZED

For trusted competitions, you can skip approval:

LIVE
 ↓
MATCH ENDED
 ↓
FINALIZED

But official tournaments should ideally have:

Scorer submits
       ↓
Umpire verifies
       ↓
Result finalized
8. SCORECARD IS THE HEART OF THE SYSTEM

Once the match starts:

Match
  ↓
Scorecard

For cricket:

LIVE SCORECARD

Warriors CC
178/6

20.0 Overs

Required:
—

Run Rate:
8.90

But underneath the scorecard, you are recording events.

For example:

Ball 1
Bowler: Suresh
Batter: Rahul
Runs: 4

Ball 2
Runs: 1

Ball 3
Wicket

...

Those events generate the statistics.

9. DON'T STORE ONLY THE FINAL SCORE

This is extremely important for your architecture.

Don't simply store:

Rahul = 74 runs

Store the underlying match events.

For cricket:

Match
│
├── Innings
│
├── Over
│
├── Ball
│    ├── Batter
│    ├── Bowler
│    ├── Runs
│    ├── Extras
│    ├── Wicket
│    └── Dismissal
│
└── Result

Then:

Ball Events
     ↓
Innings Statistics
     ↓
Player Match Statistics
     ↓
Team Match Statistics
     ↓
Match Result

This gives you much better auditability and prevents statistical inconsistencies.

10. PLAYER MATCH STATISTICS

At the end of a cricket match:

Rahul Sharma

Batting
Runs          74
Balls         42
4s             6
6s             3
Strike Rate 176.19

Bowling
Overs          4
Runs          32
Wickets        2
Economy      8.00

Fielding
Catches        1
Run Outs       0

These are Match Statistics.

But then they flow into the player's permanent profile.

11. UNIVERSAL PLAYER PROFILE

This is where your idea becomes much bigger than a tournament-management app.

Suppose Rahul plays:

Match #001
Single Match
74 runs

Match #002
Challenge
42 runs

Match #003
Tournament
81 runs

Match #004
Season
55 runs

His profile becomes:

RAHUL SHARMA

Career Cricket

Matches        4
Runs         252
Average       XX
Strike Rate   XX
Wickets        XX
Catches         XX

It doesn't matter where the match came from.

The source is secondary.

The actual Match is what matters.

12. SOURCE OF MATCH

Every Match should carry a source/context.

Something like:

match.sourceType

Possible values:

SEASON
TOURNAMENT
LEAGUE
CHALLENGE
SINGLE_MATCH
CLUB_EVENT

And:

match.sourceId

Example:

Match #4821

sourceType = TOURNAMENT
sourceId = HCC2026

Another:

Match #4822

sourceType = CHALLENGE
sourceId = CHL78291

But both eventually become:

MATCH
   ↓
SCORECARD
   ↓
PLAYER STATS
13. THIS IS THE KEY ARCHITECTURE
                     MATCH SOURCES
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
      SEASON          TOURNAMENT         CHALLENGE
        │                 │                 │
        └─────────────────┼─────────────────┘
                          │
                    SINGLE MATCH
                          │
                          ▼
                    MATCH ENTITY
                          │
                          ▼
                     SCORECARD
                          │
                          ▼
                    MATCH EVENTS
                          │
             ┌────────────┴─────────────┐
             │                          │
             ▼                          ▼
        TEAM STATS                 PLAYER STATS
             │                          │
             ▼                          ▼
       COMPETITION                  PLAYER CAREER
       STATISTICS                    STATISTICS
             │                          │
             ▼                          ▼
      LEADERBOARDS                 PLAYER PROFILE
14. NOW THE LEADERBOARD BECOMES VERY INTERESTING

There should not be one global leaderboard.

You need different leaderboard scopes.

15. SEASON LEADERBOARD — OLYMPICS MODEL

If the event is:

PlaySphere Hyderabad Sports Season 2026

you could have:

SEASON LEADERBOARD

Overall Medal/Points Table

Rank   Club              Gold  Silver  Bronze  Points
1      Hyderabad Club      8      5      4      61
2      Warriors Club       6      7      3      58
3      Titans Club         5      4      8      52

But importantly, each sport has its own leaderboard.

SPORTS

🏏 Cricket
⚽ Football
🏸 Badminton
🏐 Volleyball
🏀 Basketball
🏓 Table Tennis
♟ Chess

Tap Cricket:

CRICKET — SEASON 2026

Top Teams
Top Players
Top Clubs
16. SPORT-WISE SEASON LEADERBOARD

For Cricket:

CRICKET — SEASON LEADERBOARD

BATSMEN

1. Rahul Sharma       1,824 Runs
2. Karthik Reddy      1,560 Runs
3. Vikram Singh       1,412 Runs

BOWLERS

1. Suresh Kumar       61 Wickets
2. Naveen Reddy       54 Wickets
3. Arjun Mehta        49 Wickets

This is analogous to the Olympics concept of sport-specific competition results, although your actual ranking/points methodology can be PlaySphere-specific.

17. TOURNAMENT LEADERBOARD — IPL MODEL

Now imagine:

Hyderabad Champions Cup 2026

This is only Cricket.

Therefore:

HYDERABAD CHAMPIONS CUP

🏆 Points Table

Team
Played
Won
Lost
NRR
Points

And tabs:

Points Table
Batting
Bowling
Fielding
Player Rankings
Team Rankings
Records

This is much closer to an IPL-style tournament experience.

18. UNIVERSAL PLAYER METRICS ARE DIFFERENT

This is extremely important.

Rahul might have:

CAREER
─────────────
Cricket

All Matches
Matches        128
Runs         8,241
Wickets        184
Catches         73

But then:

2026 Season

Matches         24
Runs          1,824
Wickets         42

And:

Hyderabad Champions Cup

Matches          8
Runs           642
Wickets         11

And:

Last Match

Runs             74
Wickets           2

All are different views of the same underlying match data.

19. PLAYER PROFILE SHOULD HAVE THESE LEVELS
RAHUL SHARMA

Career
│
├── Cricket
│   ├── Career Stats
│   ├── Season Stats
│   ├── Tournament Stats
│   ├── Club Stats
│   └── Recent Matches
│
├── Badminton
│   ├── Career Stats
│   └── Match History
│
└── Football
    ├── Career Stats
    └── Match History

Then:

Cricket
   ↓
Career
Season
Tournament
Club
Match
20. MATCH HISTORY

Every player should have:

MATCH HISTORY

25 May
Warriors CC vs Titans SC
Tournament
74 Runs • 2 Wickets
WIN

20 May
Warriors CC vs Rangers CC
Challenge
51 Runs • 3 Wickets
WIN

15 May
Warriors CC vs Super Kings
Single Match
32 Runs
LOSS

This is where your CricHeroes-style experience becomes powerful.

21. ONE SCORECARD — MANY OUTPUTS

This is the principle I would make mandatory in your backend.

                    SCORECARD
                       │
       ┌───────────────┼────────────────┐
       │               │                │
       ▼               ▼                ▼
   MATCH RESULT    PLAYER STATS      TEAM STATS
       │               │                │
       │               ▼                ▼
       │          PLAYER PROFILE    TEAM PROFILE
       │               │                │
       │               ▼                ▼
       │          CAREER STATS     TEAM HISTORY
       │
       └───────────────┬────────────────┘
                       ▼
                 COMPETITION
                  LEADERBOARD

So the scorecard should never be recreated separately for tournament, challenge, season, etc.

There should be ONE scoring engine.

22. SPORT-SPECIFIC SCORECARD, COMMON FRAMEWORK

The framework is common:

MATCH
│
├── Participants
├── Officials
├── Venue
├── Start
├── Live State
├── Events
├── Result
└── Statistics

But the scoring engine changes.

Cricket
Ball
 ↓
Runs
 ↓
Wicket
 ↓
Over
 ↓
Innings
Football
Goal
Assist
Card
Substitution
Foul
 ↓
Match Result
Badminton
Rally
 ↓
Point
 ↓
Game
 ↓
Match
Volleyball
Point
 ↓
Set
 ↓
Match
Kabaddi
Raid
Tackle
Bonus
All-Out
 ↓
Half
 ↓
Match

The Match entity is common.

The Sport Scoring Engine is different.

23. MATCH FINALIZATION IS CRITICAL

When scoring finishes:

SCORER
   │
   ▼
End Match
   │
   ▼
System calculates
   │
   ├── Final Score
   ├── Winner
   ├── Player Stats
   ├── Team Stats
   └── Match Records
   │
   ▼
UMPire / OFFICIAL
   │
   ▼
VERIFY
   │
   ▼
FINALIZE

Once finalized:

FINALIZED
     │
     ├────────► Tournament Leaderboard
     │
     ├────────► Season Leaderboard
     │
     ├────────► Team Statistics
     │
     ├────────► Player Career Statistics
     │
     ├────────► Player Ranking
     │
     └────────► Club Statistics
24. DON'T DIRECTLY UPDATE EVERYTHING FROM THE UI

Avoid:

Scorer presses "End Match"
       ↓
Update 15 different tables

Instead:

Scorecard
    ↓
Match Finalization Event
    ↓
Statistics Engine
    ↓
Aggregation
    ↓
Leaderboards / Profiles

This is much safer.

25. EVENT-DRIVEN ARCHITECTURE

I strongly recommend this.

                    MATCH FINALIZED
                           │
                           ▼
                   STATISTICS ENGINE
                           │
          ┌────────────────┼────────────────┐
          │                │                │
          ▼                ▼                ▼
      Player Stats      Team Stats      Match Stats
          │                │                │
          ▼                ▼                ▼
      Career Stats     Tournament       Season
                         Stats            Stats
          │                │                │
          └────────────────┼────────────────┘
                           ▼
                       Rankings

This means if a match belongs to a Season and a Tournament:

One Match
   │
   ├── Player Career
   ├── Tournament
   └── Season

All three can receive the appropriate aggregation.

26. EXAMPLE — ONE CRICKET MATCH

Suppose:

Warriors CC
178/6

Titans SC
164/9

Warriors win by 14 runs

Rahul:

74 runs
2 wickets
1 catch

The system performs:

MATCH FINALIZED
       │
       ├──────────────► Rahul Career
       │                 +74 Runs
       │                 +2 Wickets
       │                 +1 Catch
       │
       ├──────────────► Warriors CC
       │                 +1 Win
       │
       ├──────────────► Tournament
       │                 Warriors +2 Points
       │
       ├──────────────► Season
       │                 Cricket standings updated
       │
       └──────────────► Records
                         Highest score
                         Best bowling
                         etc.

One match. Multiple projections.

27. THIS ALSO SOLVES YOUR "PLAY ANYWHERE" REQUIREMENT

This is the most important consequence.

Rahul doesn't need a separate profile for:

Tournament
Challenge
Season
Club
Friendly
Single Match

He has:

                    RAHUL SHARMA
                         │
                    PLAYER ID
                         │
             ┌───────────┴───────────┐
             │                       │
           SPORTS                   MATCHES
             │                       │
       ┌─────┼─────┐         ┌───────┼────────┐
       │     │     │         │       │        │
    Cricket Football Badminton  Tournament Challenge Single
       │                         │       │        │
       └─────────────────────────┴───────┴────────┘
                         │
                         ▼
                  CAREER METRICS
28. THE MOST IMPORTANT DATABASE RELATIONSHIP

Conceptually:

PLAYER
  │
  │ 1:N
  ▼
MATCH PARTICIPATION
  │
  ▼
MATCH
  │
  ├── source_type
  ├── source_id
  ├── sport_id
  ├── competition_id
  ├── season_id
  └── scorecard_id

And:

MATCH
  │
  ▼
MATCH EVENTS
  │
  ▼
PLAYER MATCH STATS
  │
  ▼
PLAYER CAREER STATS

This is the foundation.

29. YOUR PLAYSPHERE LEADERBOARD SYSTEM

I would create four levels.

Level 1 — Match
Match Statistics
Level 2 — Tournament
Tournament Leaderboard
Level 3 — Season
Season / Sport Leaderboard
Level 4 — Career
Player Career Statistics

So:

                         PLAYER
                           │
                ┌──────────┼──────────┐
                │          │          │
              MATCH    TOURNAMENT   SEASON
                │          │          │
                └──────────┼──────────┘
                           │
                           ▼
                     CAREER STATS
30. FINAL PLAYSPHERE FLOW

This is the flow I would consider core to the entire product:

                 SEASON / TOURNAMENT / CHALLENGE
                              │
                              ▼
                       MATCH CREATED
                              │
                              ▼
                       MATCH CENTER
                              │
                    ┌─────────┴─────────┐
                    │                   │
              ASSIGN UMPIRE        ASSIGN SCORER
                    │                   │
                    └─────────┬─────────┘
                              ▼
                         MATCH READY
                              │
                              ▼
                        START MATCH
                              │
                              ▼
                    ┌──────────────────┐
                    │  LIVE SCORECARD  │
                    │                  │
                    │  Score           │
                    │  Events          │
                    │  Players         │
                    │  Statistics      │
                    └────────┬─────────┘
                             │
                             ▼
                        END MATCH
                             │
                             ▼
                       VERIFY RESULT
                             │
                             ▼
                        FINALIZE MATCH
                             │
            ┌────────────────┼─────────────────┐
            │                │                 │
            ▼                ▼                 ▼
       MATCH RESULT     PLAYER METRICS     TEAM METRICS
                             │                 │
              ┌──────────────┼─────────┐       │
              │              │         │       │
              ▼              ▼         ▼       ▼
           CAREER        SEASON    TOURNAMENT  CLUB
           STATS          STATS      STATS     STATS
              │              │         │
              └──────────────┼─────────┘
                             ▼
                        LEADERBOARDS
The rule I would lock into PlaySphere

Every PlaySphere sporting activity must eventually become a Match. Every Match must have one canonical Scorecard. Every finalized Scorecard must feed the common Statistics Engine.

That gives you exactly what you're describing:

A player can play anywhere in PlaySphere, and every legitimate performance contributes to that player's permanent sports history.

At the same time, the competition context remains separate:

Season → Olympics-style sport-wise standings
Tournament → IPL-style tournament leaderboards
Challenge → head-to-head match history
Single Match → standalone scorecard
Player → universal career metrics

That architecture is what will make PlaySphere much more than a tournament-registration application. It becomes a persistent sports identity + competition + scoring + statistics platform