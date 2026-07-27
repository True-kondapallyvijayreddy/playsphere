# 45 Product Backlog Specification

## Purpose
Categorized backlog of features, enhancements, and technical debt items prioritized by impact (P0 = Critical MVP, P1 = High, P2 = Medium/Nice-to-have).

## Prioritized Feature Backlog

### P0 (Critical MVP Items - Completed / In Progress)
- [x] Multi-tenant organization routing (`/org/:orgId`).
- [x] Dual portal view (Admin vs Participant) based on `OrganizationMembershipEntity.role`.
- [x] Central store (`PlaySphereStore`) seeding sample org ("Maram Garlapati Homes") and events.
- [x] Live Scoring Dashboard for real-time score entry and display.
- [x] Portable Player Profile with ELO progression chart.
- [x] Talent Discovery screen with sport category and ELO rating filter.

### P1 (High Priority Next Items)
- [ ] Add explicit `usePathUrlStrategy()` configuration for Flutter Web URL routing.
- [ ] Implement Razorpay payment gateway integration for paid registrations.
- [ ] Add Push Notification triggers via Firebase Messaging for score updates.
- [ ] Implement automated PDF certificate generator with QR verification link.
- [ ] Implement Hive local storage caching for offline scoring support.

### P2 (Enhancements & Future Capabilities)
- [ ] Add Dark Mode toggle switch in main app navigation bar.
- [ ] Implement Computer Vision ball tracking for automated cricket/tennis scoring.
- [ ] Support WhatsApp API bot for receiving match updates via chat.
- [ ] Export standings to Excel (`.xlsx`) format.

## Technical Debt & Maintenance
- Refactor all `withOpacity` calls to `.withValues()` to eliminate Flutter 3.22 deprecation warnings.
- Increase unit test coverage on `PlaySphereTeamFormationEngine` to 95%.\n