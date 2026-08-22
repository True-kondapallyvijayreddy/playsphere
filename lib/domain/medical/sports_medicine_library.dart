/// The curated half of the Sports Medicine hub: warm-ups, injuries and
/// on-field emergencies, written once and shipped with the app.
///
/// ## Why this is code and not Firestore
///
/// Every other directory in PlaySphere is user-generated and therefore lives
/// in a collection. This one is the opposite: it is a fixed reference that
/// must be readable by a person standing on a ground with one bar of signal
/// and a team-mate holding their knee. Shipping it as `const` data means it
/// opens instantly, offline, on the day it is most needed, and it means the
/// content passes through code review like anything else that can hurt
/// somebody if it is wrong.
///
/// ## Why the videos are searches and not video ids
///
/// A hard-coded YouTube id is a promise that a specific upload will still be
/// there, still be public and still be the video we meant. Channels reorganise
/// and uploads get taken down, and the failure mode is a person tapping
/// "Concussion — what to do" and landing on a removed-video page or, worse, on
/// something else entirely. [VideoReference] therefore carries a [source] —
/// the body whose guidance this is — and a search that names it, so the tap
/// always lands on a live YouTube results page headed by that organisation's
/// own upload. [VideoReference.videoId] exists for the day somebody sits down
/// and verifies specific uploads one by one; until then it stays null and the
/// search is used. Naming the source in text is the part that actually carries
/// the authority, and that part cannot rot.
///
/// ## What this library is not
///
/// It is not a diagnosis and it does not replace a doctor. Every screen that
/// renders it says so, and the injury entries carry [SportsInjury.redFlags]
/// precisely so the answer is sometimes "stop reading this and go to a
/// hospital". The protocols follow published guidance — the FIFA 11+, the RAMP
/// warm-up structure, P.O.L.I.C.E. and PEACE & LOVE for soft tissue, the
/// Concussion Recognition Tool's "if in doubt, sit them out" — and each entry
/// names which.
library sports_medicine_library;

/// Where an injury is, and the filter the injury tab turns on.
///
/// Chosen to match how somebody describes a problem out loud ("my ankle went
/// over", "something pulled in the back of my thigh") rather than an
/// anatomical taxonomy. [wire] is what a practitioner's
/// `bodyPartsTreated` stores.
enum BodyPart {
  head('head', 'Head & concussion'),
  neck('neck', 'Neck'),
  shoulder('shoulder', 'Shoulder'),
  elbow('elbow', 'Elbow'),
  wristHand('wrist_hand', 'Wrist & hand'),
  spine('spine', 'Back & spine'),
  hipGroin('hip_groin', 'Hip & groin'),
  hamstring('hamstring', 'Hamstring & thigh'),
  knee('knee', 'Knee'),
  calfShin('calf_shin', 'Calf & shin'),
  ankleFoot('ankle_foot', 'Ankle & foot'),
  wholeBody('whole_body', 'Whole body');

  const BodyPart(this.wire, this.label);

  final String wire;
  final String label;

  static BodyPart fromWire(String? w) => BodyPart.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => BodyPart.wholeBody,
      );
}

/// The four phases of a RAMP warm-up, plus the one that comes after.
///
/// RAMP — Raise, Activate, Mobilise, Potentiate — is the structure Cricket
/// Australia and most national federations teach, and it is used here rather
/// than an invented one so that a coach who already knows it recognises what
/// they are reading.
enum WorkoutPhase {
  raise('raise', 'Raise', 'Get the heart rate and muscle temperature up'),
  activate('activate', 'Activate', 'Switch on the muscles that protect joints'),
  mobilise('mobilise', 'Mobilise', 'Take joints through the range the sport needs'),
  potentiate('potentiate', 'Potentiate', 'Build to match intensity'),
  cooldown('cooldown', 'Cool-down', 'Bring the body back down and start recovery');

  const WorkoutPhase(this.wire, this.label, this.blurb);

  final String wire;
  final String label;
  final String blurb;
}

/// A YouTube reference, resolved to a URL that cannot rot.
///
/// See the library doc for why this is usually a search rather than an id.
class VideoReference {
  const VideoReference({
    required this.title,
    required this.source,
    required this.search,
    this.videoId,
  });

  /// What the viewer will be watching.
  final String title;

  /// Who stands behind the guidance — "FIFA / F-MARC", "CDC HEADS UP",
  /// "St John Ambulance". Rendered next to the title, because this is the
  /// part that tells somebody whether to trust what they are about to see.
  final String source;

  /// The query used when [videoId] is null. Written to put the organisation's
  /// own upload at the top, so it always names the source.
  final String search;

  /// Set only for an upload somebody has actually checked. Null everywhere
  /// today — deliberately, see the library doc.
  final String? videoId;

  Uri get url => videoId == null
      ? Uri.https('www.youtube.com', '/results', {'search_query': search})
      : Uri.https('www.youtube.com', '/watch', {'v': videoId!});
}

/// One movement inside a warm-up.
class WorkoutStep {
  const WorkoutStep(this.name, this.dose, this.cue);

  final String name;

  /// "2 × 10 each side", "30 seconds", "6 reps building to full pace".
  final String dose;

  /// The single thing that makes the movement worth doing — the coaching
  /// point a physiotherapist would shout from the sideline. Without it these
  /// are just names of exercises, which is how warm-ups get done badly.
  final String cue;
}

/// A warm-up, activation block or cool-down for one sport.
class PreMatchWorkout {
  const PreMatchWorkout({
    required this.id,
    required this.sportIds,
    required this.title,
    required this.phase,
    required this.durationMinutes,
    required this.summary,
    required this.targets,
    required this.steps,
    required this.video,
    this.evidence,
  });

  final String id;

  /// Which sports it belongs to. Empty means every sport — the general
  /// cool-down and the hamstring block are not cricket's or football's.
  final List<String> sportIds;

  final String title;
  final WorkoutPhase phase;
  final int durationMinutes;

  /// One sentence on what it is for, in the language a captain would use.
  final String summary;

  /// Muscle groups and joints. Shown as chips.
  final List<String> targets;

  final List<WorkoutStep> steps;
  final VideoReference video;

  /// Where the protocol comes from, when it is a published one — "FIFA 11+,
  /// British Journal of Sports Medicine". Absent for routines that are
  /// ordinary practice rather than a named programme, because attributing
  /// generic mobility work to a study would be a citation nobody could check.
  final String? evidence;

  bool appliesTo(String sportId) =>
      sportIds.isEmpty || sportIds.contains(sportId);

  int get totalSteps => steps.length;
}

/// One injury: how it happens, what it feels like, what to do in the first
/// hour, and when the answer is a hospital rather than an ice pack.
class SportsInjury {
  const SportsInjury({
    required this.id,
    required this.name,
    required this.bodyPart,
    required this.sportIds,
    required this.mechanism,
    required this.symptoms,
    required this.firstAid,
    required this.redFlags,
    required this.recovery,
    required this.rehab,
    required this.video,
    this.protocol,
  });

  final String id;
  final String name;
  final BodyPart bodyPart;

  /// Empty means it is not a particular sport's injury — an ankle sprain
  /// belongs to everybody.
  final List<String> sportIds;

  /// How it happens, so somebody can recognise what they just watched.
  final String mechanism;

  final List<String> symptoms;

  /// What to do now, in order. Ordered lists rather than prose because this
  /// is read one-handed by somebody kneeling on a pitch.
  final List<String> firstAid;

  /// When to stop managing it and get to a doctor or a hospital. Never empty
  /// on any entry — an injury guide without an exit condition is the
  /// dangerous kind.
  final List<String> redFlags;

  /// Honest range, and the word "typically". Recovery is not a promise.
  final String recovery;

  final List<String> rehab;
  final VideoReference video;

  /// The named protocol the first-aid steps follow — "P.O.L.I.C.E.",
  /// "PEACE & LOVE", "Ottawa ankle rules".
  final String? protocol;

  bool appliesTo(String sportId) =>
      sportIds.isEmpty || sportIds.contains(sportId);
}

/// Something happening now, on the field, where minutes matter.
///
/// Separated from [SportsInjury] because the reading task is different: an
/// injury entry is read afterwards to decide what to do next, and these are
/// read during, by somebody who needs the first line to be the first action.
class EmergencyProtocol {
  const EmergencyProtocol({
    required this.id,
    required this.title,
    required this.oneLine,
    required this.recognise,
    required this.steps,
    required this.neverDo,
    required this.video,
    this.callEmergency = false,
    this.source,
  });

  final String id;
  final String title;

  /// The whole protocol compressed to the sentence that matters most — "If in
  /// doubt, sit them out." Rendered large, above everything else.
  final String oneLine;

  final List<String> recognise;
  final List<String> steps;

  /// The mistakes that make it worse. Present on every protocol because the
  /// instinctive action — popping a shoulder back in, sitting a heat-stroke
  /// casualty up, moving a suspected spinal injury — is very often the wrong
  /// one.
  final List<String> neverDo;

  /// Whether this is one where an ambulance is called first and everything
  /// else happens while waiting. Drives the emergency-call button on the card.
  final bool callEmergency;

  final String? source;
  final VideoReference video;
}

/// India's single emergency number, and the ambulance number most people in
/// Telangana and Andhra will actually dial.
///
/// Both, not one. 112 is the national unified number and is the correct
/// answer; 108 is the one that has been painted on ambulances here for twenty
/// years and is what a bystander will reach for. A screen that printed only
/// the technically correct one would be a screen somebody argues with while
/// a player is on the ground.
class EmergencyNumbers {
  const EmergencyNumbers._();

