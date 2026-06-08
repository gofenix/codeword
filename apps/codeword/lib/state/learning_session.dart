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

/// In-memory review state for every word the user has ever answered.
/// Lost on app restart for v0.2.0 — drift-backed persistence is W3.
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
    final next = Sm2.schedule(
      current: current,
      quality: quality,
      now: now ?? DateTime.now(),
    );
    state = {...state, wordId: next};
    try {
      ReviewRepository.instance.put(wordId, next);
    } catch (_) {}
    return next;
  }

  int get totalLearned => state.values.where((s) => s.repetitions >= 1).length;
  int get totalDue {
    final now = DateTime.now();
    return state.values
        .where((s) => s.dueAt != null && !s.dueAt!.isAfter(now))
        .length;
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

/// One question in a learning session.
class LearningQuestion {
  final VocabWord word;
  final List<String> options; // 4 options: 1 correct + 3 distractors
  final int correctIndex;

  const LearningQuestion({
    required this.word,
    required this.options,
    required this.correctIndex,
  });
}

/// State machine for a learning session.
enum SessionPhase { loading, asking, feedback, finished }

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

  /// Build a session: pick `count` words from `vocabId`, generate 4-option
  /// A/B/C/D questions.
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

    final questions = slice.map((w) {
      // Pick 3 distractors from the same vocabulary (not equal to the word's translation).
      final pool = all.where((o) => o.id != w.id).toList()..shuffle(_rng);
      final distractors = pool.take(3).map((o) => o.translation).toList();
      final options = [...distractors, w.translation]..shuffle(_rng);
      return LearningQuestion(
        word: w,
        options: options,
        correctIndex: options.indexOf(w.translation),
      );
    }).toList();

    state = LearningSessionState(
      phase: SessionPhase.asking,
      questions: questions,
      currentIndex: 0,
      correctCount: 0,
    );
  }

  /// User picks an option; we transition to feedback.
  void answer(int optionIndex) {
    if (state.phase != SessionPhase.asking) return;
    final q = state.currentQuestion!;
    final correct = optionIndex == q.correctIndex;
    state = LearningSessionState(
      phase: SessionPhase.feedback,
      questions: state.questions,
      currentIndex: state.currentIndex,
      correctCount: state.correctCount + (correct ? 1 : 0),
      lastAnswer: correct ? AnswerQuality.good : AnswerQuality.again,
      lastSelectedIndex: optionIndex,
    );
  }

  /// After 200ms feedback, advance to the next question (or finish)
  /// and persist SM-2 state.
  void next() {
    if (state.phase != SessionPhase.feedback) return;
    final q = state.currentQuestion!;
    final quality = (state.lastAnswer ?? AnswerQuality.again).toSm2Quality();
    ref.read(reviewStateProvider.notifier).recordAnswer(
          wordId: q.word.id,
          quality: quality,
        );
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
