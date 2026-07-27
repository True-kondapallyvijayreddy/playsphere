# Glossary

## Core Architecture
- **Multi-tenant**: The system architecture that allows multiple independent Organizations to operate securely within a single database and app deployment.
- **Promotion Pipeline**: The automated flow where winners or top performers at a lower tier (e.g., Community) are granted entry or linked to a higher tier (e.g., District, State).

## Entities & Hierarchy
- **Organization**: The managing body. Can be nested (Country > State > District > Community/School/Corporate).
- **OrganizationMembership**: The entity defining a user's role (Admin, Participant, Coach) within a specific Organization. Determines portal access.
- **Season**: A time-bound period of activity (e.g., "Summer League 2024"). Contains multiple sports and competitions.
- **SportCompetition**: A specific tournament or league for a single sport within a Season (e.g., "Under-15 Boys Football").
- **Stage**: A phase within a SportCompetition (e.g., Group Stage, Knockouts, Semi-Finals).
- **Fixture**: A scheduled matchup between two or more Entrants at a specific time and venue.
- **MatchEvent**: Granular data points recorded during a Fixture (e.g., goal scored, point won, foul committed).
- **Entrant**: A participant in a fixture. Can refer to an individual Player or a Team, depending on the sport.
- **Franchise**: A persistent team entity within an organization that retains its identity across multiple seasons.
- **Ad-hoc Team**: A temporary team created exclusively for a single event or season.

## Platform Mechanics
- **ELO Rating**: A mathematical system for calculating relative skill levels. The core engine uses: `Expected(A) = 1/(1+10^((RB-RA)/400))`. Ratings update after every verified match.
- **Paise**: The smallest unit of Indian currency. All monetary integers in the database represent Paise to avoid floating-point errors (1 INR = 100 Paise).
- **Career Page (Portable Profile)**: A user's public-facing or shareable resume containing all verified matches, ELO trends, teams, and certificates across all PlaySphere organizations.

## Trust & Safety
- **Verification Tier**: Indicates the rigor of identity checking. "Casual" requires just phone/email. "Sanctioned" requires government ID upload and manual admin approval.
- **Guardian Link**: A digital association between a Minor's account and an Adult's account. Mandates that the guardian receives notifications and consent requests for the minor's activities.