  static const String unified = '112';
  static const String ambulance = '108';
}

/// Everything curated, in one place, queryable by sport and body part.
class SportsMedicineLibrary {
  const SportsMedicineLibrary._();

  // --- Warm-ups -----------------------------------------------------------

  static const List<PreMatchWorkout> workouts = [
    // --- Football ---------------------------------------------------------
    PreMatchWorkout(
      id: 'fifa11plus_part1',
      sportIds: ['football'],
      title: 'FIFA 11+ · Part 1 — Running warm-up',
      phase: WorkoutPhase.raise,
      durationMinutes: 8,
      summary:
          'The opening block of the warm-up that cut lower-limb injuries by '
          'roughly a third in the trials that made it famous. Six running '
          'exercises up and down a line of cones.',
      targets: ['Whole body', 'Hips', 'Ankles'],
      evidence: 'FIFA 11+ (F-MARC), British Journal of Sports Medicine',
      steps: [
        WorkoutStep(
          'Straight-ahead jog',
          '2 lengths',
          'Easy pace — this is temperature, not fitness.',
        ),
        WorkoutStep(
          'Hip out',
          '2 lengths',
          'Lift the knee, rotate it outwards, plant. Stay tall.',
        ),
        WorkoutStep(
          'Hip in',
          '2 lengths',
          'Same but rotate the knee inwards across the body.',
        ),
        WorkoutStep(
          'Circling the partner',
          '2 lengths',
          'Shoulder to shoulder, side-step around, keep the chest up.',
        ),
        WorkoutStep(
          'Shoulder contact',
          '2 lengths',
          'Jump in and make shoulder contact — land on both feet, knees bent.',
        ),
        WorkoutStep(
          'Quick forwards and backwards sprints',
          '2 lengths',
          'Accelerate, decelerate under control, backpedal on the balls of '
              'the feet.',
        ),
      ],
      video: VideoReference(
        title: 'FIFA 11+ complete warm-up programme',
        source: 'FIFA / F-MARC',
        search: 'FIFA 11+ injury prevention warm up full programme official',
      ),
    ),
    PreMatchWorkout(
      id: 'fifa11plus_part2',
      sportIds: ['football'],
      title: 'FIFA 11+ · Part 2 — Strength, plyometrics & balance',
      phase: WorkoutPhase.activate,
      durationMinutes: 10,
      summary:
          'The part everyone skips and the part that does the work. Nordic '
          'hamstring curls here are the single best-evidenced hamstring '
          'injury reducer in football.',
      targets: ['Hamstrings', 'Core', 'Glutes', 'Balance'],
      evidence: 'FIFA 11+ (F-MARC), levels 1–3 progression',
      steps: [
        WorkoutStep(
          'Plank',
          '3 × 20–30 s',
          'Straight line from ear to ankle. Squeeze the glutes.',
        ),
        WorkoutStep(
          'Side plank',
          '3 × 20–30 s each side',
          'Hips high and stacked, not rolled back.',
        ),
        WorkoutStep(
          'Nordic hamstring curl',
          '3–5 slow reps',
          'Partner holds the ankles. Lower as slowly as you can, catch with '
              'the hands. Soreness for two days is normal the first week.',
        ),
        WorkoutStep(
          'Single-leg stance with ball throw',
          '2 × 10 each leg',
          'Slight knee bend, keep the knee over the middle of the foot.',
        ),
        WorkoutStep(
          'Squats with heel raise',
          '2 × 15',
          'Knees track over the toes, never falling inwards.',
        ),
        WorkoutStep(
          'Vertical jumps',
          '2 × 10',
          'Land softly, hips back, knees apart — this is the ACL rep.',
        ),
      ],
      video: VideoReference(
        title: 'Nordic hamstring curl — technique and progression',
        source: 'Aspetar / FIFA 11+',
        search: 'Nordic hamstring curl technique FIFA 11 plus Aspetar',
      ),
    ),
    PreMatchWorkout(
      id: 'fifa11plus_part3',
      sportIds: ['football'],
      title: 'FIFA 11+ · Part 3 — Running at speed',
      phase: WorkoutPhase.potentiate,
      durationMinutes: 3,
      summary:
          'Three short high-speed runs so the first sprint of the match is not '
          'the first sprint of the day. This is where most hamstrings go.',
      targets: ['Hamstrings', 'Nervous system'],
      evidence: 'FIFA 11+ (F-MARC)',
      steps: [
        WorkoutStep(
          'Running across the pitch',
          '2 lengths at 75–80%',
          'Build the pace, do not launch into it.',
        ),
        WorkoutStep(
          'Bounding',
          '2 lengths',
          'High knees, long stride, land on the ball of the foot.',
        ),
        WorkoutStep(
          'Plant and cut',
          '2 lengths',
          'Plant on the outside foot, push off, change direction. Knee stays '
              'over the foot.',
        ),
      ],
      video: VideoReference(
        title: 'Sprint and change-of-direction preparation',
        source: 'FIFA 11+',
        search: 'FIFA 11 plus part 3 running at speed bounding plant and cut',
      ),
    ),
    PreMatchWorkout(
      id: 'football_adductor',
      sportIds: ['football', 'hockey', 'kabaddi'],
      title: 'Groin & adductor preparation',
      phase: WorkoutPhase.activate,
      durationMinutes: 6,
      summary:
          'Groin strains are the injury that keeps recurring all season. The '
          'Copenhagen adduction exercise is the one with the trial behind it.',
      targets: ['Adductors', 'Hip flexors', 'Obliques'],
      evidence: 'Copenhagen adduction protocol (Harøy et al.)',
      steps: [
        WorkoutStep(
          'Copenhagen adduction — short lever',
          '2 × 6 each side',
          'Partner or bench holds the top ankle; knee of the bottom leg on '
              'the ground. Lift and lower slowly.',
        ),
        WorkoutStep(
          'Adductor squeeze',
          '3 × 10 s',
          'Ball between the knees, squeeze to about half effort. Stop if it '
              'is sharp.',
        ),
        WorkoutStep(
          'Lateral lunge',
          '2 × 8 each side',
          'Sit into the hip, trailing leg straight, feel the stretch inside '
              'the thigh.',
        ),
        WorkoutStep(
          'Leg swings — front to back, then across',
          '10 each direction each leg',
          'Controlled, not ballistic. Hold something for balance.',
        ),
      ],
      video: VideoReference(
        title: 'Copenhagen adduction exercise for groin injury prevention',
        source: 'Oslo Sports Trauma Research Center',
        search: 'Copenhagen adduction exercise groin injury prevention OSTRC',
      ),
    ),

    // --- Cricket ----------------------------------------------------------
    PreMatchWorkout(
      id: 'cricket_ramp',
      sportIds: ['cricket'],
      title: 'Cricket match-day RAMP warm-up',
      phase: WorkoutPhase.raise,
      durationMinutes: 15,
      summary:
          'The whole-team warm-up before the toss: raise, activate, mobilise, '
          'potentiate. Twelve minutes that decide whether the first over is '
          'bowled by a warm body or a cold one.',
      targets: ['Whole body', 'Thoracic spine', 'Glutes', 'Shoulders'],
      evidence: 'RAMP structure (Jeffreys); Cricket Australia warm-up guidance',
      steps: [
        WorkoutStep(
          'Raise — jog, side shuffle, backpedal',
          '4 minutes',
          'Finish slightly out of breath and warm to touch.',
        ),
        WorkoutStep(
          'Activate — glute bridges',
          '2 × 12',
          'Drive through the heels, squeeze at the top, no arching the back.',
        ),
        WorkoutStep(
          'Activate — band pull-aparts',
          '2 × 15',
          'Shoulder blades back and down. This is the fielding shoulder.',
        ),
        WorkoutStep(
          'Mobilise — thoracic open-books',
          '8 each side',
          'Knees stay stacked, chest rotates open. Fast bowlers need this '
              'most.',
        ),
        WorkoutStep(
          'Mobilise — world’s greatest stretch',
          '5 each side',
          'Lunge, elbow to instep, rotate up. One movement for hip, groin '
              'and spine.',
        ),
        WorkoutStep(
          'Potentiate — run-throughs',
          '3 × 30 m building to 90%',
          'The last one should feel like a chase to the boundary.',
        ),
        WorkoutStep(
          'Potentiate — throwing progression',
          '15 throws, short to long',
          'Never open with a long throw from the deep — that is how shoulders '
              'and elbows go in the first over.',
        ),
      ],
      video: VideoReference(
        title: 'RAMP warm-up protocol explained',
        source: 'Cricket Australia coaching',
        search: 'RAMP warm up protocol cricket raise activate mobilise '
            'potentiate',
      ),
    ),
    PreMatchWorkout(
      id: 'cricket_fast_bowler_spine',
      sportIds: ['cricket'],
      title: 'Fast bowler’s lumbar spine & shoulder prep',
      phase: WorkoutPhase.activate,
      durationMinutes: 10,
      summary:
          'Lumbar bone stress is the injury that ends young fast bowlers’ '
          'seasons in India, and it comes from a trunk that side-bends because '
          'the hips and thoracic spine will not rotate.',
      targets: ['Lumbar spine', 'Thoracic spine', 'Rotator cuff', 'Hips'],
      evidence:
          'Consistent with ECB/CA fast-bowling workload and screening guidance',
      steps: [
        WorkoutStep(
          'Dead bug',
          '2 × 8 each side',
          'Lower back stays flat on the ground the whole time.',
        ),
        WorkoutStep(
          'Side plank with top-leg lift',
          '2 × 20 s each side',
          'Quadratus lumborum — the muscle that takes the load at back-foot '
              'contact.',
        ),
        WorkoutStep(
          'Thoracic rotation on all fours',
          '8 each side',
          'Hand behind the head, rotate the ribcage, not the lower back.',
        ),
        WorkoutStep(
          'Band external rotation',
          '2 × 15 each arm',
          'Elbow tucked to the side, forearm rotates out. Slow on the way '
              'back.',
        ),
        WorkoutStep(
          'Scapular wall slides',
          '2 × 10',
          'Wrists and elbows stay on the wall. If they lift, you have gone '
              'too high.',
        ),
        WorkoutStep(
          'Run-up progression',
          '6 balls: walk, jog, 3/4, full',
          'Full pace only on the last two. Bowling flat out off a cold '
              'run-up is the mechanism, not bad luck.',
        ),
      ],
      video: VideoReference(
        title: 'Fast bowling injury prevention — spine and shoulder',
        source: 'Cricket sports physiotherapy',
        search: 'fast bowling lumbar stress fracture prevention exercises '
            'physiotherapy cricket',
      ),
    ),

    // --- Badminton & racquet ----------------------------------------------
    PreMatchWorkout(
      id: 'badminton_prematch',
      sportIds: ['badminton', 'squash', 'table_tennis'],
      title: 'Badminton pre-match warm-up & shadow footwork',
      phase: WorkoutPhase.raise,
      durationMinutes: 10,
      summary:
          'Court sport ankles and Achilles tendons take the load in the first '
          'three rallies. Shadow footwork puts them through it before the '
          'shuttle does.',
      targets: ['Ankles', 'Achilles', 'Shoulders', 'Wrists'],
      steps: [
        WorkoutStep(
          'Skipping or on-court jog',
          '3 minutes',
          'Light on the feet, quiet landings.',
        ),
        WorkoutStep(
          'Ankle circles & calf raises',
          '15 each',
          'Slow down on the way back — that is the part that protects the '
              'tendon.',
        ),
        WorkoutStep(
          'Wrist and forearm circles',
          '20 each direction',
          'Loose grip. The wrist does the deception; a cold one does it '
              'badly.',
        ),
        WorkoutStep(
          'Arm circles and band external rotation',
          '15 each',
          'The overhead smash is a throwing action — warm the cuff like one.',
        ),
        WorkoutStep(
          'Deep lunges to each corner',
          '6 to each of 4 corners',
          'Front knee behind the toes, chest up, push back off the heel.',
        ),
        WorkoutStep(
          'Shadow footwork, all six corners',
          '2 × 45 s',
          'Split-step every time. Build from half to match speed.',
        ),
      ],
      video: VideoReference(
        title: 'Badminton warm-up and footwork routine',
        source: 'Badminton Insight',
        search: 'Badminton Insight warm up routine before playing footwork',
      ),
    ),
    PreMatchWorkout(
      id: 'racquet_elbow_shoulder',
      sportIds: ['badminton', 'tennis', 'squash', 'table_tennis', 'pickleball',
          'padel'],
      title: 'Elbow & rotator cuff protection for racquet players',
      phase: WorkoutPhase.activate,
      durationMinutes: 7,
      summary:
          'Tennis elbow and golfer’s elbow are load problems, not '
          'accidents. Eccentric forearm work is the treatment and the '
          'prevention, and it is the same exercise.',
      targets: ['Forearm', 'Elbow', 'Rotator cuff'],
      steps: [
        WorkoutStep(
          'Eccentric wrist extension',
          '3 × 15 each side',
          'Lift with the other hand, lower slowly with the working one. Light '
              'weight — a 1 kg dumbbell or a full bottle.',
        ),
        WorkoutStep(
          'Eccentric wrist flexion',
          '3 × 15 each side',
          'Same, palm up. This is the golfer’s elbow side.',
        ),
        WorkoutStep(
          'Band external rotation at 90°',
          '2 × 12 each arm',
          'Elbow at shoulder height. This is the smash position.',
        ),
        WorkoutStep(
          'Scapular retraction rows',
          '2 × 15',
          'Blades together first, then pull. Never the other way round.',
        ),
      ],
      video: VideoReference(
        title: 'Tennis elbow eccentric exercises',
        source: 'PhysioTutors',
        search: 'PhysioTutors tennis elbow eccentric exercise protocol',
      ),
    ),

    // --- Kabaddi & contact -------------------------------------------------
    PreMatchWorkout(
      id: 'kabaddi_prep',
      sportIds: ['kabaddi', 'kho_kho'],
      title: 'Kabaddi joint mobility & ankle-hold preparation',
      phase: WorkoutPhase.mobilise,
      durationMinutes: 12,
      summary:
          'A raider is dragged, twisted and landed on. The joints that take '
          'that — ankle, knee, shoulder, neck — get prepared deliberately '
          'before the first raid, not after the first injury.',
      targets: ['Ankles', 'Knees', 'Neck', 'Shoulders', 'Core'],
      steps: [
        WorkoutStep(
          'Mat jog and side shuffle',
          '3 minutes',
          'Feel the surface. A dry mat and a wet one are different games.',
        ),
        WorkoutStep(
          'Deep squat hold with rocking',
          '60 s',
          'The raiding stance. Heels down if you can, chest up.',
        ),
        WorkoutStep(
          'Ankle dorsiflexion rocks to the wall',
          '10 each side',
          'Knee travels over the second toe, heel stays down.',
        ),
        WorkoutStep(
          'Neck isometrics — all four directions',
          '5 s hold, 3 each direction',
          'Hand resists, head does not move. Defenders take neck load in '
              'every tackle.',
        ),
        WorkoutStep(
          'Bear crawl and crab walk',
          '2 × 10 m',
          'Shoulders under load in a crawling position — the exact position '
              'of a struggle.',
        ),
        WorkoutStep(
          'Controlled falls onto the mat',
          '6 each side',
          'Roll along the shoulder, tuck the chin, never put out a straight '
              'arm. This is the shoulder-dislocation rep.',
        ),
      ],
      video: VideoReference(
        title: 'Kabaddi conditioning and joint preparation',
        source: 'Pro Kabaddi conditioning',
        search: 'Pro Kabaddi League training warm up mobility conditioning '
            'drills',
      ),
    ),

    // --- Basketball & volleyball -------------------------------------------
    PreMatchWorkout(
      id: 'jump_landing',
      sportIds: ['basketball', 'volleyball', 'throwball'],
      title: 'Jump-landing mechanics & ACL protection',
      phase: WorkoutPhase.potentiate,
      durationMinutes: 8,
      summary:
          'Most ACL tears in these sports are non-contact: a landing or a cut '
          'where the knee falls inwards. Eight minutes teaching the knee to '
          'land over the foot is the whole intervention.',
      targets: ['Knees', 'Glutes', 'Quads', 'Landing technique'],
      evidence: 'Consistent with PEP / NSCA jump-landing programmes',
      steps: [
        WorkoutStep(
          'Lateral slides and defensive shuffle',
          '2 × 20 m',
          'Stay low, do not let the feet click together.',
        ),
        WorkoutStep(
          'Reverse lunge with thoracic twist',
          '8 each side',
          'Rotate towards the front leg. Hip and spine in one movement.',
        ),
        WorkoutStep(
          'Drop jumps to a stick landing',
          '3 × 5',
          'Land, hold three seconds, check the knees are apart and over the '
              'toes. If they cave in, drop the height.',
        ),
        WorkoutStep(
          'Single-leg hop and hold',
          '3 × 5 each leg',
          'Land quietly and stop dead. Noise means you are landing stiff.',
        ),
        WorkoutStep(
          'Approach jumps at match intensity',
          '5',
          'Full approach, full jump, controlled landing.',
        ),
      ],
      video: VideoReference(
        title: 'ACL injury prevention — jump landing technique',
        source: 'NSCA / PEP programme',
        search: 'ACL injury prevention jump landing technique NSCA basketball',
      ),
    ),
    PreMatchWorkout(
      id: 'patellar_isometrics',
      sportIds: ['basketball', 'volleyball', 'badminton', 'throwball'],
      title: 'Jumper’s knee — pre-game isometric block',
      phase: WorkoutPhase.activate,
      durationMinutes: 6,
      summary:
          'For a patellar tendon that hurts. Heavy isometric holds reduce '
          'tendon pain for hours and let somebody play — they are a warm-up, '
          'not a cure.',
      targets: ['Patellar tendon', 'Quadriceps'],
      evidence: 'Isometric analgesia protocol (Rio et al.)',
      steps: [
        WorkoutStep(
          'Spanish squat',
          '5 × 45 s hold, 1 min rest',
          'Band behind the knees anchored in front, sit back into it, shins '
              'vertical. Should feel hard, not sharp.',
        ),
        WorkoutStep(
          'Wall sit',
          '3 × 45 s',
          'Alternative when there is no band. Thighs parallel.',
        ),
        WorkoutStep(
          'Slow calf raises',
          '2 × 15',
          'Three seconds down. The calf shares the landing load with the '
              'tendon.',
        ),
      ],
      video: VideoReference(
        title: 'Spanish squat for patellar tendinopathy',
        source: 'PhysioTutors',
        search: 'Spanish squat patellar tendinopathy isometric PhysioTutors',
      ),
    ),

    // --- Athletics & running -----------------------------------------------
    PreMatchWorkout(
      id: 'track_drills',
      sportIds: ['athletics_sprint', 'athletics_field'],
      title: 'Track drills & sprint preparation',
      phase: WorkoutPhase.potentiate,
      durationMinutes: 12,
      summary:
          'The drills that come between a jog and a race. Skipped, the first '
          'hard effort of the day is the one that tears something.',
      targets: ['Hamstrings', 'Hip flexors', 'Calves', 'Running mechanics'],
      steps: [
        WorkoutStep(
          'Easy jog',
          '800 m',
          'Conversational. Warm, not tired.',
        ),
        WorkoutStep(
          'A-skips',
          '2 × 20 m',
          'Knee up, toe up, strike down under the hip.',
        ),
        WorkoutStep(
          'B-skips',
          '2 × 20 m',
          'A-skip, then paw the ground back. This is the hamstring rep.',
        ),
        WorkoutStep(
          'High-knee running',
          '2 × 20 m',
          'Quick ground contact, tall posture.',
        ),
        WorkoutStep(
          'Heel flicks',
          '2 × 20 m',
          'Heels to the backside, knees pointing down.',
        ),
        WorkoutStep(
          'Strides',
          '4 × 60 m at 85–95%',
          'Build across the first 20 m. Full effort only in the last two.',
        ),
      ],
      video: VideoReference(
        title: 'Sprint drills — A-skip, B-skip, high knees',
        source: 'Athletics coaching',
        search: 'sprint drills A skip B skip technique athletics warm up '
            'coaching',
      ),
    ),
    PreMatchWorkout(
      id: 'calf_achilles_loading',
      sportIds: ['athletics_sprint', 'badminton', 'basketball', 'football',
          'volleyball'],
      title: 'Calf & Achilles loading',
      phase: WorkoutPhase.activate,
      durationMinutes: 6,
      summary:
          'The Achilles takes eight times bodyweight in a sprint push-off. '
          'Loading it gradually before the match is cheaper than six months '
          'of tendinopathy after one.',
      targets: ['Achilles', 'Calves', 'Plantar fascia'],
      steps: [
        WorkoutStep(
          'Double-leg calf raise',
          '2 × 20',
          'All the way up onto the toes, slow all the way down.',
        ),
        WorkoutStep(
          'Single-leg calf raise',
          '2 × 12 each',
          'If you cannot do twelve, that is the leg that gets injured.',
        ),
        WorkoutStep(
          'Bent-knee calf raise',
          '2 × 15',
          'Loads soleus, which the straight-knee version misses.',
        ),
        WorkoutStep(
          'Pogo hops',
          '3 × 15',
          'Stiff ankles, minimal knee bend, quick off the ground.',
        ),
      ],
      video: VideoReference(
        title: 'Achilles tendon loading exercises',
        source: 'PhysioTutors',
        search: 'Achilles tendinopathy loading exercises heel raise protocol '
            'PhysioTutors',
      ),
    ),

    // --- Everybody ---------------------------------------------------------
    PreMatchWorkout(
      id: 'general_cooldown',
      sportIds: [],
      title: 'Post-match cool-down & recovery',
      phase: WorkoutPhase.cooldown,
      durationMinutes: 10,
      summary:
          'Ten minutes after the final whistle, before the phone comes out. '
          'It does not prevent soreness — nothing does — but it brings the '
          'heart rate down properly and it is when you notice the niggle that '
          'would otherwise be Monday’s injury.',
      targets: ['Whole body'],
      steps: [
        WorkoutStep(
          'Easy jog or walk',
          '5 minutes',
          'Heart rate down gradually. Do not stop dead and sit.',
        ),
        WorkoutStep(
          'Hamstring, quad, calf and hip flexor stretches',
          '30 s each, both sides',
          'Easy hold, no bouncing. Static stretching belongs here, not '
              'before.',
        ),
        WorkoutStep(
          'Rehydrate',
          '500 ml or more, with salt if it was hot',
          'Water alone after a long hot match is how cramps arrive at night.',
        ),
        WorkoutStep(
          'Injury check',
          '1 minute',
          'Anything sharp, swollen or that changed how you moved — tell '
              'someone today, not on Monday.',
        ),
      ],
      video: VideoReference(
        title: 'Post-exercise cool-down and recovery',
        source: 'Sports physiotherapy',
        search: 'post match cool down stretching recovery routine sports '
            'physiotherapy',
      ),
    ),
    PreMatchWorkout(
      id: 'hamstring_general',
      sportIds: [],
      title: 'Hamstring resilience block',
      phase: WorkoutPhase.activate,
      durationMinutes: 8,
      summary:
          'The most-injured muscle in every running sport, and the one with '
          'the clearest answer: eccentric strength, twice a week, all season.',
      targets: ['Hamstrings', 'Glutes'],
      evidence: 'Nordic hamstring evidence base (Petersen, van Dyk et al.)',
      steps: [
        WorkoutStep(
          'Nordic hamstring curl',
          '3 × 5, lowering slowly',
          'Resist for as long as possible, catch with the hands.',
        ),
        WorkoutStep(
          'Single-leg Romanian deadlift',
          '3 × 8 each leg',
          'Hinge at the hip, back flat, feel it in the hamstring, not the '
              'lower back.',
        ),
        WorkoutStep(
          'Glute bridge march',
          '2 × 10 each side',
          'Hips stay level when one foot lifts.',
        ),
        WorkoutStep(
          'Leg swings',
          '10 each leg',
          'Only after the strength work, never as the whole warm-up.',
        ),
      ],
      video: VideoReference(
        title: 'Hamstring injury prevention programme',
        source: 'Aspetar sports medicine',
        search: 'hamstring injury prevention Nordic curl programme Aspetar',
      ),
    ),
  ];

