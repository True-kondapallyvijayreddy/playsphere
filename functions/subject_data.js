/**
 * The inventory of everywhere one person's data lives.
 *
 * ## Why this is a list and not code
 *
 * `deleteMyAccount` scrubbed the profile, the devices, the directory listing
 * and the player code — four places, hand-written, and the review found nine
 * more it had never heard of: the coach, practitioner, shop and official
 * listings a person publishes about themselves, their ground check-ins (a
 * position and a time), their arena tally, their notification inbox, their
 * guardian-consent records, and the verification documents behind a ground
 * they claimed — which include an electricity bill with a home address and
 * which `firestore.rules` marks `allow delete: if false`, so once the auth
 * user was gone nobody could ever remove them.
 *
 * The failure was structural rather than careless: every new feature that
 * stores something about a person has to remember to edit a function in a file
 * it has no other reason to touch. So the answer is a declared inventory that
 * a test can walk, rather than a longer function. A new collection that holds
 * personal data adds one row here and is covered by both erasure and export at
 * once.
 *
 * ## The three dispositions
 *
 *   * `delete` — the document is the person's own and nothing else depends on
 *     it. A coach listing, a device token, a check-in.
 *   * `scrub` — the document is partly somebody else's record and the
 *     identifiers come out of it while the skeleton stays. A player code that
 *     must stay spent so it cannot be reissued; a donation trail the team
 *     needs to reconcile.
 *   * `keep` — deliberately retained, with the reason stated. Listed rather
 *     than omitted, because a row that says "kept, and here is why" is
 *     auditable and an absent row is just a gap.
 *
 * Everything here is data, so `subjectDataPlan()` below is a pure function and
 * `subject_data.test.mjs` can assert the shape of the whole inventory without
 * a database.
 */

/**
 * Where a subject's documents are found.
 *
 * `docId`  — the document id IS the uid. One read, one write.
 * `field`  — a query on a top-level collection for a field equal to the uid.
 * `group`  — the same, but as a collection-group query, for subcollections
 *            scattered under parents whose ids we do not know.
 * `sub`    — a subcollection of `users/{uid}`, swept wholesale.
 */
export const LOOKUP = {
  docId: 'docId',
  field: 'field',
  group: 'group',
  sub: 'sub',
};

export const DISPOSITION = {
  delete: 'delete',
  scrub: 'scrub',
  keep: 'keep',
};

/**
 * Every place PlaySphere stores something about one person.
 *
 * `export` names the key this appears under in a data export, or false when it
 * carries nothing the person does not already have. `storagePathField` marks a
 * row whose documents also point at bytes in Cloud Storage, which have to be
 * deleted alongside the document or the photo outlives the account.
 */
