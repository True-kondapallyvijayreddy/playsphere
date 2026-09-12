/// Everything that answers "is this ground real, and is this person entitled
/// to rent it out?"
///
/// ## The fraud this exists to make expensive
///
/// A ground listing is an advertisement carrying a phone number, published
/// free and instantly by anyone with an account. The scam that follows writes
/// itself: list a turf you do not own, wait for a club to book Sunday
/// evening, ring them, ask for a UPI advance "to hold the slot", stop
/// answering. PlaySphere never touches that money — see `FeeSettlement` — so
/// there is nothing to reverse and nobody to chase. The only defences
/// available are the ones that act *before* the phone call.
///
/// So the cost of publishing has to move from "a free Gmail account" to
/// "stand at the ground". Every proof in this file is a fact that is cheap to
/// produce if you are physically at a ground you control and awkward to
/// produce otherwise: a live GPS fix, photographs taken by the camera at that
/// fix rather than picked from a gallery, and a document with the claimant's
/// name on it. None of them is individually unforgeable. Together they turn a
/// two-minute fraud into an afternoon's work at a real location, which is the
/// realistic goal — not perfect proof of title, which no app can obtain.
///
/// ## Why the proofs are not on the ground document
///
/// `grounds/{id}` is world-readable, deliberately: a search has to work for
/// somebody who has not signed in. A proof carries the owner's precise
/// standing position, the timestamp they were there, and an electricity bill
/// with their name and address on it. Publishing those to satisfy a badge
/// would be a far worse leak than the fraud it prevents.
///
/// The public document therefore carries only the *conclusion* — see
/// [GroundVerificationStatus] and the counters on `Ground` — and the evidence
/// lives at `grounds/{id}/verification/{proofId}`, readable by the owner who
/// filed it and by an admin reviewing it, and by nobody else.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_codec.dart';

// ---------------------------------------------------------------------------
// Review status
// ---------------------------------------------------------------------------

/// Where a listing stands with PlaySphere.
///
/// ## Why this is a review axis and not a trust score
///
/// There are two independent questions about a ground: what PlaySphere
/// decided about it, and what players who actually turned up observed. They
/// disagree usefully — a listing can be waiting on review while eleven people
/// have already stood on it, and a reviewed-and-approved listing can start
/// collecting reports the day after. Folding both into one ladder would mean
/// a check-in silently overwriting a human's judgement, or a human's approval
/// erasing the fact that nobody has ever arrived.
///
/// So this enum answers only the first question. The second lives in
/// `Ground.checkInCount`, and [GroundTrust] combines them into the one thing
/// the UI actually needs: what to show the person deciding whether to book.
enum GroundVerificationStatus {
  /// Listed before on-site capture existed, and never re-submitted.
  ///
  /// Not the same as [rejected] and not a mark against the owner — these are
  /// the grounds that were already on the platform when the rules changed.
  /// They stay bookable, because retroactively unlisting honest owners to
  /// close a hole they did not open is a worse outcome than the hole. They
  /// carry the weakest badge and sort last, and their owners get asked to
  /// complete capture.
  unverified('unverified', 'Not verified'),

  /// Captured on site, waiting for a human to look at it.
  ///
  /// The default for anything listed through the capture flow. Bookable —
  /// see the note on [verified] for why the wait is not allowed to gate
  /// somebody's income.
  pending('pending', 'Awaiting review'),

  /// A human at PlaySphere looked at the proofs and accepted them.
  ///
  /// ## Why a pending ground is still bookable
  ///
  /// The alternative is that every genuine turf owner in a district waits on
  /// one person's inbox before earning a rupee, and a marketplace with no
  /// supply has no fraud problem because it has no users. The badge is the
  /// lever, not the gate: a booker sees plainly which listings have been
  /// checked and which have not, and can filter to only the checked ones.
  verified('verified', 'Verified'),

  /// A human looked and refused — the photos were of somewhere else, the
  /// document named someone else, the pin was in a lake.
  ///
  /// Unbookable and hidden from search. Kept rather than deleted so the same
  /// account cannot quietly re-list the same fiction and start the clock
  /// again with a clean record.
  rejected('rejected', 'Rejected'),

