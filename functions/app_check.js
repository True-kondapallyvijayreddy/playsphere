/**
 * Whether callables require a verified App Check token.
 *
 * ## Why this is one constant and not twenty-two decisions
 *
 * There are twenty-two `onCall` functions in this codebase and they are the
 * smallest, sharpest part of the attack surface: `placeAuctionBid` moves
 * money, `redeemClaimCode` is reachable SIGNED OUT and mints a sign-in token
 * for a child's account, and the backfills rewrite career history across the
 * whole platform. Until now none of them asked whether the caller was the app
 * at all — a web API key is public by design, so a script holding one could
 * reach every single one.
 *
 * Enforcement is therefore something the project turns on once, everywhere,
 * rather than a flag somebody remembers per function. A partially enforced
 * surface is the worst of both: the same rollout risk, and an attacker uses
 * whichever function was forgotten.
 *
 * ## Why it ships OFF
 *
 * Turning this on before the clients can attest locks out every build already
 * on a phone. The order that works:
 *
 *   1. Ship `activateAppCheck` in the app (done — see
 *      lib/core/firebase/app_check_setup.dart). Clients start sending tokens
 *      and nothing changes, because nothing checks them.
 *   2. Watch the App Check metrics page for a week. It reports verified versus
 *      unverified requests per product, which is how you discover the old
 *      versions still in the wild and the developer devices whose debug tokens
 *      were never registered.
 *   3. Flip this to `true` and deploy functions. Callables are the right first
 *      product to enforce: the smallest surface, and the one carrying
 *      `redeemClaimCode`.
 *   4. Only then enforce Storage, and only then Firestore. Firestore last,
 *      because a mistake there is the whole product rather than one feature.
 *
 * `consumeAppCheckToken` stays false deliberately. Replay protection makes a
 * token single-use, which is correct for a payment and wrong for a pad on a
 * ground with intermittent signal — a retried call is the normal case here,
 * not an attack, and consuming tokens would turn every reconnect into a
 * failure. Turn it on per function if one ever genuinely needs it.
 */
export const ENFORCE_APP_CHECK = false;

/**
 * Options every callable should spread.
 *
 * Region included, because `asia-south1` was being repeated on some callables
 * and inherited from `setGlobalOptions` on others — which works, and means the
 * two sets drift the first time somebody changes one.
 */
export const CALLABLE_OPTS = {
  region: 'asia-south1',
  enforceAppCheck: ENFORCE_APP_CHECK,
  consumeAppCheckToken: false,
};
