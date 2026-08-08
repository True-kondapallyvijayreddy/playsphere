import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_user.dart';
import 'enums.dart';
import 'draw_config.dart';
import 'firestore_codec.dart';

/// Eligibility rule attached to a competition.
///
/// A competition is never just "Table Tennis" — in a school, college or
/// government meet it is always "Table Tennis, Boys, Under-17". Modelling the
/// category as a first-class value instead of leaving it inside the free-text
/// name is what allows the app to actually check whether an entrant may play,
/// to produce a correct medal tally, and to stop a 19-year-old being entered
/// into a U-17 draw.
class CompetitionCategory {
  const CompetitionCategory({
    required this.label,
    this.dimensions = const {CategoryDimension.openCategory},
    this.minAge,
    this.maxAge,
    this.ageCutOffDate,
    this.allowedGenders = const {},
    this.minWeightKg,
    this.maxWeightKg,
    this.grade,
  });

  /// Display name such as "U-17 Boys" or "Senior Women 57kg".
  final String label;

  final Set<CategoryDimension> dimensions;

  /// Inclusive age bounds evaluated on [ageCutOffDate].
  final int? minAge;
  final int? maxAge;

  /// The date age is measured on. Every federation fixes one for the season
  /// so that a birthday mid-tournament cannot change a player's category.
  /// When null, the competition start date is used.
  final DateTime? ageCutOffDate;

  /// Empty means open to all genders.
  final Set<Gender> allowedGenders;

  final double? minWeightKg;
  final double? maxWeightKg;

  /// Class/year for school and college meets, e.g. "Class 9" or "2nd Year".
  final String? grade;

  bool get isOpen =>
      dimensions.length == 1 &&
      dimensions.contains(CategoryDimension.openCategory);

  /// Decides whether [user] may enter, returning a human-readable reason when
  /// they may not. Returning the reason rather than a bare bool matters: an
  /// organizer rejecting an entry has to be able to tell the player why.
  CategoryEligibility check(AppUser user, {DateTime? competitionStart}) {
    if (dimensions.contains(CategoryDimension.age) &&
        (minAge != null || maxAge != null)) {
      final cutOff = ageCutOffDate ?? competitionStart ?? DateTime.now();
      final age = user.ageAt(cutOff);
      if (minAge != null && age < minAge!) {
        return CategoryEligibility.ineligible(
          'Must be at least $minAge on ${_fmt(cutOff)} — this player is $age.',
        );
      }
      if (maxAge != null && age > maxAge!) {
        return CategoryEligibility.ineligible(
          'Must be $maxAge or under on ${_fmt(cutOff)} — this player is $age.',
        );
      }
    }

    if (allowedGenders.isNotEmpty && !allowedGenders.contains(user.gender)) {
      final allowed = allowedGenders.map((g) => g.label).join(' / ');
      return CategoryEligibility.ineligible('Open to $allowed only.');
    }

    return const CategoryEligibility.eligible();
  }

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  factory CompetitionCategory.fromMap(Map<String, dynamic> d) {
    return CompetitionCategory(
      label: Fs.str(d['label'], 'Open'),
      dimensions: Fs.strList(d['dimensions'])
          .map(CategoryDimension.fromWire)
          .toSet(),
      minAge: d['minAge'] == null ? null : Fs.integer(d['minAge']),
      maxAge: d['maxAge'] == null ? null : Fs.integer(d['maxAge']),
      ageCutOffDate: Fs.dateOrNull(d['ageCutOffDate']),
      allowedGenders: Fs.strList(d['allowedGenders']).map(Gender.fromWire).toSet(),
      minWeightKg:
          d['minWeightKg'] == null ? null : Fs.decimal(d['minWeightKg']),
      maxWeightKg:
          d['maxWeightKg'] == null ? null : Fs.decimal(d['maxWeightKg']),
      grade: Fs.strOrNull(d['grade']),
    );
  }

  Map<String, Object?> toMap() => {
        'label': label,
        'dimensions': dimensions.map((d) => d.wire).toList(),
        'minAge': minAge,
        'maxAge': maxAge,
        'ageCutOffDate': Fs.ts(ageCutOffDate),
        'allowedGenders': allowedGenders.map((g) => g.wire).toList(),
        'minWeightKg': minWeightKg,
        'maxWeightKg': maxWeightKg,
        'grade': grade,
      };

