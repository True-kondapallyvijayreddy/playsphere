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

// ---------------------------------------------------------------------------
// Give — the equipment-donation network (donations, collection centers,
// verified club/player needs). See `lib/data/give_repository.dart`.
// ---------------------------------------------------------------------------

/// What a donor is contributing. Money is a distinct type from equipment
/// rather than an equipment category with a price, because the two funnels
/// go different places from the moment they're submitted: equipment needs a
/// collection center and a physical pipeline, money needs a payment gateway
/// (deferred product-wide — see `GiveDonation.amountPaise`) and funds
/// procurement instead.
enum GiveDonationType {
  equipment('equipment', 'Equipment'),
  money('money', 'Money');

  const GiveDonationType(this.wire, this.label);
  final String wire;
  final String label;

  static GiveDonationType fromWire(String? w) => GiveDonationType.values
      .firstWhere((e) => e.wire == w, orElse: () => GiveDonationType.equipment);
}

/// The vocabulary of donatable items, shared by a donation's contents and a
/// need's shortfall — the same enum on both sides is what lets a shoe
/// donation match a shoe need without a translation layer. Free text would
/// let "cricket shoes" and "Cricket Shoes" fail to match each other.
enum EquipmentCategory {
  cricketBat('cricket_bat', 'Cricket bat', '🏏'),
  cricketPad('cricket_pad', 'Cricket pads', '🏏'),
  helmet('helmet', 'Helmet', '⛑️'),
  shoes('shoes', 'Shoes', '👟'),
  jersey('jersey', 'Jersey', '👕'),
  footballBoots('football_boots', 'Football boots', '🥾'),
  football('football', 'Football', '⚽'),
  tennisRacket('tennis_racket', 'Tennis racket', '🎾'),
  badmintonRacket('badminton_racket', 'Badminton racket', '🏸'),
  sportsBag('sports_bag', 'Sports bag', '🎒'),
  trainingKit('training_kit', 'Training kit', '🏋️'),
  goalkeeperKit('goalkeeper_kit', 'Goalkeeper kit', '🧤'),
  protectiveGear('protective_gear', 'Protective equipment', '🛡️'),
  other('other', 'Other usable equipment', '🎽');

  const EquipmentCategory(this.wire, this.label, this.emoji);
  final String wire;
  final String label;
  final String emoji;

  static EquipmentCategory fromWire(String? w) => EquipmentCategory.values
      .firstWhere((e) => e.wire == w, orElse: () => EquipmentCategory.other);
}

/// The refurbishment pipeline a physical donation moves through, strictly
/// ordered. Stages after [submitted] are set by collection-center staff
/// (console / a future staff app), never by the donor's client — see
/// `firestore.rules` on `giveDonations`. [rejected] is a terminal branch off
/// [inspected], not a step in the happy path: unsafe items (a cracked
/// helmet, boots with a structural failure) are rejected rather than
/// refurbished, deliberately, because "cleaned up" is not the same claim as
/// "safe".
enum DonationStatus {
  submitted('submitted', 'Submitted', 0),
  collected('collected', 'Collected', 1),
  inspected('inspected', 'Inspected', 2),
  rejected('rejected', 'Rejected — unsafe to reuse', 3),
  cleaned('cleaned', 'Cleaned', 3),
  repaired('repaired', 'Repaired', 4),
  safetyChecked('safety_checked', 'Safety checked', 5),
  graded('graded', 'Graded', 6),
  packed('packed', 'Packed', 7),
  assigned('assigned', 'Assigned to a need', 8),
  distributed('distributed', 'Delivered', 9);

  const DonationStatus(this.wire, this.label, this.step);
  final String wire;
  final String label;

  /// Position for a progress tracker. [rejected] shares a step with
  /// [cleaned] deliberately — it branches off the same point in the pipeline
  /// rather than sitting further along it.
  final int step;

  bool get isTerminalRejection => this == DonationStatus.rejected;

  static DonationStatus fromWire(String? w) => DonationStatus.values
      .firstWhere((e) => e.wire == w, orElse: () => DonationStatus.submitted);
}

