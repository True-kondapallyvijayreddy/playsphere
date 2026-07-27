import 'dart:math' as math;

import '../enums.dart';
import '../phase5_rating_achievement.dart';

/// Concrete implementation of [RatingCalculationService] matching §5.2.
class DefaultRatingCalculationService implements RatingCalculationService {
  const DefaultRatingCalculationService();

  @override
  double expectedScore({required double ratingA, required double ratingB}) {
    final exponent = (ratingB - ratingA) / 400.0;
    return 1.0 / (1.0 + math.pow(10, exponent));
  }

  @override
  double newRating({
    required double ratingA,
    required double kFactor,
    required double actualResult,
    required double expected,
  }) {
    final delta = kFactor * (actualResult - expected);
    return ratingA + delta;
  }

  @override
  double kFactorFor({
    required RatingStatus ratingStatus,
    required VerificationTier verificationTier,
  }) {
    if (ratingStatus == RatingStatus.provisional) {
      return 32.0;
    }
    return verificationTier == VerificationTier.sanctioned ? 16.0 : 20.0;
  }

  /// Calculates inactivity decay toward population mean (1200.0)
  /// for ratings without matches for over 90 days.
  RatingRecordEntity applyInactivityDecay({
    required RatingRecordEntity record,
    required DateTime now,
    double populationMean = 1200.0,
  }) {
    final daysInactive = now.difference(record.lastResultAt).inDays;
    if (daysInactive < 90) return record;

    // Decay by 2% of distance to mean per 30 days beyond threshold
    final decayPeriods = (daysInactive - 90) ~/ 30 + 1;
    double updatedRating = record.currentRating;

    for (var i = 0; i < decayPeriods; i++) {
      updatedRating -= (updatedRating - populationMean) * 0.02;
    }

    return RatingRecordEntity(
      id: record.id,
      playerProfileId: record.playerProfileId,
      sportId: record.sportId,
      currentRating: double.parse(updatedRating.toStringAsFixed(1)),
      ratingStatus: RatingStatus.inactive,
      lastResultAt: record.lastResultAt,
      matchesPlayed: record.matchesPlayed,
    );
  }

  /// Checks whether a rating change exceeds anti-gaming threshold (80 points).
  bool isImplausibleSwing({
    required double ratingBefore,
    required double ratingAfter,
    double threshold = 80.0,
  }) {
    return (ratingAfter - ratingBefore).abs() > threshold;
  }
}
