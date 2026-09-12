// Emulator-backed tests for the player-auction rules in firestore.rules.
//
// One property is worth more here than everything else combined: **a sealed
// bid must be unreadable by anybody except the team that placed it, until the
// reveal.** If that leaks, the feature is not merely buggy, it is a fraud —
// every other bidder can win every lot by one rupee and nobody can prove it
// happened.
//
// Rules cannot hide a FIELD from a reader entitled to the document, so secrecy
// is bought by putting each bid in its own document whose id is the bidder's
// uid. These tests go at that directly, from every angle somebody would
// actually try: another bidder, the organizer, a player in the pool, and a
// collection-group query that names no path at all.
//
// The second property is that no client may write a bid, a purse, or a sold
// lot, because each is two documents that must move together. The money
// arithmetic itself lives in functions/auctions.js and is not reachable from
// here — these tests prove only that the door is shut.
//
// Run with:  npm test        (from test/security/)

import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collectionGroup,
  doc,
  deleteDoc,
  getDoc,
  getDocs,
  query,
  setDoc,
  serverTimestamp,
  updateDoc,
  where,
} from 'firebase/firestore';

let testEnv;

const ORGANIZER = 'uid_organizer';
const BIDDER_A = 'uid_bidder_a';
const BIDDER_B = 'uid_bidder_b';
const PLAYER = 'uid_player';
const OUTSIDER = 'uid_outsider';

const AUCTION = 'auction_maram';
const UNLISTED = 'auction_secret';

const RULES_FILE = process.env.RULES_FILE ?? '../../firestore.rules';

const participant = (uid, roles, status = 'approved') => ({
  uid,
  auctionId: AUCTION,
  auctionName: 'Maram 2026 Dec Sports — Cricket',
  displayName: 'Test Person',
  photoUrl: null,
  playerCode: null,
  roles,
  status,
  createdAt: serverTimestamp(),
});

const team = (uid, purse = 10000000) => ({
  auctionId: AUCTION,
  ownerUid: uid,
  ownerName: 'Owner',
  ownerPhotoUrl: null,
  name: 'Test XI',
  pursePaise: purse,
  committedPaise: 0,
  spentPaise: 0,
  wonCount: 0,
  liveBidCount: 0,
  createdAt: serverTimestamp(),
  updatedAt: serverTimestamp(),
});

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'playsphere-auctions-test',
    firestore: {
      rules: readFileSync(RULES_FILE, 'utf8'),
      host: '127.0.0.1',
      port: Number(process.env.FIRESTORE_EMULATOR_PORT ?? 8080),
    },
  });
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();

    await setDoc(doc(db, 'auctions', AUCTION), {
      name: 'Maram 2026 Dec Sports — Cricket',
      sportId: 'cricket',
      sportName: 'Cricket',
      status: 'bidding',
      visibility: 'public',
      createdByUid: ORGANIZER,
      createdByName: 'Organizer',
      joinCode: 'PSA-4K7M2',
      defaultPursePaise: 10000000,
      defaultBasePricePaise: 100000,
      round: 1,
      maxSquadSize: 11,
      teamCount: 2,
      playerCount: 1,
      soldCount: 0,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });

    // An unlisted auction nobody in these tests belongs to — the control for
    // "a private auction must be invisible to a stranger who guesses its id".
    await setDoc(doc(db, 'auctions', UNLISTED), {
      name: 'Somebody else’s auction',
      sportId: 'cricket',
      sportName: 'Cricket',
      status: 'registration',
      visibility: 'unlisted',
      createdByUid: 'uid_somebody',
      joinCode: 'PSA-ZZZZZ',
      defaultPursePaise: 5000000,
      defaultBasePricePaise: 0,
      round: 1,
      createdAt: serverTimestamp(),
    });

    const p = (uid, roles, status) =>
      setDoc(
        doc(db, 'auctions', AUCTION, 'participants', uid),
        participant(uid, roles, status),
      );
    await p(ORGANIZER, ['organizer', 'bidder']);
    await p(BIDDER_A, ['bidder']);
    await p(BIDDER_B, ['bidder']);
    await p(PLAYER, ['player']);

    await setDoc(doc(db, 'auctions', AUCTION, 'teams', BIDDER_A), team(BIDDER_A));
    await setDoc(doc(db, 'auctions', AUCTION, 'teams', BIDDER_B), team(BIDDER_B));
    await setDoc(
      doc(db, 'auctions', AUCTION, 'teams', ORGANIZER),
      team(ORGANIZER),
    );

    await setDoc(doc(db, 'auctions', AUCTION, 'lots', PLAYER), {
      auctionId: AUCTION,
      playerUid: PLAYER,
      displayName: 'Test Player',
      photoUrl: null,
      status: 'pool',
      basePricePaise: 100000,
      bidCount: 1,
      matchesPlayed: 12,
      wins: 7,
      createdAt: serverTimestamp(),
    });

    // A's sealed bid. Written with rules disabled because no client may ever
    // write one — which is itself asserted below.
    await setDoc(
      doc(db, 'auctions', AUCTION, 'lots', PLAYER, 'bids', BIDDER_A),
      {
        teamId: BIDDER_A,
        lotId: PLAYER,
        auctionId: AUCTION,
        teamName: 'A XI',
        playerName: 'Test Player',
        amountPaise: 4000000,
        round: 1,
        isWinning: false,
        amountSetAt: serverTimestamp(),
        createdAt: serverTimestamp(),
      },
    );
  });
});

