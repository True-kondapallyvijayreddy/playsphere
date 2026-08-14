import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/team.dart';

/// The Team entity.
///
/// The product rule this exists to satisfy is Rule 4 — *a team is independent
/// of club* — and the invariant that keeps that rule honest is the pairing
/// between [TeamType] and `clubId`. If those two can drift, "independent
/// team" stops meaning anything: a squad with no club could be typed
/// `permanent` and a club's squad could be typed `independent`, and every
/// screen that asks "does this team belong to anyone" gets a different answer
/// depending on which field it read.
Team makeTeam({
  String name = 'Hyderabad Strikers',
  String sportId = 'cricket',
  TeamType type = TeamType.independent,
  String createdByUid = 'u1',
  String? clubId,
  String? competitionId,
  List<String> memberUids = const ['u1'],
}) =>
    Team(
      id: 't1',
      name: name,
      sportId: sportId,
      type: type,
      createdByUid: createdByUid,
      clubId: clubId,
      competitionId: competitionId,
      memberUids: memberUids,
    );

void main() {
  group('type and club must agree', () {
    test('an independent team with no club is valid', () {
      expect(makeTeam().validationError, isNull);
    });

    test('a permanent team must name a club', () {
      final t = makeTeam(type: TeamType.permanent);
      expect(t.validationError, 'A club team must belong to a club.');
    });

    test('an independent team may not name a club', () {
      // The inverse matters as much as the forward case. Without it a club's
      // squad could be typed `independent` and would then be editable by
      // anyone, since the rules only consult a club admin when clubId is set.
      final t = makeTeam(clubId: 'org1');
      expect(t.validationError, 'An independent team cannot belong to a club.');
    });

    test('a permanent team with a club is valid', () {
      final t = makeTeam(type: TeamType.permanent, clubId: 'org1');
      expect(t.validationError, isNull);
    });
  });

  group('event teams are competition-scoped', () {
    test('an event team must say which competition it was raised for', () {
      final t = makeTeam(type: TeamType.event);
      expect(
        t.validationError,
        'An event team must name the competition it was created for.',
      );
    });

    test('an event team may be club-backed or club-less', () {
      // §21 raises an event team from a club's member pool; a group of
      // friends entering a one-off tournament is the same shape without the
      // club. Both have to be expressible.
      expect(
        makeTeam(type: TeamType.event, competitionId: 'c1').validationError,
        isNull,
      );
      expect(
        makeTeam(type: TeamType.event, competitionId: 'c1', clubId: 'org1')
            .validationError,
        isNull,
      );
    });

    test('a lasting team may not be pinned to one competition', () {
      final t = makeTeam(competitionId: 'c1');
      expect(
        t.validationError,
        'Only an event team belongs to a single competition.',
      );
    });
  });

  group('promotion (§21 — an event team need not stay one)', () {
    test('a club-less event team promotes to independent', () {
      final promoted =
          makeTeam(type: TeamType.event, competitionId: 'c1')
              .promotedToPersistent();
      expect(promoted.type, TeamType.independent);
      expect(promoted.competitionId, isNull);
      expect(promoted.validationError, isNull);
    });

    test('a club-backed event team promotes to permanent', () {
      final promoted = makeTeam(
        type: TeamType.event,
        competitionId: 'c1',
        clubId: 'org1',
      ).promotedToPersistent();
      expect(promoted.type, TeamType.permanent);
      expect(promoted.clubId, 'org1');
      expect(promoted.validationError, isNull);
    });

    test('promotion never produces a document that cannot be saved', () {
      // The invariant is the point: picking `permanent` for a club-less team
      // would fail validation, so the choice has to depend on the club.
      for (final clubId in [null, 'org1']) {
        final promoted = makeTeam(
          type: TeamType.event,
          competitionId: 'c1',
          clubId: clubId,
        ).promotedToPersistent();
        expect(promoted.validationError, isNull, reason: 'clubId=$clubId');
      }
    });
  });

  group('roster', () {
    test('a duplicated player is rejected', () {
      // A double-counted player breaks every squad-size check and any
      // statistic derived from the list.
      final t = makeTeam(memberUids: ['u1', 'u2', 'u1']);
      expect(t.validationError, 'That player is already in this team.');
    });

    test('involvedUids covers a manager who does not play', () {
      const t = Team(
        id: 't1',
        name: 'Warriors',
        sportId: 'cricket',
        type: TeamType.independent,
        createdByUid: 'owner',
        captainUid: 'cap',
        managerUid: 'mgr',
        memberUids: ['cap', 'p2'],
      );
      expect(t.involvedUids, {'owner', 'cap', 'mgr', 'p2'});
      expect(t.memberUids.contains('mgr'), isFalse);
    });
  });

  group('names and other required fields', () {
    test('a blank name is rejected, including whitespace only', () {
      expect(makeTeam(name: '').validationError, 'A team needs a name.');
      expect(makeTeam(name: '   ').validationError, 'A team needs a name.');
    });

    test('a team needs a sport', () {
      expect(makeTeam(sportId: '').validationError, 'A team needs a sport.');
    });
  });

  group('wire round-trip', () {
    test('a created team reads back as itself', () {
      const t = Team(
        id: 'ignored',
        name: '  Warriors A  ',
        sportId: 'cricket',
        type: TeamType.event,
        createdByUid: 'owner',
        clubId: 'org1',
        captainUid: 'cap',
        managerUid: 'mgr',
        memberUids: ['cap', 'p2'],
        competitionId: 'comp1',
        baseTeamId: 'baseTeam',
        homeArea: 'Gachibowli',
      );
      final wire = t.toCreate();
      final back = Team.fromDoc(
        // createdAt is a server sentinel on write and a timestamp on read;
        // dropping it here is what the server does, not a shortcut.
        Map<String, dynamic>.from(wire)..remove('createdAt'),
        'newId',
      );

      expect(back.id, 'newId');
      expect(back.name, 'Warriors A', reason: 'name is trimmed on write');
      expect(back.type, TeamType.event);
      expect(back.clubId, 'org1');
      expect(back.captainUid, 'cap');
      expect(back.managerUid, 'mgr');
      expect(back.memberUids, ['cap', 'p2']);
      expect(back.competitionId, 'comp1');
      expect(back.baseTeamId, 'baseTeam');
      expect(back.homeArea, 'Gachibowli');
    });

    test('an unreadable type falls back to independent, not permanent', () {
      // The fallback must never invent a club affiliation, because
      // affiliation is what decides who may edit the document.
      expect(TeamType.fromWire('nonsense'), TeamType.independent);
      expect(TeamType.fromWire(null), TeamType.independent);
    });

    test('a missing status reads as active', () {
      final back = Team.fromDoc(const {'name': 'X', 'sportId': 'cricket'}, 'i');
      expect(back.status, TeamStatus.active);
    });
  });

  group('lifecycle flags', () {
    test('only event teams are transient', () {
      expect(TeamType.permanent.isPersistent, isTrue);
      expect(TeamType.independent.isPersistent, isTrue);
      expect(TeamType.event.isPersistent, isFalse);
    });

    test('an archived team is not selectable but is still readable', () {
      final t = makeTeam().copyWith(status: TeamStatus.archived);
      expect(t.isSelectable, isFalse);
      // Rule 31: the document itself survives, which is why there is no
      // delete path anywhere in the repository or the rules.
      expect(t.name, 'Hyderabad Strikers');
    });
  });
}
