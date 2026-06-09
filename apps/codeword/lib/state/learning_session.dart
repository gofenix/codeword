import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lib_core/lib_core.dart';
import 'package:lib_content/lib_content.dart';

/// All built-in vocabulary ids in stable order — used for the library tab
/// and to know which JSON assets are bundled.
const List<String> kBuiltinVocabIds = [
  'cs_core',
  'python_core',
  'ai_core',
  'llm_core',
  'web_core',
  'devops_core',
  'data_core',
  'security_core',
  'product_core',
];

/// Computed stats derived from the review state + activity log.
class ReviewStats {
  final int totalSeen;
  final int totalLearned;
  final int totalDue;
  final int newToday;
  final int reviewsToday;
  final int streakDays;
  final List<int> last7Days; // length 7, index 6 = today
  final double averageEasiness;

  const ReviewStats({
    required this.totalSeen,
    required this.totalLearned,
    required this.totalDue,
    required this.newToday,
    required this.reviewsToday,
    required this.streakDays,
    required this.last7Days,
    required this.averageEasiness,
  });

  static const empty = ReviewStats(
    totalSeen: 0,
    totalLearned: 0,
    totalDue: 0,
    newToday: 0,
    reviewsToday: 0,
    streakDays: 0,
    last7Days: [0, 0, 0, 0, 0, 0, 0],
    averageEasiness: 0,
  );
}

/// In-memory review state for every word the user has ever answered.
/// Persisted to a local JSON file in the app documents directory; never
/// leaves the device.
final reviewStateProvider =
    StateNotifierProvider<ReviewStateNotifier, Map<String, ReviewState>>(
  (ref) => ReviewStateNotifier(),
);

class ReviewStateNotifier
    extends StateNotifier<Map<String, ReviewState>> {
  ReviewStateNotifier() : super(const {});

  /// Apply a SM-2 schedule for an answer and persist to file + memory.
  ReviewState recordAnswer({
    required String wordId,
    required int quality,
    DateTime? now,
  }) {
    final current = state[wordId] ?? ReviewState.fresh(wordId);
    final at = now ?? DateTime.now();
    final next = Sm2.schedule(current: current, quality: quality, now: at);
    state = {...state, wordId: next};
    try {
      ReviewRepository.instance.put(wordId, next);
      ReviewRepository.instance.recordActivity(at);
    } catch (_) {}
    return next;
  }

  int get totalLearned =>
      state.values.where((s) => s.repetitions >= 1).length;
  int get totalDue {
    final now = DateTime.now();
    return state.values
        .where((s) => s.dueAt != null && !s.dueAt!.isAfter(now))
        .length;
  }

  /// All stats for the home + stats pages. Pulls activity from the
  /// persistence layer if initialized; otherwise returns zero stats.
  ReviewStats stats({DateTime? now}) {
    final at = now ?? DateTime.now();
    if (state.isEmpty) {
      // No review state yet. Still try to surface activity from disk
      // (e.g. if the user had state, deleted the in-memory cache but
      // the file persisted). In tests (no init), fall back to zeros.
      int reviewsToday = 0;
      int streak = 0;
      List<int> last7 = const [0, 0, 0, 0, 0, 0, 0];
      try {
        final repo = ReviewRepository.instance;
        reviewsToday = repo.activityOn(at);
        streak = repo.streakDays(now: at);
        last7 = repo.last7Days(now: at);
      } catch (_) {}
      return ReviewStats(
        totalSeen: 0,
        totalLearned: 0,
        totalDue: 0,
        newToday: 0,
        reviewsToday: reviewsToday,
        streakDays: streak,
        last7Days: last7,
        averageEasiness: 0,
      );
    }
    final today = DateTime(at.year, at.month, at.day);
    final tomorrow = today.add(const Duration(days: 1));
    int reviewsToday = 0;
    int newToday = 0;
    int due = 0;
    int sumEf = 0;
    for (final s in state.values) {
      sumEf += s.easiness;
      if (s.dueAt != null && !s.dueAt!.isAfter(at)) due++;
      if (s.lastReviewedAt != null &&
          !s.lastReviewedAt!.isBefore(today) &&
          s.lastReviewedAt!.isBefore(tomorrow)) {
        reviewsToday++;
        if (s.repetitions == 1) newToday++;
      }
    }
    final avg = state.isEmpty ? 0.0 : sumEf / state.length / 100.0;

    // Activity / streak comes from the persistence layer. In tests (and
    // any pre-init code path) it isn't initialized, so we fall back to
    // zeros for those fields while still reporting the live state.
    int streak = 0;
    List<int> last7 = const [0, 0, 0, 0, 0, 0, 0];
    try {
      final repo = ReviewRepository.instance;
      streak = repo.streakDays(now: at);
      last7 = repo.last7Days(now: at);
    } catch (_) {
      // Repository not initialized (test env, pre-init). Use zeros.
    }

    return ReviewStats(
      totalSeen: state.length,
      totalLearned: totalLearned,
      totalDue: due,
      newToday: newToday,
      reviewsToday: reviewsToday,
      streakDays: streak,
      last7Days: last7,
      averageEasiness: avg,
    );
  }
}