  /// Presets covering the overwhelming majority of Indian school, college and
  /// district meets. Offering these means an organizer picks a category in
  /// one tap instead of hand-entering bounds and getting them wrong.
  static List<CompetitionCategory> presets({DateTime? cutOff}) {
    List<CompetitionCategory> ageBand(int max, String noun, Set<Gender> g, String gl) => [
          CompetitionCategory(
            label: 'U-$max $gl',
            dimensions: const {CategoryDimension.age, CategoryDimension.gender},
            maxAge: max,
            ageCutOffDate: cutOff,
            allowedGenders: g,
          ),
        ];

    return [
      const CompetitionCategory(label: 'Open'),
      for (final band in [11, 14, 17, 19])
        ...ageBand(band, 'Under', {Gender.male}, 'Boys'),
      for (final band in [11, 14, 17, 19])
        ...ageBand(band, 'Under', {Gender.female}, 'Girls'),
      CompetitionCategory(
        label: 'Senior Men',
        dimensions: const {CategoryDimension.age, CategoryDimension.gender},
        minAge: 19,
        ageCutOffDate: cutOff,
        allowedGenders: const {Gender.male},
      ),
      CompetitionCategory(
        label: 'Senior Women',
        dimensions: const {CategoryDimension.age, CategoryDimension.gender},
        minAge: 19,
        ageCutOffDate: cutOff,
        allowedGenders: const {Gender.female},
      ),
      const CompetitionCategory(
        label: 'Mixed',
        dimensions: {CategoryDimension.openCategory},
      ),
    ];
  }
}

class CategoryEligibility {
  const CategoryEligibility.eligible()
      : isEligible = true,
        reason = null;
  const CategoryEligibility.ineligible(this.reason) : isEligible = false;

  final bool isEligible;
  final String? reason;
}

/// A single contest inside an organization, at
/// `orgs/{orgId}/competitions/{compId}`.
class Competition {
  const Competition({
    required this.id,
    required this.orgId,
    required this.name,
    required this.sportId,
    required this.sportName,
    required this.archetype,
    required this.entrantType,
    required this.format,
    required this.status,
    required this.category,
    required this.scoringPluginKey,
    this.description,
    this.venue,
    this.startDate,
    this.endDate,
    this.registrationClosesAt,
    this.maxEntrants,
    this.entrantCount = 0,
    this.fixtureCount = 0,
    this.participationModel = ParticipationModel.approval,
    this.preselectedSlots = 0,
    this.waitlistEnabled = false,
    this.openToNonMembers = false,
    this.entryFeeRupees = 0,
    this.teamSize,
    this.rulesNote,
    this.confirmedCount = 0,
    this.waitlistCount = 0,
    this.verificationTier = VerificationTier.casual,
    this.rulesetVersion = 1,
    this.pointsForWin = 3,
    this.pointsForDraw = 1,
    this.pointsForLoss = 0,
    this.tiebreakChain,
    this.tournamentId,
    this.matchPointsModel = const MatchPointsModel(),
    this.drawConfig = const DrawConfig(),
    this.scheduleConfig = const ScheduleConfig(),
    this.scoringConfig = const {},
    this.cancelReason,
    this.cancelledAt,
    this.cancelledBy,
    this.participantOrgIds,
    this.createdBy,
    this.createdAt,
  });

  final String id;
  final String orgId;
  final String name;
  final String sportId;
  final String sportName;
  final CompetitionArchetype archetype;
  final EntrantType entrantType;
  final CompetitionFormat format;
  final CompetitionStatus status;
  final CompetitionCategory category;

  /// Which scoring rules apply. Resolved from the sport at creation time and
  /// then frozen, so enabling a better cricket plugin next season cannot
  /// retroactively change how last season's matches were scored.
  final String scoringPluginKey;

  final String? description;
  final String? venue;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime? registrationClosesAt;
  final int? maxEntrants;
  final int entrantCount;
  final int fixtureCount;
  final VerificationTier verificationTier;

  /// How this event fills. See [ParticipationModel] — it decides whether
  /// tapping Register puts you in the team or in a queue.
  final ParticipationModel participationModel;

  /// For [ParticipationModel.hybrid]: how many of [maxEntrants] the organizer
  /// reserves for their own picks. The rest are open to first-come
  /// registration. Zero for every other model.
  ///
  /// Example from the flow: a 13-a-side cricket match where the captain names
  /// 8 regulars is `maxEntrants: 13, preselectedSlots: 8` — five slots stay
  /// open and the sixth person to tap Register is waitlisted.
  final int preselectedSlots;