  /// Killed after reports, by the auto-suspend trigger or by an admin.
  ///
  /// Distinct from [rejected] because it says something different about the
  /// account: rejected means the evidence never held up, suspended means
  /// people who dealt with this listing came back and complained.
  suspended('suspended', 'Suspended');

  const GroundVerificationStatus(this.wire, this.label);

  final String wire;
  final String label;

  /// Whether a ground in this state may take new bookings.
  ///
  /// The one predicate that must not drift: it is mirrored in
  /// `firestore.rules` on the booking create, because a client that skips the
  /// UI must hit the same wall.
  bool get isBookable =>
      this != GroundVerificationStatus.rejected &&
      this != GroundVerificationStatus.suspended;

  /// Whether a ground in this state should appear in search at all.
  bool get isDiscoverable => isBookable;

  /// Whether this state is a human's conclusion rather than a waiting room.
  bool get isSettled =>
      this == GroundVerificationStatus.verified ||
      this == GroundVerificationStatus.rejected;

  static GroundVerificationStatus fromWire(String? w) =>
      GroundVerificationStatus.values.firstWhere(
        (e) => e.wire == w,
        // Legacy listings carry no field at all, and that is exactly what
        // `unverified` means.
        orElse: () => GroundVerificationStatus.unverified,
      );
}

// ---------------------------------------------------------------------------
// The badge a booker actually sees
// ---------------------------------------------------------------------------

/// What to tell somebody looking at a listing, from the review status and the
/// arrivals together.
///
/// Deliberately a small derived value rather than a stored field. Storing it
/// would mean two writers — the admin review and the check-in trigger — both
/// owning one field and racing to set it, and a badge that disagreed with the
/// status underneath it would be the worst possible bug in a trust feature.
enum GroundTrust {
  /// Reported or refused. The strongest thing the UI ever says.
  blocked('Not available', 'This listing has been taken down.'),

  /// No proof, no arrivals. A legacy listing nobody has been to yet.
  unproven(
    'Not verified',
    'Nobody has confirmed this ground yet. Never send money in advance.',
  ),

  /// Captured on site, but nobody has turned up yet to confirm it.
  captured(
    'Captured on site',
    'The owner listed this while standing at the ground. Not yet reviewed by '
        'PlaySphere.',
  ),

  /// Players have arrived and their phones agreed the ground is where the
  /// listing says it is.
  ///
  /// This is the badge that is genuinely hard to fake, and it costs
  /// PlaySphere nothing to produce: it is other people's evidence, not a
  /// claim by the owner and not a judgement by an admin.
  locationConfirmed(
    'Location confirmed',
    'Players have checked in at this ground on arrival.',
  ),

  /// A human at PlaySphere accepted the proofs.
  verified(
    'Verified',
    'PlaySphere has checked this ground’s photos and ownership details.',
  );

  const GroundTrust(this.label, this.blurb);

  final String label;
  final String blurb;

  /// How many independent arrivals it takes before a listing is treated as
  /// confirmed by the crowd.
  ///
  /// Three, and they have to be three different accounts — the check-in
  /// trigger enforces that, not this constant. One is a friend doing a
  /// favour; three separate clubs turning up at the same coordinates is a
  /// place that exists.
  static const confirmingCheckIns = 3;

  /// The badge for a listing, given what PlaySphere decided and how many
  /// distinct people have arrived there.
  ///
  /// Verified outranks confirmed: a human who looked at an electricity bill
  /// knows something the arrivals cannot establish, which is *who is entitled
  /// to take the money*. Arrivals only prove the ground is there.
  static GroundTrust of({
    required GroundVerificationStatus status,
    required int checkInCount,
  }) {
    if (!status.isBookable) return GroundTrust.blocked;
    if (status == GroundVerificationStatus.verified) return GroundTrust.verified;
    if (checkInCount >= confirmingCheckIns) return GroundTrust.locationConfirmed;
    if (status == GroundVerificationStatus.pending) return GroundTrust.captured;
    return GroundTrust.unproven;
  }
}

// ---------------------------------------------------------------------------
// Proof of presence
// ---------------------------------------------------------------------------

