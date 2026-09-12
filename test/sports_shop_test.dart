import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/sports_shop.dart';

/// The shop directory is only as useful as its filters, and every one of them
/// depends on what `toUpdate` actually writes.
void main() {
  const shop = SportsShop(
    uid: 'u1',
    shopName: 'Nalgonda Sports House',
    stocks: [ShopStock.equipment, ShopStock.footwear],
    services: [ShopService.clubOrders, ShopService.stringing],
    sportIds: ['cricket'],
    city: 'Nalgonda',
    district: 'Nalgonda',
    contactPhone: '9000000000',
  );

  group('what a save writes', () {
    test('city and district are mirrored lowercase for the filters', () {
      // Firestore equality is case-sensitive, so a club typing "nalgonda" and
      // one typing "Nalgonda" must reach the same shops — the same mirror the
      // ground, need and official listings already use.
      final map = shop.toUpdate();
      expect(map['cityKey'], 'nalgonda');
      expect(map['districtKey'], 'nalgonda');
      expect(map['city'], 'Nalgonda');
    });

    test('search tokens are recomputed on every write, not stored input', () {
      // A listing edited to add a service has to become findable by it in the
      // same save. Reading the array back off the document instead would let
      // the stored tokens drift from the listing they describe.
      final tokens = (shop.toUpdate()['searchTokens']! as List).cast<String>();
      expect(tokens, contains('nalgonda'));
      expect(tokens, contains('cricket'));
      // From ShopService.clubOrders.label — "Bulk & club orders".
      expect(tokens, contains('bulk'));
    });

    test('a create is unverified and nothing else claims otherwise', () {
      // isVerified is PlaySphere's judgement and the rules refuse a create
      // that says anything else. Asserted here too so a later tidy-up of the
      // map cannot quietly drop it and leave only the rule.
      expect(shop.toCreate()['isVerified'], false);
    });

    test('an owner edit never carries isVerified', () {
      // `saveMyShop` sends toUpdate() through `update`, and the rule requires
      // the field unchanged. Including it would make every ordinary edit fail
      // for a shop PlaySphere had verified.
      expect(shop.toUpdate().containsKey('isVerified'), isFalse);
    });
  });

  group('an empty sport list means all sports', () {
    test('a general shop stocks for every sport', () {
      // The opposite of CoachProfile, and on purpose: a general sports shop
      // really does sell a shuttle and a football, and hiding it from a
      // badminton search would withhold the right answer on a technicality.
      const general = SportsShop(
        uid: 'u2',
        shopName: 'City Sports',
        city: 'Warangal',
      );
      expect(general.stocksFor('badminton'), isTrue);
      expect(general.stocksFor('cricket'), isTrue);
    });

    test('a specialist only stocks what it listed', () {
      expect(shop.stocksFor('cricket'), isTrue);
      expect(shop.stocksFor('badminton'), isFalse);
    });
  });

  group('a listing always has something to sell', () {
    test('a document with no stocks reads as equipment, not empty', () {
      // An empty stock list would render a row somebody taps and cannot act
      // on, and would sort out of every filter. Degrading to the most common
      // answer keeps a half-written document useful.
      final parsed = SportsShop.fromMap('u3', const {
        'shopName': 'Corner Sports',
        'city': 'Khammam',
        'stocks': <String>[],
      });
      expect(parsed.stocks, [ShopStock.equipment]);
    });

    test('an unknown stock value is dropped rather than crashing', () {
      final parsed = SportsShop.fromMap('u4', const {
        'shopName': 'Corner Sports',
        'city': 'Khammam',
        'stocks': ['footwear', 'time_machines'],
      });
      expect(parsed.stocks, [ShopStock.footwear]);
    });
  });
}
