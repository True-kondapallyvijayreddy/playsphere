import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_codec.dart';

enum TournamentStatus {
  draft('draft', 'Draft'),
  entriesOpen('entries_open', 'Entries open'),
  entriesClosed('entries_closed', 'Entries closed'),
  scheduled('scheduled', 'Scheduled'),
  inProgress('in_progress', 'In progress'),
  completed('completed', 'Completed'),
  cancelled('cancelled', 'Cancelled');

  const TournamentStatus(this.wire, this.label);

  final String wire;
  final String label;

  static TournamentStatus fromWire(String? w) =>
      TournamentStatus.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => TournamentStatus.draft,
      );

  bool get acceptsEntries => this == TournamentStatus.entriesOpen;

  /// Whether a draw opening for entries should carry the season out of this
  /// status.
  ///
  /// True for `draft` alone. A season with a draw taking entries is by
  /// definition not unpublished, so `draft` is provably wrong and worth
  /// correcting — a member arriving from the home screen's open-registrations
  /// row must not land on a board labelled **Draft** while its Register
  /// button works.
  ///
  /// Every other value is a decision somebody made: `entriesClosed` after a
  /// deadline, `scheduled` once the timetable is published, `inProgress`
  /// mid-week, `cancelled` deliberately. Re-opening one draw of a season
  /// already being played must not drag the whole season back to "Entries
  /// open", so nothing else yields.
  ///
  /// Lives here rather than in the repository that acts on it because it is a
  /// statement about what these states mean, and the repository half cannot
  /// be tested without a Firestore.
  bool get yieldsToAnOpenDraw => this == TournamentStatus.draft;
}

/// Whether a season charges once for everything, or separately per sport.
///
/// ## Why this is stored rather than inferred
///
/// Both shapes are real and neither is rare. A school sports week takes ₹100
/// at the gate and lets a child enter six events; a district open charges
/// ₹300 for badminton and ₹500 for cricket and expects an entrant to pay for
/// each draw they enter. Guessing between them from "is the tournament's
/// number zero" would be wrong in the ordinary case where a per-event season
/// happens to price every event the same — and worse, it would silently
/// change meaning the moment an organizer edited one number to zero.
///
/// It also decides what an EVENT page may say. Under [wholeSeason] an event
/// with no fee of its own is not free, it is already paid for, and a screen
/// that cannot tell those apart will tell an entrant the wrong thing.
///
/// Neither mode collects anything — see `FeeSettlement`. This chooses what
/// number is quoted, not who takes the money.
enum SeasonFeeMode {
  /// One fee covers every event in the season. The amount lives on
  /// [Tournament.entryFeeRupees]; the events carry nothing.
  wholeSeason('season', 'One fee for the whole season'),

  /// Each event is priced on its own, on `Competition.entryFeeRupees`. The
  /// tournament's own number is unused and stays zero.
  perEvent('event', 'A separate fee for each sport');

  const SeasonFeeMode(this.wire, this.label);

  final String wire;
  final String label;

  /// Defaults to [wholeSeason], which is what every tournament written
  /// before this field existed meant: its `entryFeeRupees` was the price of
  /// entering it, and none of its events carried one.
  static SeasonFeeMode fromWire(String? w) => SeasonFeeMode.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => SeasonFeeMode.wholeSeason,
      );
}

/// How much a tournament counts — the grade every federation uses to weight
/// what winning it is worth.
///
/// Nothing consumes this yet; it exists because ranking points are
/// grade × finishing round, and a tournament that did not record its grade at
/// the time cannot be scored retrospectively without an argument. Recording
/// it now costs one field and makes the ranking ledger possible later.
enum TournamentGrade {
  club('club', 'Club', 1),
  district('district', 'District', 3),
  state('state', 'State', 6),
  national('national', 'National', 10),
  international('international', 'International', 15);

  const TournamentGrade(this.wire, this.label, this.weight);

  final String wire;
  final String label;

  /// Relative worth of a title here. Deliberately a small integer scale
  /// rather than BWF's thousands: the numbers are arbitrary until a real
  /// ranking table calibrates them, and small ones make that recalibration
  /// obvious rather than hidden behind familiar-looking figures.
  final int weight;

  static TournamentGrade fromWire(String? w) =>
      TournamentGrade.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => TournamentGrade.club,
      );
}

