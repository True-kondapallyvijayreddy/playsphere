/**
 * Team entries in an age- or gender-restricted event.
 *
 * ## Why this lives on the server
 *
 * `CompetitionCategory.check` in the app decides whether ONE person may enter,
 * and it can, because that person is reading their own profile. A team entry
 * is made by somebody else — a captain, or the organizer of a visiting club —
 * and the eleven birth dates it has to be judged on are not theirs to read: a
 * minor's profile is closed to everyone but the child, a guardian, and a
 * consent holder (`firestore.rules`, `match /users/{userId}`). An Under-19
 * cricket side is almost entirely minors, so a client-side check could not
 * see the very people it exists to check.
 *
 * So the check runs here, in two places:
 *
 * 1. `checkTeamEligibility` — asked BEFORE entering, so the captain is told
 *    "Ravi Kumar is 20 on 01/10/2026" and fixes the squad, instead of finding
 *    a rejected entry later.
 * 2. `onTeamRegistrationCreated` — the backstop. Rules cannot loop over a
 *    roster, so an entry written by a build without (1), or around it, is
 *    re-judged on arrival and rejected with the same reasons.
 *
 * What the caller learns is only the failing players' names and the reason —
 * never a birth date, and nothing about players who pass.
 */

import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { onDocumentCreated, onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions';

import { CALLABLE_OPTS } from './app_check.js';
import { persistNotifications, pushToUids } from './push.js';

function db() {
  return getFirestore();
}

// The app writes every date as a local midnight on an Indian phone. Reading the
// calendar day back in UTC would move a birthday to the day before, and a
// player born on the cut-off date would be a year out.
const ZONE = 'Asia/Kolkata';

const GENDER_LABELS = {
  male: 'Male',
  female: 'Female',
  other: 'Other',
  prefer_not_to_say: 'Prefer not to say',
};

function toDate(value) {
  if (value == null) return null;
  if (value instanceof Date) return value;
  if (typeof value.toDate === 'function') return value.toDate();
  return null;
}

/** `{ year, month, day }` of [date] as the calendar reads in India. */
export function calendarDay(date) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: ZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(date);
  const get = (type) => Number(parts.find((p) => p.type === type).value);
  return { year: get('year'), month: get('month'), day: get('day') };
}

/** Same arithmetic as `ageOnDate` in `lib/core/models/firestore_codec.dart`. */
export function ageOn(dateOfBirth, reference) {
  const dob = calendarDay(dateOfBirth);
  const ref = calendarDay(reference);
  let age = ref.year - dob.year;
  const hadBirthday = ref.month > dob.month
    || (ref.month === dob.month && ref.day >= dob.day);
  if (!hadBirthday) age -= 1;
  return age;
}

function formatDay(date) {
  const { year, month, day } = calendarDay(date);
  return `${String(day).padStart(2, '0')}/${String(month).padStart(2, '0')}/${year}`;
}

/** True when [category] restricts who may play at all. */
export function categoryRestricts(category) {
  if (!category) return false;
  const dims = Array.isArray(category.dimensions) ? category.dimensions : [];
  const ageBound = dims.includes('age')
    && (category.minAge != null || category.maxAge != null);
  const genderBound = Array.isArray(category.allowedGenders)
    && category.allowedGenders.length > 0;
  return ageBound || genderBound;
}

/**
 * Every member of a squad who may not play in [category], with the reason.
 *
 * Mirrors `CompetitionCategory.check`, with one deliberate difference: a
 * profile with no birth date FAILS an age-bound event. The app reads a missing
 * date as "today" (age 0), which passes every Under-N band — the one way an
 * over-age player could walk into a junior event unnoticed.
 *
 * @param {object} category  the competition's `category` map
 * @param {Date|null} competitionStart
 * @param {{uid: string, name: string, dateOfBirth: Date|null, gender: string|null}[]} members
 * @param {Date} now  used only when the event has neither a cut-off nor a start
 * @returns {{uid: string, name: string, reason: string}[]}
 */