const as = (uid) => testEnv.authenticatedContext(uid).firestore();
const bidRef = (db, teamId) =>
  doc(db, 'auctions', AUCTION, 'lots', PLAYER, 'bids', teamId);

// ---------------------------------------------------------------------------

describe('sealed bids stay sealed while bidding is open', () => {
  it('lets the bidder read their own bid', async () => {
    await assertSucceeds(getDoc(bidRef(as(BIDDER_A), BIDDER_A)));
  });

  it('refuses a rival bidder', async () => {
    await assertFails(getDoc(bidRef(as(BIDDER_B), BIDDER_A)));
  });

  it('refuses the ORGANIZER', async () => {
    // Deliberate and load-bearing. The organizer very often owns a side, and
    // one who could read the sealed bids could hand a figure to a friend.
    await assertFails(getDoc(bidRef(as(ORGANIZER), BIDDER_A)));
  });

  it('refuses the player being bid on', async () => {
    await assertFails(getDoc(bidRef(as(PLAYER), BIDDER_A)));
  });

  it('refuses a stranger', async () => {
    await assertFails(getDoc(bidRef(as(OUTSIDER), BIDDER_A)));
  });

  it('refuses a collection-group query that names no path', async () => {
    // The angle a path-based secret is most likely to leak from: a group query
    // has no path for the rule to compare against, so it has to be the
    // document id that saves us.
    const db = as(BIDDER_B);
    await assertFails(
      getDocs(
        query(collectionGroup(db, 'bids'), where('auctionId', '==', AUCTION)),
      ),
    );
  });

  it('lets a bidder group-query their OWN bids', async () => {
    const db = as(BIDDER_A);
    await assertSucceeds(
      getDocs(
        query(
          collectionGroup(db, 'bids'),
          where('auctionId', '==', AUCTION),
          where('teamId', '==', BIDDER_A),
        ),
      ),
    );
  });
});

describe('every bid becomes public at the reveal', () => {
  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), 'auctions', AUCTION), {
        status: 'revealed',
      });
    });
  });

  it('lets a rival read a losing bid', async () => {
    // Transparency is the point: a result nobody can check by hand is one the
    // first person who feels cheated can destroy the league over.
    await assertSucceeds(getDoc(bidRef(as(BIDDER_B), BIDDER_A)));
  });

  it('lets the player read what was bid for them', async () => {
    await assertSucceeds(getDoc(bidRef(as(PLAYER), BIDDER_A)));
  });

  it('still refuses somebody outside the auction', async () => {
    await assertFails(getDoc(bidRef(as(OUTSIDER), BIDDER_A)));
  });
});

describe('no client may write a bid, ever', () => {
  const payload = {
    teamId: BIDDER_B,
    lotId: PLAYER,
    auctionId: AUCTION,
    teamName: 'B XI',
    amountPaise: 9900000,
    round: 1,
    isWinning: false,
    amountSetAt: serverTimestamp(),
    createdAt: serverTimestamp(),
  };

  it('refuses creating one as yourself', async () => {
    // The whole budget guarantee rests on this: a bid written without the
    // matching purse update is a purse committed twice.
    await assertFails(setDoc(bidRef(as(BIDDER_B), BIDDER_B), payload));
  });

  it('refuses editing your own existing bid', async () => {
    await assertFails(
      updateDoc(bidRef(as(BIDDER_A), BIDDER_A), { amountPaise: 1 }),
    );
  });

  it('refuses deleting your own bid', async () => {
    await assertFails(deleteDoc(bidRef(as(BIDDER_A), BIDDER_A)));
  });

  it('refuses the organizer writing one', async () => {
    await assertFails(setDoc(bidRef(as(ORGANIZER), ORGANIZER), payload));
  });
});