/// What a single captured photograph is meant to show.
///
/// Asked for by name rather than "upload two photos", because the two useful
/// pictures are useful for different reasons and a fraudster asked for
/// "photos" will supply two of the same stolen wide shot. The entrance and
/// the name board are the ones that are hard to source from the internet for
/// a specific claimed address, and the ones a reviewer can cross-check
/// against a map.
enum GroundProofKind {
  playingArea('playingArea', 'The playing area',
      'Stand at the edge and photograph the pitch or court itself.'),
  entrance('entrance', 'The entrance',
      'The gate or doorway people will arrive at, from outside.'),
  nameBoard('nameBoard', 'Name board or signage',
      'Any board, painted name or shutter marking that names this place. '
          'Skip only if there genuinely is none.'),
  ownershipDocument('ownershipDocument', 'Ownership document',
      'An electricity bill, tax receipt, lease or permission letter naming '
          'you or your organisation.');

  const GroundProofKind(this.wire, this.label, this.instruction);

  final String wire;
  final String label;
  final String instruction;

  /// Whether a submission is incomplete without one.
  ///
  /// The name board is optional because plenty of real village maidans and
  /// school grounds have no signage at all, and a mandatory field that
  /// honest owners cannot satisfy teaches them to photograph something
  /// irrelevant to get past it.
  bool get isRequired => this != GroundProofKind.nameBoard;

  /// Whether the file is evidence about a place (public-ish, a photo of a
  /// pitch) or about a person (an electricity bill with a home address).
  ///
  /// Decides which Storage path it goes to, and therefore who can read it.
  bool get isPrivateDocument => this == GroundProofKind.ownershipDocument;

  static GroundProofKind fromWire(String? w) => GroundProofKind.values
      .firstWhere((e) => e.wire == w, orElse: () => GroundProofKind.playingArea);
}

/// One photograph, and the fix the phone reported at the moment it was taken.
///
/// ## Why the fix is per-photo and not per-submission
///
/// A single location captured once at the start of the flow proves only that
/// the person opened the app somewhere. Stamping every photograph with its
/// own fix means the whole set has to have been taken at one place within one
/// short window — which is what actually distinguishes "I walked round my
/// turf photographing it" from "I stood in a car park and pasted in pictures
/// I found". The spread between the fixes is checked in `SitePresence`.
///
/// ## Why [isMocked] is recorded rather than only rejected
///
/// The client refuses a mocked fix outright, and it should. But a client is
/// the thing being defended against, so the flag is written to the record as
/// well: a submission that arrives at the server carrying `isMocked: true`
/// came from something that was not the shipped app, and that is a far more
/// interesting fact about the account than the listing itself.
class GroundProof {
  const GroundProof({
    required this.id,
    required this.kind,
    required this.imageUrl,
    required this.latitude,
    required this.longitude,
    required this.accuracyMetres,
    required this.capturedAt,
    required this.capturedByUid,
    this.isMocked = false,
    this.createdAt,
  });

  final String id;
  final GroundProofKind kind;
  final String imageUrl;

  /// Where the phone said it was when the shutter fired.
  final double latitude;
  final double longitude;

  /// The phone's own estimate of how wrong it might be, in metres. A fix with
  /// 800m of slop is not evidence of standing anywhere in particular, which
  /// is why `SitePresence` has a ceiling on it.
  final double accuracyMetres;

  /// Device clock at capture. Not trusted for anything security-relevant —
  /// [createdAt] is the server's word — but it is what orders the photos
  /// within a session and reveals a set assembled over three days.
  final DateTime capturedAt;

  final String capturedByUid;
  final bool isMocked;

  /// Server timestamp. The only clock in this record that cannot be edited by
  /// the phone that produced it.
  final DateTime? createdAt;