/// Who a verified need was raised for. Drives which fields a need shows —
/// [player] shows one name and one kit list, [team]/[club] show a roster
/// count and an aggregated shortfall.
enum GiveBeneficiaryType {
  player('player', 'Player'),
  team('team', 'Team'),
  club('club', 'Club / village');

  const GiveBeneficiaryType(this.wire, this.label);
  final String wire;
  final String label;

  static GiveBeneficiaryType fromWire(String? w) => GiveBeneficiaryType.values
      .firstWhere((e) => e.wire == w, orElse: () => GiveBeneficiaryType.club);
}

/// Whether a need is still worth showing a donor.
enum GiveNeedStatus {
  open('open', 'Open'),
  partiallyFulfilled('partially_fulfilled', 'Partially fulfilled'),
  fulfilled('fulfilled', 'Fulfilled'),
  closed('closed', 'Closed');

  const GiveNeedStatus(this.wire, this.label);
  final String wire;
  final String label;

  static GiveNeedStatus fromWire(String? w) => GiveNeedStatus.values
      .firstWhere((e) => e.wire == w, orElse: () => GiveNeedStatus.open);
}

// -----------------------------------------------------------------------------
// Sponsor an Athlete / Sponsor a Team — the direct, ongoing, named-relationship
// counterpart to Give above. See `lib/core/models/sponsorship.dart` for why
// this is a distinct feature rather than another `GiveNeed` beneficiary type:
// Give is "help sports generally, anonymously, one item at a time"; Sponsor is
// "I am backing this specific person or team, and I get credited for it".
// -----------------------------------------------------------------------------

/// Who a sponsorship listing is for. Deliberately narrower than
/// [GiveBeneficiaryType] — sponsorship is a named, ongoing relationship, and
/// the vision this implements only ever describes two shapes for that:
/// backing one athlete or backing one team's whole squad. A village raising
/// general equipment for "the club" is Give's `club` need, not this.
enum SponsorshipTargetType {
  athlete('athlete', 'Athlete'),
  team('team', 'Team');

  const SponsorshipTargetType(this.wire, this.label);
  final String wire;
  final String label;

  static SponsorshipTargetType fromWire(String? w) =>
      SponsorshipTargetType.values
          .firstWhere((e) => e.wire == w, orElse: () => SponsorshipTargetType.athlete);
}

/// What kind of support a listing is asking a sponsor to provide. [equipment]
/// defers to [EquipmentCategory] for the specific item — this enum covers the
/// broader set of asks a sponsorship carries that a one-off equipment
/// donation never does: an ongoing coach's fee, a season of travel, a
/// tournament's entry costs.
enum SponsorshipSupportCategory {
  equipment('equipment', 'Equipment', '🎽'),
  coaching('coaching', 'Coaching', '🧑‍🏫'),
  travel('travel', 'Travel to matches', '🚌'),
  tournamentFees('tournament_fees', 'Tournament entry fees', '🏆'),
  trainingCamp('training_camp', 'Training camp', '⛺'),
  nutrition('nutrition', 'Nutrition', '🍎'),
  groundFees('ground_fees', 'Ground / facility fees', '🏟️'),
  other('other', 'Other support', '🤝');

  const SponsorshipSupportCategory(this.wire, this.label, this.emoji);
  final String wire;
  final String label;
  final String emoji;

  static SponsorshipSupportCategory fromWire(String? w) =>
      SponsorshipSupportCategory.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => SponsorshipSupportCategory.other,
      );
}

/// Where one sponsor's offer against a listing stands.
///
/// Deliberately not reused from anywhere else — a pledge's lifecycle
/// (`pending` → `accepted`/`declined`, plus `withdrawn` and `completed`) is
/// its own thing, distinct from [TrialInviteStatus] (a scout inviting a
/// player to a trial) even though the shape looks similar, because the two
/// features must be free to evolve their terminal states independently —
/// see `lib/core/models/scout_access.dart`.
enum SponsorPledgeStatus {
  pending('pending', 'Awaiting response'),
  accepted('accepted', 'Accepted'),
  declined('declined', 'Declined'),
  withdrawn('withdrawn', 'Withdrawn'),
  completed('completed', 'Completed');