describe('purses and squad counts are not client-writable', () => {
  const teamRef = (db, id) => doc(db, 'auctions', AUCTION, 'teams', id);

  it('refuses an owner raising their own purse', async () => {
    await assertFails(
      updateDoc(teamRef(as(BIDDER_A), BIDDER_A), { pursePaise: 99999999 }),
    );
  });

  it('refuses an owner editing committedPaise', async () => {
    // A value that actually differs from the fixture's 0 — writing the same
    // value back is a no-op that `unchanged()` rightly permits, and testing
    // that proves nothing.
    await assertFails(
      updateDoc(teamRef(as(BIDDER_A), BIDDER_A), { committedPaise: 1 }),
    );
  });

  it('refuses the ORGANIZER editing committedPaise', async () => {
    // The branch a precedence bug left open: `&&` binds tighter than `||`, so
    // a trailing guard chain after `(organizer) || (owner)` protected only the
    // owner's branch. An organizer who can write committedPaise can zero their
    // own commitments and bid the same purse twice.
    await assertFails(
      updateDoc(teamRef(as(ORGANIZER), BIDDER_A), { committedPaise: 1 }),
    );
  });

  it('refuses the ORGANIZER editing spentPaise or wonCount', async () => {
    await assertFails(
      updateDoc(teamRef(as(ORGANIZER), BIDDER_A), { spentPaise: 1 }),
    );
    await assertFails(
      updateDoc(teamRef(as(ORGANIZER), BIDDER_A), { wonCount: 5 }),
    );
  });

  it('refuses an owner editing wonCount', async () => {
    await assertFails(
      updateDoc(teamRef(as(BIDDER_A), BIDDER_A), { wonCount: 11 }),
    );
  });

  it('lets an owner rename their own side', async () => {
    await assertSucceeds(
      updateDoc(teamRef(as(BIDDER_A), BIDDER_A), { name: 'Maram Warriors' }),
    );
  });

  it('refuses an owner renaming somebody else’s side', async () => {
    await assertFails(
      updateDoc(teamRef(as(BIDDER_A), BIDDER_B), { name: 'Hijacked XI' }),
    );
  });

  it('lets the organizer set a purse', async () => {
    await assertSucceeds(
      updateDoc(teamRef(as(ORGANIZER), BIDDER_A), { pursePaise: 20000000 }),
    );
  });

  it('refuses a purse below what is already committed', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(
        doc(ctx.firestore(), 'auctions', AUCTION, 'teams', BIDDER_A),
        { committedPaise: 4000000 },
      );
    });
    // Would put the side underwater on a bid it has already made.
    await assertFails(
      updateDoc(teamRef(as(ORGANIZER), BIDDER_A), { pursePaise: 1000000 }),
    );
  });
});

describe('lots', () => {
  const lotRef = (db) => doc(db, 'auctions', AUCTION, 'lots', PLAYER);

  it('refuses a bidder marking a lot sold to themselves', async () => {
    await assertFails(
      updateDoc(lotRef(as(BIDDER_A)), {
        status: 'sold',
        soldToTeamId: BIDDER_A,
        soldPricePaise: 100000,
      }),
    );
  });

  it('refuses the organizer forging a sale', async () => {
    // Not even the organizer. The reveal is the only thing that sells a lot.
    await assertFails(
      updateDoc(lotRef(as(ORGANIZER)), {
        status: 'sold',
        soldToTeamId: ORGANIZER,
        soldPricePaise: 100000,
      }),
    );
  });

  it('refuses anybody editing bidCount', async () => {
    // A count of documents the client cannot write. Editing it would let a
    // team hide its own interest in a player.
    await assertFails(updateDoc(lotRef(as(BIDDER_A)), { bidCount: 0 }));
  });

  it('refuses repricing once bidding has opened', async () => {
    // A floor raised under a sealed bid already placed would invalidate it
    // without telling the bidder.
    await assertFails(
      updateDoc(lotRef(as(ORGANIZER)), { basePricePaise: 9000000 }),
    );
  });

  it('lets the player withdraw themselves', async () => {
    await assertSucceeds(updateDoc(lotRef(as(PLAYER)), { status: 'withdrawn' }));
  });

  it('refuses a bidder withdrawing somebody else', async () => {
    await assertFails(updateDoc(lotRef(as(BIDDER_A)), { status: 'withdrawn' }));
  });
});