  /// Whether someone arriving after the field is full is queued rather than
  /// turned away. Grassroots events lose two players to work or traffic on
  /// the morning; a waitlist is the difference between playing and cancelling.
  final bool waitlistEnabled;

  /// Whether people who are not members of the hosting club may register.
  /// False is "restricted" — an internal club event. True is the open,
  /// discoverable event the spec calls for.
  final bool openToNonMembers;

  /// Entry fee in whole rupees. Zero means free, which is the default and the
  /// overwhelmingly common case: the spec makes scoring and club management
  /// free forever, so a fee here is the organizer's ground/ball cost, not
  /// ours.
  final int entryFeeRupees;

  /// Players per side, where the sport has a fixed one. Null means "whatever
  /// turns up", which is how most pickup games actually work.
  final int? teamSize;

  /// Free-text rules and guidelines the organizer wants entrants to read
  /// before they register — "leather ball", "spikes not allowed", "report by
  /// 6am".
  final String? rulesNote;

  /// Live tallies maintained transactionally alongside the registrations they
  /// count.
  ///
  /// A count that could be derived by reading every registration is
  /// duplicated here for one reason: `firestore.rules` cannot count documents.
  /// Capacity is only enforceable server-side if the number being checked
  /// lives in a document the rules can read, which is what makes
  /// "the first thirteen get in" a guarantee rather than a client-side
  /// suggestion. See `CompetitionRepository.register`.
  final int confirmedCount;
  final int waitlistCount;

  /// Bumped whenever the organizer changes scoring configuration. Fixtures
  /// record the version they were played under so a mid-season rule change
  /// never rewrites a finished result.
  final int rulesetVersion;

  final int pointsForWin;
  final int pointsForDraw;
  final int pointsForLoss;

  /// How this league separates teams level on points, as a list of
  /// [Tiebreak] wire names. Null means "use the sport's default chain" —
  /// cricket goes to net run rate, football to goal difference, a Swiss
  /// chess field to Buchholz.
  final List<String>? tiebreakChain;

  /// The tournament this draw belongs to, when it belongs to one.
  ///
  /// Null for a standalone event — a club's Sunday league or a one-off
  /// challenge, which are the common case and must not be forced to invent a
  /// tournament around themselves. Set, it is what lets the scheduler see
  /// that this draw shares courts and players with fourteen others.
  final String? tournamentId;

  /// How match points are awarded when the margin matters — volleyball's
  /// 3-0/3-1 versus 3-2 split, a losing bonus point. Disabled by default, so
  /// an existing league keeps exactly the points it has been awarding.
  final MatchPointsModel matchPointsModel;

  /// How the draw is shaped — group count, qualifiers per group, second leg,
  /// bracket reset, shuffle seed. See [DrawConfig] for why these are stored
  /// rather than defaulted at generation time.
  final DrawConfig drawConfig;

  /// Courts, match length and rest gaps — everything the scheduler needs to
  /// turn a set of fixtures into a timetable instead of a single start time.
  final ScheduleConfig scheduleConfig;

  /// This event's overrides on top of its sport's rule preset — the organizer
  /// answer to "we play 8 overs, not 20".
  ///
  /// Empty for every event that just takes the sport's defaults, which is most
  /// of them. When set, [effectiveScoringConfig] layers it over
  /// `SportSpec.config` and that is what gets frozen onto each new fixture.
  ///
  /// Stored here rather than reached for at scoring time on purpose. §12.2
  /// says every sport parameter travels through config, and §3 says a fixture
  /// freezes the rules it was played under: an organizer shortening the format
  /// mid-event must change the matches still to come and must NOT retroactively
  /// rewrite the ones already played. Keeping the override on the competition
  /// and copying it at fixture-creation time is what gives both of those at
  /// once.
  final Map<String, dynamic> scoringConfig;

  /// The rules a new fixture of this competition should be created with.
  ///
  /// [sportConfig] is the sport's own resolved preset — `SportSpec.config`.
  /// Anything the organizer overrode wins over it; everything else falls
  /// through untouched, so an override of `oversPerInnings` does not silently
  /// drop the wide/no-ball values sitting beside it.
  Map<String, dynamic> effectiveScoringConfig(
    Map<String, dynamic> sportConfig,
  ) =>
      scoringConfig.isEmpty
          ? sportConfig
          : {...sportConfig, ...scoringConfig};

