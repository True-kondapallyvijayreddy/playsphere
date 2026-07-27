# 34 UI/UX Wireframes Specification

## Purpose
This document details the UI/UX design system, visual aesthetics, color palettes, typography, and layout wireframes for the PlaySphere cross-platform applications.

## Design Aesthetics & Tokens
- **Theme Mode:** Dual support for sleek Dark Mode (default for live scoring & command center) and modern Light Mode.
- **Color Palette:**
  - Primary Brand: Electric Indigo `#6366F1`
  - Accent / Energy: Vibrant Emerald `#10B981` & Amber `#F59E0B`
  - Background Dark: Deep Slate `#0F172A`
  - Surface Dark: Slate Card `#1E293B`
- **Typography:** Modern sans-serif font stack (Inter / Outfit) with clear hierarchy from Display Small to Body Small.
- **Visual Styles:** Glassmorphism, smooth subtle gradients, elevated card elevations (2dp-8dp), and micro-animations for interactions.

## Key Screen Wireframe Layouts

### 1. Organization Home Dashboard (`/org/:orgId`)
- Top Bar: Org Name, Logo, Role Switcher Badge (Admin / Participant).
- KPI Cards Row: Active Seasons, Total Participants, Upcoming Fixtures, Quick Actions.
- Main Section: Featured Active Competition Banner & Live Scoring Feed.

### 2. Live Operations Dashboard (`/org/:orgId/events/:eventId/live`)
- Header: Match Status, Scoreboard Display, Live Clock.
- Action Grid (Scorer Mode): Large, high-contrast event logging buttons.
- Feed Column: Real-time event log stream with undo capability.

### 3. Portable Player Profile (`/org/:orgId/members/:memberId`)
- Hero Banner: Avatar, Verified Badge, Global Portable ID, Per-Sport ELO Chips.
- ELO Progress Chart: Interactive `fl_chart` Line chart showing rating history over time.
- Achievement Timeline: List of verified tournament finishes, trophies, and milestones.

## Responsive Layout Breakpoints
- Mobile Compact: `< 600px` (Single column, bottom navigation)
- Tablet Medium: `600px - 1024px` (Two column, navigation rail)
- Desktop Expanded: `> 1024px` (Multi-column dashboard, permanent sidebar)\n