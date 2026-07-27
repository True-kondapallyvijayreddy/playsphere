import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/data/firebase_json_service.dart';
import '../domain/domain.dart';

enum PortalRole { admin, participant }

/// Backward compatible legacy models for seamless transition
class AppMember {
  const AppMember({
    required this.id,
    required this.name,
    required this.role,
    required this.rating,
    required this.achievements,
  });

  final String id;
  final String name;
  final PortalRole role;
  final int rating;
  final List<String> achievements;
}

class OrganizationSummary {
  const OrganizationSummary({
    required this.id,
    required this.name,
    required this.tier,
    required this.parentName,
  });

  final String id;
  final String name;
  final String tier;
  final String? parentName;
}

/// Central state store powering PlaySphere (§1-§10).
class PlaySphereStore extends ChangeNotifier {
  PlaySphereStore() {
    _initSeedData();
  }

  // Active state
  PortalRole _activeRole = PortalRole.admin;
  String _activeOrgId = 'maram-homes';

  // Domain Services
  final _ratingService = const DefaultRatingCalculationService();
  final _teamFormationEngine = const PlaySphereTeamFormationEngine();
  final _standingsCalculator = const StandingsCalculatorService();
  final _trustSafetyService = const PlaySphereTrustSafetyService();

  // Primary Data Repositories
  final List<OrganizationEntity> _organizations = [];
  final List<UserEntity> _users = [];
  final List<PlayerProfileEntity> _playerProfiles = [];
  final List<SeasonEntity> _seasons = [];
  final List<SportCompetitionEntity> _competitions = [];
  final List<FixtureEntity> _fixtures = [];
  final Map<String, Map<String, double>> _fixtureScores = {}; // fixtureId -> {entrantId: score}
  final List<StandingEntity> _standings = [];
  final List<RatingRecordEntity> _ratingRecords = [];
  final List<RatingHistoryEntryEntity> _ratingHistory = [];
  final List<AchievementEntity> _achievements = [];
  final List<GuardianLinkEntity> _guardianLinks = [];
  final List<AuctionLotEntity> _auctionLots = [];
  final List<FormedTeamResult> _formedTeams = [];

  // Getters
  PortalRole get role => _activeRole;
  bool get isSignedIn => true; // Skip login enabled by default
  String get activeOrgId => _activeOrgId;
  PlaySphereTrustSafetyService get trustSafetyService => _trustSafetyService;
  UnmodifiableListView<RatingHistoryEntryEntity> get ratingHistory => UnmodifiableListView(_ratingHistory);

  OrganizationEntity get activeOrganization => _organizations.firstWhere(
        (o) => o.id == _activeOrgId,
        orElse: () => _organizations.first,
      );

  OrganizationSummary get organization => OrganizationSummary(
        id: activeOrganization.id,
        name: activeOrganization.name,
        tier: activeOrganization.orgType == OrgType.residentialCommunity
            ? 'Community league'
            : activeOrganization.orgType == OrgType.districtAssociation
                ? 'District Association'
                : 'State Council (Premier League)',
        parentName: activeOrganization.parentOrgId != null
            ? _organizations.firstWhere((o) => o.id == activeOrganization.parentOrgId).name
            : null,
      );

  AppMember get member => _activeRole == PortalRole.admin
      ? const AppMember(
          id: 'admin-1',
          name: 'Ananya Rao',
          role: PortalRole.admin,
          rating: 1420,
          achievements: ['Verified Community Organizer', 'Table Tennis Finalist 2025'],
        )
      : const AppMember(
          id: 'player-1',
          name: 'Aarav Sharma',
          role: PortalRole.participant,
          rating: 1384,
          achievements: ['Table Tennis Champion 2025', 'Cricket Semi-Finalist 2026'],
        );

