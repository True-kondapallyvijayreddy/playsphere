# 36 Acceptance Criteria Specification

## Overview
This document specifies standard Gherkin-formatted (Given-When-Then) acceptance criteria for PlaySphere's core technical workflows.

## Feature 1: Multi-Tenant Role Authorization
```gherkin
Scenario: Admin views admin actions on organization dashboard
  Given a user signed in with an active membership in "Maram Homes" having role "admin"
  When the user navigates to "/org/maram-homes"
  Then the Admin Portal controls (Create Season, Add Member, Manage Roles) are visible
  And the role badge displays "ADMIN".

Scenario: Member views participant view on organization dashboard
  Given a user signed in with an active membership in "Maram Homes" having role "member"
  When the user navigates to "/org/maram-homes"
  Then the Admin Portal creation tools are hidden
  And the Participant view (Browse Events, My Registrations) is displayed.
```

## Feature 2: AI-Balanced Team Shuffle
```gherkin
Scenario: Executing AI team shuffle on 16 registered players into 4 teams
  Given 16 player registrations with per-sport ELO ratings ranging from 1000 to 1800
  When the Admin selects strategy "aiBalanced" with team count 4 and executes shuffle
  Then 4 teams of 4 players each are generated
  And the total rating variance between the highest and lowest average team rating is < 5%.
```

## Feature 3: ELO Rating Update on Fixture Completion
```gherkin
Scenario: Player A (1400 ELO) defeats Player B (1200 ELO) in a casual match
  Given Player A has current ELO 1400 and Player B has current ELO 1200
  When a Table Tennis fixture between Player A and B is completed with Player A winning
  Then Player A's new ELO increases by approximately +6 points (K=20)
  And Player B's new ELO decreases by -6 points
  And a new append-only RatingHistoryEntry is created for both players.
```

## Feature 4: Minor Protection Visibility Hard-Lock
```gherkin
Scenario: Minor profile without verified guardian remains hard-locked to private
  Given a user profile where dateOfBirth indicates age < 18
  And no verified GuardianLink exists for the user
  When any external user attempts to search or view the profile
  Then the system restricts profile visibility to "private" regardless of stored defaults.
```\n