export function teamProblems(category, competitionStart, members, now = new Date()) {
  if (!categoryRestricts(category)) return [];
  const dims = Array.isArray(category.dimensions) ? category.dimensions : [];
  const minAge = category.minAge ?? null;
  const maxAge = category.maxAge ?? null;
  const ageBound = dims.includes('age') && (minAge != null || maxAge != null);
  const cutOff = toDate(category.ageCutOffDate) ?? competitionStart ?? now;
  const genders = Array.isArray(category.allowedGenders) ? category.allowedGenders : [];
  const label = category.label || 'this category';

  const problems = [];
  for (const m of members) {
    if (ageBound) {
      if (!m.dateOfBirth) {
        problems.push({
          uid: m.uid,
          name: m.name,
          reason: `${m.name} has no date of birth on their profile, so their `
            + `age for ${label} cannot be checked.`,
        });
        continue;
      }
      const age = ageOn(m.dateOfBirth, cutOff);
      if (maxAge != null && age > maxAge) {
        problems.push({
          uid: m.uid,
          name: m.name,
          reason: `${m.name} is ${age} on ${formatDay(cutOff)} — ${label} `
            + `allows ${maxAge} or under.`,
        });
        continue;
      }
      if (minAge != null && age < minAge) {
        problems.push({
          uid: m.uid,
          name: m.name,
          reason: `${m.name} is ${age} on ${formatDay(cutOff)} — ${label} `
            + `needs ${minAge} or over.`,
        });
        continue;
      }
    }
    if (genders.length > 0 && !genders.includes(m.gender)) {
      const allowed = genders.map((g) => GENDER_LABELS[g] ?? g).join(' / ');
      problems.push({
        uid: m.uid,
        name: m.name,
        reason: `${m.name} cannot play in ${label} — open to ${allowed} only.`,
      });
    }
  }
  return problems;
}

/** The squad's profiles, in roster order. Unreadable/missing profiles fail. */
export async function loadMembers(memberUids) {
  if (!memberUids.length) return [];
  const refs = memberUids.map((uid) => db().collection('users').doc(uid));
  const snaps = await db().getAll(...refs);
  return snaps.map((snap, i) => {
    const d = snap.exists ? snap.data() : {};
    return {
      uid: memberUids[i],
      name: d.displayName || 'A player',
      dateOfBirth: toDate(d.dateOfBirth),
      gender: d.gender ?? null,
    };
  });
}

async function roleAt(orgId, uid) {
  if (!orgId) return null;
  const snap = await db().doc(`orgs/${orgId}/members/${uid}`).get();
  if (!snap.exists || snap.get('status') !== 'active') return null;
  return snap.get('role') ?? null;
}

const COMPETITION_ROLES = ['owner', 'admin', 'event_manager'];

/**
 * Who may ask: whoever runs the team (the same people `teamRuns` lets enter
 * it), the organizers of the club that owns it, and the host's organizers.
 */
async function mayAsk(uid, team, orgId) {
  if ([team.createdByUid, team.captainUid, team.managerUid].includes(uid)) {
    return true;
  }
  if (COMPETITION_ROLES.includes(await roleAt(team.clubId, uid))) return true;
  return COMPETITION_ROLES.includes(await roleAt(orgId, uid));
}

export const checkTeamEligibility = onCall(
  { ...CALLABLE_OPTS },
  async (request) => {
    const caller = request.auth?.uid;
    if (!caller) {
      throw new HttpsError('unauthenticated', 'Sign in to enter a team.');
    }
    const { orgId, compId, teamId } = request.data ?? {};
    for (const [key, value] of Object.entries({ orgId, compId, teamId })) {
      if (typeof value !== 'string' || !value || value.includes('/')) {
        throw new HttpsError('invalid-argument', `Missing ${key}.`);
      }
    }

    const [compSnap, teamSnap] = await Promise.all([
      db().doc(`orgs/${orgId}/competitions/${compId}`).get(),
      db().doc(`teams/${teamId}`).get(),
    ]);
    if (!compSnap.exists) {
      throw new HttpsError('not-found', 'That event no longer exists.');
    }
    if (!teamSnap.exists) {
      throw new HttpsError('not-found', 'That team no longer exists.');
    }
    const team = teamSnap.data();
    if (!(await mayAsk(caller, team, orgId))) {
      throw new HttpsError(
        'permission-denied',
        'Only the people who run this team can enter it.',
      );
    }

    const comp = compSnap.data();
    const category = comp.category ?? null;
    if (!categoryRestricts(category)) return { eligible: true, problems: [] };

    const members = await loadMembers(team.memberUids ?? []);
    const problems = teamProblems(category, toDate(comp.startDate), members);
    return {
      eligible: problems.length === 0,
      problems: problems.map(({ name, reason }) => ({ name, reason })),
    };
  },
);

/**
 * The backstop: a team entry that should not have been made is rejected on
 * arrival, its slot handed back, and whoever entered it told why.
 */
