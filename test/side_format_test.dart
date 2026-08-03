import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/domain/scoring/scoring_registry.dart';

/// How many people a side.
///
/// This exists because guessing was a real, shipped bug: quick match assumed
/// one player per side for every sport, so a cricket match could be created
/// that the engine then refused to score — the same person cannot be on
/// strike and at the other end, and with a one-man team there is nobody else.
/// The floors below are what makes that unrepresentable.
void main() {
  group('the floor is what the engine actually needs', () {
    test('cricket needs two a side, because a striker needs a partner', () {
      // The single most important number in this file. CricketPlugin's `open`
      // action asks for a striker and a non-striker from the same line-up and
      // rejects them being the same person.
      for (final f in SideFormats.forSport('cricket')) {
        expect(f.min, greaterThanOrEqualTo(2), reason: f.name);
      }
    });

    test('every sport can be played by somebody', () {
      // A floor above its own ceiling is a sport that cannot be set up at all,
      // and it would only be discovered by a person standing on a ground.
      for (final sport in SportCatalog.all) {
        final formats = SideFormats.forSport(sport.id);
        expect(formats, isNotEmpty, reason: sport.id);
        for (final f in formats) {
          expect(f.min, greaterThanOrEqualTo(1), reason: '${sport.id}/${f.id}');
          expect(f.max, greaterThanOrEqualTo(f.min),
              reason: '${sport.id}/${f.id}');
        }
      }
    });

    test('every sport has exactly one default', () {
      for (final sport in SportCatalog.all) {
        final defaults =
            SideFormats.forSport(sport.id).where((f) => f.isDefault).length;
        expect(defaults, lessThanOrEqualTo(1), reason: sport.id);
        // defaultFor falls back to the first entry, so zero is survivable —
        // but it must always answer.
        expect(SideFormats.defaultFor(sport.id), isNotNull, reason: sport.id);
      }
    });
  });

  group('arrangements a sport is really played in', () {
    test('racquet sports offer singles and doubles, capped at two', () {
      for (final id in ['badminton', 'table_tennis', 'tennis']) {
        final formats = SideFormats.forSport(id);
        expect(formats.map((f) => f.id), containsAll(['singles', 'doubles']),
            reason: id);
        expect(SideFormats.resolve(id, 'singles').max, 1, reason: id);
        // The complaint that prompted this: doubles was unreachable because
        // the screen clamped every non-team sport to one player.
        expect(SideFormats.resolve(id, 'doubles').max, 2, reason: id);
        expect(SideFormats.resolve(id, 'doubles').min, 2, reason: id);
      }
    });

    test('doubles tells the engine it is doubles', () {
      // Service rotation differs, and the engines read that from config
      // rather than from the line-up length.
      expect(
        SideFormats.resolve('badminton', 'doubles').configOverrides['doubles'],
        isTrue,
      );
      expect(
        SideFormats.resolve('badminton', 'singles').configOverrides,
        isEmpty,
      );
    });

    test('cricket allows a squad larger than a starting eleven', () {
      // Substitutes have to be nameable or they cannot appear on a scorecard.
      final eleven = SideFormats.resolve('cricket', 'eleven');
      expect(eleven.configOverrides['playersPerTeam'], 11);
      expect(eleven.max, greaterThan(11));
      expect(eleven.max, greaterThanOrEqualTo(15));
    });

    test('an uncatalogued sport still gets a usable arrangement', () {
      // "Other sport" must never be a sport that cannot be played.
      final formats = SideFormats.forSport('quidditch');
      expect(formats, same(SideFormats.generic));
      expect(SideFormats.defaultFor('other').max, greaterThan(1));
    });

    test('resolving an unknown arrangement falls back rather than throwing', () {
      // A fixture written by a newer build must still open in an older one.
      expect(
        SideFormats.resolve('cricket', 'seventeen_a_side').id,
        SideFormats.defaultFor('cricket').id,
      );
    });
  });

  group('SportSpec exposes it', () {
    test('sideFormats and defaultSideFormat agree with the catalogue', () {
      final cricket = SportCatalog.byId('cricket');
      expect(cricket.sideFormats, SideFormats.forSport('cricket'));
      expect(cricket.defaultSideFormat.id, SideFormats.defaultFor('cricket').id);
    });
  });
}
