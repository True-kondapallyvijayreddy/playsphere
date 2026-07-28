# PlaySphere

A sports operating system for schools, colleges, communities and associations.
One Flutter codebase running on Android, iOS and the web.

**Firebase project:** `playsphere-os` · **Firestore region:** `asia-south1`
(Mumbai, permanent) · **Auth:** Google Sign-In

---

## What it does

Three things, in priority order:

1. **Event creation** — an organizer picks a sport, an age/gender category and
   a format, opens entries, approves players, and generates a draw.
2. **Club handling** — organizations with real membership, invite codes,
   approval queues and five distinct roles enforced server-side.
3. **Live scoring** — a scorer taps or types; anyone, anywhere, watching on a
   phone or a laptop, sees it change immediately.

---

## Architecture

### The security boundary is `firestore.rules`, not the app

Client-side permission checks (`lib/core/permissions/capability.dart`) exist to
grey out buttons. They prevent nothing. Every authority decision is re-made in
`firestore.rules` against a server-side read of the caller's membership
document. Assume the client is hostile.

When you change one, change both in the same commit.

### Scoring is event-sourced

```
orgs/{orgId}/competitions/{compId}/fixtures/{fixtureId}
    ├── scoreState   ← denormalized projection (what spectators read)
    ├── lastSeq      ← monotonic, enforced by rules
    └── events/{000000001}, {000000002}, …   ← append-only truth
```

The event log is the truth; `scoreState` is a cache of it that can always be
rebuilt by replaying events through the sport's plugin. This buys three things:

- **Spectators are cheap.** One document listener per viewer, not a listener
  over a growing collection. Ten thousand viewers cost ten thousand small
  reads, not ten thousand reads *per ball*.
- **Disputes are answerable.** Replaying reproduces the score exactly, so "the
  scorer added runs that never happened" is checkable rather than arguable.
- **Offline is honest.** Queued events carry an idempotency key, so replaying
  after reconnection cannot double-count.

**The concurrency guard costs nothing:** each event's document id is its
zero-padded sequence number. Firestore `create` fails when a document already
exists, so two scorers acting on the same ball cannot both win — the loser gets
rejected and re-syncs. No locks, no transactions, no server code.

### Adding a sport

A sport is data. Add a `SportSpec` to `lib/domain/scoring/scoring_registry.dart`
naming an existing plugin and its configuration. Nothing else changes — plugins
declare their own scoring pads, so the UI adapts automatically.

Adding a genuinely new *kind* of scoring means a new `ScoringPlugin`. Plugins
must be pure: `apply(state, action) -> state`, touching nothing else. Purity is
what lets the same code run on the scorer's phone, replay a stored log, and
later run server-side, with guaranteed identical answers.

Current plugins: `simple_points`, `set_based`, `goal_based`, `cricket`.

### Cross-platform parity

`lib/core/layout/responsive.dart` defines one layout vocabulary. Navigation goes
drawer → rail → permanent sidebar by window width, not by platform, so a
Chromebook and an iPad at the same width get the same layout. Screens never
branch on platform.

The scoring pad has both large touch targets and keyboard shortcuts, because
the scorer is on a phone at the boundary or a laptop at the desk.

---

## Layout

```
lib/
  core/
    auth/          Google Sign-In, web/mobile split contained here
    firebase/      every Firestore path, in one file
    layout/        breakpoints and adaptive containers
    models/        Firestore-mappable domain models + wire-value enums
    permissions/   capability matrix (advisory mirror of firestore.rules)
    router/        GoRouter + the single authority gate
    providers.dart dependency injection; everything org-scoped
  data/            repositories; Firebase errors translated at this boundary
  domain/
    draw/          fixture generation (round robin, seeded knockout)
    scoring/       plugin contract, registry, sport catalogue, per-sport rules
  features/        screens, one folder per area
  shared/          app shell, empty/error states
```

---

## Running it

```bash
flutter pub get
flutter run -d chrome          # web
flutter run -d <device-id>     # Android / iOS
flutter test                   # 47 tests
flutter analyze                # clean
```

Deploy:

```bash
firebase deploy --only firestore:rules,firestore:indexes --project playsphere-os
flutter build web --release
firebase deploy --only hosting --project playsphere-os
```

---

## Decisions worth knowing

**Date of birth is write-once.** Every age-category rule depends on it, and a
self-editable birth date makes junior results contestable. Age fraud is the
most common integrity problem in school sport, so the rules reject any update
that changes it.

**Age is measured on a cut-off date, not "now."** A player who is U-17 on the
cut-off stays U-17 through their birthday mid-tournament. Computing against
`DateTime.now()` silently disqualifies people halfway through a competition.

**Registration and entrant are different objects.** A registration is an
application; an entrant is a starter. Closing entries converts one to the
other, which is what stops a late application appearing inside a bracket
already being played.

**Spectating needs no account.** The `/watch/` route is public. Requiring a
sign-in to follow a school match would defeat the product.

**Firebase failing to start is fatal.** The previous build caught the error and
dropped into an in-memory demo mode, telling people their scores were saved
when nothing reached a server. An app with no backend must say so.

---

## Known gaps

Deliberately not built yet, in rough priority order:

- **Elo ratings** — the model supports it; the service is not reconnected.
- **Standings tables** — fixtures produce results, but the league table is not
  yet computed from them.
- **Performance sports** — athletics and swimming are catalogued and the
  `CompetitionArchetype.performance` archetype exists, but the attempts/heats
  UI is not built. Versus sports work end to end.
- **Server-authoritative scoring** — results are currently computed client-side
  and constrained by rules. Making them tamper-proof needs a Cloud Function,
  which needs billing enabled. The event log is already structured for it.
- **Team entrants** — the model supports teams; only individual entrants are
  wired through registration.
- **Payments, certificates, QR check-in, notifications, exports.**
- **Localisation** — strings are hardcoded English.