/// A tournament, at `orgs/{orgId}/tournaments/{tournamentId}` — the container
/// that owns many [Competition] draws.
///
/// ## Why this has to exist
///
/// A `Competition` is *one draw*. A real tournament is not:
///
/// > Hyderabad District Badminton Championship
/// > ├── U-13 Boys Singles      (knockout, 32)
/// > ├── U-13 Girls Singles     (knockout, 16)
/// > ├── U-17 Boys Doubles      (groups → knockout, 24)
/// > ├── Senior Men's Singles   (groups → knockout, 38)
/// > └── … eleven more
///
/// Without this entity that structure could not be expressed at all, and the
/// absence was not cosmetic — **the hard problem only exists at this level**:
///
/// - One player enters singles, doubles and mixed. They must not be drawn onto
///   two courts at the same minute, and must get a rest gap between their own
///   matches **across different draws**. A per-competition scheduler cannot see
///   the conflict, because it can only see one draw.
/// - Fifteen events share six courts. Court allocation is one global problem,
///   not fifteen local ones that each believe they own the hall.
/// - "Finish the U-13 events before lunch so the children can go home" is a
///   per-event priority with nowhere else to live.
///
/// That cross-event contention — not the draw, not the scoring — is what makes
/// a tournament day that was planned to end at six end at eleven.
class Tournament {
  const Tournament({
    required this.id,
    required this.orgId,
    required this.name,
    required this.status,
    this.grade = TournamentGrade.club,
    this.description,
    this.bannerUrl,
    this.logoUrl,
    this.venueIds = const [],
    this.startDate,
    this.endDate,
    this.entryDeadline,
    this.eventCount = 0,
    this.contactPhone,
    this.entryFeeRupees = 0,
    this.feeMode = SeasonFeeMode.wholeSeason,
    this.matchMinutesDefault = 30,
    this.changeoverMinutes = 5,
    this.restGapMinutes = 20,
    this.venueTransitionMinutes = 0,
    this.isScheduleLocked = false,
    this.scheduleReleasedAt,
    this.isSuspended = false,
    this.suspendReason,
    this.suspendedAt,
    this.suspendedBy,
    this.createdBy,
    this.createdAt,
  });

  final String id;
  final String orgId;
  final String name;
  final TournamentStatus status;
  final TournamentGrade grade;
  final String? description;

  /// The artwork across the top of the season's page and its public link.
  ///
  /// Null is the normal state: `PsBanner` paints generated art from the
  /// season's own colour when this is absent, so a tournament created in a
  /// hurry still has a header worth sharing.
  final String? bannerUrl;

  /// The season's own mark — a school crest, a league badge, a sponsor's
  /// logo — shown on the banner, in the season list and on the public link.
  ///
  /// Separate from [bannerUrl] because they answer different questions and a
  /// club almost always has one before the other: the badge is the thing
  /// already sitting on somebody's phone, while a 1600px header photograph is
  /// something a season has to be given. Folding them into one field would
  /// mean an organizer with only a badge either stretches it across the header
  /// or uploads nothing.
  ///
  /// Null is the normal state: `PsBanner` simply draws no crest, rather than
  /// a placeholder box, so a season without one is not marked as incomplete.
  final String? logoUrl;

  /// Whether the timetable has been published to participants.
  ///
  /// `TournamentRepository.lockSchedule` wrote this field from the day it was
  /// added and nothing ever read it back, so the app could not tell a
  /// published season from a draft one: the "Lock & publish" button stayed
  /// live after publishing and a second press re-notified everybody, and no
  /// screen could say when the schedule had been released.
  ///
  /// It is the participant-facing half of `Fixture.isDraft` — that flag hides
  /// individual matches, this one records that the organizer has committed to
  /// the whole timetable. They move together, in the same batch.
  final bool isScheduleLocked;

  /// When it was published. Null until it is.
  ///
  /// Kept separate from [isScheduleLocked] rather than inferred from it being
  /// non-null, because a season locked before this field existed has the flag
  /// and no date, and "published, date unknown" is the truth there.
  final DateTime? scheduleReleasedAt;

  /// Whether the organizer has put this season on hold.
  ///
  /// ## Why this is a flag and not a status
  ///
  /// A suspension has to be undoable, and [status] is the one field that
  /// cannot survive being overwritten: a season paused halfway through is
  /// `in_progress`, one paused before the draw is `entries_open`, and a
  /// `suspended` status would have to guess which to restore on the way back.
  /// The guess is wrong exactly when it matters — a monsoon week in the
  /// middle of a league — and it would reopen entries on a field that had
  /// already closed.
  ///
  /// So this sits beside the lifecycle rather than inside it, the same shape
  /// as [isScheduleLocked]: suspending sets it, resuming clears it, and the
  /// status underneath is never touched by either. What it changes is what
  /// the app will let happen while it is set — no new entries, no new
  /// matches started — not what the season *is*.
  final bool isSuspended;

  /// Why it was paused, shown to everyone who entered.
  ///
  /// Required by `TournamentRepository.suspendTournament` for the same reason
  /// `Competition.cancelReason` is: a season that goes quiet without one is
  /// indistinguishable from the app being broken, and "Ground waterlogged —
  /// back on the 14th" is the difference between a phone call to the
  /// organizer and no phone call.
  final String? suspendReason;