  // --- Injuries -----------------------------------------------------------

  static const List<SportsInjury> injuries = [
    SportsInjury(
      id: 'ankle_lateral_sprain',
      name: 'Lateral ankle sprain',
      bodyPart: BodyPart.ankleFoot,
      sportIds: [],
      protocol: 'P.O.L.I.C.E. + Ottawa ankle rules',
      mechanism:
          'The foot rolls inwards on landing — off an opponent’s foot, '
          'off the edge of a mat, or in a pothole on an uneven ground. The '
          'ligaments on the outside of the ankle take it.',
      symptoms: [
        'Pain and swelling on the outside of the ankle, often within minutes',
        'Bruising that appears over the next day or two',
        'Difficulty putting weight through it',
        'Feeling that the ankle "gave way"',
      ],
      firstAid: [
        'Stop playing. Continuing on a fresh sprain is what turns three weeks '
            'into three months.',
        'Protect — take the boot or shoe off before swelling makes it hard to.',
        'Optimal Loading — put weight through it only as much as is '
            'comfortable; complete rest for days is now known to slow '
            'recovery.',
        'Ice for 15 minutes, wrapped in cloth, not directly on skin.',
        'Compress with an elastic bandage, firm but never numbing or '
            'throbbing.',
        'Elevate above the level of the heart whenever sitting.',
      ],
      redFlags: [
        'Cannot take four steps on it, at the time or afterwards',
        'Bone tenderness on the back edge or tip of either ankle bone — this '
            'is the Ottawa rule and it means an X-ray',
        'Obvious deformity, or the foot pointing the wrong way',
        'Numbness, pins and needles, or a foot that is cold or pale',
      ],
      recovery:
          'Typically 1–3 weeks for a mild sprain, 4–8 weeks for a moderate '
          'one. Return-to-play is decided by balance and hopping, not by the '
          'calendar.',
      rehab: [
        'Ankle alphabet and gentle range of movement from day 2–3',
        'Calf raises, double then single leg',
        'Single-leg balance — eyes open, then eyes closed',
        'Hopping and cutting drills before returning to a match',
        'Brace or tape for the first season back — recurrence risk is real',
      ],
      video: VideoReference(
        title: 'Ankle sprain — first aid and rehabilitation',
        source: 'PhysioTutors',
        search: 'ankle sprain rehabilitation exercises physiotherapy protocol',
      ),
    ),
    SportsInjury(
      id: 'acl_tear',
      name: 'ACL tear',
      bodyPart: BodyPart.knee,
      sportIds: ['football', 'basketball', 'kabaddi', 'volleyball', 'hockey'],
      protocol: 'Immediate immobilisation, urgent assessment',
      mechanism:
          'Usually non-contact: landing or cutting with the knee falling '
          'inwards and the foot planted. Many players describe a "pop" they '
          'heard or felt.',
      symptoms: [
        'A pop or a snap at the moment of injury',
        'The knee swells within a few hours — fast swelling is the key sign',
        'The knee feels unstable, like it will give way',
        'Cannot continue playing',
      ],
      firstAid: [
        'Stop immediately. Do not run it off.',
        'Support the leg, keep it still, ice for 15 minutes.',
        'Compress lightly and elevate.',
        'Do not put full weight on it — help them off the field, or use '
            'crutches if there are any.',
        'Arrange an orthopaedic assessment. A knee that swells within hours '
            'needs one within days, not weeks.',
      ],
      redFlags: [
        'Rapid swelling within 2 hours of the injury',
        'The knee locks, or cannot be fully straightened',
        'Obvious deformity — this could be a dislocation, which is an '
            'emergency',
        'Numbness below the knee, or a cold foot',
      ],
      recovery:
          'Typically 9–12 months to competitive sport after reconstruction. '
          'Some people manage without surgery; that decision belongs to an '
          'orthopaedic surgeon who has seen the scan, not to a warm-up guide.',
      rehab: [
        'Regain full straightening first — this is non-negotiable',
        'Quadriceps activation and swelling control in the early weeks',
        'Progressive strength through the whole leg, both sides',
        'Hop testing and agility before any return to play',
        'A supervised return-to-sport programme roughly halves reinjury risk',
      ],
      video: VideoReference(
        title: 'ACL injury — what happens and what comes next',
        source: 'Sports orthopaedics',
        search: 'ACL tear injury explained diagnosis surgery rehabilitation '
            'timeline',
      ),
    ),
    SportsInjury(
      id: 'hamstring_strain',
      name: 'Hamstring strain',
      bodyPart: BodyPart.hamstring,
      sportIds: [],
      protocol: 'PEACE & LOVE',
      mechanism:
          'A sudden grab in the back of the thigh during a sprint, usually in '
          'the last stride before the foot lands, or overstretching for a '
          'ball. Most common late in a match when tired.',
      symptoms: [
        'Sudden sharp pain in the back of the thigh — often a hand goes '
            'straight to it',
        'Tender to press on a specific spot',
        'Bruising down the back of the thigh after a day or two',
        'Pain on stretching or on trying to sprint',
      ],
      firstAid: [
        'Stop. A hamstring played on is a hamstring torn further.',
        'Protect — no stretching, no "walking it off" fast.',
        'Elevate the leg when resting.',
        'Avoid anti-inflammatory tablets in the first day or two if you can; '
            'the early inflammation is part of healing.',
        'Compress with a bandage or tights and ice briefly for comfort.',
        'Load — start gentle pain-free movement within a couple of days '
            'rather than resting completely.',
      ],
      redFlags: [
        'A pop with immediate inability to walk',
        'A visible gap or lump in the muscle',
        'Extensive bruising all the way to the knee within hours',
        'Pain right at the sitting bone, especially with numbness down the '
            'leg — this can be a tendon avulsion and needs a surgeon',
      ],
      recovery:
          'Typically 2–6 weeks depending on grade. Reinjury rate is high and '
          'almost always due to returning early.',
      rehab: [
        'Pain-free isometric holds in the first days',
        'Progressive eccentric work — Nordic curls, slow Romanian deadlifts',
        'Running progression: jog, stride, sprint, then match speed',
        'Do not return until sprinting is pain-free at full speed',
        'Keep the eccentric work going all season — that is the prevention',
      ],
      video: VideoReference(
        title: 'Hamstring strain rehabilitation',
        source: 'PhysioTutors',
        search: 'hamstring strain rehabilitation protocol return to running '
            'physiotherapy',
      ),
    ),
    SportsInjury(
      id: 'groin_adductor_strain',
      name: 'Groin / adductor strain',
      bodyPart: BodyPart.hipGroin,
      sportIds: ['football', 'hockey', 'kabaddi', 'kho_kho'],
      protocol: 'P.O.L.I.C.E.',
      mechanism:
          'Kicking, a sharp change of direction, or a stretch for a tackle. '
          'The adductors on the inside of the thigh take the load.',
      symptoms: [
        'Pain on the inside of the thigh or at the pubic bone',
        'Hurts to squeeze the knees together',
        'Worse on kicking, sprinting or getting out of a car',
      ],
      firstAid: [
        'Stop playing — groin strains that are played through become '
            'season-long.',
        'Ice for 15 minutes for comfort.',
        'Avoid stretching it hard in the first days.',
        'Gentle pain-free adductor squeezes can start within a few days.',
      ],
      redFlags: [
        'Pain with a lump or bulge in the groin — could be a hernia',
        'Pain that came on with no incident and is worst at night',
        'Fever, or pain spreading into the abdomen',
        'Groin pain in a growing adolescent that is not settling — hips need '
            'imaging at that age',
      ],
      recovery:
          'Typically 2–6 weeks. Recurrence is very common without a strength '
          'programme afterwards.',
      rehab: [
        'Isometric adductor squeezes, increasing effort as pain allows',
        'Copenhagen adduction, short lever then long lever',
        'Side-lying leg raises and hip abduction work — both sides matter',
        'Change-of-direction drills before returning to a match',
      ],
      video: VideoReference(
        title: 'Groin strain rehabilitation and prevention',
        source: 'Aspetar / OSTRC',
        search: 'adductor groin strain rehabilitation Copenhagen protocol '
            'football',
      ),
    ),
    SportsInjury(
      id: 'cricket_lumbar_stress',
      name: 'Lumbar bone stress injury (fast bowlers)',
      bodyPart: BodyPart.spine,
      sportIds: ['cricket'],
      mechanism:
          'Repeated bowling load on a growing spine, usually with a mixed '
          'action that side-bends the trunk. It builds over weeks — it is not '
          'a single ball.',
      symptoms: [
        'One-sided low back pain, usually on the non-bowling-arm side',
        'Worse during and after bowling, better with rest',
        'Pain on arching backwards, especially standing on one leg',
        'Common in bowlers aged 14–21 during a heavy season',
      ],
      firstAid: [
        'Stop bowling. Not "reduce" — stop.',
        'This is not managed with ice and a bandage; it needs imaging.',
        'See a sports physician. An MRI is the test that finds it; an X-ray '
            'often misses it early.',
        'Batting and fielding may continue only if a clinician says so.',
      ],
      redFlags: [
        'Back pain in a teenage fast bowler that persists more than 2–3 weeks',
        'Pain, numbness or weakness travelling down a leg',
        'Any loss of bladder or bowel control — this is an emergency',
        'Night pain that wakes them, or unexplained weight loss',
      ],
      recovery:
          'Typically 3–6 months, with a graded bowling return. Bowling '
          'through it is what turns a stress reaction into a fracture.',
      rehab: [
        'Complete rest from bowling for the period the clinician sets',
        'Core and gluteal strength, then hip and thoracic mobility',
        'Action screening — a mixed action usually has to change',
        'Graded return: run-up without ball, then 30%, 50%, 75%, match load',
        'Long-term workload limits by age — this is prevention, and it works',
      ],
      video: VideoReference(
        title: 'Fast bowling lumbar stress fractures explained',
        source: 'Cricket sports medicine',
        search: 'fast bowler lumbar stress fracture cricket back injury '
            'management',
      ),
    ),
    SportsInjury(
      id: 'cricket_side_strain',
      name: 'Side strain',
      bodyPart: BodyPart.spine,
      sportIds: ['cricket'],
      protocol: 'P.O.L.I.C.E.',
      mechanism:
          'A tear where the internal oblique attaches to the lower ribs, on '
          'the non-bowling-arm side, at the moment of front-foot contact.',
      symptoms: [
        'Sharp pain on the side of the ribcage, usually mid-delivery',
        'Painful to take a deep breath, cough or reach overhead',
        'Bruising along the lower ribs after a day or two',
      ],
      firstAid: [
        'Stop bowling immediately.',
        'Ice for comfort; support the ribs with the arm.',
        'Do not stretch into it.',
        'Get it assessed — the grade decides the timeline and only a scan '
            'settles it.',
      ],
      redFlags: [
        'Severe breathlessness or pain that is worse lying down',
        'Pain following a direct blow to the chest rather than a delivery — '
            'this could be a rib fracture',
        'Coughing blood',
      ],
      recovery: 'Typically 4–8 weeks, sometimes longer for a full tear.',
      rehab: [
        'Rest from bowling and overhead loading in the early phase',
        'Breathing and gentle trunk range of movement',
        'Progressive oblique strengthening',
        'Graded bowling return, pace built last',
      ],
      video: VideoReference(
        title: 'Side strain in cricket fast bowlers',
        source: 'Cricket sports medicine',
        search: 'side strain cricket fast bowler oblique injury rehabilitation',
      ),
    ),
    SportsInjury(
      id: 'rotator_cuff',
      name: 'Rotator cuff strain & impingement',
      bodyPart: BodyPart.shoulder,
      sportIds: ['cricket', 'badminton', 'volleyball', 'tennis', 'throwball'],
      mechanism:
          'Repeated overhead throwing, smashing or serving, usually on a '
          'shoulder whose scapular control has not kept up with its volume.',
      symptoms: [
        'Pain on the outside of the shoulder, worse reaching overhead',
        'Ache at night, especially lying on that side',
        'Weakness on throwing or smashing',
        'A painful arc roughly halfway through lifting the arm sideways',
      ],
      firstAid: [
        'Stop the aggravating action — throwing, smashing, serving.',
        'Ice after activity for comfort.',
        'Keep moving the shoulder gently; a shoulder that stops moving stiffens '
            'quickly.',
        'See a physiotherapist rather than resting and hoping.',
      ],
      redFlags: [
        'Cannot lift the arm at all after a fall — possible full tear',
        'Sudden weakness with no pain',
        'Deformity, or the shoulder looking dropped compared with the other',
        'Pain with pins and needles down the arm',
      ],
      recovery:
          'Typically 6–12 weeks with a loading programme. Rest alone tends to '
          'return it exactly as it was.',
      rehab: [
        'Band external and internal rotation, progressively heavier',
        'Scapular control — rows, wall slides, serratus work',
        'Throwing or smashing progression by volume, then by intensity',
        'Address the total load, not just the shoulder — this is a workload '
            'problem as much as a strength one',
      ],
      video: VideoReference(
        title: 'Rotator cuff rehabilitation exercises',
        source: 'PhysioTutors',
        search: 'rotator cuff rehabilitation exercises shoulder impingement '
            'physiotherapy',
      ),
    ),
    SportsInjury(
      id: 'shoulder_dislocation',
      name: 'Shoulder dislocation',
      bodyPart: BodyPart.shoulder,
      sportIds: ['kabaddi', 'kho_kho', 'hockey', 'football'],
      protocol: 'Immobilise and transfer — never reduce on the field',
      mechanism:
          'A fall onto an outstretched arm, or an arm pulled backwards and '
          'outwards in a tackle or an ankle hold.',
      symptoms: [
        'Severe pain and an arm the player will not move',
        'The shoulder looks square rather than rounded',
        'A visible bulge at the front of the shoulder',
        'They support the injured arm with the other hand',
      ],
      firstAid: [
        'Do not try to put it back. Ever. Nerves and blood vessels run '
            'through there and an untrained reduction can damage them '
            'permanently.',
        'Support the arm exactly where it is comfortable — a sling, a jacket, '
            'a folded towel.',
        'Ice over the shoulder for comfort.',
        'Nothing to eat or drink; they may need an anaesthetic.',
        'Get them to a hospital now.',
      ],
      redFlags: [
        'Numbness or pins and needles in the arm or hand',
        'Cold, pale hand, or no pulse at the wrist',
        'Inability to feel the skin over the outer shoulder',
        'Any suspicion of an associated fracture',
      ],
      recovery:
          'Typically 6–12 weeks after a first dislocation. Under 20, the '
          'chance of it happening again is high — a surgical opinion is '
          'worth having.',
      rehab: [
        'Sling for the period the hospital sets, then early controlled '
            'movement',
        'Rotator cuff and scapular strengthening',
        'Sport-specific work in the overhead and behind positions last',
        'Contact sport only when strength matches the other side',
      ],
      video: VideoReference(
        title: 'Dislocated shoulder — first aid',
        source: 'St John Ambulance',
        search: 'St John Ambulance dislocated shoulder first aid sling',
      ),
    ),
    SportsInjury(
      id: 'tennis_elbow',
      name: 'Tennis elbow (and golfer’s elbow)',
      bodyPart: BodyPart.elbow,
      sportIds: ['badminton', 'tennis', 'squash', 'table_tennis', 'cricket',
          'pickleball', 'padel'],
      mechanism:
          'Overload of the forearm tendons where they attach at the elbow. '
          'Often follows a change — a new racquet, a tighter string, a heavier '
          'grip, or suddenly playing twice as much.',
      symptoms: [
        'Pain on the outside of the elbow (inside for golfer’s elbow)',
        'Tender to press on the bony point',
        'Weak grip — dropping a kettle is the classic complaint',
        'Worse on backhands, or on gripping the racquet tightly',
      ],
      firstAid: [
        'Reduce the aggravating load rather than stopping everything.',
        'Check the equipment: grip size, string tension, racquet weight.',
        'Ice after play for comfort.',
        'Start eccentric forearm loading — this is the treatment with the '
            'evidence.',
      ],
      redFlags: [
        'Numbness or pins and needles in the fingers — a nerve, not a tendon',
        'Elbow that locks or catches',
        'Pain following a fall rather than building up over weeks',
        'Swelling and redness with fever',
      ],
      recovery:
          'Typically 3–6 months, and slower if the load that caused it does '
          'not change. Injections give short-term relief and worse long-term '
          'outcomes — worth knowing before asking for one.',
      rehab: [
        'Eccentric wrist extension, 3 × 15 daily, light weight',
        'Grip strengthening as pain allows',
        'Shoulder and scapular strength — a weak shoulder makes the forearm '
            'work harder',
        'Technique review; a late backhand is a common cause',
      ],
      video: VideoReference(
        title: 'Tennis elbow — evidence-based treatment',
        source: 'PhysioTutors',
        search: 'tennis elbow lateral epicondylalgia treatment exercises '
            'PhysioTutors',
      ),
    ),
    SportsInjury(
      id: 'achilles_tendinopathy',
      name: 'Achilles tendinopathy',
      bodyPart: BodyPart.calfShin,
      sportIds: ['badminton', 'athletics_sprint', 'football', 'basketball',
          'squash'],
      mechanism:
          'Load applied to the tendon faster than it adapts — a jump in '
          'training volume, a new court surface, or a season starting after '
          'months off.',
      symptoms: [
        'Pain and stiffness in the tendon, worst in the first steps of the '
            'morning',
        'Warms up during activity and hurts again afterwards',
        'Tender and sometimes thickened to squeeze',
      ],
      firstAid: [
        'Reduce jumping and sprinting volume, do not stop moving entirely.',
        'Start heel raises — loading is the treatment, rest is not.',
        'Check footwear; a small heel raise in the shoe helps in the short '
            'term.',
        'See a physiotherapist if it is not improving in a few weeks.',
      ],
      redFlags: [
        'A sudden pop with the feeling of being kicked in the back of the '
            'ankle — this is a rupture and needs a hospital today',
        'Inability to push off or stand on tiptoe on that leg',
        'A palpable gap in the tendon',
        'Redness, heat and fever',
      ],
      recovery:
          'Typically 3–6 months of consistent loading. It responds well but '
          'slowly, and stopping the exercises when it feels better is why it '
          'comes back.',
      rehab: [
        'Isometric calf holds for pain relief',
        'Heavy slow calf raises, straight and bent knee, 3 times a week',
        'Progress to hopping and skipping',
        'Return to sprinting and jumping last',
      ],
      video: VideoReference(
        title: 'Achilles tendinopathy loading programme',
        source: 'PhysioTutors',
        search: 'Achilles tendinopathy heavy slow resistance loading programme',
      ),
    ),
    SportsInjury(
      id: 'patellar_tendinopathy',
      name: 'Jumper’s knee (patellar tendinopathy)',
      bodyPart: BodyPart.knee,
      sportIds: ['basketball', 'volleyball', 'badminton', 'throwball',
          'athletics_field'],
      mechanism:
          'Repeated jumping and landing load on the tendon just below the '
          'kneecap, usually after a spike in training volume.',
      symptoms: [
        'Pain at a specific point just below the kneecap',
        'Hurts on jumping, landing and going down stairs',
        'Stiff after sitting for a long time',
        'Often warms up and then hurts again later',
      ],
      firstAid: [
        'Reduce jumping volume rather than resting completely.',
        'Isometric holds — Spanish squats or wall sits — for pain relief '
            'before play.',
        'Ice after training for comfort only.',
        'Get a physiotherapist to look at landing mechanics.',
      ],
      redFlags: [
        'Sudden severe pain with inability to straighten the knee — possible '
            'tendon rupture',
        'The kneecap sitting visibly higher than the other side',
        'Locking or giving way',
        'Knee pain in a growing adolescent that is at the bony bump below the '
            'knee — that is a different problem and needs different advice',
      ],
      recovery: 'Typically 3–6 months with a proper loading programme.',
      rehab: [
        'Isometric holds daily in the painful phase',
        'Heavy slow squats and leg press through the pain-free range',
        'Hip and calf strength — the knee rarely fails alone',
        'Jump and landing retraining before returning to full volume',
      ],
      video: VideoReference(
        title: 'Patellar tendinopathy rehabilitation',
        source: 'PhysioTutors',
        search: 'patellar tendinopathy jumpers knee rehabilitation loading '
            'programme',
      ),
    ),
    SportsInjury(
      id: 'shin_splints',
      name: 'Shin splints (medial tibial stress syndrome)',
      bodyPart: BodyPart.calfShin,
      sportIds: ['athletics_sprint', 'football', 'basketball', 'kabaddi'],
      mechanism:
          'Bone and muscle overload along the inner shin, from a sharp '
          'increase in running volume or a change to a harder surface.',
      symptoms: [
        'Aching along the inside edge of the shin bone',
        'Sore to press along a length of the bone, not one point',
        'Hurts at the start of a run, sometimes eases, returns afterwards',
      ],
      firstAid: [
        'Cut running volume substantially — this is a load problem.',
        'Swap some sessions for cycling or swimming to keep fitness.',
        'Ice the shin after activity.',
        'Look at footwear and at how fast the training load increased.',
      ],
      redFlags: [
        'Pain at one specific point on the bone rather than along it — that '
            'is a stress fracture and needs imaging',
        'Pain at rest or at night',
        'Severe pain with numbness and a tight, hard calf after exercise — '
            'possible compartment syndrome, which is urgent',
      ],
      recovery: 'Typically 4–8 weeks if the load actually comes down.',
      rehab: [
        'Calf and tibialis posterior strengthening',
        'Gradual running progression — no more than about 10% a week',
        'Running technique: shorter, quicker steps reduce shin load',
        'Address the surface if training moved onto concrete',
      ],
      video: VideoReference(
        title: 'Shin splints — causes and rehabilitation',
        source: 'Sports physiotherapy',
        search: 'shin splints medial tibial stress syndrome treatment exercises',
      ),
    ),
    SportsInjury(
      id: 'plantar_fasciitis',
      name: 'Plantar fasciitis',
      bodyPart: BodyPart.ankleFoot,
      sportIds: [],
      mechanism:
          'Overload of the tissue along the sole of the foot, common in '
          'runners and court players and in anyone who trains barefoot on '
          'hard ground.',
      symptoms: [
        'Sharp heel pain with the first steps in the morning',
        'Eases after walking, returns after standing all day',
        'Tender to press at the front of the heel bone',
      ],
      firstAid: [
        'Supportive footwear, and stop training barefoot on concrete.',
        'Roll the sole over a ball or a frozen bottle.',
        'Calf and plantar fascia stretching morning and evening.',
        'Start high-load calf raises with the toes propped up.',
      ],
      redFlags: [
        'Heel pain after a fall from height — possible calcaneal fracture',
        'Numbness or burning in the sole — possible nerve entrapment',
        'Redness, heat and swelling with fever',
      ],
      recovery: 'Typically 3–12 months. Slow, but it does settle.',
      rehab: [
        'Heel raises with a towel under the toes, 3 × 12, every other day',
        'Calf stretching, straight and bent knee',
        'Foot intrinsic strengthening — toe curls and short-foot holds',
        'Load management: reduce the running, do not stop it entirely',
      ],
      video: VideoReference(
        title: 'Plantar fasciitis exercises that work',
        source: 'PhysioTutors',
        search: 'plantar fasciitis high load strength training exercises '
            'PhysioTutors',
      ),
    ),
    SportsInjury(
      id: 'itb_syndrome',
      name: 'IT band syndrome',
      bodyPart: BodyPart.knee,
      sportIds: ['athletics_sprint', 'football'],
      mechanism:
          'Compression of tissue on the outside of the knee, typically in '
          'runners increasing distance, or running consistently on a camber.',
      symptoms: [
        'Pain on the outside of the knee, coming on at a predictable '
            'distance into a run',
        'Worse downhill and on shortened stride',
        'Settles quickly with rest, returns at the same point next run',
      ],
      firstAid: [
        'Reduce running distance and avoid downhill and cambered routes.',
        'Do not roll aggressively over the painful spot — it is compressed '
            'already.',
        'Start hip abductor strengthening.',
      ],
      redFlags: [
        'Swelling inside the knee joint rather than on the outside',
        'Locking or giving way',
        'Pain that does not settle within minutes of stopping',
      ],
      recovery: 'Typically 4–8 weeks.',
      rehab: [
        'Side-lying hip abduction and side planks with leg lift',
        'Single-leg squat control — the hip must not drop',
        'Cadence increase of around 5% reduces the load',
        'Return to distance gradually, hills last',
      ],
      video: VideoReference(
        title: 'IT band syndrome rehabilitation',
        source: 'Sports physiotherapy',
        search: 'IT band syndrome runners knee rehabilitation hip strengthening',
      ),
    ),
    SportsInjury(
      id: 'finger_injuries',
      name: 'Jammed, dislocated or split finger',
      bodyPart: BodyPart.wristHand,
      sportIds: ['cricket', 'basketball', 'volleyball', 'throwball'],
      mechanism:
          'A ball striking the end of a finger — a dropped catch, a block at '
          'the net, a wicketkeeping take. Split webbing between the fingers '
          'comes from a ball forced between them.',
      symptoms: [
        'Immediate pain, swelling and difficulty bending the finger',
        'Obvious crookedness in a dislocation',
        'A bleeding split in the web between two fingers',
      ],
      firstAid: [
        'Take rings off immediately, before swelling makes it impossible.',
        'Do not pull a dislocated finger straight yourself.',
        'Ice and elevate; buddy-tape to the neighbouring finger for support.',
        'Clean and dress a split; deep splits need stitching and are easy to '
            'infect.',
        'X-ray if there is any deformity or if it cannot be bent.',
      ],
      redFlags: [
        'A finger that will not straighten at the tip — mallet finger, needs '
            'a splint for weeks',
        'Any deformity or rotation of the finger',
        'A wound over a knuckle from a tooth or another player — these '
            'infect badly and need antibiotics',
        'Numbness or a white fingertip',
      ],
      recovery:
          'Typically 2–6 weeks. Stiffness lasts longer than pain and is what '
          'people regret not treating.',
      rehab: [
        'Early gentle bending once a fracture has been ruled out',
        'Buddy taping for sport for several weeks',
        'Grip strengthening with putty or a ball',
        'Keepers and blockers: return with taping, not without',
      ],
      video: VideoReference(
        title: 'Finger injuries in sport — first aid and taping',
        source: 'Sports first aid',
        search: 'jammed finger dislocation buddy taping sports first aid',
      ),
    ),
    SportsInjury(
      id: 'mat_burns',
      name: 'Mat burns, grazes & abrasions',
      bodyPart: BodyPart.wholeBody,
      sportIds: ['kabaddi', 'kho_kho', 'football', 'hockey'],
      mechanism:
          'Skin dragged across a mat or a hard ground. Common on the knees, '
          'elbows, hips and back.',
      symptoms: [
        'Raw, stinging area of broken skin',
        'Oozing rather than heavy bleeding',
        'Grit or mat fibre in the wound',
      ],
      firstAid: [
        'Wash hands or use gloves first.',
        'Rinse the wound with clean running water until no grit is left.',
        'Pat dry around it and cover with a non-stick dressing.',
        'Do not use cotton wool — it sticks to the wound.',
        'Change the dressing daily and keep it clean and covered.',
      ],
      redFlags: [
        'Spreading redness, heat, pus or a red line tracking up the limb',
        'Fever a day or two later',
        'A wound that will not stop bleeding after 10 minutes of pressure',
        'No tetanus vaccination in the last 10 years, or a dirty wound',
      ],
      recovery: 'Typically 1–2 weeks. Infection is the only real risk.',
      rehab: [
        'Keep it covered while playing',
        'Moist wound healing — a dressing, not open air',
        'Avoid picking scabs; it scars more',
      ],
      video: VideoReference(
        title: 'Cleaning and dressing a graze',
        source: 'St John Ambulance',
        search: 'St John Ambulance how to treat a graze cuts wound first aid',
      ),
    ),
    SportsInjury(
      id: 'muscle_cramp',
      name: 'Exercise-associated muscle cramp',
      bodyPart: BodyPart.wholeBody,
      sportIds: [],
      mechanism:
          'A sudden involuntary contraction, usually calf or hamstring, late '
          'in a hard match — most often in heat, in players going beyond '
          'their usual duration.',
      symptoms: [
        'Sudden, visible, painful hardening of the muscle',
        'Player unable to continue, often clutching the calf',
        'Sometimes moves from one muscle to another',
      ],
      firstAid: [
        'Gently stretch the cramping muscle and hold — for the calf, pull '
            'the toes towards the shin.',
        'Massage the muscle lightly while stretched.',
        'Give fluid with salt in it — an ORS sachet, or a pinch of salt and '
            'sugar in water.',
        'Cool them down if it is hot; get them out of direct sun.',
        'Do not send them straight back on; cramp usually returns.',
      ],
      redFlags: [
        'Cramp with confusion, a very high temperature or collapse — treat '
            'as heat stroke and call an ambulance',
        'Dark brown urine afterwards — possible muscle breakdown, needs a '
            'hospital',
        'Chest pain or breathlessness',
        'Cramps at rest, at night, over weeks — that is a medical question, '
            'not a sporting one',
      ],
      recovery: 'Minutes to hours. Soreness may last a day or two.',
      rehab: [
        'Rehydrate with electrolytes over the following hours',
        'Build up match duration in training rather than jumping into a full '
            'game',
        'Strength work in the muscles that cramp reduces recurrence',
      ],
      video: VideoReference(
        title: 'Managing muscle cramps in sport',
        source: 'Sports medicine first aid',
        search: 'exercise associated muscle cramp treatment stretching '
            'electrolytes',
      ),
    ),
  ];

