import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/permissions/capability.dart';

/// The rules a club's delegation model has to keep, stated as tests so a later
/// change to the matrix cannot quietly hand the treasurer the member roster.
void main() {
  group('portfolios are orthogonal to rank', () {
    test('an admin does not get departmental power by rank alone', () {
      final caps = PermissionMatrix.capabilitiesOf(MembershipRole.admin);
      expect(caps, contains(Capability.manageMembers));
      expect(caps, isNot(contains(Capability.manageFinance)));
      expect(caps, isNot(contains(Capability.manageVenues)));
    });

    test('a plain member can be the treasurer without gaining governance', () {
      final caps = PermissionMatrix.effectiveCapabilities(
        role: MembershipRole.member,
        portfolios: {ClubPortfolio.finance},
      );
      expect(caps, contains(Capability.manageFinance));
      expect(caps, isNot(contains(Capability.manageMembers)));
      expect(caps, isNot(contains(Capability.manageCompetitions)));
      expect(caps, isNot(contains(Capability.manageOrganization)));
    });

    test('no portfolio grants governance', () {
      const governance = {
        Capability.manageOrganization,
        Capability.manageMembers,
        Capability.manageCompetitions,
        Capability.manageRegistrations,
      };
      for (final p in ClubPortfolio.values) {
        expect(
          PermissionMatrix.capabilitiesOfPortfolio(p).intersection(governance),
          isEmpty,
          reason: '${p.wire} must not be a route to running the club',
        );
      }
    });

    test('the officials brief carries the pen', () {
      expect(
        PermissionMatrix.effectiveCapabilities(
          role: MembershipRole.member,
          portfolios: {ClubPortfolio.officials},
        ),
        contains(Capability.scoreMatches),
      );
    });
  });

  group('the owner is the super user', () {
    test('holds every capability, including ones added later', () {
      expect(
        PermissionMatrix.capabilitiesOf(MembershipRole.owner),
        containsAll(Capability.values),
      );
    });

    test('holds every portfolio without one being stored', () {
      expect(
        PermissionMatrix.implicitPortfoliosOf(MembershipRole.owner),
        ClubPortfolio.values.toSet(),
      );
      for (final r in MembershipRole.values) {
        if (r == MembershipRole.owner) continue;
        expect(PermissionMatrix.implicitPortfoliosOf(r), isEmpty);
      }
    });
  });

  group('who may hand out a brief', () {
    test('an owner may hand out every department', () {
      expect(
        PermissionMatrix.portfoliosAssignableBy(
          actorRole: MembershipRole.owner,
        ),
        ClubPortfolio.values.toSet(),
      );
    });

    test('an admin may pass on only what they hold themselves', () {
      final assignable = PermissionMatrix.portfoliosAssignableBy(
        actorRole: MembershipRole.admin,
        actorPortfolios: {ClubPortfolio.grounds},
      );
      expect(assignable, {ClubPortfolio.grounds});
      expect(assignable, isNot(contains(ClubPortfolio.finance)));
    });

    test('an admin with no brief may hand out nothing', () {
      expect(
        PermissionMatrix.portfoliosAssignableBy(
          actorRole: MembershipRole.admin,
        ),
        isEmpty,
      );
    });

    test('somebody who cannot manage members may hand out nothing', () {
      for (final r in [
        MembershipRole.eventManager,
        MembershipRole.judgeScorer,
        MembershipRole.member,
      ]) {
        expect(
          PermissionMatrix.portfoliosAssignableBy(
            actorRole: r,
            // Even holding the brief is not enough without the authority to
            // appoint people at all.
            actorPortfolios: {ClubPortfolio.finance},
          ),
          isEmpty,
          reason: '${r.wire} cannot appoint anybody',
        );
      }
    });
  });

  group('rank promotion is unchanged by portfolios', () {
    test('only an owner may create an admin', () {
      expect(
        PermissionMatrix.assignableBy(MembershipRole.admin),
        isNot(contains(MembershipRole.admin)),
      );
      expect(
        PermissionMatrix.assignableBy(MembershipRole.owner),
        contains(MembershipRole.admin),
      );
    });
  });

  group('wire format', () {
    test('round-trips and drops values it does not know', () {
      final set = ClubPortfolio.setFrom(['finance', 'grounds', 'not_a_thing']);
      expect(set, {ClubPortfolio.finance, ClubPortfolio.grounds});
      expect(ClubPortfolio.wiresOf(set), ['finance', 'grounds']);
    });

    test('wires are sorted so an unchanged set writes an identical array', () {
      expect(
        ClubPortfolio.wiresOf(ClubPortfolio.values.toSet()),
        equals(ClubPortfolio.wiresOf(ClubPortfolio.values.toSet())),
      );
      expect(
        ClubPortfolio.wiresOf({ClubPortfolio.medical, ClubPortfolio.finance}),
        ['finance', 'medical'],
      );
    });
  });
}
