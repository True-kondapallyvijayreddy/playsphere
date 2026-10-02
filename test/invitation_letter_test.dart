import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/tournament.dart';
import 'package:playsphere/core/models/tournament_invite.dart';
import 'package:playsphere/domain/tournament/invitation_letter.dart';

void main() {
  group('InvitationLetter.compose', () {
    test('writes the letter the organizer asked for', () {
      final letter = InvitationLetter.compose(
        hostClubName: 'XYZ Sports Club',
        seasonName: 'Summer Games 2026',
        kind: SeasonKind.season,
        sports: const ['Cricket', 'Table Tennis', 'Cricket', 'Badminton'],
        startDate: DateTime(2026, 8, 12),
        endDate: DateTime(2026, 8, 24),
        place: 'Adibatla, Hyderabad',
      );
      expect(
        letter,
        'Dear sports enthusiasts,\n\n'
        'We from XYZ Sports Club are conducting Summer Games 2026 — a season '
        'for Cricket, Table Tennis and Badminton — from 12 Aug to 24 Aug 2026 '
        'at Adibatla, Hyderabad.\n\n'
        'Please participate. Register your club using the link below.',
      );
    });

    test('calls a one-sport tournament a tournament', () {
      final letter = InvitationLetter.compose(
        hostClubName: 'XYZ',
        seasonName: 'Open Championship',
        kind: SeasonKind.tournament,
        sports: const ['Badminton'],
      );
      expect(letter, contains('Open Championship — a tournament for Badminton.'));
    });

    test('drops the clauses it has no facts for', () {
      final letter = InvitationLetter.compose(
        hostClubName: 'XYZ',
        seasonName: 'Sports Week',
        kind: SeasonKind.season,
      );
      expect(letter, contains('We from XYZ are conducting Sports Week — a season.'));
      expect(letter, isNot(contains('null')));
      expect(letter, isNot(contains(' at ')));
    });
  });

  group('InvitationLetter.dateSpan', () {
    test('one day', () {
      expect(
        InvitationLetter.dateSpan(DateTime(2026, 8, 12), DateTime(2026, 8, 12)),
        'on 12 Aug 2026',
      );
    });

    test('across a new year writes both years', () {
      expect(
        InvitationLetter.dateSpan(DateTime(2026, 12, 28), DateTime(2027, 1, 3)),
        'from 28 Dec 2026 to 3 Jan 2027',
      );
    });

    test('no start, no span', () {
      expect(InvitationLetter.dateSpan(null, DateTime(2026)), '');
    });
  });

  test('shareText puts the registration link on its own line', () {
    expect(
      InvitationLetter.shareText(
        letter: 'Dear sports enthusiasts,\n\nCome.\n',
        registrationUrl: 'https://playsphere-os.web.app/org/o/tournaments/t/register',
      ),
      'Dear sports enthusiasts,\n\nCome.\n\n'
      'Register here: https://playsphere-os.web.app/org/o/tournaments/t/register',
    );
  });

  test('the invitation id stays the shape the rules reach it by', () {
    expect(
      TournamentInvite.idFor(fromOrgId: 'a', tournamentId: 't', toOrgId: 'b'),
      'a_t_b',
    );
  });

  test('a season document without a kind is a season', () {
    expect(SeasonKind.fromWire(null), SeasonKind.season);
    expect(SeasonKind.fromWire('tournament'), SeasonKind.tournament);
  });
}