  factory GroundProof.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return GroundProof(
      id: doc.id,
      kind: GroundProofKind.fromWire(Fs.str(d['kind'])),
      imageUrl: Fs.str(d['imageUrl']),
      latitude: Fs.decimal(d['latitude']),
      longitude: Fs.decimal(d['longitude']),
      accuracyMetres: Fs.decimal(d['accuracyMetres']),
      capturedAt: Fs.date(d['capturedAt'], DateTime.now()),
      capturedByUid: Fs.str(d['capturedByUid']),
      isMocked: Fs.boolean(d['isMocked']),
      createdAt: Fs.dateOrNull(d['createdAt']),
    );
  }

  Map<String, Object?> toCreate() => {
        'kind': kind.wire,
        'imageUrl': imageUrl,
        'latitude': latitude,
        'longitude': longitude,
        'accuracyMetres': accuracyMetres,
        'capturedAt': Fs.ts(capturedAt),
        'capturedByUid': capturedByUid,
        'isMocked': isMocked,
        'createdAt': FieldValue.serverTimestamp(),
      };
}

// ---------------------------------------------------------------------------
// Ownership claim
// ---------------------------------------------------------------------------

/// On what basis this person says they may rent this place out.
///
/// ## Why the honest answer is offered
///
/// Most of the people listing a ground in a Telangana district are not the
/// registered owner of the land. They are the lessee running a turf, the
/// caretaker of a school field, or a panchayat secretary. A form that only
/// offers "I am the owner" makes every one of them either lie or leave, and a
/// declaration everybody lies on is worth nothing as evidence. Offering the
/// real relationships means the untrue answer is a specific, checkable claim
/// rather than a shrug.
enum GroundClaimType {
  owner('owner', 'I own this ground',
      'The land or the building is in your name or your family’s.'),
  lessee('lessee', 'I lease and run it',
      'You rent the ground from its owner and run it as a business.'),
  caretaker('caretaker', 'I manage it for the owner',
      'A school, college, club or trust ground you are responsible for.'),
  publicBody('publicBody', 'It is a public ground I am authorised for',
      'A panchayat, municipal or government ground you have permission to '
          'allot.');

  const GroundClaimType(this.wire, this.label, this.blurb);

  final String wire;
  final String label;
  final String blurb;

  static GroundClaimType fromWire(String? w) => GroundClaimType.values
      .firstWhere((e) => e.wire == w, orElse: () => GroundClaimType.owner);
}

/// What kind of paper was supplied to back the claim.
///
/// A closed list, so a reviewer can tell at a glance whether the document
/// type even matches the claim — a lessee producing a property tax receipt in
/// somebody else's name is the interesting case, and it is only visible if
/// the claim and the document are separate fields.
enum GroundDocumentKind {
  electricityBill('electricityBill', 'Electricity bill'),
  taxReceipt('taxReceipt', 'Property tax receipt'),
  leaseAgreement('leaseAgreement', 'Lease or rent agreement'),
  permissionLetter('permissionLetter', 'Permission / authorisation letter'),
  institutionLetter('institutionLetter', 'School or club letterhead'),
  other('other', 'Something else');

  const GroundDocumentKind(this.wire, this.label);

  final String wire;
  final String label;

  static GroundDocumentKind fromWire(String? w) => GroundDocumentKind.values
      .firstWhere((e) => e.wire == w, orElse: () => GroundDocumentKind.other);
}

/// The declaration a person signs when they list a ground, at
/// `grounds/{groundId}/verification/claim`.
///
/// A fixed document id rather than a generated one: there is exactly one
/// claim per ground and it is replaced, not appended to, when an owner
/// re-submits after a rejection.
class GroundOwnershipClaim {
  const GroundOwnershipClaim({
    required this.claimType,
    required this.holderName,
    required this.documentKind,
    required this.documentUrl,
    required this.declaredByUid,
    this.contactPhone,
    this.declaredAt,
  });

  final GroundClaimType claimType;

  /// The name as it appears on the document. Asked for separately from the
  /// account's display name, because "Vijay" on a Google account and
  /// "K. Vijay Reddy" on an electricity bill are the same person and a
  /// reviewer needs to be told that rather than left to guess.
  final String holderName;

  final GroundDocumentKind documentKind;

  /// Private in Storage, unlike the ground's advertising photo. See
  /// [GroundProofKind.isPrivateDocument].
  final String documentUrl;

  final String declaredByUid;

