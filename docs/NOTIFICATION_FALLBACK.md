# A second delivery channel for critical notifications

**Status:** not built. This document exists because the code used to claim it
was.

`lib/core/notifications/notification_model.dart` described a WhatsApp/SMS
fallback in the present tense and pointed at a `NotificationFallbackPolicy` in
`fallback_policy.dart`. Neither the class nor the file was ever written.
`pubspec.yaml` said the same thing. Those comments are now corrected; this is
the scope they were standing in for.

## Why it matters more here than it would elsewhere

Firebase Cloud Messaging is the only way PlaySphere reaches a phone. On the
handsets this product is actually used on — 2–4 GB Android devices from
Xiaomi, Realme, Vivo, Oppo and Samsung's A series — the vendor's battery
manager routinely kills background delivery for an app the user has not opened
recently, which is precisely the user a match reminder is for. Nothing in the
app can detect this. A push that never arrives and a push that arrived and was
dismissed look identical from the server.

The product's own reasoning makes the consequence explicit. From
`notification_model.dart`: a missed match-start notification "means a player
genuinely does not show up". From `matchRsvp`: somebody who does not see it
until Monday "did not miss a notification, they missed the game". And the
thing PlaySphere is replacing — a WhatsApp group — does not have this problem,
because a group message is put in front of you whether or not the app was
open.

So this is not a nice-to-have channel. It is the difference between the product
being more reliable than the WhatsApp group it replaces or less.

## Scope

Only the types already marked `isCritical: true`, which is the set
`CRITICAL_NOTIFICATION_TYPES` in `functions/index.js` mirrors:

| Type | Why a second channel |
|---|---|
| `event_reminder` | The whole point is arriving in time to act. |
| `match_start` | A player who misses it does not show up. |
| `result` | Settles an argument at the ground, not the next day. |
| `match_rsvp` | An invitation that expires. |
| `match_clash` | Somebody is about to be double-booked. |
| `tournament_announced` | Entries close. |
| `event_cancelled` | People travel to grounds. |

Everything else keeps going through the digest. Sending a second channel for
non-critical events would train people to ignore both.

## The shape it should take

1. **A ledger, not a retry.** Each critical notification gets a
   `users/{uid}/notifications/{id}` document already — that write exists and
   is the durable half. Add `deliveredAt` (set by the client when it actually
   renders the notification) and a scheduled sweep that escalates anything
   still undelivered after a threshold. Escalating on a timer rather than on a
   push failure is the only honest trigger, because FCM reports a successful
   *send* and knows nothing about arrival.

2. **The threshold is per type, derived from the event.** A match reminder is
   useless after the match starts; escalating at T-minus-30-minutes is right
   and escalating at T-plus-10 is worse than silence. `event_reminder` and
   `match_start` need a deadline relative to `scheduledAt`, not a fixed delay.

3. **WhatsApp Business Cloud API, not SMS, as the first channel.** Cheaper per
   message in India, far higher open rate, and it carries a deep link that
   opens the app. It needs pre-approved message templates — one per type above
   — and a template approval cycle measured in days, which is the long pole in
   this work and should be started before any code.

4. **SMS as the floor.** For accounts with no WhatsApp. A DLT-registered sender
   and template per TRAI rules, which is its own registration process.

5. **Phone numbers are opt-in and currently mostly absent.** `AppUser.phone`
   exists and is nullable, and nothing asks for it. A channel that reaches 4%
   of users is not a fallback. Collecting it needs a reason the user
   recognises — "so we can text you if a match moves" — asked at the point
   they join a club, not at signup.

## What this costs

Per message, the WhatsApp utility-template rate in India is small; the real
costs are the template approval cycle, DLT registration for the SMS floor, and
a per-user rate limit so a scheduling mistake cannot text a club forty times.
The engineering is perhaps a week; the approvals are longer and should run in
parallel.

## What not to do

Do not fall back on every push. Do not escalate non-critical types. Do not add
a "resend" button — a person who did not get the notification is not looking at
the app.

And do not describe this as implemented until it is. That is how this document
came to exist.
