/// Single source of truth for every enumerated value in PlaySphere.
///
/// Every enum here carries an explicit [wire] string. That string is the
/// exact value stored in Firestore and referenced by `firestore.rules`.
/// Never persist `Enum.name` directly — renaming a Dart constant would
/// silently orphan every existing document. Parse with `fromWire`, which
/// falls back to a documented default rather than throwing, so a document
/// written by a newer client version can still be read by an older one.
library playsphere_enums;

// ---------------------------------------------------------------------------
// Identity & organization
// ---------------------------------------------------------------------------

enum OrgType {
  residentialCommunity('residential_community', 'Residential Community'),
  village('village', 'Village / Mandal Club'),
  individual('individual', 'Pickup Group / Individual'),
  school('school', 'School'),
  college('college', 'College / University'),
  academy('academy', 'Sports Academy'),
  corporate('corporate', 'Corporate'),
  cityClub('city_club', 'City Club'),
  districtAssociation('district_association', 'District Association'),
  stateCouncil('state_council', 'State Sports Council'),
  nationalFederation('national_federation', 'National Federation');

  const OrgType(this.wire, this.label);
  final String wire;
  final String label;

  static OrgType fromWire(String? w) => OrgType.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => OrgType.residentialCommunity,
      );
}

enum OrgVisibility {
  public('public'),
  unlisted('unlisted');

  const OrgVisibility(this.wire);
  final String wire;

  static OrgVisibility fromWire(String? w) => OrgVisibility.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => OrgVisibility.unlisted,
      );
}

/// Ordered least-privileged first. [rank] lets us compare authority
/// without a lookup table (e.g. "you may not edit someone above you").
enum MembershipRole {
  member('member', 'Member', 0),
  judgeScorer('judge_scorer', 'Judge / Scorer', 1),
  eventManager('event_manager', 'Event Manager', 2),
  admin('admin', 'Admin', 3),
  owner('owner', 'Owner', 4);

  const MembershipRole(this.wire, this.label, this.rank);
  final String wire;
  final String label;
  final int rank;

  static MembershipRole fromWire(String? w) => MembershipRole.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => MembershipRole.member,
      );
}

enum MembershipStatus {
  pending('pending'),
  active('active'),
  suspended('suspended'),
  removed('removed');

  const MembershipStatus(this.wire);
  final String wire;

  static MembershipStatus fromWire(String? w) =>
      MembershipStatus.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => MembershipStatus.pending,
      );
}

enum Gender {
  male('male', 'Male'),
  female('female', 'Female'),
  other('other', 'Other'),
  preferNotToSay('prefer_not_to_say', 'Prefer not to say');

  const Gender(this.wire, this.label);
  final String wire;
  final String label;

  static Gender fromWire(String? w) => Gender.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => Gender.preferNotToSay,
      );
}

// ---------------------------------------------------------------------------
// Competition structure
// ---------------------------------------------------------------------------

/// The two fundamentally different shapes a sporting contest can take.
///
/// [versus] competitions pair entrants against each other and produce a
/// winner per fixture (football, chess, badminton).
///
/// [performance] competitions measure each entrant independently against
/// a scale and rank the results (100m sprint, shot put, swimming). They
/// have no opponent, so they never produce a fixture — they produce
/// attempts. Modelling only [versus] is the single most common reason a
/// tournament product cannot run a school athletics meet.
enum CompetitionArchetype {
  versus('versus'),
  performance('performance');

  const CompetitionArchetype(this.wire);
  final String wire;

  static CompetitionArchetype fromWire(String? w) =>
      CompetitionArchetype.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => CompetitionArchetype.versus,
      );
}

enum EntrantType {
  individual('individual'),
  team('team');

  const EntrantType(this.wire);
  final String wire;

  static EntrantType fromWire(String? w) => EntrantType.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => EntrantType.individual,
      );
}

enum CompetitionFormat {
  roundRobin('round_robin', 'Round Robin'),
  knockout('knockout', 'Single Knockout'),
  doubleElimination('double_elimination', 'Double Elimination'),
  groupThenKnockout('group_then_knockout', 'Groups + Knockout'),
  swiss('swiss', 'Swiss'),
  leagueTable('league_table', 'League Table'),

  /// One match, no draw, no registration.
  ///
  /// The club's own Sunday game and two friends on a court are the most
  /// common thing that happens in grassroots sport and the product could not
  /// express either: every match had to arrive through create event → open
  /// entries → register → close entries → generate draw, which is six steps
  /// and a wait before a single ball. This format skips all of it — the two
  /// sides are named at creation and the fixture exists immediately.
  singleMatch('single_match', 'Single Match'),

  // Performance-archetype formats.
  finalOnly('final_only', 'Single Final'),
  heatsThenFinal('heats_then_final', 'Heats + Final');

  const CompetitionFormat(this.wire, this.label);
  final String wire;
  final String label;