  /// The number the owner will actually answer, recorded with the claim as
  /// well as on the public listing.
  ///
  /// The listing's number can be edited freely afterwards; this one is part
  /// of a signed declaration and is what a report gets matched against. A
  /// listing that quietly swaps its phone number after being verified is a
  /// classic takeover, and without a fixed copy there is nothing to compare.
  final String? contactPhone;

  final DateTime? declaredAt;

  /// The sentence the owner is agreeing to. Kept here rather than in the
  /// widget for the same reason `FeeSettlement` is a constant: it is a legal
  /// statement, and it must not be quietly reworded screen by screen.
  static const undertaking =
      'I declare that the details above are true, that I am entitled to let '
      'this ground, and that I will not ask anyone to send money in advance '
      'to hold a booking. PlaySphere may suspend this listing and share these '
      'details with the authorities if this declaration is false.';

  factory GroundOwnershipClaim.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return GroundOwnershipClaim(
      claimType: GroundClaimType.fromWire(Fs.str(d['claimType'])),
      holderName: Fs.str(d['holderName']),
      documentKind: GroundDocumentKind.fromWire(Fs.str(d['documentKind'])),
      documentUrl: Fs.str(d['documentUrl']),
      declaredByUid: Fs.str(d['declaredByUid']),
      contactPhone: Fs.strOrNull(d['contactPhone']),
      declaredAt: Fs.dateOrNull(d['declaredAt']),
    );
  }

  Map<String, Object?> toCreate() => {
        'claimType': claimType.wire,
        'holderName': holderName,
        'documentKind': documentKind.wire,
        'documentUrl': documentUrl,
        'declaredByUid': declaredByUid,
        'contactPhone': contactPhone,
        'undertaking': undertaking,
        'declaredAt': FieldValue.serverTimestamp(),
      };
}

// ---------------------------------------------------------------------------
// Reports
// ---------------------------------------------------------------------------

/// Why somebody is reporting a listing.
///
/// ## Why the reasons are weighted
///
/// "The address is wrong" and "he asked me to send ₹2000 on UPI to hold the
/// slot" are not the same event, and a flat count treats them as one. The
/// weights are what let a single credible fraud report do more than three
/// pedantic ones, which matters because the auto-suspend threshold has to
/// fire fast on the scam and slowly on everything else.
///
/// The same weights are re-declared in `functions/grounds.js`, which is what
/// actually acts on them. Duplicating them is the lesser evil: the
/// alternative is the client telling the server how much its own report is
/// worth, which is the one thing a report system must never do.
enum GroundReportReason {
  /// The one this whole feature exists for.
  askedForAdvance(
    'askedForAdvance',
    'They asked me to pay in advance',
    'Someone from this listing asked for money before the booking — UPI, '
        'GPay, a deposit to hold the slot.',
    weight: 3,
    isFraud: true,
  ),

  doesNotExist(
    'doesNotExist',
    'There is no ground here',
    'You went to the location and there is no playable ground at it.',
    weight: 3,
    isFraud: true,
  ),

  notTheirGround(
    'notTheirGround',
    'They do not run this ground',
    'The ground is real, but the person who listed it has nothing to do '
        'with it.',
    weight: 3,
    isFraud: true,
  ),

  refusedBooking(
    'refusedBooking',
    'They would not honour the booking',
    'You had a confirmed slot and were turned away, or the ground was double '
        'let.',
    weight: 2,
    isFraud: false,
  ),

  unreachable(
    'unreachable',
    'Nobody answers',
    'The number on the listing does not work or is never answered.',
    weight: 1,
    isFraud: false,
  ),

  wrongDetails(
    'wrongDetails',
    'The details are wrong',
    'Wrong address, wrong rate, wrong sport, wrong opening hours.',
    weight: 1,
    isFraud: false,
  ),

  duplicate(
    'duplicate',
    'This is listed twice',
    'The same ground already appears on PlaySphere under another listing.',
    weight: 1,
    isFraud: false,
  );

  const GroundReportReason(
    this.wire,
    this.label,
    this.blurb, {
    required this.weight,
    required this.isFraud,
  });

  final String wire;
  final String label;
  final String blurb;

  /// What this report contributes to the suspension score.
  final int weight;

  /// Whether this alleges dishonesty rather than sloppiness. Drives the
  /// wording of the confirmation and how loudly an admin is told.
  final bool isFraud;