/// Lazy-loaded vocabulary content cache. Loads JSON on first request.
final vocabCacheProvider =
    FutureProvider.family<List<VocabWord>, String>((ref, listId) async {
  return ContentLoader.loadList(listId);
});

/// Metadata for a vocabulary (synchronous, no asset load needed).
final vocabMetaProvider = Provider<Map<String, VocabList>>((ref) {
  return {for (final l in kBuiltinLists) l.id: l};
});

enum QuestionType { seeWordPickMeaning, seeMeaningPickWord, listenPickMeaning, seeContextPickWord }

/// One question in a learning session.
class LearningQuestion {
  final VocabWord word;
  final QuestionType type;
  final List<String> options;
  final int correctIndex;
  final String prompt;

  const LearningQuestion({
    required this.word,
    required this.type,
    required this.options,
    required this.correctIndex,
    this.prompt = '',
  });
}

/// State machine for a learning session.
enum SessionPhase { loading, asking, wrongDetail, finished }

class LearningSessionState {
  final SessionPhase phase;
  final List<LearningQuestion> questions;
  final int currentIndex;
  final int correctCount;
  final AnswerQuality? lastAnswer;
  final int? lastSelectedIndex;

  const LearningSessionState({
    required this.phase,
    required this.questions,
    required this.currentIndex,
    required this.correctCount,
    this.lastAnswer,
    this.lastSelectedIndex,
  });

  factory LearningSessionState.loading() => const LearningSessionState(
        phase: SessionPhase.loading,
        questions: [],
        currentIndex: 0,
        correctCount: 0,
      );

  LearningQuestion? get currentQuestion =>
      (currentIndex < questions.length) ? questions[currentIndex] : null;

  double get progress =>
      questions.isEmpty ? 0 : currentIndex / questions.length;

  bool get isCorrect => lastAnswer != null && lastAnswer != AnswerQuality.again;
}