  /// Returns this competition with the organizer's rule edits applied.
  ///
  /// The other half of [withDrawSetup], and separate from it because the two
  /// answer different questions: that one shapes the bracket, this one changes
  /// how a match inside it is played. Both are narrow for the same reason —
  /// see [withDrawSetup].
  Competition withRules({
    Map<String, dynamic>? scoringConfig,
    ScheduleConfig? scheduleConfig,
  }) =>
      withDrawSetup(
        scheduleConfig: scheduleConfig,
        scoringConfig: scoringConfig,
      );

  /// Returns this competition with the organizer's draw setup applied.
  ///
  /// Deliberately narrow rather than a general `copyWith`: these are the only
  /// fields a screen changes between reading a competition and handing it
  /// straight back to `generateDraw`, and a full copy-with over thirty-odd
  /// fields is thirty-odd chances to drop one silently.
  Competition withDrawSetup({
    DrawConfig? drawConfig,
    ScheduleConfig? scheduleConfig,
    Map<String, dynamic>? scoringConfig,
  }) =>
      Competition(
        id: id,
        orgId: orgId,
        name: name,
        sportId: sportId,
        sportName: sportName,
        archetype: archetype,
        entrantType: entrantType,
        format: format,
        status: status,
        category: category,
        scoringPluginKey: scoringPluginKey,
        description: description,
        venue: venue,
        startDate: startDate,
        endDate: endDate,
        registrationClosesAt: registrationClosesAt,
        maxEntrants: maxEntrants,
        entrantCount: entrantCount,
        fixtureCount: fixtureCount,
        participationModel: participationModel,
        preselectedSlots: preselectedSlots,
        waitlistEnabled: waitlistEnabled,
        openToNonMembers: openToNonMembers,
        entryFeeRupees: entryFeeRupees,
        teamSize: teamSize,
        rulesNote: rulesNote,
        confirmedCount: confirmedCount,
        waitlistCount: waitlistCount,
        verificationTier: verificationTier,
        rulesetVersion: rulesetVersion,
        pointsForWin: pointsForWin,
        pointsForDraw: pointsForDraw,
        pointsForLoss: pointsForLoss,
        tiebreakChain: tiebreakChain,
        tournamentId: tournamentId,
        matchPointsModel: matchPointsModel,
        drawConfig: drawConfig ?? this.drawConfig,
        scheduleConfig: scheduleConfig ?? this.scheduleConfig,
        scoringConfig: scoringConfig ?? this.scoringConfig,
        cancelReason: cancelReason,
        cancelledAt: cancelledAt,
        cancelledBy: cancelledBy,
        participantOrgIds: participantOrgIds,
        createdBy: createdBy,
        createdAt: createdAt,
      );

  /// Why this event was called off, in the organizer's own words.
  ///
  /// ## Why a reason is mandatory rather than encouraged
  ///
  /// An event that vanishes is indistinguishable from a bug. Somebody who
  /// booked a Saturday, arranged a lift and told their family they were
  /// playing opens the app to find nothing there, and the only available
  /// conclusion is that the app lost it. A cancelled event with "Ground
  /// waterlogged — rescheduling for the 14th" against it is a different
  /// experience entirely, and it is the same one line of text.
  ///
  /// It is also what makes the notification worth sending: "Sunday Cricket was
  /// cancelled" prompts a WhatsApp message to the organizer asking why, which
  /// is the work the notification was supposed to save.
  ///
  /// Null for every event that has not been cancelled.
  /// `CompetitionRepository.cancelCompetition` refuses to write one without it.
  final String? cancelReason;

  final DateTime? cancelledAt;
  final String? cancelledBy;

  bool get isCancelled => status == CompetitionStatus.cancelled;

  /// The organizations taking part, when this competition spans more than the
  /// one that owns it — a school-vs-school or village-vs-village challenge.
  ///
  /// ## Why the document is not enough on its own
  ///
  /// Competitions live at `orgs/{orgId}/competitions/{compId}`, which encodes
  /// exactly one owner. An inter-club match has two, and the club that did not
  /// happen to host it still has to read the fixture, watch it live and see its
  /// own result. This field is what the security rules consult to grant that
  /// second club access, so it is the authorization record for the match, not a
  /// convenience copy.
  ///
  /// Null for ordinary internal competitions. When present it always contains
  /// exactly two org ids, one of which is [orgId] — `firestore.rules` enforces
  /// both, because the read rule checks the entries by index and a longer list
  /// would silently grant nobody the access they were promised.
  final List<String>? participantOrgIds;

  final String? createdBy;
  final DateTime? createdAt;