  static CompetitionFormat fromWire(String? w) =>
      CompetitionFormat.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => CompetitionFormat.roundRobin,
      );

  bool get isPerformanceFormat =>
      this == CompetitionFormat.finalOnly ||
      this == CompetitionFormat.heatsThenFinal;

  /// Whether this format's fixtures are named at creation rather than drawn.
  bool get isSingleMatch => this == CompetitionFormat.singleMatch;
}

enum CompetitionStatus {
  draft('draft', 'Draft'),
  registrationOpen('registration_open', 'Registration Open'),
  registrationClosed('registration_closed', 'Registration Closed'),
  scheduled('scheduled', 'Scheduled'),
  inProgress('in_progress', 'In Progress'),
  completed('completed', 'Completed'),
  cancelled('cancelled', 'Cancelled');

  const CompetitionStatus(this.wire, this.label);
  final String wire;
  final String label;

  static CompetitionStatus fromWire(String? w) =>
      CompetitionStatus.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => CompetitionStatus.draft,
      );

  /// Fixtures may only be generated once entries are frozen.
  bool get acceptsRegistrations => this == CompetitionStatus.registrationOpen;
  bool get isLive => this == CompetitionStatus.inProgress;
}

/// How an event decides who is actually playing.
///
/// This is the difference between a product that fills a match and one that
/// makes an organizer chase thirteen people over WhatsApp. A community
/// cricket event on a Sunday morning does not want an approval queue — the
/// first thirteen who tap Register are the team, and the fourteenth is the
/// reserve. A school trial does: the coach picks. Most real events are
/// neither, they are both at once — the captain names the seven regulars and
/// throws the rest open.
///
/// The model is fixed when the event is created because it decides what
/// tapping "Register" *means*, and that cannot be allowed to change under
/// someone who has already tapped it.
enum ParticipationModel {
  /// First come, first in. A registration is confirmed the moment it is made,
  /// until the capacity is reached; after that it is waitlisted if the
  /// organizer allowed a waitlist, and refused if they did not.
  open('open', 'Open — first come, first served'),

  /// The organizer names some of the field directly and the remaining slots
  /// are open to whoever registers first. `preselectedSlots` on the
  /// competition says how many are reserved for the organizer's picks.
  hybrid('hybrid', 'Hybrid — some picked, rest open'),

  /// Every registration is an application. Nobody plays until an organizer
  /// confirms them. This is the original behaviour, and the right one for
  /// trials, selections and anything with an eligibility check that a
  /// human has to make.
  approval('approval', 'By approval — organizer confirms each entry');

  const ParticipationModel(this.wire, this.label);
  final String wire;
  final String label;

  static ParticipationModel fromWire(String? w) =>
      ParticipationModel.values.firstWhere(
        (e) => e.wire == w,
        // Events created before this field existed were all approval-gated,
        // because that was the only behaviour the app had. Defaulting to
        // anything else would retroactively let people into old events.
        orElse: () => ParticipationModel.approval,
      );

  /// True when a registration decides its own outcome rather than waiting for
  /// an organizer — the open slots of an open or hybrid event.
  bool get autoConfirms => this != ParticipationModel.approval;
}

enum RegistrationStatus {
  pending('pending', 'Pending Approval'),
  confirmed('confirmed', 'Confirmed'),
  waitlisted('waitlisted', 'Waitlisted'),
  rejected('rejected', 'Rejected'),
  withdrawn('withdrawn', 'Withdrawn');

  const RegistrationStatus(this.wire, this.label);
  final String wire;
  final String label;

  static RegistrationStatus fromWire(String? w) =>
      RegistrationStatus.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => RegistrationStatus.pending,
      );

  bool get occupiesSlot =>
      this == RegistrationStatus.pending ||
      this == RegistrationStatus.confirmed ||
      this == RegistrationStatus.waitlisted;
}

// ---------------------------------------------------------------------------
// Fixtures & scoring
// ---------------------------------------------------------------------------

enum FixtureStatus {
  scheduled('scheduled', 'Scheduled'),
  live('live', 'Live'),
  completed('completed', 'Completed'),
  walkover('walkover', 'Walkover'),
  abandoned('abandoned', 'Abandoned'),
  disputed('disputed', 'Disputed');

  const FixtureStatus(this.wire, this.label);
  final String wire;
  final String label;

  static FixtureStatus fromWire(String? w) => FixtureStatus.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => FixtureStatus.scheduled,
      );

  /// A result exists and standings/ratings should count it.
  bool get isResulted =>
      this == FixtureStatus.completed || this == FixtureStatus.walkover;

  bool get acceptsScoring =>
      this == FixtureStatus.scheduled || this == FixtureStatus.live;
}