class LearningSessionNotifier
    extends StateNotifier<LearningSessionState> {
  final Ref ref;
  final Random _rng = Random();

  LearningSessionNotifier(this.ref) : super(LearningSessionState.loading());

  /// Build a session: pick `count` words from `vocabId`, generate mixed
  /// question types (5 types rotated).
  Future<void> start({required String vocabId, int count = 10}) async {
    state = LearningSessionState.loading();
    final all = await ref.read(vocabCacheProvider(vocabId).future);
    if (all.isEmpty) {
      state = const LearningSessionState(
        phase: SessionPhase.finished,
        questions: [],
        currentIndex: 0,
        correctCount: 0,
      );
      return;
    }
    final picked = [...all]..shuffle(_rng);
    final slice = picked.take(count.clamp(1, all.length)).toList();

    final types = QuestionType.values;
    final questions = slice.asMap().entries.map((entry) {
      final w = entry.value;
      final t = types[entry.key % types.length];
      return _buildQuestion(w, t, all);
    }).toList();

    state = LearningSessionState(
      phase: SessionPhase.asking,
      questions: questions,
      currentIndex: 0,
      correctCount: 0,
    );
  }

  LearningQuestion _buildQuestion(VocabWord w, QuestionType type, List<VocabWord> all) {
    final pool = all.where((o) => o.id != w.id).toList()..shuffle(_rng);
    switch (type) {
      case QuestionType.seeWordPickMeaning:
        final distractors = pool.take(3).map((o) => o.translation).toList();
        final options = [...distractors, w.translation]..shuffle(_rng);
        return LearningQuestion(
          word: w, type: type, options: options,
          correctIndex: options.indexOf(w.translation),
          prompt: w.word,
        );
      case QuestionType.seeMeaningPickWord:
        final distractors = pool.take(3).map((o) => o.word).toList();
        final options = [...distractors, w.word]..shuffle(_rng);
        return LearningQuestion(
          word: w, type: type, options: options,
          correctIndex: options.indexOf(w.word),
          prompt: w.translation,
        );
      case QuestionType.listenPickMeaning:
        final distractors = pool.take(3).map((o) => o.translation).toList();
        final options = [...distractors, w.translation]..shuffle(_rng);
        return LearningQuestion(
          word: w, type: type, options: options,
          correctIndex: options.indexOf(w.translation),
          prompt: w.word,
        );
      case QuestionType.seeContextPickWord:
        final distractors = pool.take(3).map((o) => o.word).toList();
        final options = [...distractors, w.word]..shuffle(_rng);
        return LearningQuestion(
          word: w, type: type, options: options,
          correctIndex: options.indexOf(w.word),
          prompt: w.exampleEn,
        );
    }
  }

  /// User picks an option; correct → immediately next, wrong → wrongDetail.
  void answer(int optionIndex) {
    if (state.phase != SessionPhase.asking) return;
    final q = state.currentQuestion!;
    final correct = optionIndex == q.correctIndex;
    final quality = correct ? AnswerQuality.good : AnswerQuality.again;
    ref.read(reviewStateProvider.notifier).recordAnswer(
          wordId: q.word.id,
          quality: quality.toSm2Quality(),
        );
    if (correct) {
      final nextIndex = state.currentIndex + 1;
      state = LearningSessionState(
        phase: nextIndex >= state.questions.length ? SessionPhase.finished : SessionPhase.asking,
        questions: state.questions,
        currentIndex: nextIndex,
        correctCount: state.correctCount + 1,
      );
    } else {
      state = LearningSessionState(
        phase: SessionPhase.wrongDetail,
        questions: state.questions,
        currentIndex: state.currentIndex,
        correctCount: state.correctCount,
        lastAnswer: quality,
        lastSelectedIndex: optionIndex,
      );
    }
  }

  /// Advance from wrong-detail to next question (or finish).
  void next() {
    if (state.phase != SessionPhase.wrongDetail) return;
    final nextIndex = state.currentIndex + 1;
    if (nextIndex >= state.questions.length) {
      state = LearningSessionState(
        phase: SessionPhase.finished,
        questions: state.questions,
        currentIndex: nextIndex,
        correctCount: state.correctCount,
      );
      return;
    }
    state = LearningSessionState(
      phase: SessionPhase.asking,
      questions: state.questions,
      currentIndex: nextIndex,
      correctCount: state.correctCount,
    );
  }
}

final learningSessionProvider = StateNotifierProvider.autoDispose<
    LearningSessionNotifier, LearningSessionState>(
  (ref) => LearningSessionNotifier(ref),
);