describe('the auction document', () => {
  const ref = (db) => doc(db, 'auctions', AUCTION);

  it('refuses a bidder driving the status', async () => {
    await assertFails(updateDoc(ref(as(BIDDER_A)), { status: 'revealed' }));
  });

  it('refuses the ORGANIZER driving the status directly', async () => {
    // Status moves through the callables, which carry the transactions each
    // transition needs. A client-set `revealed` would be a reveal with no
    // lots resolved and no money moved.
    await assertFails(updateDoc(ref(as(ORGANIZER)), { status: 'revealed' }));
  });

  it('refuses the organizer changing the join code', async () => {
    // It is on somebody's noticeboard by now, and the auctionCodes document
    // pointing here would be orphaned.
    await assertFails(updateDoc(ref(as(ORGANIZER)), { joinCode: 'PSA-11111' }));
  });

  it('refuses the organizer changing the sport', async () => {
    await assertFails(updateDoc(ref(as(ORGANIZER)), { sportId: 'kabaddi' }));
  });

  it('lets the organizer edit ordinary settings', async () => {
    await assertSucceeds(
      updateDoc(ref(as(ORGANIZER)), {
        name: 'Maram 2026 — Cricket',
        defaultPursePaise: 15000000,
      }),
    );
  });

  it('hides an unlisted auction from a stranger', async () => {
    await assertFails(getDoc(doc(as(OUTSIDER), 'auctions', UNLISTED)));
  });

  it('shows a public auction to any signed-in person', async () => {
    await assertSucceeds(getDoc(doc(as(OUTSIDER), 'auctions', AUCTION)));
  });
});

describe('joining', () => {
  const meRef = (db, uid) =>
    doc(db, 'auctions', AUCTION, 'participants', uid);

  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), 'auctions', AUCTION), {
        status: 'registration',
      });
    });
  });

  it('refuses self-approval', async () => {
    await assertFails(
      setDoc(meRef(as(OUTSIDER), OUTSIDER), {
        ...participant(OUTSIDER, ['player'], 'approved'),
        createdAt: serverTimestamp(),
      }),
    );
  });

  it('refuses granting yourself the organizer role', async () => {
    // Authority spreads sideways from somebody who has it, never out of
    // nothing — the same rule the club portfolios follow.
    await assertFails(
      setDoc(meRef(as(OUTSIDER), OUTSIDER), {
        ...participant(OUTSIDER, ['organizer'], 'pending'),
        createdAt: serverTimestamp(),
      }),
    );
  });

  it('allows an honest pending request', async () => {
    await assertSucceeds(
      setDoc(meRef(as(OUTSIDER), OUTSIDER), {
        ...participant(OUTSIDER, ['player', 'bidder'], 'pending'),
        createdAt: serverTimestamp(),
      }),
    );
  });

  it('refuses writing somebody else’s row', async () => {
    await assertFails(
      setDoc(meRef(as(OUTSIDER), BIDDER_A), {
        ...participant(BIDDER_A, ['player'], 'pending'),
        createdAt: serverTimestamp(),
      }),
    );
  });

  it('lets the organizer approve', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), 'auctions', AUCTION, 'participants', OUTSIDER),
        participant(OUTSIDER, ['player'], 'pending'),
      );
    });
    await assertSucceeds(
      updateDoc(meRef(as(ORGANIZER), OUTSIDER), { status: 'approved' }),
    );
  });

  it('refuses a bidder approving anybody', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), 'auctions', AUCTION, 'participants', OUTSIDER),
        participant(OUTSIDER, ['player'], 'pending'),
      );
    });
    await assertFails(
      updateDoc(meRef(as(BIDDER_A), OUTSIDER), { status: 'approved' }),
    );
  });

  it('finds my auctions by collection group', async () => {
    await assertSucceeds(
      getDocs(
        query(
          collectionGroup(as(BIDDER_A), 'participants'),
          where('uid', '==', BIDDER_A),
        ),
      ),
    );
  });

  it('refuses a collection-group query for somebody else’s memberships', async () => {
    await assertFails(
      getDocs(
        query(
          collectionGroup(as(BIDDER_A), 'participants'),
          where('uid', '==', BIDDER_B),
        ),
      ),
    );
  });
});