  /// The date this event should be ordered by: when it happens, not when
  /// somebody typed it in.
  ///
  /// Sorting a club's events by [createdAt] puts a tournament entered late for
  /// last month above one starting tomorrow, which is how a list of events
  /// stops being a list anybody can read down. The fallbacks matter as much as
  /// the first choice: a draft with no dates yet still has to land somewhere
  /// stable rather than jumping around as other events are added.
  DateTime get sortDate =>
      startDate ?? registrationClosesAt ?? createdAt ?? DateTime(2000);

  /// True when this competition exists because a challenge was accepted, and
  /// therefore answers to two clubs rather than one.
  bool get isInterClub =>
      participantOrgIds != null && participantOrgIds!.length == 2;

  /// The other club in an inter-club match, from [orgId]'s point of view.
  String? opponentOf(String someOrgId) {
    final ids = participantOrgIds;
    if (ids == null) return null;
    for (final id in ids) {
      if (id != someOrgId) return id;
    }
    return null;
  }

  bool get isFull => maxEntrants != null && entrantCount >= maxEntrants!;

  /// How many places are open to first-come registration.
  ///
  /// For a hybrid event this is capacity minus the slots the organizer has
  /// reserved for their own picks — the "remaining 5" of the flow's 8 + 5.
  /// Null when the event has no capacity at all, which means unlimited.
  int? get openSlots {
    final cap = maxEntrants;
    if (cap == null) return null;
    if (participationModel != ParticipationModel.hybrid) return cap;
    final open = cap - preselectedSlots;
    return open < 0 ? 0 : open;
  }

  /// Places still available to someone registering right now.
  ///
  /// Counts against [openSlots] rather than [maxEntrants], so an organizer's
  /// reserved picks cannot be taken by whoever refreshes fastest.
  int? get slotsRemaining {
    final open = openSlots;
    if (open == null) return null;
    final left = open - confirmedCount;
    return left < 0 ? 0 : left;
  }

  /// True when the open portion of the field is taken.
  bool get openSlotsFull {
    final left = slotsRemaining;
    return left != null && left == 0;
  }

  /// Whether the registration deadline has passed at [now].
  ///
  /// False when no deadline was set — an event with no cut-off closes when
  /// the organizer says so, not on its own.
  bool registrationDeadlinePassed([DateTime? now]) {
    final closes = registrationClosesAt;
    if (closes == null) return false;
    return (now ?? DateTime.now()).isAfter(closes);
  }

  /// The status to SHOW, as distinct from the one stored in Firestore.
  ///
  /// A competition's `status` field only changes when somebody writes it, and
  /// nothing writes it when a registration deadline passes — there is no
  /// server tier running a scheduled job over every event. So an event whose
  /// entries closed on Friday still advertised "Registration Open" the
  /// following week, and players kept tapping a Register button that
  /// [registrationIsOpen] had already, correctly, disabled. The label and the
  /// button disagreed, which reads as a broken app rather than a closed event.
  ///
  /// Deriving it on read fixes that for every event at once, including the
  /// ones already sitting in the database, and needs no migration and no
  /// scheduled function.
  ///
  /// Only ever moves `registrationOpen` → `registrationClosed`. A deadline
  /// says nothing about an event that is already running, finished or
  /// cancelled, and inferring anything further would overwrite a real
  /// decision an organizer made.
  CompetitionStatus displayStatus([DateTime? now]) {
    if (status != CompetitionStatus.registrationOpen) return status;
    return registrationDeadlinePassed(now)
        ? CompetitionStatus.registrationClosed
        : status;
  }

  bool get registrationIsOpen {
    if (!status.acceptsRegistrations) return false;
    // A full field is no longer open — unless there is a waitlist, in which
    // case joining the queue is a legitimate thing to be able to do.
    if (openSlotsFull && !waitlistEnabled) return false;
    if (isFull && !waitlistEnabled) return false;
    final closes = registrationClosesAt;
    if (closes != null && DateTime.now().isAfter(closes)) return false;
    return true;
  }

  /// What tapping Register right now would actually produce.
  ///
  /// Kept on the model rather than inside the repository so the button can
  /// say the true thing before it is pressed — "Register" versus "Join
  /// waitlist" versus "Apply" — instead of the user finding out afterwards.
  /// The repository re-decides this inside a transaction against fresh
  /// counts; this is the honest prediction, not the authority.
  RegistrationStatus get outcomeOfRegisteringNow {
    if (!participationModel.autoConfirms) return RegistrationStatus.pending;
    if (openSlotsFull) return RegistrationStatus.waitlisted;
    return RegistrationStatus.confirmed;
  }

  bool get isFree => entryFeeRupees <= 0;

