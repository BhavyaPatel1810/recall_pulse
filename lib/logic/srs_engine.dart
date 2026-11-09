import 'dart:math';
import '../models/flashcard.dart';

class SRSReviewResult {
  final double easeFactor;
  final int interval;
  final int repetitions;
  final DateTime nextReviewDate;

  const SRSReviewResult({
    required this.easeFactor,
    required this.interval,
    required this.repetitions,
    required this.nextReviewDate,
  });
}

class SRSEngine {
  static const int ratingAgain = 1;
  static const int ratingHard = 2;
  static const int ratingGood = 3;
  static const int ratingEasy = 4;

  static const double minimumEaseFactor = 1.3;

  /// Calculates the next review metrics for a card using the Anki SM-2 spaced repetition variant.
  static SRSReviewResult calculateNextReview(Flashcard card, int rating) {
    double newEaseFactor = card.easeFactor;
    int newInterval = card.interval;
    int newRepetitions = card.repetitions;
    DateTime nextReviewDate;

    final now = DateTime.now();

    switch (rating) {
      case ratingAgain:
        // Lapse: reset progress, schedule review in 10 minutes, decrease ease factor
        newRepetitions = 0;
        newInterval = 0;
        newEaseFactor = max(minimumEaseFactor, card.easeFactor - 0.20);
        nextReviewDate = now.add(const Duration(minutes: 10));
        break;

      case ratingHard:
        // Hard: minor increase in interval, ease factor penalty
        newRepetitions = card.repetitions + 1;
        newEaseFactor = max(minimumEaseFactor, card.easeFactor - 0.15);
        if (card.repetitions == 0) {
          newInterval = 1;
        } else if (card.repetitions == 1) {
          newInterval = 2;
        } else {
          newInterval = max(card.interval + 1, (card.interval * 1.2).round());
        }
        nextReviewDate = now.add(Duration(days: newInterval));
        break;

      case ratingGood:
        // Good: regular graduation sequence
        newRepetitions = card.repetitions + 1;
        if (card.repetitions == 0) {
          newInterval = 1;
        } else if (card.repetitions == 1) {
          newInterval = 6;
        } else {
          newInterval = max(card.interval + 1, (card.interval * card.easeFactor).round());
        }
        nextReviewDate = now.add(Duration(days: newInterval));
        break;

      case ratingEasy:
        // Easy: accelerated interval with bonus multiplier, increase ease factor
        newRepetitions = card.repetitions + 1;
        newEaseFactor = card.easeFactor + 0.15;
        if (card.repetitions == 0) {
          newInterval = 4;
        } else if (card.repetitions == 1) {
          newInterval = 8;
        } else {
          newInterval = max(card.interval + 2, (card.interval * card.easeFactor * 1.3).round());
        }
        nextReviewDate = now.add(Duration(days: newInterval));
        break;

      default:
        throw ArgumentError('Invalid SRS Rating: $rating. Valid values are 1, 2, 3, 4.');
    }

    return SRSReviewResult(
      easeFactor: double.parse(newEaseFactor.toStringAsFixed(2)),
      interval: newInterval,
      repetitions: newRepetitions,
      nextReviewDate: nextReviewDate,
    );
  }

  /// Returns a human-readable interval preview string for button labels (e.g., '<10m', '1d', '6d', '1.2mo').
  static String getIntervalPreview(Flashcard card, int rating) {
    if (rating == ratingAgain) {
      return '<10m';
    }

    int prospectiveInterval;
    switch (rating) {
      case ratingHard:
        if (card.repetitions == 0) {
          prospectiveInterval = 1;
        } else if (card.repetitions == 1) {
          prospectiveInterval = 2;
        } else {
          prospectiveInterval = max(card.interval + 1, (card.interval * 1.2).round());
        }
        break;
      case ratingGood:
        if (card.repetitions == 0) {
          prospectiveInterval = 1;
        } else if (card.repetitions == 1) {
          prospectiveInterval = 6;
        } else {
          prospectiveInterval = max(card.interval + 1, (card.interval * card.easeFactor).round());
        }
        break;
      case ratingEasy:
        if (card.repetitions == 0) {
          prospectiveInterval = 4;
        } else if (card.repetitions == 1) {
          prospectiveInterval = 8;
        } else {
          prospectiveInterval = max(card.interval + 2, (card.interval * card.easeFactor * 1.3).round());
        }
        break;
      default:
        return '1d';
    }

    return formatDaysToHuman(prospectiveInterval);
  }

  static String formatDaysToHuman(int days) {
    if (days <= 0) return '<10m';
    if (days == 1) return '1d';
    if (days < 30) return '${days}d';
    if (days < 365) {
      final months = (days / 30).toStringAsFixed(1);
      return months.endsWith('.0') ? '${days ~/ 30}mo' : '${months}mo';
    }
    final years = (days / 365).toStringAsFixed(1);
    return years.endsWith('.0') ? '${days ~/ 365}y' : '${years}y';
  }
}