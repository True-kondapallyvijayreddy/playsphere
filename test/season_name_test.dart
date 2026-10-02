import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/tournament.dart';
import 'package:playsphere/core/models/tournament_invite.dart';
import 'package:playsphere/domain/tournament/season_name.dart';

/// Names and invitation fields are checked by the app against the same
/// numbers `firestore.rules` enforces. A season is created without waiting on
/// the server, so a limit only the rules knew about made a season vanish after
/// the organizer had already landed on its page.
void main() {
  Tournament season(String id, String name,
          {TournamentStatus status = TournamentStatus.entriesOpen}) =>
      Tournament(id: id, orgId: 'org1', name: name, status: status);

  group('SeasonName', () {
    test('a normal name is fine', () {
      expect(SeasonName.problem('Nizampet Sports Week 2026'), isNull);
    });

    test('too short and too long are refused', () {
      expect(SeasonName.problem('  ab '), contains('at least 3'));
      expect(SeasonName.problem('x' * 120), isNull);
      expect(SeasonName.problem('x' * 121), contains('120'));
    });

    test('the limit is measured on the name as stored', () {
      // Spaces a user pasted in do not count against them.
      expect(SeasonName.problem('  ${'x' * 60}     ${'y' * 59}  '), isNull);
      expect(SeasonName.normalize('  Sports   Week \n 2026 '), 'Sports Week 2026');
    });

    test('a name another live season of the club holds is refused', () {
      final taken = SeasonName.takenKeys([season('s1', 'Sports Week 2026')]);
      expect(
        SeasonName.problem('  sports   WEEK 2026', taken: taken),
        contains('already has'),
      );
      expect(SeasonName.problem('Sports Week 2027', taken: taken), isNull);
    });

    test('the season being renamed and cancelled seasons do not count', () {
      final seasons = [
        season('s1', 'Sports Week 2026'),
        season('s2', 'Monsoon Cup', status: TournamentStatus.cancelled),
      ];
      final taken = SeasonName.takenKeys(seasons, exceptId: 's1');
      expect(SeasonName.problem('Sports Week 2026', taken: taken), isNull);
      expect(SeasonName.problem('Monsoon Cup', taken: taken), isNull);
    });
  });

  group('TournamentInvite limits', () {
    test('a long place is fitted at a word, under the rule', () {
      final place = List.filled(40, 'Ground').join(' ');
      final fitted = TournamentInvite.fit(place, TournamentInvite.maxPlaceLength)!;
      expect(fitted.length, lessThanOrEqualTo(TournamentInvite.maxPlaceLength));
      expect(fitted, endsWith('…'));
      expect(fitted, isNot(contains('Groun…')));
    });

    test('a short place is left alone and blank is null', () {
      expect(TournamentInvite.fit(' Adibatla ', 200), 'Adibatla');
      expect(TournamentInvite.fit('   ', 200), isNull);
    });

    test('more sports than an invitation carries say how many more', () {
      final names = [for (var i = 0; i < 36; i++) 'Sport $i', 'Sport 1'];
      final fitted = TournamentInvite.fitSportNames(names);
      expect(fitted.length, TournamentInvite.maxSportNames);
      expect(fitted.last, 'and 7 more');
    });
  });

  group('editing a season whose name predates the rules', () {
    test('an unchanged name is not a rename, whatever its case or spacing',
        () {
      expect(SeasonName.isRename('Sports Week 2026', 'sports  week 2026'),
          isFalse);
      expect(SeasonName.isRename('U9', 'U9'), isFalse);
      expect(SeasonName.isRename('U9', 'U9 Cup'), isTrue);
    });

    test('an untouched old name is stored exactly as it was', () {
      expect(SeasonName.toStore('U9  Cup', 'U9 Cup'), 'U9  Cup');
      expect(SeasonName.toStore('Sports week', 'Sports Week'), 'Sports Week');
      expect(SeasonName.toStore('Old', '  New   name '), 'New name');
    });
  });
}