  factory Competition.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Competition(
      id: doc.id,
      orgId: Fs.str(d['orgId']),
      name: Fs.str(d['name'], 'Untitled competition'),
      sportId: Fs.str(d['sportId']),
      sportName: Fs.str(d['sportName']),
      archetype: CompetitionArchetype.fromWire(Fs.str(d['archetype'])),
      entrantType: EntrantType.fromWire(Fs.str(d['entrantType'])),
      format: CompetitionFormat.fromWire(Fs.str(d['format'])),
      status: CompetitionStatus.fromWire(Fs.str(d['status'])),
      category: CompetitionCategory.fromMap(Fs.map(d['category'])),
      scoringPluginKey: Fs.str(d['scoringPluginKey'], 'simple_points'),
      description: Fs.strOrNull(d['description']),
      venue: Fs.strOrNull(d['venue']),
      startDate: Fs.dateOrNull(d['startDate']),
      endDate: Fs.dateOrNull(d['endDate']),
      registrationClosesAt: Fs.dateOrNull(d['registrationClosesAt']),
      maxEntrants: d['maxEntrants'] == null ? null : Fs.integer(d['maxEntrants']),
      entrantCount: Fs.integer(d['entrantCount']),
      fixtureCount: Fs.integer(d['fixtureCount']),
      participationModel:
          ParticipationModel.fromWire(Fs.strOrNull(d['participationModel'])),
      preselectedSlots: Fs.integer(d['preselectedSlots']),
      waitlistEnabled: Fs.boolean(d['waitlistEnabled']),
      openToNonMembers: Fs.boolean(d['openToNonMembers']),
      entryFeeRupees: Fs.integer(d['entryFeeRupees']),
      teamSize: d['teamSize'] == null ? null : Fs.integer(d['teamSize']),
      rulesNote: Fs.strOrNull(d['rulesNote']),
      confirmedCount: Fs.integer(d['confirmedCount']),
      waitlistCount: Fs.integer(d['waitlistCount']),
      verificationTier: VerificationTier.fromWire(Fs.str(d['verificationTier'])),
      rulesetVersion: Fs.integer(d['rulesetVersion'], 1),
      pointsForWin: Fs.integer(d['pointsForWin'], 3),
      pointsForDraw: Fs.integer(d['pointsForDraw'], 1),
      pointsForLoss: Fs.integer(d['pointsForLoss']),
      tiebreakChain:
          d['tiebreakChain'] is List ? Fs.strList(d['tiebreakChain']) : null,
      tournamentId: Fs.strOrNull(d['tournamentId']),
      matchPointsModel: MatchPointsModel.fromMap(
        d['matchPointsModel'] is Map
            ? Map<String, dynamic>.from(d['matchPointsModel'] as Map)
            : null,
      ),
      drawConfig: DrawConfig.fromMap(
        d['drawConfig'] is Map
            ? Map<String, dynamic>.from(d['drawConfig'] as Map)
            : null,
      ),
      scheduleConfig: ScheduleConfig.fromMap(
        d['scheduleConfig'] is Map
            ? Map<String, dynamic>.from(d['scheduleConfig'] as Map)
            : null,
      ),
      scoringConfig: Fs.map(d['scoringConfig']),
      cancelReason: Fs.strOrNull(d['cancelReason']),
      cancelledAt: Fs.dateOrNull(d['cancelledAt']),
      cancelledBy: Fs.strOrNull(d['cancelledBy']),
      participantOrgIds: d['participantOrgIds'] is List
          ? Fs.strList(d['participantOrgIds'])
          : null,
      createdBy: Fs.strOrNull(d['createdBy']),
      createdAt: Fs.dateOrNull(d['createdAt']),
    );
  }

  Map<String, Object?> toCreate() => {
        'orgId': orgId,
        'name': name,
        'nameLower': name.toLowerCase(),
        'sportId': sportId,
        'sportName': sportName,
        'archetype': archetype.wire,
        'entrantType': entrantType.wire,
        'format': format.wire,
        // An ordinary competition always starts as a draft, so the organizer
        // configures it before anyone can enter. A challenge match has nothing
        // left to configure — both clubs already agreed the sport, the slot and
        // the venue when the challenge was accepted — so it is created ready to
        // play. `firestore.rules` permits exactly these two starting states.
        //
        // A single match is the third case. It has no field to assemble and
        // no draw to make — both sides were named on the way in — so it opens
        // already in progress and the scoring pad is reachable on the next
        // tap. Sitting it in `draft` would reintroduce exactly the ceremony
        // the format exists to remove.
        'status': switch (true) {
          _ when isInterClub => CompetitionStatus.scheduled.wire,
          _ when format.isSingleMatch => CompetitionStatus.inProgress.wire,
          _ => CompetitionStatus.draft.wire,
        },
        'category': category.toMap(),
        'scoringPluginKey': scoringPluginKey,
        'description': description,
        'venue': venue,
        'startDate': Fs.ts(startDate),
        'endDate': Fs.ts(endDate),
        'registrationClosesAt': Fs.ts(registrationClosesAt),
        'maxEntrants': maxEntrants,
        'entrantCount': 0,
        'fixtureCount': 0,
        'participationModel': participationModel.wire,
        'preselectedSlots': preselectedSlots,
        'waitlistEnabled': waitlistEnabled,
        'openToNonMembers': openToNonMembers,
        'entryFeeRupees': entryFeeRupees,
        'teamSize': teamSize,
        'rulesNote': rulesNote,
        // Both counters start at zero and are only ever moved by the
        // registration transaction. Seeding them here rather than letting
        // them be absent is what allows `firestore.rules` to compare against
        // `resource.data.confirmedCount` without a null check on every path.
        'confirmedCount': 0,
        'waitlistCount': 0,
        'verificationTier': verificationTier.wire,
        'rulesetVersion': rulesetVersion,
        'pointsForWin': pointsForWin,
        'pointsForDraw': pointsForDraw,
        'pointsForLoss': pointsForLoss,
        'tiebreakChain': tiebreakChain,
        'tournamentId': tournamentId,
        'matchPointsModel': matchPointsModel.toMap(),
        'drawConfig': drawConfig.toMap(),
        'scheduleConfig': scheduleConfig.toMap(),
        'scoringConfig': scoringConfig,
        'participantOrgIds': participantOrgIds,
        'createdBy': createdBy,
        'createdAt': FieldValue.serverTimestamp(),
      };

  Map<String, Object?> toUpdate() => Fs.prune({
        'name': name,
        'nameLower': name.toLowerCase(),
        'description': description,
        'venue': venue,
        'startDate': Fs.ts(startDate),
        'endDate': Fs.ts(endDate),
        'registrationClosesAt': Fs.ts(registrationClosesAt),
        'maxEntrants': maxEntrants,
        // `participationModel` and `preselectedSlots` are deliberately absent:
        // they define what tapping Register meant to everyone who has already
        // tapped it, and changing that retroactively would silently move
        // people between the team and the queue. The organizer picks them
        // once, at creation.
        'waitlistEnabled': waitlistEnabled,
        'openToNonMembers': openToNonMembers,
        'entryFeeRupees': entryFeeRupees,
        'teamSize': teamSize,
        'rulesNote': rulesNote,
        'category': category.toMap(),
        'pointsForWin': pointsForWin,
        'pointsForDraw': pointsForDraw,
        'pointsForLoss': pointsForLoss,
        'tiebreakChain': tiebreakChain,
        'drawConfig': drawConfig.toMap(),
        'scheduleConfig': scheduleConfig.toMap(),
        // Editable after creation, unlike `participationModel` above. Changing
        // the format of matches still to be played is a normal organizer
        // decision — rain shortens a day and a 20-over event becomes a 12-over
        // one. Fixtures already created keep the config frozen onto them, so
        // this never rewrites a match that has been played.
        'scoringConfig': scoringConfig,
        'updatedAt': FieldValue.serverTimestamp(),
      });
}