export const SUBJECT_DATA = [
  // --- The profile itself ------------------------------------------------
  {
    id: 'profile',
    collection: 'users',
    lookup: LOOKUP.docId,
    disposition: DISPOSITION.scrub,
    export: 'profile',
    // dateOfBirth is retained deliberately — see account.js. Age is what every
    // minor-safety gate reads, and a null makes those gates unanswerable for
    // the records this account still appears on.
    reason: 'Scrubbed in place: every scorecard this person appears on points here.',
  },
  {
    id: 'devices',
    collection: 'users',
    lookup: LOOKUP.sub,
    subcollection: 'devices',
    disposition: DISPOSITION.delete,
    export: false,
    reason: 'Push tokens. A deleted account must stop reaching a phone.',
  },
  {
    id: 'notifications',
    collection: 'users',
    lookup: LOOKUP.sub,
    subcollection: 'notifications',
    disposition: DISPOSITION.delete,
    export: false,
    reason: 'The durable half of a push. Nobody else reads it.',
  },
  {
    id: 'notificationDigest',
    collection: 'users',
    lookup: LOOKUP.sub,
    subcollection: 'notificationDigest',
    disposition: DISPOSITION.delete,
    export: false,
    reason: 'Pending-digest counters.',
  },
  {
    id: 'ratings',
    collection: 'users',
    lookup: LOOKUP.sub,
    subcollection: 'ratings',
    disposition: DISPOSITION.delete,
    export: 'ratings',
    reason: 'Per-sport Glicko. Exported, then removed with the account.',
  },
  {
    id: 'career_stats',
    collection: 'users',
    lookup: LOOKUP.sub,
    subcollection: 'career_stats',
    disposition: DISPOSITION.delete,
    export: 'careerStats',
    reason: 'Career rollups. The underlying fixtures stay as the event record.',
  },
  {
    id: 'guardianConsents',
    collection: 'users',
    lookup: LOOKUP.sub,
    subcollection: 'guardianConsents',
    disposition: DISPOSITION.delete,
    export: 'guardianConsents',
    reason: 'Consent records about this minor. Meaningless once the account is gone.',
  },

  // --- Things the person published about themselves ----------------------
  {
    id: 'playerDirectory',
    collection: 'playerDirectory',
    lookup: LOOKUP.docId,
    disposition: DISPOSITION.delete,
    export: false,
    reason: 'The one place the profile was deliberately searchable.',
  },
  {
    id: 'coachListing',
    collection: 'coaches',
    lookup: LOOKUP.docId,
    disposition: DISPOSITION.delete,
    export: 'coachListing',
    reason: 'A public invitation carrying a phone number.',
  },
  {
    id: 'medicListing',
    collection: 'sportsMedics',
    lookup: LOOKUP.docId,
    disposition: DISPOSITION.delete,
    export: 'medicListing',
    reason: 'A public practice listing carrying a phone number.',
  },
  {
    id: 'shopListing',
    collection: 'sportsShops',
    lookup: LOOKUP.docId,
    disposition: DISPOSITION.delete,
    export: 'shopListing',
    reason: 'A published business listing.',
  },
  {
    id: 'umpireProfile',
    collection: 'umpires',
    lookup: LOOKUP.docId,
    disposition: DISPOSITION.delete,
    export: 'umpireProfile',
    reason: 'A personal officiating listing carrying contact details.',
  },
  {
    id: 'umpireMatches',
    collection: 'umpires',
    lookup: LOOKUP.sub,
    subcollection: 'matches',
    disposition: DISPOSITION.delete,
    export: 'matchesOfficiated',
    reason: 'Which matches this official stood in. Derivable from the fixtures.',
  },
  {
    id: 'arenaStats',
    collection: 'arenaStats',
    lookup: LOOKUP.docId,
    disposition: DISPOSITION.delete,
    export: 'arenaStats',
    reason: 'The fun ladder. Nothing depends on a departed player\'s row.',
  },

  // --- Things that name the person by a field ----------------------------
  {
    id: 'playerCode',
    collection: 'playerCodes',
    lookup: LOOKUP.field,
    field: 'uid',
    disposition: DISPOSITION.scrub,
    scrubTo: { displayName: 'Deleted player', photoUrl: null },
    export: 'playerCode',
    reason: 'Scrubbed, not deleted: the code stays spent so it cannot be reissued.',
  },
  {
    id: 'checkIns',
    collection: 'checkIns',
    lookup: LOOKUP.group,
    field: 'uid',
    disposition: DISPOSITION.delete,
    export: 'groundCheckIns',
    reason: 'A position and a time. The most sensitive thing in the database.',
  },
  {
    id: 'memories',
    collection: 'memories',
    lookup: LOOKUP.group,
    field: 'uploaderUid',
    disposition: DISPOSITION.delete,
    storagePathField: 'storagePath',
    export: 'memoriesUploaded',
    reason: 'Photos this person uploaded, and the bytes behind them.',
  },
  {
    id: 'donations',
    collection: 'giveDonations',
    lookup: LOOKUP.field,
    field: 'donorUid',
    disposition: DISPOSITION.scrub,
    scrubTo: { donorName: 'Former donor', donorPhone: null, donorEmail: null },
    export: 'donations',
    reason: 'Scrubbed: the team still has to reconcile equipment already collected.',
  },
  {
    id: 'sponsorPledges',
    collection: 'sponsorPledges',
    lookup: LOOKUP.field,
    field: 'sponsorUid',
    disposition: DISPOSITION.scrub,
    scrubTo: { sponsorName: 'Former sponsor' },
    export: 'sponsorPledges',
    reason: 'Scrubbed: a listing owner is entitled to their own pledge history.',
  },
  {
    id: 'clubOrders',
    collection: 'clubOrders',
    lookup: LOOKUP.field,
    field: 'buyerUid',
    disposition: DISPOSITION.scrub,
    scrubTo: { buyerName: 'Former member' },
    export: 'clubOrders',
    reason: 'Scrubbed: a club\'s order book is its own record.',
  },
  {
    id: 'foodOrders',
    collection: 'foodOrders',
    lookup: LOOKUP.field,
    field: 'buyerUid',
    disposition: DISPOSITION.scrub,
    scrubTo: { buyerName: 'Former customer' },
    export: 'foodOrders',
    reason: 'Scrubbed: a ground\'s order book is its own record.',
  },
  {
    id: 'payments',
    collection: 'payments',
    lookup: LOOKUP.field,
    field: 'payerUid',
    disposition: DISPOSITION.keep,
    export: 'payments',
    reason:
      'Kept: a payment ledger is a financial record with its own statutory ' +
      'retention, and it carries no contact detail — a uid, an amount and a ' +
      'gateway reference.',
  },
  {
    id: 'groundVerification',
    collection: 'verification',
    lookup: LOOKUP.group,
    field: 'ownerUid',
    disposition: DISPOSITION.delete,
    export: false,
    reason:
      'An ownership declaration and a utility bill with a home address. ' +
      'Rules mark these undeletable by any client, which meant they outlived ' +
      'the account permanently.',
  },
  {
    id: 'groundReports',
    collection: 'groundReports',
    lookup: LOOKUP.field,
    field: 'reporterUid',
    disposition: DISPOSITION.keep,
    export: 'groundReports',
    reason:
      'Kept: a safety complaint that disappears when the reporter leaves is ' +
      'a complaint an owner can wait out. The report names a uid nobody can ' +
      'resolve to a person once the profile is scrubbed.',
  },
  {
    id: 'registrations',
    collection: 'registrations',
    lookup: LOOKUP.group,
    field: 'uid',
    disposition: DISPOSITION.keep,
    export: 'competitionEntries',
    reason:
      'Kept: an entry list is the event\'s record of who was in the draw, and ' +
      'removing one would unbalance a completed bracket.',
  },
];

/**
 * Everything the inventory says to do for `uid`, as plain data.
 *
 * Separated from the execution so the plan is assertable in a unit test and so
 * a dry run is the same code path as a real one.
 */
export function subjectDataPlan(uid) {
  if (typeof uid !== 'string' || uid.length === 0) {
    throw new TypeError('subjectDataPlan needs a uid');
  }
  return SUBJECT_DATA.map((row) => ({
    ...row,
    target:
      row.lookup === LOOKUP.docId
        ? `${row.collection}/${uid}`
        : row.lookup === LOOKUP.sub
          ? `${row.collection}/${uid}/${row.subcollection}`
          : `${row.lookup}:${row.collection}.${row.field} == ${uid}`,
  }));
}

/** The rows an erasure actually writes to. */
export function erasureRows() {
  return SUBJECT_DATA.filter((r) => r.disposition !== DISPOSITION.keep);
}

/** The rows an export reads from, and the key each lands under. */
export function exportRows() {
  return SUBJECT_DATA.filter((r) => r.export);
}