  // --- On-field emergencies ------------------------------------------------

  static const List<EmergencyProtocol> emergencies = [
    EmergencyProtocol(
      id: 'concussion',
      title: 'Suspected concussion',
      oneLine: 'If in doubt, sit them out.',
      callEmergency: false,
      source: 'Concussion Recognition Tool 5 / CDC HEADS UP',
      recognise: [
        'Any blow to the head, face, neck or body that transmits force to '
            'the head',
        'Lying motionless, slow to get up, or unsteady on their feet',
        'Blank or vacant look; confusion about the score, ground or '
            'opponent',
        'Headache, dizziness, nausea, blurred vision, sensitivity to light',
        'Behaving out of character, or unusually emotional',
      ],
      steps: [
        'Remove them from play immediately. There is no same-day return, at '
            'any level, at any age.',
        'Do not leave them alone for the first few hours.',
        'Ask the memory questions: which ground are we at, which half is it, '
            'who scored last, did we win our last match, what is the score '
            'now. Getting any wrong is a failed screen.',
        'Have them seen by a doctor the same day.',
        'No alcohol, no driving, no sleeping tablets that night.',
        'Return to play only through a graded, day-by-day programme cleared '
            'by a doctor — typically a minimum of 1–2 weeks, longer for '
            'children.',
      ],
      neverDo: [
        'Never let them go back on "because they feel fine now"',
        'Never move a player with neck pain — treat it as a spinal injury '
            'and wait for the ambulance',
        'Never let them drive themselves home',
        'Never use smelling salts or slaps to bring them round',
      ],
      video: VideoReference(
        title: 'Recognising concussion in sport',
        source: 'CDC HEADS UP',
        search: 'CDC HEADS UP concussion recognition signs symptoms sport '
            'coaches',
      ),
    ),
    EmergencyProtocol(
      id: 'red_flags_head',
      title: 'Head injury — call an ambulance now',
      oneLine:
          'Any one of these signs means an ambulance, not an ice pack.',
      callEmergency: true,
      source: 'Concussion Recognition Tool 5 red flags',
      recognise: [
        'Neck pain or tenderness',
        'Double vision',
        'Weakness, numbness or tingling in arms or legs',
        'Severe or increasing headache',
        'Any seizure or convulsion',
        'Loss of consciousness, even briefly',
        'Deteriorating consciousness, or increasing confusion',
        'Vomiting, or unequal pupils',
      ],
      steps: [
        'Call ${EmergencyNumbers.unified} or ${EmergencyNumbers.ambulance} '
            'immediately.',
        'Do not move them if there is any neck pain — hold the head still in '
            'the position found.',
        'If they are unconscious and breathing normally with no suspected '
            'neck injury, put them in the recovery position.',
        'If they are not breathing normally, start CPR.',
        'Stay with them, keep them warm, and keep talking to them.',
        'Note the time of the injury and what happened — the hospital will '
            'ask.',
      ],
      neverDo: [
        'Never move a player with neck pain to get them off the pitch faster',
        'Never remove a helmet where one is worn, unless the airway needs it',
        'Never give them anything to eat or drink',
        'Never let anyone drive them if an ambulance is on the way',
      ],
      video: VideoReference(
        title: 'Head injury red flags and emergency response',
        source: 'St John Ambulance',
        search: 'St John Ambulance head injury first aid unconscious recovery '
            'position',
      ),
    ),
    EmergencyProtocol(
      id: 'cardiac_arrest',
      title: 'Collapse & cardiac arrest',
      oneLine:
          'Not breathing normally? Call for help, start chest compressions, '
          'send for the nearest defibrillator.',
      callEmergency: true,
      source: 'Basic life support guidance',
      recognise: [
        'Sudden collapse with no warning, often in a young, fit player',
        'Unresponsive to a shout and a shake',
        'Not breathing, or only gasping — gasping is not breathing',
        'Brief jerking movements immediately after collapse are common and '
            'are not a seizure',
      ],
      steps: [
        'Shout for help. Send one named person to call '
            '${EmergencyNumbers.unified} and another to find a defibrillator.',
        'Check for response and for normal breathing, for no more than 10 '
            'seconds.',
        'Start chest compressions: centre of the chest, 5–6 cm deep, about '
            '100–120 per minute. Push hard and fast.',
        'Attach a defibrillator as soon as it arrives and follow its spoken '
            'instructions exactly.',
        'Keep going until the ambulance crew take over or the person starts '
            'breathing normally.',
        'Swap the person doing compressions every two minutes — everyone '
            'tires faster than they expect.',
      ],
      neverDo: [
        'Never wait to see if they come round',
        'Never stop compressions to check repeatedly for a pulse',
        'Never assume a young athlete cannot have a cardiac arrest',
        'Never delay compressions to look for the defibrillator yourself — '
            'send someone else',
      ],
      video: VideoReference(
        title: 'Hands-only CPR and defibrillator use',
        source: 'Basic life support training',
        search: 'hands only CPR chest compressions AED how to use '
            'demonstration',
      ),
    ),
    EmergencyProtocol(
      id: 'heat_illness',
      title: 'Heat exhaustion & heat stroke',
      oneLine:
          'Confusion or collapse in the heat is heat stroke — cool first, '
          'transport second.',
      callEmergency: true,
      source: 'Sports medicine heat illness guidance',
      recognise: [
        'Heat exhaustion: heavy sweating, dizziness, nausea, cramps, '
            'headache, clammy pale skin',
        'Heat stroke: confusion, aggression, slurred speech, staggering or '
            'collapse',
        'Very hot skin, which may be dry or still sweaty — dry skin is not '
            'required',
        'Common in Indian afternoon matches in April–June, and in players '
            'who have not been drinking',
      ],
      steps: [
        'Get them into shade immediately and remove excess kit and padding.',
        'For heat exhaustion: lie them down, raise the legs, give cool fluid '
            'with salt — an ORS sachet is ideal.',
        'For heat stroke, call ${EmergencyNumbers.unified} and start cooling '
            'at once — cold water immersion if a tub or tank is available, '
            'otherwise wet towels changed constantly plus fanning, ice packs '
            'to the neck, armpits and groin.',
        'Cool first, then transport. Cooling in the first minutes is what '
            'decides the outcome.',
        'Keep cooling until they are alert and their skin is no longer '
            'burning hot.',
        'Anyone with heat stroke goes to hospital even if they recover on '
            'the field.',
      ],
      neverDo: [
        'Never give fluids to someone who is confused or drowsy — they may '
            'choke',
        'Never send them back on to finish the match',
        'Never delay cooling in order to move them to a hospital',
        'Never leave them alone to "rest in the dressing room"',
      ],
      video: VideoReference(
        title: 'Heat stroke on the field — cool first, transport second',
        source: 'Sports medicine',
        search: 'exertional heat stroke cool first transport second sports '
            'medicine cold water immersion',
      ),
    ),
    EmergencyProtocol(
      id: 'fracture_dislocation',
      title: 'Suspected fracture or dislocation',
      oneLine:
          'Support it exactly where it lies. Never straighten it, never put '
          'it back.',
      callEmergency: false,
      source: 'St John Ambulance first aid',
      recognise: [
        'Pain out of proportion, and a limb they will not use',
        'Deformity, shortening or an unnatural angle',
        'Swelling and bruising coming on fast',
        'A snap heard or felt at the moment of injury',
        'Grating on movement',
      ],
      steps: [
        'Tell them to keep still and support the limb by hand, in the '
            'position found.',
        'Pad around it with something soft — a folded towel, a jacket.',
        'For an arm: a broad-arm sling. For a leg: pad and support, and do '
            'not attempt to move them far.',
        'Ice over the area, not directly on skin, for comfort.',
        'Nothing to eat or drink — they may need an anaesthetic.',
        'Take them to hospital, or call an ambulance for a leg, hip or open '
            'fracture.',
      ],
      neverDo: [
        'Never try to straighten a deformed limb or push a dislocation back',
        'Never let them walk on a suspected leg fracture',
        'Never remove a bone or object protruding from a wound — pad around '
            'it',
        'Never give food or drink',
      ],
      video: VideoReference(
        title: 'Fractures and dislocations — first aid',
        source: 'St John Ambulance',
        search: 'St John Ambulance broken bone fracture first aid sling '
            'immobilisation',
      ),
    ),
    EmergencyProtocol(
      id: 'severe_bleeding',
      title: 'Severe bleeding',
      oneLine: 'Pressure, hard and continuous, straight onto the wound.',
      callEmergency: true,
      source: 'St John Ambulance first aid',
      recognise: [
        'Blood coming fast, or soaking through dressings',
        'A deep cut from a stud, a stump, a boundary board or broken glass '
            'on the ground',
        'Pale, cold, clammy skin; fast breathing; feeling faint',
      ],
      steps: [
        'Put on gloves if there are any.',
        'Press firmly directly on the wound with a clean pad and keep '
            'pressing.',
        'Call ${EmergencyNumbers.unified} for anything that will not stop or '
            'is spurting.',
        'Add more dressings on top if blood soaks through — do not take the '
            'first one off.',
        'Raise the injured part above the heart if you can do it without '
            'causing more harm.',
        'Lie them down, keep them warm, and watch their breathing until help '
            'arrives.',
      ],
      neverDo: [
        'Never keep lifting the dressing to check',
        'Never use a tourniquet unless trained and the bleeding is '
            'life-threatening and uncontrollable',
        'Never wash out a deep wound on the field',
        'Never give them anything to eat or drink',
      ],
      video: VideoReference(
        title: 'How to treat severe bleeding',
        source: 'St John Ambulance',
        search: 'St John Ambulance severe bleeding first aid direct pressure',
      ),
    ),
  ];