  final DateTime? suspendedAt;
  final String? suspendedBy;

  /// The venues this tournament runs across. Ids into `orgs/{orgId}/venues`,
  /// not names — see [Venue] for why the difference matters.
  final List<String> venueIds;

  final DateTime? startDate;
  final DateTime? endDate;

  /// After this, entries close. Every federation publishes one, and a
  /// tournament without one cannot seed, because seeding needs a settled
  /// field.
  final DateTime? entryDeadline;

  /// How many competitions hang off this tournament. Denormalized so a list
  /// of tournaments does not need a subquery per row.
  final int eventCount;

  final String? contactPhone;
  final int entryFeeRupees;

  /// Whether [entryFeeRupees] is the price of the whole season, or whether
  /// each event carries its own — see [SeasonFeeMode].
  final SeasonFeeMode feeMode;

  /// True when one payment at the gate covers every event here.
  ///
  /// The guard on `entryFeeRupees` matters: a season set to [
  /// SeasonFeeMode.wholeSeason] with nothing entered is simply free, and an
  /// event inside it must read as free rather than as "already covered".
  bool get seasonFeeCoversEverything =>
      feeMode == SeasonFeeMode.wholeSeason && entryFeeRupees > 0;

  /// True when an entrant pays per draw they enter.
  bool get chargesPerEvent => feeMode == SeasonFeeMode.perEvent;

  /// Scheduling defaults inherited by every event that does not override
  /// them. A tournament-wide rest gap is the one that matters most: it is
  /// the promise that a player in three draws is not called straight from
  /// one court to the next, and it is meaningless unless it is set once for
  /// the whole tournament rather than per draw.
  final int matchMinutesDefault;
  final int changeoverMinutes;
  final int restGapMinutes;

  /// Extra time a person is owed, on top of their rest, when their next match
  /// is at a *different* venue.
  ///
  /// Zero for the ordinary club event, where everything is in one hall and
  /// there is nothing to travel. It matters the moment a season runs across
  /// town: someone finishing on the cricket ground at 17:00 with a 30-minute
  /// rest cannot be on a table-tennis table at 17:30 if the hall is twenty
  /// minutes away, and a timetable that says they can is a timetable that
  /// runs late from its first clash onward.
  final int venueTransitionMinutes;

  final String? createdBy;
  final DateTime? createdAt;

  int get slotMinutes => matchMinutesDefault + changeoverMinutes;

  /// Days the tournament runs over, inclusive. One when no end date is set.
  int get dayCount {
    final start = startDate;
    final end = endDate;
    if (start == null) return 1;
    if (end == null) return 1;
    final days = DateTime(end.year, end.month, end.day)
            .difference(DateTime(start.year, start.month, start.day))
            .inDays +
        1;
    return days < 1 ? 1 : days;
  }

