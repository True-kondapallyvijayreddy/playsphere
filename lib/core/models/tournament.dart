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
    this.venueIds = const [],
    this.startDate,
    this.endDate,
    this.entryDeadline,
    this.eventCount = 0,
    this.contactPhone,
    this.entryFeeRupees = 0,
    this.matchMinutesDefault = 30,
    this.changeoverMinutes = 5,
    this.restGapMinutes = 20,
    this.isScheduleLocked = false,
    this.scheduleReleasedAt,
    this.createdBy,
    this.createdAt,
  });

  final String id;
  final String orgId;
  final String name;
  final TournamentStatus status;
  final TournamentGrade grade;
  final String? description;

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

  /// Scheduling defaults inherited by every event that does not override
  /// them. A tournament-wide rest gap is the one that matters most: it is
  /// the promise that a player in three draws is not called straight from
  /// one court to the next, and it is meaningless unless it is set once for
  /// the whole tournament rather than per draw.
  final int matchMinutesDefault;
  final int changeoverMinutes;
  final int restGapMinutes;

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
      venueIds: Fs.strList(d['venueIds']),
      startDate: Fs.dateOrNull(d['startDate']),
      endDate: Fs.dateOrNull(d['endDate']),
      entryDeadline: Fs.dateOrNull(d['entryDeadline']),
      eventCount: Fs.integer(d['eventCount']),
      contactPhone: Fs.strOrNull(d['contactPhone']),
      entryFeeRupees: Fs.integer(d['entryFeeRupees']),
      matchMinutesDefault: Fs.integer(d['matchMinutesDefault'], 30),
      changeoverMinutes: Fs.integer(d['changeoverMinutes'], 5),
      restGapMinutes: Fs.integer(d['restGapMinutes'], 20),
      isScheduleLocked: Fs.boolean(d['isScheduleLocked']),
      scheduleReleasedAt: Fs.dateOrNull(d['scheduleReleasedAt']),
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
        'venueIds': venueIds,
        'startDate': Fs.ts(startDate),
        'endDate': Fs.ts(endDate),
        'entryDeadline': Fs.ts(entryDeadline),
        'eventCount': 0,
        'contactPhone': contactPhone,
        'entryFeeRupees': entryFeeRupees,
        'matchMinutesDefault': matchMinutesDefault,
        'changeoverMinutes': changeoverMinutes,
        'restGapMinutes': restGapMinutes,
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
        'matchMinutesDefault': matchMinutesDefault,
        'changeoverMinutes': changeoverMinutes,
        'restGapMinutes': restGapMinutes,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  Tournament copyWith({
    String? name,
    TournamentStatus? status,
    TournamentGrade? grade,
    String? description,
    List<String>? venueIds,
    DateTime? startDate,
    DateTime? endDate,
    DateTime? entryDeadline,
    int? eventCount,
    String? contactPhone,
    int? entryFeeRupees,
    int? matchMinutesDefault,
    int? changeoverMinutes,
    int? restGapMinutes,
    bool? isScheduleLocked,
    DateTime? scheduleReleasedAt,
  }) =>
      Tournament(
        id: id,
        orgId: orgId,
        name: name ?? this.name,
        status: status ?? this.status,
        grade: grade ?? this.grade,
        description: description ?? this.description,
        venueIds: venueIds ?? this.venueIds,
        startDate: startDate ?? this.startDate,
        endDate: endDate ?? this.endDate,
        entryDeadline: entryDeadline ?? this.entryDeadline,
        eventCount: eventCount ?? this.eventCount,
        contactPhone: contactPhone ?? this.contactPhone,
        entryFeeRupees: entryFeeRupees ?? this.entryFeeRupees,
        matchMinutesDefault: matchMinutesDefault ?? this.matchMinutesDefault,
        changeoverMinutes: changeoverMinutes ?? this.changeoverMinutes,
        restGapMinutes: restGapMinutes ?? this.restGapMinutes,
        isScheduleLocked: isScheduleLocked ?? this.isScheduleLocked,
        scheduleReleasedAt: scheduleReleasedAt ?? this.scheduleReleasedAt,
        createdBy: createdBy,
        createdAt: createdAt,
      );
}