  const SponsorPledgeStatus(this.wire, this.label);
  final String wire;
  final String label;

  static SponsorPledgeStatus fromWire(String? w) => SponsorPledgeStatus.values
      .firstWhere((e) => e.wire == w, orElse: () => SponsorPledgeStatus.pending);
}

// -----------------------------------------------------------------------------
// Club Commerce — every club's own store, distinct from `ShopRepository`'s
// curated Decathlon link-out catalog. See `lib/core/models/club_product.dart`
// for why a club's own jersey needs a real cart and a curated vendor
// affiliate catalog deliberately does not.
// -----------------------------------------------------------------------------

/// The vocabulary of what a club sells under its own name. Deliberately a
/// small, apparel-shaped set rather than reusing `EquipmentCategory` — that
/// enum is Give/Sponsor's donatable-item vocabulary (bats, pads, rackets);
/// a club store sells branded merchandise, not equipment, and the two lists
/// would drift apart the moment either one grows (a "cricket bat" is never
/// club-branded merchandise; a "training kit" can be both, which is why it
/// appears on both enums rather than forcing one to import the other).
enum ClubProductCategory {
  jersey('jersey', 'Jersey', '👕'),
  tshirt('tshirt', 'T-shirt', '👕'),
  cap('cap', 'Cap', '🧢'),
  trainingKit('training_kit', 'Training kit', '🏋️'),
  accessory('accessory', 'Accessory', '🎒'),
  other('other', 'Other merchandise', '🛍️');

  const ClubProductCategory(this.wire, this.label, this.emoji);
  final String wire;
  final String label;
  final String emoji;

  static ClubProductCategory fromWire(String? w) => ClubProductCategory.values
      .firstWhere((e) => e.wire == w, orElse: () => ClubProductCategory.other);
}

/// Where one order stands. A club fulfils its own orders by hand — see
/// `ClubOrder`'s class doc — so this pipeline is deliberately shorter than
/// `DonationStatus`: there is no collection center or refurbishment step,
/// just "the club knows about it", "the club is preparing it" and "the
/// buyer has it", plus the one terminal exit.
enum ClubOrderStatus {
  placed('placed', 'Placed', 0),
  confirmed('confirmed', 'Preparing', 1),
  fulfilled('fulfilled', 'Delivered', 2),
  cancelled('cancelled', 'Cancelled', 2);

  const ClubOrderStatus(this.wire, this.label, this.step);
  final String wire;
  final String label;
  final int step;

  bool get isTerminal =>
      this == ClubOrderStatus.fulfilled || this == ClubOrderStatus.cancelled;

  static ClubOrderStatus fromWire(String? w) => ClubOrderStatus.values
      .firstWhere((e) => e.wire == w, orElse: () => ClubOrderStatus.placed);
}

// -----------------------------------------------------------------------------
// Advertising — the self-serve console `lib/core/ads/promo.dart`'s own file
// doc says fills the same `Promo` shape once it exists. See
// `lib/core/models/ad_campaign.dart`.
// -----------------------------------------------------------------------------

/// Where one campaign stands. Deliberately mirrors `GiveNeed.verified`'s
/// posture rather than reusing any status enum above: a client may create a
/// campaign, but only staff (the same `admin` claim `isGiveStaff()` checks)
/// may move it out of [pending] — see `firestore.rules` on `adCampaigns`.
enum AdCampaignStatus {
  pending('pending', 'Awaiting review'),
  approved('approved', 'Live'),
  rejected('rejected', 'Not approved'),
  paused('paused', 'Paused');

  const AdCampaignStatus(this.wire, this.label);
  final String wire;
  final String label;

  static AdCampaignStatus fromWire(String? w) => AdCampaignStatus.values
      .firstWhere((e) => e.wire == w, orElse: () => AdCampaignStatus.pending);
}