describe('the exchange window', () => {
  const tradesRef = (db, id) => doc(db, 'auctions', AUCTION, 'trades', id);

  const offer = {
    auctionId: AUCTION,
    fromTeamId: BIDDER_A,
    fromTeamName: 'A XI',
    toTeamId: BIDDER_B,
    toTeamName: 'B XI',
    fromLotIds: [PLAYER],
    toLotIds: [],
    fromLotNames: ['Test Player'],
    toLotNames: [],
    fromCashPaise: 0,
    toCashPaise: 0,
    status: 'proposed',
    teamIds: [BIDDER_A, BIDDER_B],
    createdAt: serverTimestamp(),
  };

  it('refuses a trade while bidding is still open', async () => {
    // Squads do not exist yet. A swap before the reveal is a swap of nothing.
    await assertFails(setDoc(tradesRef(as(BIDDER_A), 't1'), offer));
  });

  describe('once revealed', () => {
    beforeEach(async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await updateDoc(doc(ctx.firestore(), 'auctions', AUCTION), {
          status: 'revealed',
          exchangeClosesAt: new Date(Date.now() + 86400000),
        });
      });
    });

    it('lets a side propose one', async () => {
      await assertSucceeds(setDoc(tradesRef(as(BIDDER_A), 't1'), offer));
    });

    it('refuses proposing in somebody else’s name', async () => {
      await assertFails(
        setDoc(tradesRef(as(BIDDER_B), 't2'), offer),
      );
    });

    it('lets the other side accept', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), 'auctions', AUCTION, 'trades', 't3'),
          offer,
        );
      });
      await assertSucceeds(
        updateDoc(tradesRef(as(BIDDER_B), 't3'), { status: 'accepted' }),
      );
    });

    it('refuses the PROPOSER accepting their own offer', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), 'auctions', AUCTION, 'trades', 't4'),
          offer,
        );
      });
      await assertFails(
        updateDoc(tradesRef(as(BIDDER_A), 't4'), { status: 'accepted' }),
      );
    });

    it('refuses editing what is on offer after the fact', async () => {
      // An offer edited after acceptance is a different offer.
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), 'auctions', AUCTION, 'trades', 't5'),
          offer,
        );
      });
      await assertFails(
        updateDoc(tradesRef(as(BIDDER_B), 't5'), {
          status: 'accepted',
          fromCashPaise: 5000000,
        }),
      );
    });

    it('refuses a client marking a trade executed', async () => {
      // executedAt is the roster-moving transaction's to write.
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), 'auctions', AUCTION, 'trades', 't6'),
          offer,
        );
      });
      await assertFails(
        updateDoc(tradesRef(as(BIDDER_B), 't6'), {
          status: 'accepted',
          executedAt: serverTimestamp(),
        }),
      );
    });

    it('hides a trade from sides that are not party to it', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), 'auctions', AUCTION, 'trades', 't7'),
          offer,
        );
      });
      await assertFails(getDoc(tradesRef(as(PLAYER), 't7')));
    });
  });

  describe('once the window has closed', () => {
    beforeEach(async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await updateDoc(doc(ctx.firestore(), 'auctions', AUCTION), {
          status: 'revealed',
          exchangeClosesAt: new Date(Date.now() - 1000),
        });
      });
    });

    it('refuses a new offer after exchangeClosesAt', async () => {
      await assertFails(setDoc(tradesRef(as(BIDDER_A), 't8'), offer));
    });
  });

  describe('once squads are locked', () => {
    beforeEach(async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await updateDoc(doc(ctx.firestore(), 'auctions', AUCTION), {
          status: 'locked',
          exchangeClosesAt: new Date(Date.now() + 86400000),
        });
      });
    });

    it('refuses a new offer even inside the date window', async () => {
      // Two independent gates. An organizer whose event starts early is
      // protected by the button; one who forgets the button is protected by
      // the date.
      await assertFails(setDoc(tradesRef(as(BIDDER_A), 't9'), offer));
    });
  });
});
