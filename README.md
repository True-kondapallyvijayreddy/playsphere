# PlaySphere — Flutter App Scaffold

Basic code structure for the PlaySphere Event & Competition Operating
System client (Blueprint v1.0), generated as a feature-first / clean
architecture skeleton so each module (Events, Registration, Fixtures,
Scoring, etc.) can be built out independently and in parallel.

## Structure

```
lib/
  main.dart                  # App entry point (ProviderScope + MaterialApp.router)
  core/
    config/                  # Env / build-time config (--dart-define)
    constants/                # Shared enums: UserRole, EventStage, EventCategory, ...
    errors/                   # AppException hierarchy
    network/                  # Shared Dio client + interceptors
    router/                   # go_router route table (app_router.dart)
    theme/                    # AppTheme (light/dark, per-org branding)
    widgets/                  # (reserved) core-level shared widgets
  features/
    auth/                     # Login, splash, session
    organization/             # Org profile, departments, houses, clubs, venues
    members/                  # Member profiles, digital ID, QR identity
    events/                   # Event CRUD + lifecycle (fully wired example, see below)
    registration/             # Online/bulk/QR registration, payments, waitlist
    teams/                    # Team formation (random/manual/AI/auction/house/dept)
    fixtures/                 # Bracket/schedule generation (knockout/league/Swiss/...)
    live_ops/                 # Check-in, live score, referee/volunteer dashboards
    scoring/                  # Per-sport ScorePlugin contract (cricket/football/chess/...)
    media/                    # Albums, photos, videos, streaming, AI summaries
    awards/                   # Awards + QR-verifiable certificate generation
    finance/                  # Income/expense, sponsors, invoices, budgets
    inventory/                # Equipment/asset tracking
    notifications/            # Push/email/SMS/WhatsApp templates
    analytics/                # Dashboards & metrics
    archive/                  # Historical preservation (reserved)
  shared/
    widgets/                  # Cross-feature reusable widgets
    models/                   # Cross-feature shared models
```

Each feature follows the same three-layer split:

```
features/<feature>/
  data/
    models/        # JSON <-> domain-entity mapping
    repositories/   # Concrete implementation (Dio/Firestore/...)
  domain/
    entities/       # Pure business objects, no JSON/UI knowledge
    repositories/    # Abstract contracts the presentation layer depends on
  presentation/
    screens/        # Route-level widgets
    widgets/        # Feature-local widgets
    state/          # Riverpod providers/controllers
```

**`features/events/`** is fleshed out end-to-end (entity → model →
repository interface → repository impl → Riverpod providers → screens)
as a reference pattern to copy for the remaining features, which
currently contain domain entities plus placeholder screens wired into
the router.

## Stack

- **State management:** flutter_riverpod
- **Routing:** go_router (deep-linkable: `/org/:orgId/events/:eventId/...`)
- **Networking:** dio (+ retrofit for typed clients, optional)
- **Realtime/backend:** Firebase / Supabase (either or both, per Blueprint §22)
- **Local storage:** hive / shared_preferences
- **Models:** freezed + json_serializable (recommended for new features)

## Getting started

```bash
flutter pub get
flutter run
```

Configure the API base URL at build/run time:

```bash
flutter run --dart-define=API_BASE_URL=https://api.playsphere.dev/v1
```

## Next steps

1. Wire real auth (Firebase Auth / Supabase Auth) into `features/auth`.
2. Replace placeholder screens with real UI, feature by feature,
   following the `events` module pattern.
3. Add `freezed`/`json_serializable` code generation for models as
   they stabilize (`dart run build_runner build --delete-conflicting-outputs`).
4. Implement sport-specific `ScorePlugin`s under `features/scoring/`.