  static GroundReportReason fromWire(String? w) =>
      GroundReportReason.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => GroundReportReason.wrongDetails,
      );
}

/// One complaint about one listing, at `groundReports/{uid}_{groundId}`.
///
/// ## Why the document id is composite
///
/// One person gets one report per ground. A generated id would let a single
/// account file the same complaint forty times and suspend a competitor's
/// listing before lunch — and since the auto-suspend threshold is a score,
/// that is a denial-of-service on honest owners dressed up as safety. A
/// deterministic id makes the limit a property of the collection rather than
/// a rule somebody has to remember to write, and `firestore.rules` checks the
/// id matches the caller so it cannot be sidestepped.
class GroundReport {
  const GroundReport({
    required this.id,
    required this.groundId,
    required this.groundName,
    required this.groundOwnerUid,
    required this.reporterUid,
    required this.reporterName,
    required this.reason,
    this.note,
    this.bookingId,
    this.createdAt,
  });

  final String id;
  final String groundId;

  /// Denormalized so the admin queue reads as a list of complaints without
  /// one extra document read per row.
  final String groundName;

  /// The account being complained about. Carried on the report so a pattern
  /// across several of one person's listings is one query rather than a join.
  final String groundOwnerUid;

  final String reporterUid;
  final String reporterName;
  final GroundReportReason reason;
  final String? note;

  /// The booking this happened on, when there was one. A report from someone
  /// who actually held a slot is worth more than one from a passer-by, and
  /// this is what lets a reviewer tell them apart.
  final String? bookingId;

  final DateTime? createdAt;

  /// The id one person's report on one ground must have.
  static String idFor({required String reporterUid, required String groundId}) =>
      '${reporterUid}_$groundId';

  factory GroundReport.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return GroundReport(
      id: doc.id,
      groundId: Fs.str(d['groundId']),
      groundName: Fs.str(d['groundName'], 'Ground'),
      groundOwnerUid: Fs.str(d['groundOwnerUid']),
      reporterUid: Fs.str(d['reporterUid']),
      reporterName: Fs.str(d['reporterName'], 'Someone'),
      reason: GroundReportReason.fromWire(Fs.str(d['reason'])),
      note: Fs.strOrNull(d['note']),
      bookingId: Fs.strOrNull(d['bookingId']),
      createdAt: Fs.dateOrNull(d['createdAt']),
    );
  }

  Map<String, Object?> toCreate() => {
        'groundId': groundId,
        'groundName': groundName,
        'groundOwnerUid': groundOwnerUid,
        'reporterUid': reporterUid,
        'reporterName': reporterName,
        'reason': reason.wire,
        // Written by the client and re-derived by the trigger from the wire
        // value, never trusted as sent. Stored so the admin queue can sort
        // without re-deriving.
        'weight': reason.weight,
        'note': note,
        'bookingId': bookingId,
        'createdAt': FieldValue.serverTimestamp(),
      };
}

// ---------------------------------------------------------------------------
// Arrival check-in
// ---------------------------------------------------------------------------

/// Somebody who booked this ground standing on it, at
/// `grounds/{groundId}/checkIns/{bookingId}`.
///
/// ## Why this is the strongest signal available, and the cheapest
///
/// Every other proof in this file is produced by the person with the motive
/// to lie. This one is produced by the person with the motive to complain.
/// Three unrelated clubs whose phones all reported standing within a hundred
/// metres of the listing's pin is evidence no fraudster can manufacture
/// without recruiting three strangers to drive to a real ground.
///
/// It also produces the inverse, which is the part that matters most: a
/// listing accumulating bookings and no check-ins at all. That pattern —
/// slots being taken and nobody ever arriving — is what a phone-advance scam
/// looks like from the outside, and nothing else in the system can see it.
///
/// Keyed by booking id, so the same slot cannot be checked in twice.
class GroundCheckIn {
  const GroundCheckIn({
    required this.bookingId,
    required this.uid,
    required this.latitude,
    required this.longitude,
    required this.accuracyMetres,
    required this.distanceMetres,
    required this.capturedAt,
    this.isMocked = false,
    this.createdAt,
  });