/// *How* a match ended, as distinct from what state it is in.
///
/// [FixtureStatus] answers "where is this fixture in its lifecycle"; this
/// answers "what kind of result is on the sheet". Conflating the two loses
/// information a tournament cannot do without: a retirement and a clean
/// straight-games win are both `completed` with a winner, and once written
/// they are indistinguishable — so a scorecard cannot show "RET", a referee
/// reviewing a protest cannot see what happened, and career statistics count
/// a match that lasted four points as a full one.
///
/// ## Why each flag is separate
///
/// The three questions a result gets asked have genuinely different answers,
/// and the codebase previously answered all three with `status.isResulted`:
///
/// - **Standings.** A walkover awards the points — the opponent's failure to
///   appear is their loss, and a league table that ignored it would let a
///   team improve its position by not turning up.
/// - **Rating.** A walkover must NOT move Glicko. Nobody played, so there is
///   no evidence about anyone's skill, and awarding a rating gain for an
///   opponent's flat tyre is how a rating system stops meaning anything.
/// - **Career statistics.** A retirement's partial figures are real and are
///   kept; a walkover has no figures at all to keep.
enum MatchResultType {
  /// Played to its natural end.
  normal('normal', 'Result'),

  /// One side never appeared. The other advances without playing.
  walkover('walkover', 'Walkover'),

  /// Started, and one side could not continue — injury, most often.
  ///
  /// A real match with a real winner: the play that did happen counts.
  retired('retired', 'Retired'),

  /// Conduct, eligibility or equipment. The result stands against the
  /// disqualified side, but it is not evidence of anyone's playing strength.
  disqualified('disqualified', 'Disqualified'),

  /// Neither side appeared. Nothing to award to anybody.
  noShow('no_show', 'No show'),

  /// Weather, light, or the venue becoming unusable. Not a draw — treating it
  /// as one silently awards a point nobody earned.
  abandoned('abandoned', 'Abandoned'),

  /// The entrant withdrew from the competition, resolving this and every
  /// other match still ahead of them.
  conceded('conceded', 'Conceded');

  const MatchResultType(this.wire, this.label);

  final String wire;
  final String label;

  /// Defaults to [normal], which is what every fixture written before this
  /// field existed was — anything unusual went through `forceResult`, which
  /// set a distinct [FixtureStatus].
  static MatchResultType fromWire(String? w) =>
      MatchResultType.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => MatchResultType.normal,
      );

  /// Whether the league table should award points for this.
  ///
  /// Everything except the two where nothing was decided: an abandoned match
  /// is replayed or voided by the organizer, and a no-show has no winner to
  /// award anything to.
  bool get countsForStandings =>
      this != MatchResultType.abandoned && this != MatchResultType.noShow;

  /// Whether Glicko-2 should move on this result.
  ///
  /// Only where the two sides actually competed. This is the check that was
  /// missing: nothing anywhere asked it, so the answer was whatever the
  /// scoring engine happened to report, and a forced result bypassed the
  /// question entirely rather than answering "no" deliberately.
  bool get countsForRating =>
      this == MatchResultType.normal || this == MatchResultType.retired;

  /// Whether per-player figures from this match belong on a career profile.
  ///
  /// Same set as [countsForRating], and deliberately a separate getter: they
  /// are the same answer for different reasons, and a future decision to
  /// count disqualified matches' statistics (the play was real) while still
  /// refusing to rate them should not have to disentangle one flag.
  bool get countsForCareerStats =>
      this == MatchResultType.normal || this == MatchResultType.retired;

  /// Whether a human should be told why. A normal result explains itself.
  bool get wantsNote => this != MatchResultType.normal;
}

/// Whether a result was produced under conditions we trust enough to move
/// a rating aggressively. Casual community matches move ratings less than
/// sanctioned, officiated ones.
enum VerificationTier {
  casual('casual', 'Community'),
  sanctioned('sanctioned', 'Sanctioned');

  const VerificationTier(this.wire, this.label);
  final String wire;
  final String label;

  static VerificationTier fromWire(String? w) =>
      VerificationTier.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => VerificationTier.casual,
      );
}

enum RatingStatus {
  provisional('provisional'),
  established('established'),
  inactive('inactive');

  const RatingStatus(this.wire);
  final String wire;

  static RatingStatus fromWire(String? w) => RatingStatus.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => RatingStatus.provisional,
      );
}

// ---------------------------------------------------------------------------
// Trust & safety
// ---------------------------------------------------------------------------

enum ProfileVisibility {
  private('private', 'Private'),
  community('community', 'My organizations only'),
  public('public', 'Public career page');

  const ProfileVisibility(this.wire, this.label);
  final String wire;
  final String label;

  static ProfileVisibility fromWire(String? w) =>
      ProfileVisibility.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => ProfileVisibility.community,
      );
}

enum GuardianVerificationStatus {
  pending('pending'),
  verified('verified'),
  rejected('rejected');

  const GuardianVerificationStatus(this.wire);
  final String wire;

  static GuardianVerificationStatus fromWire(String? w) =>
      GuardianVerificationStatus.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => GuardianVerificationStatus.pending,
      );
}

// ---------------------------------------------------------------------------
// Categories
// ---------------------------------------------------------------------------

/// How eligibility for a category is decided.
enum CategoryDimension {
  age('age', 'Age'),
  gender('gender', 'Gender'),
  weight('weight', 'Weight'),
  grade('grade', 'Class / Grade'),
  openCategory('open', 'Open');

  const CategoryDimension(this.wire, this.label);
  final String wire;
  final String label;

  static CategoryDimension fromWire(String? w) =>
      CategoryDimension.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => CategoryDimension.openCategory,
      );
}