/// An application to take part, at
/// `orgs/{orgId}/competitions/{compId}/registrations/{uid}`.
///
/// The document id is the applicant's uid, so a player physically cannot hold
/// two registrations for the same competition.
class Registration {
  const Registration({
    required this.uid,
    required this.displayName,
    required this.status,
    this.photoUrl,
    this.teamName,
    this.eligibilityNote,
    this.decidedBy,
    this.createdAt,
    this.waitlistPosition,
    this.preselected = false,
  });

  final String uid;
  final String displayName;
  final RegistrationStatus status;
  final String? photoUrl;
  final String? teamName;

  /// Place in the queue, 1-based, for a waitlisted entrant.
  ///
  /// Stored rather than derived from creation order because it is the thing
  /// the entrant is actually told ("you are 2nd reserve"), and a number that
  /// changes every time someone else's document happens to sort differently
  /// is not a promise anyone can rely on.
  final int? waitlistPosition;

  /// True when an organizer put this entrant in the field directly rather
  /// than the entrant registering — the preselected 8 of a hybrid event.
  /// Shown in the entrant list so the open registrants can see which slots
  /// were ever really available.
  final bool preselected;

  /// Recorded when an organizer overrode a failed eligibility check, so the
  /// decision is visible later if the result is protested.
  final String? eligibilityNote;