  final String bookingId;
  final String uid;

  final double latitude;
  final double longitude;
  final double accuracyMetres;

  /// How far the arriving phone was from the listing's pin, computed on the
  /// client for the message it shows and recomputed by the trigger before it
  /// is allowed to count. The client's number is a courtesy; the server's is
  /// the one that moves `checkInCount`.
  final double distanceMetres;

  final DateTime capturedAt;
  final bool isMocked;
  final DateTime? createdAt;

  /// How far from the pin still counts as "at the ground".
  ///
  /// 250m, which is generous on purpose. A cricket ground is 150m across, the
  /// gate can be a walk from the pitch, and a phone under a stand loses a lot
  /// of accuracy. A tight radius would reject honest arrivals, and an honest
  /// arrival rejected is a person who never checks in again.
  static const confirmingRadiusMetres = 250.0;

  bool get isWithinRange => distanceMetres <= confirmingRadiusMetres;

  factory GroundCheckIn.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return GroundCheckIn(
      bookingId: doc.id,
      uid: Fs.str(d['uid']),
      latitude: Fs.decimal(d['latitude']),
      longitude: Fs.decimal(d['longitude']),
      accuracyMetres: Fs.decimal(d['accuracyMetres']),
      distanceMetres: Fs.decimal(d['distanceMetres']),
      capturedAt: Fs.date(d['capturedAt'], DateTime.now()),
      isMocked: Fs.boolean(d['isMocked']),
      createdAt: Fs.dateOrNull(d['createdAt']),
    );
  }

  Map<String, Object?> toCreate() => {
        'uid': uid,
        'latitude': latitude,
        'longitude': longitude,
        'accuracyMetres': accuracyMetres,
        'distanceMetres': distanceMetres,
        'capturedAt': Fs.ts(capturedAt),
        'isMocked': isMocked,
        'createdAt': FieldValue.serverTimestamp(),
      };
}

// ---------------------------------------------------------------------------
// Risk flags
// ---------------------------------------------------------------------------

/// What the server noticed about a listing when it arrived.
///
/// Written to the ground by the risk trigger, never by the client. These do
/// not block anything on their own — a flagged listing is still bookable —
/// they order the admin review queue, so the one person doing reviews spends
/// their attention on the listings most likely to be fake instead of working
/// through them in the order they arrived.
enum GroundRiskFlag {
  mockedLocation('mockedLocation', 'Location was mocked',
      'A capture reported a fake GPS fix. This did not come from the app '
          'behaving normally.'),
  pinFarFromCapture('pinFarFromCapture', 'Pin is far from where photos were taken',
      'The listed location and the place the photographs were taken are not '
          'the same place.'),
  capturesScattered('capturesScattered', 'Photos taken in different places',
      'The photographs in this submission were not all taken at one ground.'),
  duplicatePin('duplicatePin', 'Another owner already listed this spot',
      'A different account has a ground at almost exactly these coordinates.'),
  reusedPhone('reusedPhone', 'Phone number used on another owner’s listing',
      'This contact number already appears on a ground owned by someone '
          'else.'),
  newAccount('newAccount', 'Account is new',
      'The account listed this ground within days of being created.'),
  listingVelocity('listingVelocity', 'Several listings in a short time',
      'This account has published an unusual number of grounds recently.'),
  noPin('noPin', 'No location captured',
      'A legacy listing with no coordinates at all — it cannot be '
          'checked against arrivals.'),
  bookedNeverVisited('bookedNeverVisited', 'Bookings but no arrivals',
      'This ground has taken bookings and nobody has ever checked in at it.');

  const GroundRiskFlag(this.wire, this.label, this.blurb);

  final String wire;
  final String label;
  final String blurb;

  static GroundRiskFlag? fromWire(String? w) {
    for (final f in GroundRiskFlag.values) {
      if (f.wire == w) return f;
    }
    return null;
  }

  /// Turns the stored string array into flags, dropping anything a newer
  /// server version writes that this build does not know about.
  static List<GroundRiskFlag> listFrom(Object? v) =>
      Fs.strList(v).map(fromWire).whereType<GroundRiskFlag>().toList();
}