export const onTeamRegistrationCreated = onDocumentCreated(
  { region: 'asia-south1', document: 'orgs/{orgId}/competitions/{compId}/registrations/{regId}' },
  async (event) => {
    const reg = event.data?.data();
    if (!reg || !reg.teamId) return;

    const { orgId, compId, regId } = event.params;
    const compRef = db().doc(`orgs/${orgId}/competitions/${compId}`);
    const compSnap = await compRef.get();
    if (!compSnap.exists) return;
    const comp = compSnap.data();
    if (!categoryRestricts(comp.category)) return;

    const members = await loadMembers(reg.memberUids ?? []);
    const problems = teamProblems(comp.category, toDate(comp.startDate), members);
    if (problems.length === 0) return;

    const note = problems.map((p) => p.reason).join(' ');
    const regRef = event.data.ref;

    const rejected = await db().runTransaction(async (tx) => {
      const fresh = await tx.get(regRef);
      if (!fresh.exists) return false;
      const before = fresh.get('status');
      // Already decided — an organizer got there first, or this is a retry.
      if (!['pending', 'confirmed', 'waitlisted'].includes(before)) return false;

      // Handing a confirmed slot on to the first reserve, in the same commit,
      // for the reason `_moveRegistration` does: never a window where the
      // field is a side short while somebody is queued for it.
      // Ordered in memory rather than with `orderBy('waitlistPosition')`: the
      // (status, waitlistPosition) index now exists, but a trigger that fails
      // silently whenever an index is missing in some environment is worse
      // here than reading a short queue and sorting it.
      let promote = null;
      if (before === 'confirmed') {
        const queue = await tx.get(
          compRef.collection('registrations')
            .where('status', '==', 'waitlisted')
            .limit(50),
        );
        const waiting = queue.docs
          .filter((d) => d.id !== regId)
          .sort((a, b) => (a.get('waitlistPosition') ?? Number.MAX_SAFE_INTEGER)
            - (b.get('waitlistPosition') ?? Number.MAX_SAFE_INTEGER));
        promote = waiting[0] ?? null;
      }

      tx.update(regRef, {
        status: 'rejected',
        waitlistPosition: null,
        eligibilityNote: note.slice(0, 1000),
        decidedBy: 'system:eligibility',
        decidedAt: FieldValue.serverTimestamp(),
      });

      if (before === 'confirmed' && promote) {
        tx.update(promote.ref, { status: 'confirmed', waitlistPosition: null });
        tx.update(compRef, { waitlistCount: FieldValue.increment(-1) });
      } else if (before === 'confirmed') {
        tx.update(compRef, { confirmedCount: FieldValue.increment(-1) });
      } else if (before === 'waitlisted') {
        tx.update(compRef, { waitlistCount: FieldValue.increment(-1) });
      }
      return true;
    });
    if (!rejected) return;

    logger.info(`Rejected team entry ${regId} in ${orgId}/${compId}: ${note}`);

    const to = reg.registeredByUid;
    if (!to) return;
    const payload = {
      id: `team_ineligible_${compId}_${regId}`,
      type: 'event_reminder',
      title: `${reg.teamName ?? 'Your team'} could not be entered`,
      body: `${comp.name ?? 'This event'}: ${note}`.slice(0, 400),
      deepLinkRoute: '/org/:orgId/event/:compId',
      deepLinkParam_orgId: orgId,
      deepLinkParam_compId: compId,
    };
    const unique = await persistNotifications([to], payload);
    await pushToUids(unique, payload);
  },
);

// ---------------------------------------------------------------------------
// Line-ups: the match-day half of the same check (TC-ADM-069 / TC-ADM-073).
// ---------------------------------------------------------------------------
//
// A line-up is picked from the whole club, not only the squad that entered —
// a substitute on the day is normal. The app used to check each pick against
// the player's own profile, which it cannot read for a minor or for an adult
// with a private profile, and so it waved those players through: in an
// Under-19 event, nearly everybody. These ask the server, which can read them.

const LINEUP_ROLES = ['owner', 'admin', 'event_manager', 'judge_scorer'];
const MAX_LINEUP_CHECK = 40;

/** The account uids on a stored line-up. Pure. */
export function lineupUids(lineup) {
  if (!Array.isArray(lineup)) return [];
  return [...new Set(lineup
    .map((p) => (p && typeof p.uid === 'string' ? p.uid : null))
    .filter(Boolean))];
}

/** Whether [caller] may pick players for [fixture]. */
async function mayPickFor(caller, orgId, fixture) {
  if ((fixture.scorerUids ?? []).includes(caller)) return true;
  if ((fixture.officials ?? []).some((o) => o?.uid === caller)) return true;
  const orgs = [orgId, ...(Array.isArray(fixture.participantOrgIds) ? fixture.participantOrgIds : [])];
  for (const org of new Set(orgs)) {
    if (LINEUP_ROLES.includes(await roleAt(org, caller))) return true;
  }
  return false;
}

