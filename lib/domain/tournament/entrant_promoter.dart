import '../../core/models/competition.dart';
import '../../core/models/enums.dart';

/// Turns a confirmed registration list into the entrants that will play, at
/// the moment the organizer closes the field.
///
/// ## Why this is not in the repository
///
/// It used to be. The promotion rules — which house a student belongs to, who
/// is partnered with whom, whether a captain's squad is complete — are the
/// part of closing a field most likely to be wrong, and while they sat inside
/// a Firestore batch they could not be tested without a live database, so
/// they never were. A doubles event silently paired a player who had already
/// named somebody with whoever happened to be next in the list, and nothing
/// caught it.
///
/// Here the rules are a pure function over registrations, so every branch is
/// reachable from a test. The repository keeps what only it can do: read the
/// registrations and write the result.
///
/// ## Why problems are returned rather than thrown
///
/// An organizer closing entries wants to know everything that is wrong, not
/// the first thing. Two students without a house and an unpaired player is
/// one trip to the team builder if reported together, and three if reported
/// one at a time.
class PromotionResult {
  const PromotionResult({
    this.entrants = const [],
    this.problems = const [],
  });

  /// The field, ready to write. Empty whenever [problems] is not.
  final List<Entrant> entrants;

  /// Everything standing between these registrations and a draw, phrased for
  /// the organizer who has to fix it.
  final List<String> problems;

  bool get isReady => problems.isEmpty;

  factory PromotionResult.blocked(List<String> problems) =>
      PromotionResult(problems: problems);
}

class EntrantPromoter {
  const EntrantPromoter();

  PromotionResult promote({
    required TeamEntryMode mode,
    required List<Registration> confirmed,
  }) {
    switch (mode) {
      case TeamEntryMode.houseBatch:
        return _byBucket(
          confirmed,
          key: (r) => r.houseName,
          idPrefix: 'house',
          missingLabel: 'no house',
          missingHint:
              'Assign them in the team builder before closing entries.',
          tooFew: 'At least two houses with confirmed members are needed to '
              'make a draw.',
        );
      case TeamEntryMode.preformedTeam:
        return _byBucket(
          confirmed,
          key: (r) => r.teamName,
          idPrefix: 'team',
          missingLabel: 'no team',
          missingHint: 'Every player must be attached to a squad.',
          tooFew: 'At least two teams with confirmed players are needed to '
              'make a draw.',
        );
      case TeamEntryMode.playerPool:
        // A pool is not a field. Promoting it here produced one individual
        // entrant per student — a 44-player singles bracket for what the
        // organizer set up as a team event — so this refuses and points at
        // the tool that actually forms the squads.
        return PromotionResult.blocked([
          'This event uses a player pool, so there is no field to freeze yet. '
              'Open "Team Builder & Draft" to form the squads — that closes '
              'entries for you.',
        ]);
      case TeamEntryMode.doubles:
        return _doubles(confirmed);
      case TeamEntryMode.individual:
        return _individual(confirmed);
    }
  }

  // --- Houses and captain-led squads --------------------------------------

  PromotionResult _byBucket(
    List<Registration> confirmed, {
    required String? Function(Registration) key,
    required String idPrefix,
    required String missingLabel,
    required String missingHint,
    required String tooFew,
  }) {
    final buckets = <String, List<Registration>>{};
    final unassigned = <Registration>[];

    for (final reg in confirmed) {
      final raw = key(reg);
      // Somebody with no bucket recorded is NOT quietly dropped into the
      // first preset one, which is what the house branch used to do: that put
      // a student on a side they never chose and gave the organizer no way to
      // notice it had happened.
      if (raw == null || raw.trim().isEmpty) {
        unassigned.add(reg);
        continue;
      }
      buckets.putIfAbsent(raw.trim(), () => []).add(reg);
    }

    final problems = <String>[];
    if (unassigned.isNotEmpty) {
      problems.add(
        '${unassigned.length} confirmed '
        '${unassigned.length == 1 ? "entry has" : "entries have"} '
        '$missingLabel: '
        '${unassigned.map((r) => r.displayName).join(", ")}. $missingHint',
      );
    }
    if (buckets.length < 2) problems.add(tooFew);
    if (problems.isNotEmpty) return PromotionResult.blocked(problems);

    return PromotionResult(
      entrants: [
        for (final entry in buckets.entries)
          Entrant(
            id: '${idPrefix}_${_slug(entry.key)}',
            displayName: entry.key,
            entrantType: EntrantType.team,
            memberUids: [for (final m in entry.value) m.uid],
            uid: entry.value.first.uid,
          ),
      ],
    );
  }

