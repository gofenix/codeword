import 'models/vocab_list.dart';

/// SM-2 spaced repetition algorithm (Anki-style "again/hard/good/easy" quality).
///
/// Quality scale (0..5):
///   0..2  = incorrect (reset repetitions, schedule again same day)
///   3     = hard (correct but with serious difficulty)
///   4     = good (correct with some hesitation)
///   5     = easy (perfect recall)
///
/// Output: next [ReviewState] with updated easiness, interval, repetitions, dueAt.
class Sm2 {
  static ReviewState schedule({
    required ReviewState current,
    required int quality,
    required DateTime now,
  }) {
    assert(quality >= 0 && quality <= 5, 'quality must be 0..5');

    int easiness = current.easiness;
    int interval = current.interval;
    int repetitions = current.repetitions;

    // Update easiness factor
    // EF' = EF + (0.1 - (5-q) * (0.08 + (5-q)*0.02))
    // clamp to >= 130 (1.3)
    final delta = 0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02);
    final newEf = (easiness / 100.0) + delta;
    easiness = (newEf.clamp(1.3, 2.5) * 100).round();

    if (quality < 3) {
      repetitions = 0;
      interval = 0; // due again same day
    } else {
      repetitions += 1;
      if (repetitions == 1) {
        interval = 1;
      } else if (repetitions == 2) {
        interval = 6;
      } else {
        final newInterval = (current.interval * easiness / 100.0).round();
        interval = newInterval.clamp(1, 365);
      }
    }

    final dueAt = interval == 0 ? now : now.add(Duration(days: interval));

    return ReviewState(
      wordId: current.wordId,
      easiness: easiness,
      interval: interval,
      repetitions: repetitions,
      dueAt: dueAt,
      lastReviewedAt: now,
      firstReviewedAt: current.firstReviewedAt ?? now,
    );
  }
}

/// User's self-assessed answer to a learning question.
enum AnswerQuality { again, hard, good, easy }

extension AnswerQualityX on AnswerQuality {
  int toSm2Quality() {
    switch (this) {
      case AnswerQuality.again:
        return 0; // SM-2 quality 0 = complete blackout (no recall at all)
      case AnswerQuality.hard:
        return 3;
      case AnswerQuality.good:
        return 4;
      case AnswerQuality.easy:
        return 5;
    }
  }
}
