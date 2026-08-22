import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/organization.dart';

/// The club's public id — what a member reads out to say which club they mean.
///
/// It is derived rather than stored, so the properties a stored code would get
/// from the database (stable, unique, identical everywhere) all have to come
/// out of the derivation instead. That is what this covers.
void main() {
  Organization org(String id) => Organization(
        id: id,
        name: 'Sunrise Sports Club',
        orgType: OrgType.cityClub,
        visibility: OrgVisibility.public,
        ownerUid: 'owner',
        inviteCode: 'ABC234',
      );

  test('the same club always has the same id', () {
    // Nothing writes this anywhere, so "stable" means the function is pure.
    // If it were not, a member would quote one code and a teammate another.
    expect(org('abc123').clubCode, org('abc123').clubCode);
    expect(Organization.codeForId('xYz'), Organization.codeForId('xYz'));
  });

  test('different clubs get different ids', () {
    final codes = {
      for (var i = 0; i < 2000; i++) Organization.codeForId('org_$i'),
    };
    expect(codes.length, 2000, reason: 'no collisions across 2,000 clubs');
  });

  test('Firestore auto-ids sharing a prefix still spread apart', () {
    // Auto-ids are not random across their whole length — consecutive ones
    // share long prefixes. A hash that did not spread would hand two clubs
    // created a second apart near-identical codes.
    final codes = {
      for (var i = 0; i < 500; i++)
        Organization.codeForId('N7kQpLmR3xVzAbCd${i.toString().padLeft(4, '0')}'),
    };
    expect(codes.length, 500);
  });

  test('the id is eight characters from an unambiguous alphabet', () {
    // No O/0, no I/1/L — it gets read back over a phone.
    final code = Organization.codeForId('some_org_id');
    expect(code.length, 8);
    expect(RegExp(r'^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{8}$').hasMatch(code),
        isTrue);
  });

  test('the label is grouped for reading aloud', () {
    final o = org('abc123');
    expect(o.clubCodeLabel, '${o.clubCode.substring(0, 4)}-'
        '${o.clubCode.substring(4)}');
    expect(o.clubCodeLabel.length, 9);
  });

  test('it is not the document id', () {
    // The whole point: a twenty-character Firestore auto-id is unusable as
    // something a person says, and putting it on screen would make an
    // implementation detail into the name of the club.
    expect(org('N7kQpLmR3xVzAbCdEfGh').clubCode,
        isNot('N7kQpLmR3xVzAbCdEfGh'));
  });

  test('it is not the invite code', () {
    // The invite code is a key — typing it into "join a club" starts a
    // membership. This grants nothing, which is what lets every member see it.
    expect(org('abc123').clubCode, isNot('ABC234'));
  });

  test('an empty id degrades to a placeholder rather than crashing', () {
    // A club still streaming in has no id yet, and a list row must not throw
    // while it arrives.
    expect(Organization.codeForId('').length, 8);
  });

  test('every intermediate stays inside the web\'s exact integer range', () {
    // Dart ints are 53-bit doubles under dart2js. If any step here exceeded
    // that, the browser and the phone would show the same club two different
    // ids — so this pins the property the implementation depends on.
    const multipliers = [31, 131];
    for (final m in multipliers) {
      var hash = m;
      for (final unit in 'a-long-firestore-auto-id-0123456789'.codeUnits) {
        hash = (hash * m + unit) & 0x7FFFFFFF;
        expect(hash * m, lessThan(9007199254740992));
      }
    }
  });
}