  // --- Doubles ------------------------------------------------------------

  PromotionResult _doubles(List<Registration> confirmed) {
    final byUid = {for (final r in confirmed) r.uid: r};
    final processed = <String>{};
    final pairs = <(Registration, Registration)>[];
    final soloPool = <Registration>[];
    final problems = <String>[];

    // Pass 1: honour every named partner.
    //
    // The old loop reached for `firstOrNull` of whoever was left whenever a
    // registration had no partner recorded, so a player who HAD named a
    // partner could be silently claimed as somebody else's — and a named
    // partner who never registered still produced an entrant carrying their
    // uid into the draw.
    for (final reg in confirmed) {
      if (processed.contains(reg.uid)) continue;
      final partnerUid = reg.partnerUid;
      if (partnerUid == null || partnerUid.isEmpty) continue;

      final partner = byUid[partnerUid];
      if (partner == null) {
        problems.add(
          '${reg.displayName} named a partner who has not confirmed an entry.',
        );
        processed.add(reg.uid);
        continue;
      }
      if (processed.contains(partner.uid)) {
        problems.add(
          '${reg.displayName} named ${partner.displayName}, who is already '
          'paired with somebody else.',
        );
        processed.add(reg.uid);
        continue;
      }
      final back = partner.partnerUid;
      if (back != null && back.isNotEmpty && back != reg.uid) {
        problems.add(
          '${reg.displayName} named ${partner.displayName}, who named '
          'somebody else.',
        );
        processed
          ..add(reg.uid)
          ..add(partner.uid);
        continue;
      }
      processed
        ..add(reg.uid)
        ..add(partner.uid);
      pairs.add((reg, partner));
    }

    // Pass 2: the free agents, paired in entry order.
    for (final reg in confirmed) {
      if (processed.contains(reg.uid)) continue;
      processed.add(reg.uid);
      soloPool.add(reg);
    }
    for (var i = 0; i + 1 < soloPool.length; i += 2) {
      pairs.add((soloPool[i], soloPool[i + 1]));
    }
    if (soloPool.length.isOdd) {
      problems.add(
        '${soloPool.last.displayName} is looking for a partner and nobody is '
        'left to pair with.',
      );
    }

    if (problems.isEmpty && pairs.length < 2) {
      problems.add('At least two doubles pairs are needed to generate a draw.');
    }
    if (problems.isNotEmpty) return PromotionResult.blocked(problems);

    return PromotionResult(
      entrants: [
        for (final (a, b) in pairs)
          Entrant(
            // Keyed on the two uids rather than a running index, so locking
            // the field twice lands on the same entrant instead of minting a
            // second one beside it. Sorted, so which of the two the loop
            // happened to reach first cannot change the id either.
            id: 'pair_${_pairKey(a.uid, b.uid)}',
            displayName: '${a.displayName} / ${b.displayName}',
            entrantType: EntrantType.team,
            memberUids: [a.uid, b.uid],
            uid: a.uid,
          ),
      ],
    );
  }

  // --- Individuals --------------------------------------------------------

  PromotionResult _individual(List<Registration> confirmed) {
    if (confirmed.length < 2) {
      return PromotionResult.blocked([
        'At least two confirmed entries are needed before you can close '
            'entries and make a draw.',
      ]);
    }
    return PromotionResult(
      entrants: [
        for (final reg in confirmed)
          Entrant(
            id: reg.uid,
            displayName: reg.displayName,
            entrantType: EntrantType.individual,
            uid: reg.uid,
            photoUrl: reg.photoUrl,
          ),
      ],
    );
  }

  static String _slug(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), '_');

  static String _pairKey(String a, String b) =>
      (a.compareTo(b) <= 0) ? '${a}_$b' : '${b}_$a';
}
