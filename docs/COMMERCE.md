# Commerce — plans, ads, shop and grounds

What was built, what is deliberately stubbed, and the one thing that must not
be forgotten before real money moves.

---

## ⚠ The blocking constraint

**PlaySphere currently grants paid entitlements from the client.**

`Pricing.introOfferActive` (`lib/core/models/billing.dart`) makes both paid
plans cost ₹0. While that is true there is no payment processor in the loop,
so the app writes its own `plan` / `planValidUntil` fields.

A client that writes its own entitlement can lie. `firestore.rules` bounds
what the lie is worth rather than pretending to prevent it:

| Guard | Effect |
|---|---|
| `payments` rows must have `amountPaise == 0` and `gateway == 'none'` | A client cannot forge a receipt claiming money was collected. The ledger stays trustworthy as a financial record. |
| `planGrantIsBounded()` | A grant is at most ~1 year. Nobody writes themselves a decade. |
| `isVerified` is not client-writable | A ground owner cannot self-certify. |
| `bookings.amountPaise` must equal the ground's rate × hours | A booker cannot charge themselves ₹0 for a ₹2,000 pitch. |

The worst a hostile client can do **today** is grant itself a plan that is
already being given away to anyone who asks. That is fine for a launch offer
and **not** fine afterwards.

### Before `introOfferActive` is set to `false`

Three changes ship together or the product gives away paid plans:

1. **A real gateway.** Implement `PaymentGateway` against Razorpay and swap it
   in at `billingRepositoryProvider` — that provider is the only injection
   point, so no screen changes. Note `FreeCheckout` *throws* on a non-zero
   amount, so if step 1 is skipped every purchase fails loudly rather than
   silently succeeding for free.
2. **Server-side entitlement.** The webhook writes `plan*` on `orgs/` and
   `users/` with the Admin SDK. The `planGrantIsBounded()` escape hatch in
   `firestore.rules` becomes plain `planFieldsUnchanged()`.
3. **App-store billing.** Premium is a digital subscription: Apple and Google
   require it to go through IAP on mobile (15–30% commission). Razorpay is for
   the web checkout and for club plans. Ground bookings and shop orders are
   physical goods/services and stay outside IAP.

---

## What ships now

### Plans

| | Price | Launch | Where |
|---|---|---|---|
| Club plan | ₹999/year, unlimited members | ₹0 | Step 2 of club creation |
| Premium | ₹99/year | ₹0 | `/premium`, from the three-lines menu |

Billed yearly, never monthly — at ₹99 a year the collection cost of a monthly
charge exceeds a meaningful share of the charge.

A lapsed plan is **not** a lockout. A club whose plan expired mid-season keeps
its fixtures, results and records; the plan gates depth, never participation.
Same principle on the member side: joining clubs, entering events, playing and
being scored are free forever.

Early renewal extends from the existing expiry, not from today
(`PlanState.extendedFrom`) — anything else charges for time already owned.

### Ledger

`payments/{id}`, one row per charge, **written even at ₹0**. A ledger with
holes cannot answer "how many clubs activated in March" separately from "how
many paid in March", and the zero rows mean the reporting and refund paths are
exercised from day one instead of first meeting real data under money.

### Ads

House-controlled, no ad-network SDK. Three reasons, in order of weight: a
large share of members are minors and an arbitrary demand stack cannot be
pointed at them; network inventory is generic, which throws away the only
advertising advantage PlaySphere has (it knows the sport, club and ground);
and an SDK is a third-party binary with network access inside an app holding
children's data.

- Banner shows a 5-second countdown, then a close button. It does **not**
  auto-hide — the countdown unlocks dismissal, the user decides when.
- Dismissal lasts the session only, in memory. "Not now", not "never again".
- Hidden entirely for Premium members.
- Minors see PlaySphere's own promotions but never third-party ads — India's
  DPDP Act prohibits targeted advertising directed at children.
- Every banner carries a disclosure line (`Ad · Decathlon` vs
  `From PlaySphere`).

### Shop

Curated listings pointing at Decathlon; the vendor takes the payment, ships,
and handles returns. PlaySphere earns referral commission.

Deliberately not a cart. An in-app checkout is a warehouse, a logistics
contract, a returns policy and a consumer-protection liability, and it earns
roughly the same margin as a link until real volume. Category URLs rather than
SKU deep links, because a dead product page is worse than a less specific live
one.

The bundled `DecathlonCatalog` is yielded before Firestore is even asked, so
the shelf is stocked on the first frame and a refused read leaves a stale shop
rather than an empty one.

### Grounds

Top-level `grounds/`, **not** `orgs/{id}/venues/`. A `Venue` is a club's own
hall for scheduling its own draws; a ground is a business someone else owns
and rents to anybody. Nesting would make "cricket grounds in Hyderabad free on
Sunday" unanswerable without reading every club in the country.

Booking is a **Firestore transaction**, not a write. Two clubs checking a
popular ground at the same time is the expected traffic pattern, not a rare
race, and its consequence is two teams on one pitch. The transaction re-reads
the day's bookings and Firestore aborts it if any changed underneath.

Slots are a `yyyy-MM-dd` day key plus two integer hours, half-open
`[start, end)`. Two timestamps would make the conflict check a range read plus
client filtering in an unagreed timezone; this makes it one small indexed
query a transaction can afford. `firestore.rules` enforces shape; the
transaction enforces exclusivity — rules cannot query siblings.

Paid grounds are **settle-at-venue** for now. The booking records what is
*owed*; no `payments` row is written, because logging money nobody received is
worse than logging nothing.

In event creation, "Book a ground" is **off by default**. Most clubs in India
play somewhere they already have, and a form treating "we have somewhere" as
the awkward path is a form written for the cities.

---

## Still missing

- Server-side entitlement (see above) — the blocker.
- Renewal/expiry scheduled function and dunning notifications.
- Geo search. Grounds match on `cityKey` only; `latitude`/`longitude` are
  stored and nothing queries them. No map, no distance sort.
- Ground verification flow — `isVerified` is server-only and nothing sets it.
- Advertiser console, impression/click tracking, BigQuery pipeline.
- Ground owner payouts and commission split (`domain/payments/route_split.dart`
  models it and nothing calls it).