  UnmodifiableListView<OrganizationEntity> get organizations => UnmodifiableListView(_organizations);
  UnmodifiableListView<SeasonEntity> get seasons => UnmodifiableListView(_seasons);
  UnmodifiableListView<SportCompetitionEntity> get competitions => UnmodifiableListView(_competitions);
  UnmodifiableListView<FixtureEntity> get fixtures => UnmodifiableListView(_fixtures);
  UnmodifiableListView<StandingEntity> get standings => UnmodifiableListView(_standings);
  UnmodifiableListView<PlayerProfileEntity> get playerProfiles => UnmodifiableListView(_playerProfiles);
  UnmodifiableListView<RatingRecordEntity> get ratingRecords => UnmodifiableListView(_ratingRecords);
  UnmodifiableListView<AchievementEntity> get achievements => UnmodifiableListView(_achievements);
  UnmodifiableListView<GuardianLinkEntity> get guardianLinks => UnmodifiableListView(_guardianLinks);
  UnmodifiableListView<AuctionLotEntity> get auctionLots => UnmodifiableListView(_auctionLots);
  UnmodifiableListView<FormedTeamResult> get formedTeams => UnmodifiableListView(_formedTeams);
  UnmodifiableMapView<String, Map<String, double>> get fixtureScores => UnmodifiableMapView(_fixtureScores);

  // Actions

  void toggleRole() {
    _activeRole = _activeRole == PortalRole.admin ? PortalRole.participant : PortalRole.admin;
    notifyListeners();
  }

  void setActiveRole(PortalRole role) {
    _activeRole = role;
    notifyListeners();
  }

  void switchOrganization(String orgId) {
    if (_organizations.any((o) => o.id == orgId)) {
      _activeOrgId = orgId;
      notifyListeners();
    }
  }

  void signIn(PortalRole selectedRole) {
    _activeRole = selectedRole;
    notifyListeners();
  }

  void signOut() {
    _activeRole = PortalRole.participant;
    notifyListeners();
  }

  bool register(String competitionId) {
    final compIndex = _competitions.indexWhere((c) => c.id == competitionId);
    if (compIndex != -1) {
      final comp = _competitions[compIndex];
      if (comp.status == SportCompetitionStatus.open) {
        notifyListeners();
        return true;
      }
    }
    return false;
  }

