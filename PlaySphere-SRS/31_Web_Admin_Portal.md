# 31 Web Admin Portal Specification

## Purpose
The PlaySphere Web Admin Portal is an optimized web application designed for Desktop and Tablet browsers. It empowers organization owners, sports coordinators, and tournament managers to administer complex multi-sport seasons, manage registrations, trigger AI team shuffles, and oversee live scoring control rooms.

## Business Requirements
- Provide a comprehensive command center for managing single-day community games up to state-wide leagues.
- Enable multi-tenant dashboard switching for users managing multiple sports organizations.
- Export registration rosters, standings tables, and financial statements to CSV/PDF formats.

## Functional Requirements
- **Organization Management:** Configure organization profile, parent-child links, branding, and feature flags.
- **Season & Event Builder:** Multi-step wizard to create seasons, add sport competitions, configure points/tiebreaker rules, and publish schedules.
- **AI Team Formation Control Room:** Configure team strategy (AI Balanced ELO, Random, House-wise, Auction) and execute idempotent team shuffles with real-time preview.
- **Live Scoring Command Center:** Multi-field live scoring dashboard allowing central monitoring of simultaneous matches.
- **User & Membership Management:** Roles & permissions matrix manager, guardian consent review queue, and member directory.

## Non-Functional Requirements
- Responsive web design optimized for 1920x1080 desktop and tablet viewport sizes.
- Keyboard shortcuts for rapid live scoring entry.

## User Stories
- As an Org Admin, I want to run an AI-balanced team shuffle so that all teams have an equal average ELO rating.
- As a Tournament Director, I want to monitor 4 ongoing badminton courts from one central web screen.

## UI Screens
- Dashboard Home with KPI summary cards.
- Season & Competition Management Hub.
- Bracket & Fixture Generator Interface.
- Live Operations Control Room.

## Acceptance Criteria
- Web portal builds into optimized web bundle (`flutter build web`).
- Responsive layout smoothly scales across 1024px to 4K display viewports.\n