/**
 * A team's roster changing after the team has entered something.
 *
 * ## What used to go wrong
 *
 * An entry copies the team's `memberUids` at the moment it is made — onto the
 * registration, then onto the draw's entrant document, and from there into
 * every fixture's `squadUids` (`syncFixtureSquads`). Nothing ever copied them
 * again. A captain who added two players on Friday had a squad the draw did
 * not know about: the newcomers' matches never appeared on their own lists,
 * the scheduler could not see their clashes in other sports, and an over-age
 * player added to an Under-19 side was never checked at all, because the
 * eligibility check runs when the entry is made (`team_eligibility.js`).
 *
 * ## What this does
 *
 * Every live entry of the team — not withdrawn, not rejected, in an event
 * that is neither finished nor cancelled — takes the new roster: the
 * registration, the entrant, and the `squadUids` of its unplayed fixtures.
 * Played fixtures keep the squad they were played with.
 *
 * Anybody NEWLY added is checked against each event's age/gender limits. A
 * failure does not throw the team out: it may be halfway through a season,
 * and one wrong name is the captain's to fix, not a reason to forfeit eleven
 * people's matches. So the entry is flagged (`eligibilityNote`, shown to the
 * organizer on the entries list) and the person who entered the team is told
 * exactly who and why.
 */

import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions';

import { collectPaged } from './paged_scan.js';
import { persistNotifications, pushToUids } from './push.js';
import { categoryRestricts, loadMembers, teamProblems } from './team_eligibility.js';

function db() {
  return getFirestore();
}

const LIVE_REGISTRATION = new Set(['pending', 'confirmed', 'waitlisted']);
const OVER = new Set(['completed', 'cancelled']);

/** Pure: the uids in [after] that were not in [before]. */
export function addedMembers(before, after) {
  const was = new Set(Array.isArray(before) ? before : []);
  return (Array.isArray(after) ? after : []).filter((u) => typeof u === 'string' && !was.has(u));
}

/** Pure: whether two rosters hold the same people, in any order. */
export function sameRoster(a, b) {
  const x = new Set(Array.isArray(a) ? a : []);
  const y = new Set(Array.isArray(b) ? b : []);
  if (x.size !== y.size) return false;
  for (const u of x) if (!y.has(u)) return false;
  return true;
}

export const onTeamRosterChanged = onDocumentUpdated(
  { region: 'asia-south1', document: 'teams/{teamId}' },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    if (sameRoster(before.memberUids, after.memberUids)) return;

    const { teamId } = event.params;
    const roster = (after.memberUids ?? []).filter((u) => typeof u === 'string' && u);
    const added = addedMembers(before.memberUids, roster);
    const compCache = new Map();
    const compOf = async (ref) => {
      if (!compCache.has(ref.path)) compCache.set(ref.path, await ref.get());
      return compCache.get(ref.path);
    };

    // ---- Registrations ----------------------------------------------------
    // Bounded by one team's entries, but paged like every other
    // collection-group read here (see paged_scan.js).
    const regs = await collectPaged(
      db().collectionGroup('registrations').where('teamId', '==', teamId),
      { label: 'team roster registrations' },
    );
    for (const reg of regs) {
      const r = reg.data();
      if (!LIVE_REGISTRATION.has(r.status)) continue;
      const compRef = reg.ref.parent.parent;
      const comp = await compOf(compRef);
      if (!comp.exists || OVER.has(comp.get('status'))) continue;

      const update = { memberUids: roster };
      let problems = [];
      if (added.length > 0 && categoryRestricts(comp.get('category'))) {
        const members = await loadMembers(added);
        problems = teamProblems(comp.get('category'), comp.get('startDate')?.toDate?.() ?? null, members);
      }
      if (problems.length > 0) {
        update.eligibilityNote = problems.map((p) => p.reason).join(' ').slice(0, 1000);
        update.eligibilityFlaggedAt = FieldValue.serverTimestamp();
      }
      await reg.ref.update(update);

      if (problems.length > 0 && typeof r.registeredByUid === 'string') {
        const orgId = compRef.parent.parent.id;
        const payload = {
          id: `team_roster_ineligible_${compRef.id}_${teamId}_${Date.now()}`,
          type: 'event_reminder',
          title: `${after.name ?? 'Your team'}: check your squad`,
          body: `${comp.get('name') ?? 'An event'}: ${update.eligibilityNote}`
            + ' They cannot play in it — take them off the squad or pick them'
            + ' for a different event.',
          deepLinkRoute: '/org/:orgId/event/:compId',
          deepLinkParam_orgId: orgId,
          deepLinkParam_compId: compRef.id,
        };
        payload.body = payload.body.slice(0, 400);
        const to = [...new Set([r.registeredByUid, after.captainUid].filter(Boolean))];
        const unique = await persistNotifications(to, payload);
        await pushToUids(unique, payload);
        logger.info(`Flagged ${teamId} in ${compRef.path}: ${update.eligibilityNote}`);
      }
    }

    // ---- Draw entrants, and the squads on their unplayed fixtures ----------
    const entrants = await collectPaged(
      db().collectionGroup('entrants').where('teamId', '==', teamId),
      { label: 'team roster entrants' },
    );
    for (const ent of entrants) {
      if (ent.get('withdrawn') === true) continue;
      const compRef = ent.ref.parent.parent;
      const comp = await compOf(compRef);
      if (!comp.exists || OVER.has(comp.get('status'))) continue;
      if (sameRoster(ent.get('memberUids'), roster)) continue;
      await ent.ref.update({ memberUids: roster });

      const fixtures = compRef.collection('fixtures');
      const [asA, asB] = await Promise.all([
        fixtures.where('entrantAId', '==', ent.id).get(),
        fixtures.where('entrantBId', '==', ent.id).get(),
      ]);
      for (const fx of [...asA.docs, ...asB.docs]) {
        const f = fx.data();
        if (f.status !== 'scheduled' || (f.lastSeq ?? 0) > 0) continue;
        // The other side's squad stays; this side's is replaced.
        const otherId = f.entrantAId === ent.id ? f.entrantBId : f.entrantAId;
        let other = [];
        if (otherId) {
          const o = await compRef.collection('entrants').doc(otherId).get();
          if (o.exists) other = [o.get('uid'), ...(o.get('memberUids') ?? [])];
        }
        const squad = [...new Set([
          ...other, ...roster, f.entrantAUid, f.entrantBUid,
        ].filter((u) => typeof u === 'string' && u))].sort();
        if (!sameRoster(f.squadUids, squad)) await fx.ref.update({ squadUids: squad });
      }
    }
  },
);