  // --- Queries -------------------------------------------------------------

  /// Warm-ups for one sport, general ones included.
  ///
  /// Sport-specific first: a footballer opening this expects the FIFA 11+ at
  /// the top, not the general cool-down that happens to sort earlier.
  static List<PreMatchWorkout> workoutsFor(String? sportId) {
    if (sportId == null) return workouts;
    final specific = [
      for (final w in workouts)
        if (w.sportIds.contains(sportId)) w,
    ];
    final general = [
      for (final w in workouts)
        if (w.sportIds.isEmpty) w,
    ];
    return [...specific, ...general];
  }

  /// Injuries, narrowed by sport and body part. Either filter may be null.
  static List<SportsInjury> injuriesFor({String? sportId, BodyPart? part}) => [
        for (final i in injuries)
          if ((sportId == null || i.appliesTo(sportId)) &&
              (part == null || i.bodyPart == part))
            i,
      ];

  /// The body parts that actually have entries, in enum order. Used for the
  /// filter row, so it never offers a chip that returns nothing.
  static List<BodyPart> bodyPartsWithInjuries({String? sportId}) {
    final present = <BodyPart>{
      for (final i in injuriesFor(sportId: sportId)) i.bodyPart,
    };
    return [
      for (final p in BodyPart.values)
        if (present.contains(p)) p,
    ];
  }

  static PreMatchWorkout? workoutById(String id) {
    for (final w in workouts) {
      if (w.id == id) return w;
    }
    return null;
  }
}