export const checkLineupEligibility = onCall(
  { ...CALLABLE_OPTS },
  async (request) => {
    const caller = request.auth?.uid;
    if (!caller) throw new HttpsError('unauthenticated', 'Sign in first.');
    const { orgId, compId, fixtureId, uids } = request.data ?? {};
    for (const [key, value] of Object.entries({ orgId, compId, fixtureId })) {
      if (typeof value !== 'string' || !value || value.includes('/')) {
        throw new HttpsError('invalid-argument', `Missing ${key}.`);
      }
    }
    if (!Array.isArray(uids) || uids.length === 0 || uids.length > MAX_LINEUP_CHECK
        || uids.some((u) => typeof u !== 'string' || !u || u.includes('/'))) {
      throw new HttpsError('invalid-argument', 'Name between 1 and 40 players.');
    }

    const compRef = db().doc(`orgs/${orgId}/competitions/${compId}`);
    const [compSnap, fxSnap] = await Promise.all([
      compRef.get(),
      compRef.collection('fixtures').doc(fixtureId).get(),
    ]);
    if (!compSnap.exists || !fxSnap.exists) {
      throw new HttpsError('not-found', 'That match no longer exists.');
    }
    if (!(await mayPickFor(caller, orgId, fxSnap.data()))) {
      throw new HttpsError('permission-denied', 'Only the people running this match can pick its players.');
    }

    const comp = compSnap.data();
    if (!categoryRestricts(comp.category)) return { problems: [] };
    const problems = teamProblems(comp.category, toDate(comp.startDate), await loadMembers([...new Set(uids)]));
    return { problems: problems.map(({ uid, name, reason }) => ({ uid, name, reason })) };
  },
);

/**
 * The backstop: whatever wrote the line-up — an older app, an offline edit,
 * a write that went around the check — the match carries `lineupIssues`, which
 * the line-up editor and the match centre show, and the people running the
 * match are told the moment a new problem appears. Not refused: the toss may
 * be minutes away, and taking a player off the sheet is a decision for the
 * ground.
 */
export const onLineupChanged = onDocumentUpdated(
  { region: 'asia-south1', document: 'orgs/{orgId}/competitions/{compId}/fixtures/{fixtureId}' },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    const uidsBefore = [...lineupUids(before.lineupA), ...lineupUids(before.lineupB)].sort();
    const uidsAfter = [...lineupUids(after.lineupA), ...lineupUids(after.lineupB)].sort();
    if (uidsBefore.join() === uidsAfter.join()) return;

    const { orgId, compId } = event.params;
    const comp = await db().doc(`orgs/${orgId}/competitions/${compId}`).get();
    if (!comp.exists) return;

    let problems = [];
    if (categoryRestricts(comp.get('category')) && uidsAfter.length > 0) {
      problems = teamProblems(
        comp.get('category'),
        toDate(comp.get('startDate')),
        await loadMembers([...new Set(uidsAfter)].slice(0, MAX_LINEUP_CHECK)),
      );
    }
    const issues = problems.map(({ uid, name, reason }) => ({ uid, name, reason }));
    const previous = Array.isArray(after.lineupIssues) ? after.lineupIssues : [];
    if (issues.length === 0 && previous.length === 0) return;
    await event.data.after.ref.update({
      lineupIssues: issues.length > 0 ? issues : FieldValue.delete(),
    });

    const known = new Set(previous.map((p) => p?.uid));
    const fresh = issues.filter((p) => !known.has(p.uid));
    if (fresh.length === 0) return;

    const organizers = await db().collection(`orgs/${orgId}/members`)
      .where('status', '==', 'active')
      .where('role', 'in', COMPETITION_ROLES)
      .get();
    const to = [...new Set([
      ...organizers.docs.map((d) => d.id),
      ...(after.scorerUids ?? []),
    ])].filter(Boolean);
    if (to.length === 0) return;
    const payload = {
      id: `lineup_ineligible_${event.params.fixtureId}_${fresh.map((p) => p.uid).join('_')}`.slice(0, 200),
      type: 'event_reminder',
      title: `${after.entrantAName ?? 'Side A'} v ${after.entrantBName ?? 'Side B'}: check the line-up`,
      body: `${fresh.map((p) => p.reason).join(' ')}`.slice(0, 400),
      deepLinkRoute: '/org/:orgId/event/:compId',
      deepLinkParam_orgId: orgId,
      deepLinkParam_compId: compId,
    };
    const unique = await persistNotifications(to, payload);
    await pushToUids(unique, payload);
    logger.info(`Line-up issues on ${event.params.fixtureId}: ${payload.body}`);
  },
);
