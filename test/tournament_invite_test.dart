import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/core/models/organization.dart';
import 'package:playsphere/core/models/tournament.dart';
import 'package:playsphere/core/models/tournament_invite.dart';
import 'package:playsphere/core/models/venue.dart';
import 'package:playsphere/core/permissions/capability.dart';
import 'package:playsphere/core/providers.dart';
import 'package:playsphere/features/tournaments/tournament_detail_screen.dart';

/// Cross-club invitations, and the tournament screen that offers them.
void main() {
  const hostOrg = 'org_host';
  const guestOrg = 'org_guest';
  const tournamentId = 'tour_1';

  TournamentInvite invite({String status = 'pending'}) => TournamentInvite(
        id: 'inv1',
        tournamentId: tournamentId,
        tournamentName: 'District Championship',
        fromOrgId: hostOrg,
        fromOrgName: 'Host Club',
        toOrgId: guestOrg,
        toOrgName: 'Guest Club',
        status: status,
      );

  group('who may do what to an invitation', () {
    test('the host may take back an offer nobody has answered', () {
      expect(invite().canBeWithdrawnBy(hostOrg), isTrue);
    });

    test('the host may not take back one the club has accepted', () {
      // By then the guest club has a date in its calendar on the strength of
      // it. Unpicking that is a conversation, not a button — the same
      // asymmetry a challenge draws between declining and withdrawing.
      expect(invite(status: 'accepted').canBeWithdrawnBy(hostOrg), isFalse);
    });

    test('the invited club may not withdraw an invitation against itself', () {
      // Its answer is 'declined'. It does not get to rewrite the record as
      // the other side having backed out.
      expect(invite().canBeWithdrawnBy(guestOrg), isFalse);
      expect(invite().isIncomingFor(guestOrg), isTrue);
      expect(invite().isIncomingFor(hostOrg), isFalse);
    });
  });

  group('one row, read from either side', () {
    test('each club sees the OTHER club named', () {
      expect(invite().otherNameFor(hostOrg), 'Guest Club');
      expect(invite().otherNameFor(guestOrg), 'Host Club');
    });
  });

  // -------------------------------------------------------------------------
  // The bug in the screenshot: a season with five sports in it rendered as
  // one error card and nothing else, because the matches feed needed a
  // composite index that did not exist. The index is the fix; this pins the
  // behaviour that made a missing index cost the whole page.
  // -------------------------------------------------------------------------
  group('the tournament screen when the matches feed is down', () {
    const tournament = Tournament(
      id: tournamentId,
      orgId: hostOrg,
      name: 'Maram 2026 Sports Season',
      status: TournamentStatus.draft,
    );

    const event = Competition(
      id: 'c1',
      orgId: hostOrg,
      tournamentId: tournamentId,
      name: 'Maram 2026 — Kabaddi',
      sportId: 'kabaddi',
      sportName: 'Kabaddi',
      archetype: CompetitionArchetype.versus,
      entrantType: EntrantType.team,
      format: CompetitionFormat.roundRobin,
      status: CompetitionStatus.draft,
      category: CompetitionCategory(label: 'Open'),
      scoringPluginKey: 'kabaddi',
    );

    Widget harness() {
      final router = GoRouter(
        initialLocation: '/org/$hostOrg/tournaments/$tournamentId',
        routes: [
          GoRoute(
            path: '/org/:orgId/tournaments/:tournamentId',
            builder: (_, state) => TournamentDetailScreen(
              orgId: state.pathParameters['orgId']!,
              tournamentId: state.pathParameters['tournamentId']!,
            ),
          ),
        ],
      );

      return ProviderScope(
        overrides: [
          currentUidProvider.overrideWithValue('uid_owner'),
          organizationProvider.overrideWith(
            (ref, id) => Stream.value(const Organization(
              id: hostOrg,
              name: 'Host Club',
              orgType: OrgType.school,
              visibility: OrgVisibility.public,
              ownerUid: 'uid_owner',
              inviteCode: 'ABC234',
            )),
          ),
          myCapabilitiesProvider.overrideWith(
            (ref, id) => PermissionMatrix.capabilitiesOf(MembershipRole.owner),
          ),
          venuesProvider.overrideWith((ref, id) => Stream.value(const <Venue>[])),
          tournamentProvider.overrideWith((ref, key) => Stream.value(tournament)),
          tournamentEventsProvider.overrideWith(
            (ref, key) => Stream.value(const [event]),
          ),
          // The failure under test: exactly what a missing composite index
          // looks like to the client.
          tournamentFixturesProvider.overrideWith(
            (ref, key) => Stream<List<Fixture>>.error(
              Exception('The query requires an index'),
            ),
          ),
          tournamentInvitesProvider.overrideWith(
            (ref, key) => Stream.value(const <TournamentInvite>[]),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      );
    }

    testWidgets('says the matches are missing without hiding the season',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      // Honest about what failed…
      expect(find.textContaining('Could not load the matches'), findsOneWidget);
      // …and still the tournament. Before the fix this screen was the error
      // card alone.
      expect(find.text('Maram 2026 Sports Season'), findsOneWidget);
      expect(find.text('Maram 2026 — Kabaddi'), findsOneWidget);
      expect(find.text('No events yet'), findsNothing);
    });

    testWidgets('offers the organizer the cross-club invite', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      expect(
        find.byTooltip('Invite other clubs'),
        findsOneWidget,
        reason: 'the public link broadcasts; this is how named clubs are asked',
      );
      expect(find.byTooltip('Edit'), findsOneWidget);
      expect(find.byTooltip('Share the public link'), findsOneWidget);
    });
  });
}
