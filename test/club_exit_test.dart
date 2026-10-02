import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/organization.dart';
import 'package:playsphere/domain/governance/club_exit.dart';

/// Leaving a club, and handing it over on the way out.
///
/// The one thing this must never allow is a club with no owner: only an owner
/// can appoint one, so an ownerless club is stuck for good.
void main() {
  Membership m(
    String uid,
    MembershipRole role, {
    String? name,
    MembershipStatus status = MembershipStatus.active,
  }) =>
      Membership(
        uid: uid,
        orgId: 'org',
        role: role,
        status: status,
        displayName: name ?? uid,
      );

  group('path', () {
    test('a member just leaves', () {
      final me = m('me', MembershipRole.admin);
      expect(
        ClubExit.pathFor(me: me, roster: [me, m('o', MembershipRole.owner)]),
        ClubExitPath.leave,
      );
    });

    test('an owner with a co-owner steps down and leaves', () {
      final me = m('me', MembershipRole.owner);
      expect(
        ClubExit.pathFor(me: me, roster: [me, m('o2', MembershipRole.owner)]),
        ClubExitPath.stepDownAndLeave,
      );
    });

    test('a pending or removed owner row is not a co-owner', () {
      final me = m('me', MembershipRole.owner);
      final roster = [
        me,
        m('x', MembershipRole.owner, status: MembershipStatus.removed),
        m('p', MembershipRole.member),
      ];
      expect(
        ClubExit.pathFor(me: me, roster: roster),
        ClubExitPath.handOverAndLeave,
      );
    });

    test('the sole owner must hand the club over', () {
      final me = m('me', MembershipRole.owner);
      expect(
        ClubExit.pathFor(me: me, roster: [me, m('a', MembershipRole.member)]),
        ClubExitPath.handOverAndLeave,
      );
    });

    test('the sole owner and sole member has nobody to hand to', () {
      final me = m('me', MembershipRole.owner);
      final pending = m('p', MembershipRole.member,
          status: MembershipStatus.pending);
      expect(
        ClubExit.pathFor(me: me, roster: [me, pending]),
        ClubExitPath.nobodyToHandTo,
      );
    });
  });

  group('successors', () {
    test('active non-owners only, most senior first, then by name', () {
      final me = m('me', MembershipRole.owner);
      final roster = [
        me,
        m('1', MembershipRole.member, name: 'zara'),
        m('2', MembershipRole.admin, name: 'Priya'),
        m('3', MembershipRole.member, name: 'Arjun'),
        m('4', MembershipRole.owner, name: 'Co-owner'),
        m('5', MembershipRole.eventManager, name: 'Ravi'),
        m('6', MembershipRole.admin, name: 'Pending',
            status: MembershipStatus.pending),
      ];
      expect(
        ClubExit.successorsFor(me: me, roster: roster)
            .map((x) => x.displayName),
        ['Priya', 'Ravi', 'Arjun', 'zara'],
      );
    });
  });
}
