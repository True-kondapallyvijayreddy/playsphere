/**
 * Walks the inventory in subject_data.js against the real database.
 *
 * Kept apart from the inventory so the inventory stays pure and testable, and
 * apart from account.js so erasure and export run the same traversal. Two
 * callers that each hand-rolled their own walk is how they came to disagree
 * about which collections exist in the first place.
 */

import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { logger } from 'firebase-functions';

import {
  DISPOSITION,
  LOOKUP,
  erasureRows,
  exportRows,
} from './subject_data.js';

function db() {
  return getFirestore();
}

/** Firestore's per-batch write ceiling. */
const BATCH_LIMIT = 400;

/**
 * Every document one inventory row matches for `uid`.
 *
 * A collection-group query is the only way to reach a subcollection whose
 * parent ids are unknown — "every check-in this person made" spans one
 * subcollection per ground. Those need a collection-group index; a row whose
 * index is missing throws, and that is deliberately NOT swallowed here, because
 * an erasure that silently skipped a collection is the failure this whole
 * module exists to prevent.
 */
async function docsFor(row, uid) {
  switch (row.lookup) {
    case LOOKUP.docId: {
      const snap = await db().collection(row.collection).doc(uid).get();
      return snap.exists ? [snap] : [];
    }
    case LOOKUP.sub: {
      const snap = await db()
        .collection(row.collection)
        .doc(uid)
        .collection(row.subcollection)
        .get();
      return snap.docs;
    }
    case LOOKUP.field: {
      const snap = await db()
        .collection(row.collection)
        .where(row.field, '==', uid)
        .get();
      return snap.docs;
    }
    case LOOKUP.group: {
      const snap = await db()
        .collectionGroup(row.collection)
        .where(row.field, '==', uid)
        .get();
      return snap.docs;
    }
    default:
      throw new Error(`unknown lookup "${row.lookup}" on row "${row.id}"`);
  }
}

/**
 * Deletes the Cloud Storage objects a set of documents points at.
 *
 * By stored path rather than by prefix, because the uid sits in the middle of
 * a memory's path (`memories/{orgId}/{fixtureId}/{uid}/{file}`) and no prefix
 * can select it. The document is the index into the bucket; that is what
 * `storagePath` is for.
 *
 * A missing object is not an error — it means somebody already deleted the
 * photo, which is the desired end state either way.
 */
async function deleteStorageFor(docs, field) {
  const bucket = getStorage().bucket();
  let deleted = 0;
  await Promise.all(
    docs.map(async (doc) => {
      const path = doc.data()?.[field];
      if (typeof path !== 'string' || path.length === 0) return;
      try {
        await bucket.file(path).delete({ ignoreNotFound: true });
        deleted += 1;
      } catch (err) {
        // Logged, never thrown: a stuck object must not strand the rest of an
        // erasure, and the row is reported so it can be swept by hand.
        logger.warn('subject erasure: storage delete failed', { path, err });
      }
    }),
  );
  return deleted;
}

/**
 * Applies every non-`keep` row of the inventory to `uid`.
 *
 * Returns a per-row report rather than a bare count, so the caller can log
 * what actually happened and a test can assert the whole traversal ran. With
 * `dryRun`, nothing is written and the report says what would have been.
 */
export async function eraseSubject(uid, { dryRun = false, profileScrub } = {}) {
  const report = [];

  for (const row of erasureRows()) {
    let docs;
    try {
      docs = await docsFor(row, uid);
    } catch (err) {
      // Surfaced, not swallowed. A row that cannot be read is a row that was
      // not erased, and the caller has to know which one.
      logger.error('subject erasure: lookup failed', { row: row.id, err });
      report.push({ row: row.id, error: String(err?.message ?? err) });
      continue;
    }

    if (docs.length === 0) {
      report.push({ row: row.id, matched: 0 });
      continue;
    }

    let storageDeleted = 0;
    if (row.storagePathField && !dryRun) {
      storageDeleted = await deleteStorageFor(docs, row.storagePathField);
    }

    if (!dryRun) {
      for (let i = 0; i < docs.length; i += BATCH_LIMIT) {
        const batch = db().batch();
        for (const doc of docs.slice(i, i + BATCH_LIMIT)) {
          if (row.disposition === DISPOSITION.delete) {
            batch.delete(doc.ref);
          } else {
            // The profile's scrub is passed in rather than declared in the
            // inventory: it is the one row whose replacement fields are shared
            // with the client model, so account.js owns its shape.
            batch.set(
              doc.ref,
              {
                ...(row.id === 'profile' ? profileScrub : row.scrubTo),
                updatedAt: FieldValue.serverTimestamp(),
              },
              { merge: true },
            );
          }
        }
        await batch.commit();
      }
    }

    report.push({
      row: row.id,
      matched: docs.length,
      disposition: row.disposition,
      ...(storageDeleted ? { storageDeleted } : {}),
    });
  }

  return report;
}

/**
 * Reads every exportable row of the inventory for `uid`.
 *
 * The shape is a plain object keyed by the inventory's `export` name, which is
 * what the client writes out as JSON. Document ids are included because an
 * export a person cannot correlate with what they see in the app is not much
 * of an answer to "what do you hold about me".
 *
 * A row that cannot be read is reported in `_problems` rather than thrown: a
 * partial export the person can see the gaps in beats a failed one that hands
 * them nothing.
 */
export async function exportSubject(uid) {
  const out = { _subject: uid, _generatedAt: new Date().toISOString() };
  const problems = [];

  for (const row of exportRows()) {
    try {
      const docs = await docsFor(row, uid);
      const payload = docs.map((d) => ({ id: d.id, path: d.ref.path, ...d.data() }));
      out[row.export] = row.lookup === LOOKUP.docId ? (payload[0] ?? null) : payload;
    } catch (err) {
      logger.warn('subject export: row failed', { row: row.id, err });
      problems.push({ row: row.id, error: String(err?.message ?? err) });
    }
  }

  if (problems.length > 0) out._problems = problems;
  return out;
}