  void addCompetition({required String name, required String sport}) {
    final compId = 'comp-${DateTime.now().millisecondsSinceEpoch}';
    _competitions.add(
      SportCompetitionEntity(
        id: compId,
        seasonId: 'season-community-2026',
        sportId: sport.toLowerCase().replaceAll(' ', '_'),
        name: name,
        entrantType: EntrantType.individual,
        format: CompetitionFormat.leagueTable,
        pointsConfigId: 'pc-standard',
        status: SportCompetitionStatus.open,
      ),
    );
    notifyListeners();
  }
  void createClub({
    required String id,
    required String name,
    required String description,
    required String district,
    required String inviteCode,
  }) {
    final newOrg = OrganizationEntity(
      id: id,
      name: name,
      slug: id,
      orgType: OrgType.residentialCommunity,
      visibility: OrgVisibility.public,
      creatorUserId: 'admin-1',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      featureFlags: const FeatureFlags(),
    );

    _organizations.add(newOrg);
    _activeOrgId = id;
    _activeRole = PortalRole.admin;
    notifyListeners();

    FirebaseJsonService.saveProductionJsonData({
      'newClubCreated': name,
      'inviteCode': inviteCode,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  void triggerAITeamShuffle(String competitionId, {TeamFormationStrategyType strategy = TeamFormationStrategyType.aiBalanced}) {
    final comp = _competitions.firstWhere((c) => c.id == competitionId, orElse: () => _competitions.first);

    // Mock registrants with rating lookup
    final registrants = _playerProfiles.take(8).map((prof) {
      final ratingRec = _ratingRecords.firstWhere(
        (r) => r.playerProfileId == prof.id,
        orElse: () => RatingRecordEntity(
          id: 'temp',
          playerProfileId: prof.id,
          sportId: comp.sportId,
          currentRating: 1200.0,
          ratingStatus: RatingStatus.provisional,
          lastResultAt: DateTime.now(),
          matchesPlayed: 0,
        ),
      );

      return RegistrantWithRating(
        registration: RegistrationEntity(
          id: 'reg-${prof.id}',
          sportCompetitionId: comp.id,
          playerProfileId: prof.id,
          registeredByUserId: prof.userId,
          status: RegistrationStatus.confirmed,
        ),
        playerProfileId: prof.id,
        displayName: prof.displayName,
        rating: ratingRec.currentRating,
      );
    }).toList();

    _formedTeams.clear();
    _formedTeams.addAll(
      _teamFormationEngine.formTeams(
        competition: comp,
        strategyType: strategy,
        registrants: registrants,
        teamCount: 2,
      ),
    );

    notifyListeners();
  }

  void updateScore(String fixtureId, {required bool home, required int delta}) {
    final fIndex = _fixtures.indexWhere((item) => item.id == fixtureId);
    if (fIndex != -1) {
      final f = _fixtures[fIndex];
      final currentScores = _fixtureScores[fixtureId] ?? {f.entrantAId: 0.0, f.entrantBId: 0.0};
      final targetEntrant = home ? f.entrantAId : f.entrantBId;

      currentScores[targetEntrant] = ((currentScores[targetEntrant] ?? 0.0) + delta).clamp(0.0, 99.0);
      _fixtureScores[fixtureId] = currentScores;

      notifyListeners();
    }
  }

  void finalizeFixture(String fixtureId) {
    final fIndex = _fixtures.indexWhere((item) => item.id == fixtureId);
    if (fIndex != -1) {
      final f = _fixtures[fIndex];
      final scores = _fixtureScores[fixtureId] ?? {f.entrantAId: 2.0, f.entrantBId: 1.0};

      final scoreA = scores[f.entrantAId] ?? 0.0;
      final scoreB = scores[f.entrantBId] ?? 0.0;

      final isDraw = scoreA == scoreB;
      final winnerId = isDraw ? null : (scoreA > scoreB ? f.entrantAId : f.entrantBId);

      _fixtures[fIndex] = FixtureEntity(
        id: f.id,
        stageId: f.stageId,
        entrantAId: f.entrantAId,
        entrantBId: f.entrantBId,
        status: FixtureStatus.completed,
        isDraw: isDraw,
        resultEntrantId: winnerId,
        scheduledAt: f.scheduledAt,
        venueId: f.venueId,
        officiatedByUserId: f.officiatedByUserId,
        disputeWindowClosesAt: DateTime.now().add(const Duration(hours: 24)),
        verificationTier: f.verificationTier,
      );

      // Recalculate Elo Ratings
      _applyEloForFixture(f.entrantAId, f.entrantBId, scoreA, scoreB, f.verificationTier);

      // Recompute Standings
      _recomputeStandings(f.stageId);

      notifyListeners();
    }
  }

  void placeAuctionBid(String lotId, String teamId, Paise amount) {
    final lotIndex = _auctionLots.indexWhere((l) => l.id == lotId);
    if (lotIndex != -1) {
      final lot = _auctionLots[lotIndex];
      _auctionLots[lotIndex] = AuctionLotEntity(
        id: lot.id,
        seasonId: lot.seasonId,
        playerProfileId: lot.playerProfileId,
        basePrice: lot.basePrice,
        status: AuctionLotStatus.live,
        winningTeamId: teamId,
        finalPrice: amount,
      );
      notifyListeners();
    }
  }

  // Internal seed initializer
  void _initSeedData() {
    final now = DateTime.now();

    // Orgs
    final stateOrg = OrganizationEntity(
      id: 'telangana-state',
      name: 'Telangana State Sports Council',
      slug: 'telangana-sports',
      orgType: OrgType.stateCouncil,
      visibility: OrgVisibility.public,
      creatorUserId: 'admin-state',
      featureFlags: const FeatureFlags(franchiseLeagues: true, venueMarketplace: true, mediaProduction: true),
      orgVerificationStatus: OrgVerificationStatus.verified,
      createdAt: now,
      updatedAt: now,
    );

    final districtOrg = OrganizationEntity(
      id: 'hyd-district',
      name: 'Hyderabad District Sports Association',
      slug: 'hyd-sports',
      orgType: OrgType.districtAssociation,
      parentOrgId: 'telangana-state',
      visibility: OrgVisibility.public,
      creatorUserId: 'admin-district',
      featureFlags: const FeatureFlags(officiatingRegistry: true),
      orgVerificationStatus: OrgVerificationStatus.verified,
      createdAt: now,
      updatedAt: now,
    );

    final communityOrg = OrganizationEntity(
      id: 'maram-homes',
      name: 'Maram Garlapati Homes',
      slug: 'maram-homes',
      orgType: OrgType.residentialCommunity,
      parentOrgId: 'hyd-district',
      visibility: OrgVisibility.public,
      creatorUserId: 'admin-1',
      featureFlags: const FeatureFlags(),
      orgVerificationStatus: OrgVerificationStatus.unverified,
      createdAt: now,
      updatedAt: now,
    );

    _organizations.addAll([stateOrg, districtOrg, communityOrg]);

    // Users & Player Profiles
    final user1 = UserEntity(
      id: 'player-1',
      fullName: 'Aarav Sharma',
      email: 'aarav@example.com',
      dateOfBirth: DateTime(1998, 5, 12),
      authProvider: AuthProvider.otp,
      accountStatus: AccountStatus.active,
      createdAt: now,
      updatedAt: now,
    );

    final user2 = UserEntity(
      id: 'player-2',
      fullName: 'Riya Sen',
      email: 'riya@example.com',
      dateOfBirth: DateTime(2001, 9, 20),
      authProvider: AuthProvider.otp,
      accountStatus: AccountStatus.active,
      createdAt: now,
      updatedAt: now,
    );

    final userMinor = UserEntity(
      id: 'player-minor',
      fullName: 'Kavya Sharma',
      email: 'kavya.minor@example.com',
      dateOfBirth: DateTime(2012, 3, 15), // 14 years old
      authProvider: AuthProvider.otp,
      accountStatus: AccountStatus.active,
      createdAt: now,
      updatedAt: now,
    );

    _users.addAll([user1, user2, userMinor]);

    const prof1 = PlayerProfileEntity(
      id: 'prof-aarav',
      userId: 'player-1',
      displayName: 'Aarav Sharma',
      primarySportIds: ['tt', 'cricket'],
      visibilityDefault: ProfileVisibility.statewide,
      careerPageSlug: 'aarav-sharma-2026',
    );

    const prof2 = PlayerProfileEntity(
      id: 'prof-riya',
      userId: 'player-2',
      displayName: 'Riya Sen',
      primarySportIds: ['tt', 'badminton'],
      visibilityDefault: ProfileVisibility.community,
      careerPageSlug: 'riya-sen-2026',
    );

    const profMinor = PlayerProfileEntity(
      id: 'prof-kavya',
      userId: 'player-minor',
      displayName: 'Kavya Sharma',
      primarySportIds: ['badminton'],
      visibilityDefault: ProfileVisibility.private,
      careerPageSlug: 'kavya-sharma-minor',
    );

    _playerProfiles.addAll([prof1, prof2, profMinor]);

    // Ratings
    _ratingRecords.addAll([
      RatingRecordEntity(
        id: 'r-aarav-tt',
        playerProfileId: 'prof-aarav',
        sportId: 'tt',
        currentRating: 1420.0,
        ratingStatus: RatingStatus.established,
        lastResultAt: now,
        matchesPlayed: 14,
      ),
      RatingRecordEntity(
        id: 'r-riya-tt',
        playerProfileId: 'prof-riya',
        sportId: 'tt',
        currentRating: 1380.0,
        ratingStatus: RatingStatus.established,
        lastResultAt: now,
        matchesPlayed: 12,
      ),
    ]);

    // Achievements
    _achievements.addAll([
      const AchievementEntity(
        id: 'ach-1',
        playerProfileId: 'prof-aarav',
        sportId: 'tt',
        achievementType: AchievementType.competitionWin,
        description: 'Table Tennis Monsoon Champion · Maram Homes 2025',
        verificationTier: VerificationTier.casual,
      ),
      const AchievementEntity(
        id: 'ach-2',
        playerProfileId: 'prof-aarav',
        sportId: 'cricket',
        achievementType: AchievementType.stageFinish,
        description: 'District Cup Semi-Finalist · Hyderabad District 2026',
        verificationTier: VerificationTier.sanctioned,
      ),
    ]);

    // Guardian Link
    _guardianLinks.add(
      GuardianLinkEntity(
        id: 'g-link-1',
        minorUserId: 'player-minor',
        guardianUserId: 'player-1',
        relationship: GuardianRelationship.parent,
        verificationStatus: GuardianVerificationStatus.verified,
        verificationMethod: GuardianVerificationMethod.orgAdminAttestation,
        verifiedAt: now,
      ),
    );

    // Competitions & Fixtures
    const comp1 = SportCompetitionEntity(
      id: 'tt-2026',
      seasonId: 'season-monsoon-2026',
      sportId: 'tt',
      name: 'Monsoon Table Tennis League',
      entrantType: EntrantType.individual,
      format: CompetitionFormat.leagueTable,
      pointsConfigId: 'pc-standard',
      status: SportCompetitionStatus.inProgress,
    );

    _competitions.add(comp1);

    final f1 = FixtureEntity(
      id: 'f1',
      stageId: 'stage-group-1',
      entrantAId: 'prof-aarav',
      entrantBId: 'prof-riya',
      status: FixtureStatus.live,
      isDraw: false,
      scheduledAt: now,
      venueId: 'Court 1',
      disputeWindowClosesAt: now.add(const Duration(hours: 24)),
      verificationTier: VerificationTier.casual,
    );

    _fixtures.add(f1);
    _fixtureScores['f1'] = {'prof-aarav': 2.0, 'prof-riya': 1.0};

    _recomputeStandings('stage-group-1');

    // Premier League Auction Lots
    _auctionLots.addAll([
      const AuctionLotEntity(
        id: 'lot-1',
        seasonId: 'season-tpl-2026',
        playerProfileId: 'prof-aarav',
        basePrice: 500000, // 5,000 INR
        status: AuctionLotStatus.live,
        winningTeamId: 'Hyderabad Hawks',
        finalPrice: 1200000, // 12,000 INR
      ),
      const AuctionLotEntity(
        id: 'lot-2',
        seasonId: 'season-tpl-2026',
        playerProfileId: 'prof-riya',
        basePrice: 500000,
        status: AuctionLotStatus.upcoming,
      ),
    ]);
  }

  void _applyEloForFixture(String entrantA, String entrantB, double scoreA, double scoreB, VerificationTier tier) {
    final indexA = _ratingRecords.indexWhere((r) => r.playerProfileId == entrantA);
    final indexB = _ratingRecords.indexWhere((r) => r.playerProfileId == entrantB);

    final ratingA = indexA != -1 ? _ratingRecords[indexA].currentRating : 1200.0;
    final ratingB = indexB != -1 ? _ratingRecords[indexB].currentRating : 1200.0;

    final expA = _ratingService.expectedScore(ratingA: ratingA, ratingB: ratingB);
    final expB = 1.0 - expA;

    final actualA = scoreA > scoreB ? 1.0 : (scoreA == scoreB ? 0.5 : 0.0);
    final actualB = 1.0 - actualA;

    final kA = _ratingService.kFactorFor(ratingStatus: RatingStatus.established, verificationTier: tier);
    final kB = _ratingService.kFactorFor(ratingStatus: RatingStatus.established, verificationTier: tier);

    final newA = _ratingService.newRating(ratingA: ratingA, kFactor: kA, actualResult: actualA, expected: expA);
    final newB = _ratingService.newRating(ratingA: ratingB, kFactor: kB, actualResult: actualB, expected: expB);

    if (indexA != -1) {
      _ratingRecords[indexA] = RatingRecordEntity(
        id: _ratingRecords[indexA].id,
        playerProfileId: entrantA,
        sportId: 'tt',
        currentRating: double.parse(newA.toStringAsFixed(1)),
        ratingStatus: RatingStatus.established,
        lastResultAt: DateTime.now(),
        matchesPlayed: _ratingRecords[indexA].matchesPlayed + 1,
      );
    }

    if (indexB != -1) {
      _ratingRecords[indexB] = RatingRecordEntity(
        id: _ratingRecords[indexB].id,
        playerProfileId: entrantB,
        sportId: 'tt',
        currentRating: double.parse(newB.toStringAsFixed(1)),
        ratingStatus: RatingStatus.established,
        lastResultAt: DateTime.now(),
        matchesPlayed: _ratingRecords[indexB].matchesPlayed + 1,
      );
    }
  }

  void _recomputeStandings(String stageId) {
    const pointsConfig = PointsConfigEntity(
      id: 'pc-standard',
      winPoints: 3.0,
      drawPoints: 1.0,
      lossPoints: 0.0,
      tiebreakerOrder: ['points', 'score_diff'],
    );

    final completed = _fixtures.where((f) => f.status == FixtureStatus.completed).toList();
    final entrants = ['prof-aarav', 'prof-riya'];

    _standings.clear();
    _standings.addAll(
      _standingsCalculator.computeStandings(
        stageId: stageId,
        entrantIds: entrants,
        completedFixtures: completed,
        pointsConfig: pointsConfig,
        matchScores: _fixtureScores,
      ),
    );
  }
}

final playSphereStoreProvider = ChangeNotifierProvider<PlaySphereStore>(
  (ref) => PlaySphereStore(),
);