  final String? decidedBy;
  final DateTime? createdAt;

  factory Registration.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Registration(
      uid: doc.id,
      displayName: Fs.str(d['displayName'], 'Player'),
      status: RegistrationStatus.fromWire(Fs.str(d['status'])),
      photoUrl: Fs.strOrNull(d['photoUrl']),
      teamName: Fs.strOrNull(d['teamName']),
      eligibilityNote: Fs.strOrNull(d['eligibilityNote']),
      decidedBy: Fs.strOrNull(d['decidedBy']),
      createdAt: Fs.dateOrNull(d['createdAt']),
      waitlistPosition:
          d['waitlistPosition'] == null ? null : Fs.integer(d['waitlistPosition']),
      preselected: Fs.boolean(d['preselected']),
    );
  }

  /// The registration document as first written.
  ///
  /// [status] is passed in rather than fixed at `pending` because the outcome
  /// is decided by the event's [ParticipationModel] against its live counts,
  /// inside the transaction that also moves those counts. `firestore.rules`
  /// re-checks every combination this can produce — a client cannot confirm
  /// itself into an approval event by calling this with the wrong argument.
  Map<String, Object?> toCreate({
    RegistrationStatus status = RegistrationStatus.pending,
    int? waitlistPosition,
    bool preselected = false,
  }) =>
      {
        'uid': uid,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'teamName': teamName,
        'status': status.wire,
        'waitlistPosition': waitlistPosition,
        'preselected': preselected,
        'eligibilityNote': eligibilityNote,
        'createdAt': FieldValue.serverTimestamp(),
      };
}

/// A confirmed competitor in the draw, at
/// `orgs/{orgId}/competitions/{compId}/entrants/{entrantId}`.
///
/// Separate from [Registration] because a registration is an *application*
/// and an entrant is a *starter*. Keeping them apart is what allows an
/// organizer to close entries, seed the field, and generate a draw without
/// late applications silently appearing inside a bracket already in play.
class Entrant {
  const Entrant({
    required this.id,
    required this.displayName,
    required this.entrantType,
    this.uid,
    this.photoUrl,
    this.seed,
    this.memberUids = const [],
    this.clubId,
    this.withdrawn = false,
  });

  final String id;
  final String displayName;
  final EntrantType entrantType;

  /// Set for individual entrants; null for teams.
  final String? uid;
  final String? photoUrl;

  /// Lower is stronger. Drives knockout bracket placement so the top two
  /// seeds cannot meet before the final.
  final int? seed;

  /// Populated for team entrants.
  final List<String> memberUids;

  /// Returns this entrant carrying [seed], for handing a freshly-computed
  /// seeding to the draw generator without mutating what was read.
  Entrant withSeed(int? seed) => Entrant(
        id: id,
        displayName: displayName,
        entrantType: entrantType,
        uid: uid,
        photoUrl: photoUrl,
        seed: seed,
        memberUids: memberUids,
        clubId: clubId,
        withdrawn: withdrawn,
      );

  /// Which club this entrant represents, when the field spans several.
  ///
  /// Drives association protection in a federation draw — two players from
  /// one club travelling to a district championship to meet each other in
  /// round one is exactly what a draw is supposed to avoid. Null in a club's
  /// own event, where everyone shares a club and protection means nothing.
  final String? clubId;

  final bool withdrawn;

  factory Entrant.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Entrant(
      id: doc.id,
      displayName: Fs.str(d['displayName'], 'Entrant'),
      entrantType: EntrantType.fromWire(Fs.str(d['entrantType'])),
      uid: Fs.strOrNull(d['uid']),
      photoUrl: Fs.strOrNull(d['photoUrl']),
      seed: d['seed'] == null ? null : Fs.integer(d['seed']),
      memberUids: Fs.strList(d['memberUids']),
      clubId: Fs.strOrNull(d['clubId']),
      withdrawn: Fs.boolean(d['withdrawn']),
    );
  }

  Map<String, Object?> toMap() => {
        'displayName': displayName,
        'entrantType': entrantType.wire,
        'uid': uid,
        'photoUrl': photoUrl,
        'seed': seed,
        'memberUids': memberUids,
        'clubId': clubId,
        'withdrawn': withdrawn,
      };
}
