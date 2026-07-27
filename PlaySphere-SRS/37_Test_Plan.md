# 37 Test Plan Specification

## Purpose
The PlaySphere Test Plan outlines the testing strategy, automation framework, unit test requirements, UI widget tests, and integration test flows required to ensure high quality across Web and Mobile targets.

## Test Strategy & Coverage Targets
- **Unit Tests:** > 80% coverage on Domain Entities, Services (Rating Calculation, Team Formation, Standings Recompute), and State Stores.
- **Widget Tests:** Test all critical UI screens (`OrganizationHomeScreen`, `LiveDashboardScreen`, `MemberProfileScreen`, `TalentDiscoveryScreen`).
- **Integration Tests:** End-to-end user navigation flows using `flutter_test` and `integration_test`.

## Unit Test Matrix
1. **Rating Calculation Engine (`rating_service_test.dart`):**
   - Verify `expectedScore` formula matches `1 / (1 + 10^((RB-RA)/400))`.
   - Verify K-factor calculation based on `RatingStatus` and `VerificationTier`.
   - Test draw handling (`actualScore = 0.5`).
2. **Team Formation Engine (`team_formation_service_test.dart`):**
   - Test `random` shuffle bucket distribution.
   - Test `aiBalanced` greedy snake draft for rating variance minimization.
   - Test `houseWise` and `departmentWise` tag grouping.
3. **Scoring Plugins (`scoring_plugins_test.dart`):**
   - Test event replay immutability and undo capability for Cricket, Chess, Badminton, and Football.

## Automated Command Execution
- Run unit and widget tests: `flutter test`
- Run static code analysis: `flutter analyze`
- Run integration tests: `flutter test integration_test/app_test.dart`

## Acceptance Benchmarks
- Zero analyzer errors or warnings (`flutter analyze` passes clean).
- All unit and widget test suites execute with 100% pass rate.\n