  factory Tournament.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Tournament(
      id: doc.id,
      orgId: Fs.str(d['orgId']),
      name: Fs.str(d['name'], 'Tournament'),
      status: TournamentStatus.fromWire(Fs.strOrNull(d['status'])),
      grade: TournamentGrade.fromWire(Fs.strOrNull(d['grade'])),
      description: Fs.strOrNull(d['description']),
      bannerUrl: Fs.strOrNull(d['bannerUrl']),
      logoUrl: Fs.strOrNull(d['logoUrl']),
      venueIds: Fs.strList(d['venueIds']),
      startDate: Fs.dateOrNull(d['startDate']),
      endDate: Fs.dateOrNull(d['endDate']),
      entryDeadline: Fs.dateOrNull(d['entryDeadline']),
      eventCount: Fs.integer(d['eventCount']),
      contactPhone: Fs.strOrNull(d['contactPhone']),
      entryFeeRupees: Fs.integer(d['entryFeeRupees']),
      feeMode: SeasonFeeMode.fromWire(Fs.strOrNull(d['feeMode'])),
      matchMinutesDefault: Fs.integer(d['matchMinutesDefault'], 30),
      changeoverMinutes: Fs.integer(d['changeoverMinutes'], 5),
      restGapMinutes: Fs.integer(d['restGapMinutes'], 20),
      venueTransitionMinutes: Fs.integer(d['venueTransitionMinutes']),
      isScheduleLocked: Fs.boolean(d['isScheduleLocked']),
      scheduleReleasedAt: Fs.dateOrNull(d['scheduleReleasedAt']),
      isSuspended: Fs.boolean(d['isSuspended']),
      suspendReason: Fs.strOrNull(d['suspendReason']),
      suspendedAt: Fs.dateOrNull(d['suspendedAt']),
      suspendedBy: Fs.strOrNull(d['suspendedBy']),
      createdBy: Fs.strOrNull(d['createdBy']),
      createdAt: Fs.dateOrNull(d['createdAt']),
    );
  }

  Map<String, Object?> toCreate() => {
        'orgId': orgId,
        'name': name,
        'nameLower': name.toLowerCase(),
        'status': status.wire,
        'grade': grade.wire,
        'description': description,
        'bannerUrl': bannerUrl,
        'logoUrl': logoUrl,
        'venueIds': venueIds,
        'startDate': Fs.ts(startDate),
        'endDate': Fs.ts(endDate),
        'entryDeadline': Fs.ts(entryDeadline),
        'eventCount': 0,
        'contactPhone': contactPhone,
        'entryFeeRupees': entryFeeRupees,
        'feeMode': feeMode.wire,
        'matchMinutesDefault': matchMinutesDefault,
        'changeoverMinutes': changeoverMinutes,
        'restGapMinutes': restGapMinutes,
        'venueTransitionMinutes': venueTransitionMinutes,
        'createdBy': createdBy,
        'createdAt': FieldValue.serverTimestamp(),
      };

  Map<String, Object?> toUpdate() => {
        'name': name,
        'nameLower': name.toLowerCase(),
        'status': status.wire,
        'grade': grade.wire,
        'description': description,
        'venueIds': venueIds,
        'startDate': Fs.ts(startDate),
        'endDate': Fs.ts(endDate),
        'entryDeadline': Fs.ts(entryDeadline),
        'contactPhone': contactPhone,
        'entryFeeRupees': entryFeeRupees,
        'feeMode': feeMode.wire,
        'matchMinutesDefault': matchMinutesDefault,
        'changeoverMinutes': changeoverMinutes,
        'restGapMinutes': restGapMinutes,
        'venueTransitionMinutes': venueTransitionMinutes,
        'updatedAt': FieldValue.serverTimestamp(),
      };
  // `bannerUrl` and `logoUrl` are deliberately absent from `toUpdate` for the same reason
  // the suspension fields are: the edit sheet does not show it, so writing it
  // there would mean an organizer fixing a typo in the name silently erased
  // the artwork somebody else uploaded. `TournamentRepository.uploadSeasonBanner`
  // and `uploadSeasonLogo` own those two fields.
  //
  // The suspension fields are deliberately absent from both maps above.
  // `TournamentRepository.suspendTournament` and `resumeTournament` own them,
  // and an organizer opening the edit sheet to fix a typo in the name must not
  // quietly bring a paused season back to life.

  Tournament copyWith({
    String? name,
    TournamentStatus? status,
    TournamentGrade? grade,
    String? description,
    String? bannerUrl,
    String? logoUrl,
    List<String>? venueIds,
    DateTime? startDate,
    DateTime? endDate,
    DateTime? entryDeadline,
    int? eventCount,
    String? contactPhone,
    int? entryFeeRupees,
    SeasonFeeMode? feeMode,
    int? matchMinutesDefault,
    int? changeoverMinutes,
    int? restGapMinutes,
    int? venueTransitionMinutes,
    bool? isScheduleLocked,
    DateTime? scheduleReleasedAt,
    bool? isSuspended,
    String? suspendReason,
    DateTime? suspendedAt,
    String? suspendedBy,
  }) =>
      Tournament(
        id: id,
        orgId: orgId,
        name: name ?? this.name,
        status: status ?? this.status,
        grade: grade ?? this.grade,
        description: description ?? this.description,
        bannerUrl: bannerUrl ?? this.bannerUrl,
        logoUrl: logoUrl ?? this.logoUrl,
        venueIds: venueIds ?? this.venueIds,
        startDate: startDate ?? this.startDate,
        endDate: endDate ?? this.endDate,
        entryDeadline: entryDeadline ?? this.entryDeadline,
        eventCount: eventCount ?? this.eventCount,
        contactPhone: contactPhone ?? this.contactPhone,
        entryFeeRupees: entryFeeRupees ?? this.entryFeeRupees,
        feeMode: feeMode ?? this.feeMode,
        matchMinutesDefault: matchMinutesDefault ?? this.matchMinutesDefault,
        changeoverMinutes: changeoverMinutes ?? this.changeoverMinutes,
        restGapMinutes: restGapMinutes ?? this.restGapMinutes,
        venueTransitionMinutes:
            venueTransitionMinutes ?? this.venueTransitionMinutes,
        isScheduleLocked: isScheduleLocked ?? this.isScheduleLocked,
        scheduleReleasedAt: scheduleReleasedAt ?? this.scheduleReleasedAt,
        isSuspended: isSuspended ?? this.isSuspended,
        suspendReason: suspendReason ?? this.suspendReason,
        suspendedAt: suspendedAt ?? this.suspendedAt,
        suspendedBy: suspendedBy ?? this.suspendedBy,
        createdBy: createdBy,
        createdAt: createdAt,
      );
}
