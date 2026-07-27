import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/domain/domain.dart';

void main() {
  group('Elo Rating Calculation Service Tests', () {
    const ratingService = DefaultRatingCalculationService();

    test('expectedScore gives equal chance for equal ratings', () {
      final exp = ratingService.expectedScore(ratingA: 1200, ratingB: 1200);
      expect(exp, closeTo(0.5, 0.001));
    });

    test('expectedScore gives ~76% chance for +200 rating advantage', () {
      final exp = ratingService.expectedScore(ratingA: 1400, ratingB: 1200);
      expect(exp, closeTo(0.7597, 0.001));
    });

    test('newRating updates properly after a win', () {
      final exp = ratingService.expectedScore(ratingA: 1400, ratingB: 1200);
      final newR = ratingService.newRating(
        ratingA: 1400,
        kFactor: 20,
        actualResult: 1.0,
        expected: exp,
      );
      expect(newR, closeTo(1404.8, 0.1));
    });

    test('kFactorFor returns correct factors per tier', () {
      expect(
        ratingService.kFactorFor(
          ratingStatus: RatingStatus.provisional,
          verificationTier: VerificationTier.casual,
        ),
        equals(32.0),
      );
      expect(
        ratingService.kFactorFor(
          ratingStatus: RatingStatus.established,
          verificationTier: VerificationTier.sanctioned,
        ),
        equals(16.0),
      );
    });

    test('isImplausibleSwing flags swings over 80 points', () {
      expect(ratingService.isImplausibleSwing(ratingBefore: 1200, ratingAfter: 1290), isTrue);
      expect(ratingService.isImplausibleSwing(ratingBefore: 1200, ratingAfter: 1250), isFalse);
    });
  });

  group('AI Team Formation Engine Tests', () {
    const engine = PlaySphereTeamFormationEngine();

    const competition = SportCompetitionEntity(
      id: 'comp-1',
      seasonId: 'season-1',
      sportId: 'tt',
      name: 'TT League',
      entrantType: EntrantType.individual,
      format: CompetitionFormat.leagueTable,
      pointsConfigId: 'pc1',
      status: SportCompetitionStatus.open,
    );

    final registrants = [
      const RegistrantWithRating(
        registration: RegistrationEntity(
          id: 'r1',
          sportCompetitionId: 'comp-1',
          playerProfileId: 'p1',
          registeredByUserId: 'u1',
          status: RegistrationStatus.confirmed,
        ),
        playerProfileId: 'p1',
        displayName: 'Player 1',
        rating: 1800,
      ),
      const RegistrantWithRating(
        registration: RegistrationEntity(
          id: 'r2',
          sportCompetitionId: 'comp-1',
          playerProfileId: 'p2',
          registeredByUserId: 'u2',
          status: RegistrationStatus.confirmed,
        ),
        playerProfileId: 'p2',
        displayName: 'Player 2',
        rating: 1700,
      ),
      const RegistrantWithRating(
        registration: RegistrationEntity(
          id: 'r3',
          sportCompetitionId: 'comp-1',
          playerProfileId: 'p3',
          registeredByUserId: 'u3',
          status: RegistrationStatus.confirmed,
        ),
        playerProfileId: 'p3',
        displayName: 'Player 3',
        rating: 1300,
      ),
      const RegistrantWithRating(
        registration: RegistrationEntity(
          id: 'r4',
          sportCompetitionId: 'comp-1',
          playerProfileId: 'p4',
          registeredByUserId: 'u4',
          status: RegistrationStatus.confirmed,
        ),
        playerProfileId: 'p4',
        displayName: 'Player 4',
        rating: 1200,
      ),
    ];

    test('aiBalanced strategy minimizes rating variance across 2 teams', () {
      final teams = engine.formTeams(
        competition: competition,
        strategyType: TeamFormationStrategyType.aiBalanced,
        registrants: registrants,
        teamCount: 2,
      );

      expect(teams.length, equals(2));
      expect(teams[0].averageRating, equals(1500.0));
      expect(teams[1].averageRating, equals(1500.0));
    });
  });

  group('Standings Calculator Tests', () {
    const calc = StandingsCalculatorService();
    const pointsConfig = PointsConfigEntity(
      id: 'pc1',
      winPoints: 3.0,
      drawPoints: 1.0,
      lossPoints: 0.0,
      tiebreakerOrder: ['points', 'score_diff'],
    );

    test('computes points and ranks correctly', () {
      final fixtures = [
        FixtureEntity(
          id: 'f1',
          stageId: 'stage-1',
          entrantAId: 'team-A',
          entrantBId: 'team-B',
          status: FixtureStatus.completed,
          isDraw: false,
          resultEntrantId: 'team-A',
          disputeWindowClosesAt: DateTime.now(),
        ),
        FixtureEntity(
          id: 'f2',
          stageId: 'stage-1',
          entrantAId: 'team-A',
          entrantBId: 'team-C',
          status: FixtureStatus.completed,
          isDraw: true,
          disputeWindowClosesAt: DateTime.now(),
        ),
      ];

      final standings = calc.computeStandings(
        stageId: 'stage-1',
        entrantIds: ['team-A', 'team-B', 'team-C'],
        completedFixtures: fixtures,
        pointsConfig: pointsConfig,
      );

      expect(standings.length, equals(3));
      expect(standings[0].entrantId, equals('team-A'));
      expect(standings[0].points, equals(4.0));
      expect(standings[0].rank, equals(1));
    });
  });

  group('Trust & Safety Minor Protection Tests', () {
    const safetyService = PlaySphereTrustSafetyService();

    test('hard locks unverified minor profile visibility to private', () {
      final user = UserEntity(
        id: 'u-minor',
        fullName: 'Minor Player',
        email: 'minor@example.com',
        dateOfBirth: DateTime.now().subtract(const Duration(days: 365 * 14)),
        authProvider: AuthProvider.otp,
        accountStatus: AccountStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      const profile = PlayerProfileEntity(
        id: 'prof-minor',
        userId: 'u-minor',
        displayName: 'Minor Player',
        visibilityDefault: ProfileVisibility.statewide,
      );

      final resolved = safetyService.resolveProfileVisibility(
        user: user,
        profile: profile,
        guardianLinks: const [],
      );

      expect(resolved, equals(ProfileVisibility.private));
    });
  });
}
