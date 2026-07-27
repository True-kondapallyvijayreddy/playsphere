# 30 Mobile App Specification

## Purpose
The PlaySphere Mobile App provides a native cross-platform (iOS & Android) experience built using Flutter. It caters to players, admins, guardians, and spectators, enabling on-the-go registration, match check-in, live score viewing, and profile management.

## Business Requirements
- Deliver 100% feature parity for mobile users across iOS and Android.
- Support smooth 60 FPS performance on mid-tier mobile devices.
- Enable offline score entry for scorers operating in venues with intermittent connectivity.

## Functional Requirements
- **Authentication & Role Switching:** OTP/Email login, biometric login, and dynamic role switcher between Admin and Participant modes.
- **Event & Match Discovery:** Browse upcoming seasons, view interactive brackets, and follow live match updates.
- **QR Code Scanner:** Embedded camera QR scanner for quick player check-in at tournament venues.
- **Push Notifications:** Instant alerts for match schedules, live scoring milestones, and team assignments.
- **Offline Caching:** Local caching using Hive/SharedPreferences for offline viewing of downloaded fixtures and profiles.

## Non-Functional Requirements
- App cold boot time < 2.0 seconds.
- Responsive layout adapting to various mobile screen sizes and orientations.

## User Stories
- As a Player, I want to scan my QR code at the venue check-in desk so that my attendance is recorded instantly.
- As a Scorer, I want to record scores offline during a match so that my data syncs automatically when signal is restored.

## UI Screens & Architecture
- Built using Flutter with Riverpod state management and Material 3 design system.
- Bottom Navigation Bar with Home, Events, Live Ops, Profile, and Settings tabs.

## Database & Caching
- Local Hive key-value store for offline persistence.
- Automatic sync queue engine for pending offline HTTP requests.

## Security & Compliance
- Secure storage (iOS Keychain / Android Keystore) for JWT auth tokens.
- Biometric authentication support (Face ID / Fingerprint).

## Acceptance Criteria
- App compiles cleanly for Android (APK/AAB) and iOS (IPA).
- QR scanner successfully decodes player ticket payload within 300ms.\n