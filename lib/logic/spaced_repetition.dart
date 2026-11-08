enum ReviewRating { again, hard, good, easy }

class SpacedRepetitionEngine {
  static Map<String, dynamic> calculateNextReview({
    required int currentRepetitions,
    required double currentEaseFactor,
    required int currentInterval,
    required ReviewRating rating,
  }) {
    int quality;
    switch (rating) {
      case ReviewRating.again: quality = 1; break;
      case ReviewRating.hard: quality = 3; break;
      case ReviewRating.good: quality = 4; break;
      case ReviewRating.easy: quality = 5; break;
    }

    int nextRepetitions = currentRepetitions;
    int nextInterval = currentInterval;
    double nextEaseFactor = currentEaseFactor;

    if (quality >= 3) {
      if (currentRepetitions == 0) {
        nextInterval = 1;
      } else if (currentRepetitions == 1) {
        nextInterval = 6;
      } else {
        nextInterval = (currentInterval * currentEaseFactor).round();
      }
      nextRepetitions += 1;
    } else {
      nextRepetitions = 0;
      nextInterval = 1;
    }

    nextEaseFactor = currentEaseFactor + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02));
    if (nextEaseFactor < 1.3) nextEaseFactor = 1.3;

    final nextReviewDate = DateTime.now().add(Duration(days: nextInterval));

    return {
      'repetitions': nextRepetitions,
      'easeFactor': nextEaseFactor,
      'interval': nextInterval,
      'nextReviewDate': nextReviewDate,
    };
  }
}
