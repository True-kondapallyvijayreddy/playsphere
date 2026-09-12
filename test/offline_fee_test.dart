import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/billing.dart';
import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/ground.dart';
import 'package:playsphere/core/models/tournament.dart';
import 'package:playsphere/shared/offline_fee_notice.dart';

/// The money PlaySphere deliberately does NOT touch.
///
/// Entry fees and ground rates are declared by an organizer and settled in
/// person, because there is no way yet to verify that an organizer is
/// genuine — collecting on behalf of one would make PlaySphere the implied
/// guarantor of an event that may never happen.
///
/// That policy lives in copy and in the absence of code, which is exactly the
/// kind of thing that rots: a later change adding a "pay now" button to an
/// event would break nothing and no test would notice. These assertions are
/// what makes the absence deliberate rather than merely current.
void main() {
  group('an entry fee is a declared number, not a charge', () {
    test('a competition defaults to free', () {
      const c = Competition(
        id: 'c1',
        orgId: 'o1',
        name: 'Club singles',
        sportId: 'badminton',
        sportName: 'Badminton',
        archetype: CompetitionArchetype.versus,
        entrantType: EntrantType.individual,
        format: CompetitionFormat.knockout,
        status: CompetitionStatus.registrationOpen,
        category: CompetitionCategory(label: 'Open'),
        scoringPluginKey: 'badminton',
      );
      expect(c.entryFeeRupees, 0);
      expect(c.isFree, isTrue);
    });

    test('a declared fee survives the Firestore round trip', () {
      const c = Competition(
        id: 'c1',
        orgId: 'o1',
        name: 'Open singles',
        sportId: 'badminton',
        sportName: 'Badminton',
        archetype: CompetitionArchetype.versus,
        entrantType: EntrantType.individual,
        format: CompetitionFormat.knockout,
        status: CompetitionStatus.registrationOpen,
        category: CompetitionCategory(label: 'Open'),
        scoringPluginKey: 'badminton',
        entryFeeRupees: 500,
      );
      expect(c.toCreate()['entryFeeRupees'], 500);
      expect(c.isFree, isFalse);
    });

    test('a tournament defaults to free and carries a declared fee', () {
      const free = Tournament(
        id: 't1',
        orgId: 'o1',
        name: 'Season',
        status: TournamentStatus.draft,
      );
      expect(free.entryFeeRupees, 0);

      const paid = Tournament(
        id: 't2',
        orgId: 'o1',
        name: 'Open',
        status: TournamentStatus.draft,
        entryFeeRupees: 300,
      );
      expect(paid.toCreate()['entryFeeRupees'], 300);
    });
  });

  group('a season charges once, or per sport, never both', () {
    Tournament season({
      required SeasonFeeMode mode,
      int fee = 0,
    }) =>
        Tournament(
          id: 't1',
          orgId: 'o1',
          name: 'School sports week',
          status: TournamentStatus.entriesOpen,
          feeMode: mode,
          entryFeeRupees: fee,
        );

    test('one fee for the whole season covers every event', () {
      final s = season(mode: SeasonFeeMode.wholeSeason, fee: 100);
      expect(s.seasonFeeCoversEverything, isTrue);
      expect(s.chargesPerEvent, isFalse);
    });

    test('a whole-season season with no fee is free, not "covered"', () {
      // The distinction an event page depends on: "already paid for" and
      // "nothing to pay" must not render the same way, or a free event would
      // tell entrants they owe a season fee that does not exist.
      final s = season(mode: SeasonFeeMode.wholeSeason);
      expect(s.seasonFeeCoversEverything, isFalse);
    });

    test('per-sport pricing never quotes a season-level number', () {
      final s = season(mode: SeasonFeeMode.perEvent);
      expect(s.chargesPerEvent, isTrue);
      expect(s.seasonFeeCoversEverything, isFalse);
      expect(s.entryFeeRupees, 0);
    });

    test('the mode survives the Firestore round trip', () {
      expect(
        season(mode: SeasonFeeMode.perEvent).toCreate()['feeMode'],
        'event',
      );
      expect(
        season(mode: SeasonFeeMode.wholeSeason).toCreate()['feeMode'],
        'season',
      );
    });

    test('a season written before this field existed reads as whole-season', () {
      // Legacy rows carry `entryFeeRupees` and no `feeMode`, and that number
      // always meant the price of entering the tournament. Defaulting to
      // per-event would silently stop quoting it.
      expect(SeasonFeeMode.fromWire(null), SeasonFeeMode.wholeSeason);
      expect(SeasonFeeMode.fromWire('nonsense'), SeasonFeeMode.wholeSeason);
    });
  });

  group('no entry fee can ever become a ledger row', () {
    // The ledger records money PlaySphere actually collected. An entry fee is
    // collected by the organizer at the venue, so there is deliberately no
    // `PlanPaymentKind` that could describe one — this asserts the gap stays
    // open rather than being helpfully filled in later.
    test('PlanPaymentKind has no entry-fee kind', () {
      final wires = PlanPaymentKind.values.map((k) => k.wire).toSet();
      expect(
        wires,
        {'org_plan', 'member_plan', 'ground_booking', 'club_store'},
        reason: 'Adding an entry-fee payment kind would mean PlaySphere is '
            'collecting money for an organizer it cannot yet verify. If that '
            'is genuinely intended, the fraud controls have to land first.',
      );
    });
  });

  group('a ground rate is what is owed, not what was paid', () {
    const g = Ground(
      id: 'g1',
      ownerUid: 'u1',
      name: 'Turf 7',
      city: 'Hyderabad',
      hourlyRatePaise: 60000,
    );

    test('the rate is quoted per hour and multiplies by the slot', () {
      expect(g.rateLabel, '₹600/hour');
      expect(g.priceForPaise(2), 120000);
      expect(g.isFree, isFalse);
    });

    test('a free ground says so rather than showing ₹0', () {
      const free = Ground(
        id: 'g2',
        ownerUid: 'u1',
        name: 'School maidan',
        city: 'Hyderabad',
      );
      expect(free.rateLabel, 'Free');
      expect(free.isFree, isTrue);
    });
  });

  group('the settlement wording', () {
    // Worded once, in one place, because six screens restating it is six
    // chances for one to drift into an implied guarantee.
    test('names who actually holds the money', () {
      for (final copy in [FeeSettlement.entry, FeeSettlement.ground]) {
        expect(copy.toLowerCase(), contains('playsphere does not collect'));
      }
      expect(FeeSettlement.entry.toLowerCase(), contains('organiser'));
      expect(FeeSettlement.ground.toLowerCase(), contains('ground'));
    });

    test('promises nothing about safety', () {
      // PlaySphere cannot verify the organizer, so it must not imply the
      // payment is protected. "Pay safely at the venue" would be a guarantee
      // the product has no mechanism to honour.
      const forbidden = ['safe', 'secure', 'guarantee', 'protected', 'refund'];
      final all = [
        FeeSettlement.entry,
        FeeSettlement.entryShort,
        FeeSettlement.ground,
        FeeSettlement.groundShort,
        FeeSettlement.organiserHelper,
      ].join(' ').toLowerCase();

      for (final word in forbidden) {
        expect(
          all.contains(word),
          isFalse,
          reason: '"$word" implies protection PlaySphere cannot provide while '
              'organisers are unverified.',
        );
      }
    });

    test('tells the organizer they are the one collecting', () {
      expect(
        FeeSettlement.organiserHelper.toLowerCase(),
        contains('collected by you'),
      );
      expect(FeeSettlement.organiserHelper, contains('0'));
    });
  });
}
