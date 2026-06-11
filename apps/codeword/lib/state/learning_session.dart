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

/// Mastery bucket for the distribution chart.
///
/// Thresholds (from SM-2 easiness + repetitions):
///   熟悉  : EF ≥ 2.5 AND reps ≥ 3   — well-known
///   认识  : EF ≥ 2.3 AND reps ≥ 2   — recognized
///   模糊  : EF ≥ 1.8 AND reps ≥ 1   — seen, shaky
///   陌生  : state exists, reps == 0 — failed at least once
///   待学习: no state at all         — not yet seen
enum MasteryLevel { familiar, recognized, vague, unfamiliar, unseen }

extension MasteryLevelX on MasteryLevel {
  String get label => switch (this) {
    MasteryLevel.familiar => '熟悉',
    MasteryLevel.recognized => '认识',
    MasteryLevel.vague => '模糊',
    MasteryLevel.unfamiliar => '陌生',
    MasteryLevel.unseen => '待学习',
  };

  int get rank => index; // higher rank = better mastery
}

class MasteryBucket {
  final MasteryLevel level;
  final int count;
  const MasteryBucket({required this.level, required this.count});
}

/// Per-vocabulary progress, used in the stats page list.
class VocabProgress {
  final String vocabId;
  final String name;
  final String emoji;
  final int totalWords; // words in the bundled JSON
  final int seen; // words with a review state
  final int learned; // words with repetitions >= 1
  final int due; // words due for review
  final double averageEasiness;

  const VocabProgress({
    required this.vocabId,
    required this.name,
    required this.emoji,
    required this.totalWords,
    required this.seen,
    required this.learned,
    required this.due,
    required this.averageEasiness,
  });

  double get coverage => totalWords == 0 ? 0 : learned / totalWords;
}

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

  // v0.4.7 additions:
  final List<MasteryBucket> mastery; // 5 buckets, total seen + unseen
  final List<VocabProgress> perVocab;
  final int favorites; // count
  final int removed; // count
  final int openCountToday;
  final int studyMinutesToday;
  final int totalStudyMinutes;
  final List<int> last30Days; // daily activity counts
  final List<int> last30DaysMinutes; // daily study minutes
  final List<bool> last90DaysActivity; // streak schedule booleans

  const ReviewStats({
    required this.totalSeen,
    required this.totalLearned,
    required this.totalDue,
    required this.newToday,
    required this.reviewsToday,
    required this.streakDays,
    required this.last7Days,
    required this.averageEasiness,
    required this.mastery,
    required this.perVocab,
    required this.favorites,
    required this.removed,
    required this.openCountToday,
    required this.studyMinutesToday,
    required this.totalStudyMinutes,
    required this.last30Days,
    required this.last30DaysMinutes,
    required this.last90DaysActivity,
  });

  static const _emptyMastery = <MasteryBucket>[
    MasteryBucket(level: MasteryLevel.familiar, count: 0),
    MasteryBucket(level: MasteryLevel.recognized, count: 0),
    MasteryBucket(level: MasteryLevel.vague, count: 0),
    MasteryBucket(level: MasteryLevel.unfamiliar, count: 0),
    MasteryBucket(level: MasteryLevel.unseen, count: 0),
  ];

  static const empty = ReviewStats(
    totalSeen: 0,
    totalLearned: 0,
    totalDue: 0,
    newToday: 0,
    reviewsToday: 0,
    streakDays: 0,
    last7Days: [0, 0, 0, 0, 0, 0, 0],
    averageEasiness: 0,
    mastery: _emptyMastery,
    perVocab: [],
    favorites: 0,
    removed: 0,
    openCountToday: 0,
    studyMinutesToday: 0,
    totalStudyMinutes: 0,
    last30Days: _emptyInt30,
    last30DaysMinutes: _emptyInt30,
    last90DaysActivity: _emptyBool90,
  );

  static const _emptyInt30 = <int>[
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
  ];
  static const _emptyBool90 = <bool>[
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
  ];
}

/// In-memory review state for every word the user has ever answered.
/// Persisted to a local JSON file in the app documents directory; never
/// leaves the device.
final reviewStateProvider =
    StateNotifierProvider<ReviewStateNotifier, Map<String, ReviewState>>(
      (ref) => ReviewStateNotifier(),
    );

class ReviewStateNotifier extends StateNotifier<Map<String, ReviewState>> {
  ReviewStateNotifier([Map<String, ReviewState>? initialState])
    : super(initialState ?? _loadInitialState());

  static Map<String, ReviewState> _loadInitialState() {
    try {
      return ReviewRepository.instance.all;
    } catch (_) {
      return const {};
    }
  }

  Set<String> _removedWordIds() {
    try {
      return ReviewRepository.instance.removed;
    } catch (_) {
      return const {};
    }
  }

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

  int get totalLearned => state.values.where((s) => s.repetitions >= 1).length;
  int get totalDue {
    final now = DateTime.now();
    return state.values
        .where((s) => s.dueAt != null && !s.dueAt!.isAfter(now))
        .length;
  }

  /// Top-N words most overdue for review. Loads each owning vocab on
  /// demand (cached) to surface the human-readable word, phonetic,
  /// translation. Used by the Pulse tab.
  ///
  /// Returns entries sorted by most-overdue first. If [now] is omitted
  /// we use the wall clock.
  Future<List<PulseWordEntry>> dueWords({int limit = 3, DateTime? now}) async {
    final at = now ?? DateTime.now();
    final removed = _removedWordIds();
    final dueEntries =
        state.entries
            .where(
              (e) =>
                  !removed.contains(e.key) &&
                  e.value.dueAt != null &&
                  !e.value.dueAt!.isAfter(at),
            )
            .toList()
          ..sort((a, b) => a.value.dueAt!.compareTo(b.value.dueAt!));
    if (dueEntries.isEmpty) return const [];
    return _hydrate(entries: dueEntries.take(limit).toList(), at: at);
  }

  /// Top-N recommended new words. Picks the vocab with the lowest
  /// coverage that still has unseen words, then returns the first few
  /// of those.
  ///
  /// Falls back to `ai_core` if every vocab is fully learned.
  Future<List<PulseWordEntry>> recommendedNewWords({int limit = 3}) async {
    final stats = this.stats();
    String? targetId;
    double lowestCoverage = double.infinity;
    for (final v in stats.perVocab) {
      final unseen = v.totalWords - v.seen;
      if (unseen > 0 && v.coverage < lowestCoverage) {
        lowestCoverage = v.coverage;
        targetId = v.vocabId;
      }
    }
    targetId ??= 'ai_core';
    final list = await ContentLoader.loadList(targetId);
    final seenIds = state.keys.toSet();
    final removed = _removedWordIds();
    final newOnes = list
        .where((w) => !seenIds.contains(w.id) && !removed.contains(w.id))
        .take(limit)
        .toList();
    return [
      for (final w in newOnes)
        PulseWordEntry(
          word: w.word,
          translation: w.translation,
          phonetic: w.phonetic,
          level: w.level,
          vocabId: targetId,
        ),
    ];
  }

  Future<List<PulseWordEntry>> _hydrate({
    required List<MapEntry<String, ReviewState>> entries,
    required DateTime at,
  }) async {
    final byVocab = <String, List<String>>{};
    for (final e in entries) {
      final vid = _vocabIdFromWordId(e.key);
      byVocab.putIfAbsent(vid, () => []).add(e.key);
    }
    final out = <PulseWordEntry>[];
    for (final vid in byVocab.keys) {
      try {
        final list = await ContentLoader.loadList(vid);
        final byId = {for (final w in list) w.id: w};
        for (final wid in byVocab[vid]!) {
          final w = byId[wid];
          if (w == null) continue;
          final s = state[wid]!;
          final overdue = s.dueAt == null ? 0 : at.difference(s.dueAt!).inDays;
          out.add(
            PulseWordEntry(
              word: w.word,
              translation: w.translation,
              phonetic: w.phonetic,
              level: w.level,
              vocabId: vid,
              overdueDays: overdue < 0 ? 0 : overdue,
            ),
          );
        }
      } catch (_) {
        // Vocab not bundled — skip.
      }
    }
    out.sort((a, b) => (b.overdueDays ?? 0).compareTo(a.overdueDays ?? 0));
    return out;
  }

  /// All stats for the home + stats pages. Pulls activity from the
  /// persistence layer if initialized; otherwise returns zero stats.
  ReviewStats stats({DateTime? now}) {
    final at = now ?? DateTime.now();
    final today = DateTime(at.year, at.month, at.day);
    final tomorrow = today.add(const Duration(days: 1));

    int reviewsToday = 0;
    int newToday = 0;
    int due = 0;
    int sumEf = 0;
    final masteryCount = <MasteryLevel, int>{
      for (final l in MasteryLevel.values) l: 0,
    };
    final perVocabStats = <String, _MutableVocabStats>{};

    void accumulate(String vocabId, ReviewState s) {
      sumEf += s.easiness;
      if (s.dueAt != null && !s.dueAt!.isAfter(at)) due++;
      if (s.lastReviewedAt != null &&
          !s.lastReviewedAt!.isBefore(today) &&
          s.lastReviewedAt!.isBefore(tomorrow)) {
        reviewsToday++;
        if (s.repetitions == 1) newToday++;
      }
      final ef = s.easiness / 100.0;
      final bucket = _classify(ef, s.repetitions);
      masteryCount[bucket] = (masteryCount[bucket] ?? 0) + 1;
      final v = perVocabStats.putIfAbsent(vocabId, () => _MutableVocabStats());
      v.seen++;
      v.sumEf += s.easiness;
      if (s.repetitions >= 1) v.learned++;
      if (s.dueAt != null && !s.dueAt!.isAfter(at)) v.due++;
    }

    for (final entry in state.entries) {
      final vocabId = _vocabIdFromWordId(entry.key);
      accumulate(vocabId, entry.value);
    }

    final avg = state.isEmpty ? 0.0 : sumEf / state.length / 100.0;

    int streak = 0;
    List<int> last7 = const [0, 0, 0, 0, 0, 0, 0];
    List<int> last30 = const [];
    List<int> last30Min = const [];
    List<bool> last90 = const [];
    int favs = 0;
    int removed = 0;
    int opensToday = 0;
    int minsToday = 0;
    int totalMins = 0;
    try {
      final repo = ReviewRepository.instance;
      streak = repo.streakDays(now: at);
      last7 = repo.last7Days(now: at);
      last30 = repo.last30Days(now: at);
      last30Min = repo.last30DaysMinutes(now: at);
      last90 = repo.last90DaysActivity(now: at);
      favs = repo.favorites.length;
      removed = repo.removed.length;
      opensToday = repo.openCountOn(at);
      minsToday = repo.studyMinutesOn(at);
      totalMins = repo.totalStudyMinutes;
    } catch (_) {
      // Repository not initialized (test env). Use zeros / empty.
    }

    final meta = kBuiltinLists;
    final perVocabOut = <VocabProgress>[];
    for (final list in meta) {
      final total = list.wordCount;
      final m = perVocabStats[list.id] ?? _MutableVocabStats();
      masteryCount[MasteryLevel.unseen] =
          (masteryCount[MasteryLevel.unseen] ?? 0) + (total - m.seen);
      perVocabOut.add(
        VocabProgress(
          vocabId: list.id,
          name: list.name,
          emoji: list.emoji,
          totalWords: total,
          seen: m.seen,
          learned: m.learned,
          due: m.due,
          averageEasiness: m.seen == 0 ? 0 : m.sumEf / m.seen / 100.0,
        ),
      );
    }
    final mastery = <MasteryBucket>[
      for (final l in MasteryLevel.values)
        MasteryBucket(level: l, count: masteryCount[l] ?? 0),
    ];

    return ReviewStats(
      totalSeen: state.length,
      totalLearned: totalLearned,
      totalDue: due,
      newToday: newToday,
      reviewsToday: reviewsToday,
      streakDays: streak,
      last7Days: last7,
      averageEasiness: avg,
      mastery: mastery,
      perVocab: perVocabOut,
      favorites: favs,
      removed: removed,
      openCountToday: opensToday,
      studyMinutesToday: minsToday,
      totalStudyMinutes: totalMins,
      last30Days: last30.isEmpty ? List<int>.filled(30, 0) : last30,
      last30DaysMinutes: last30Min.isEmpty
          ? List<int>.filled(30, 0)
          : last30Min,
      last90DaysActivity: last90.isEmpty
          ? List<bool>.filled(90, false)
          : last90,
    );
  }

  static MasteryLevel _classify(double ef, int reps) {
    if (reps == 0) return MasteryLevel.unfamiliar;
    if (ef >= 2.5 && reps >= 3) return MasteryLevel.familiar;
    if (ef >= 2.3 && reps >= 2) return MasteryLevel.recognized;
    // Any word with reps >= 1 and ef < 2.3 is "vague" — the user has
    // answered correctly at least once but retention is shaky. Don't
    // fall through to "unfamiliar" which is reserved for reps == 0.
    return MasteryLevel.vague;
  }

  static String _vocabIdFromWordId(String wid) {
    final idx = wid.lastIndexOf('_');
    if (idx <= 0) return wid;
    final prefix = wid.substring(0, idx);
    switch (prefix) {
      case 'ai':
        return 'ai_core';
      case 'cs':
        return 'cs_core';
      case 'py':
        return 'python_core';
      case 'web':
        return 'web_core';
      case 'llm':
        return 'llm_core';
      case 'devops':
        return 'devops_core';
      case 'data':
        return 'data_core';
      case 'sec':
        return 'security_core';
      case 'prod':
        return 'product_core';
      default:
        return '${prefix}_core';
    }
  }
}

class _MutableVocabStats {
  int seen = 0;
  int learned = 0;
  int due = 0;
  int sumEf = 0;
}

/// Lightweight DTO used by the Pulse tab. The full [VocabWord] is in
/// `lib_content`; this is a trimmed projection for the daily digest.
class PulseWordEntry {
  final String word;
  final String translation;
  final String phonetic;
  final String level;
  final String vocabId;
  final int? overdueDays; // null for new-word recommendations
  const PulseWordEntry({
    required this.word,
    required this.translation,
    required this.phonetic,
    required this.level,
    required this.vocabId,
    this.overdueDays,
  });
}

/// Lazy-loaded vocabulary content cache. Loads JSON on first request.
final vocabCacheProvider = FutureProvider.family<List<VocabWord>, String>((
  ref,
  listId,
) async {
  return ContentLoader.loadList(listId);
});

/// Metadata for a vocabulary (synchronous, no asset load needed).
final vocabMetaProvider = Provider<Map<String, VocabList>>((ref) {
  return {for (final l in kBuiltinLists) l.id: l};
});

enum QuestionType {
  seeWordPickMeaning,
  seeMeaningPickWord,
  listenPickMeaning,
  seeContextPickWord,
}

enum SessionQuestionSource { due, newWord, retry }

/// One question in a learning session.
class LearningQuestion {
  final VocabWord word;
  final QuestionType type;
  final List<String> options;
  final int correctIndex;
  final String prompt;
  final SessionQuestionSource source;
  final int attemptNo;

  const LearningQuestion({
    required this.word,
    required this.type,
    required this.options,
    required this.correctIndex,
    this.prompt = '',
    this.source = SessionQuestionSource.newWord,
    this.attemptNo = 0,
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
  final bool lastQuestionQueuedForRetry;

  const LearningSessionState({
    required this.phase,
    required this.questions,
    required this.currentIndex,
    required this.correctCount,
    this.lastAnswer,
    this.lastSelectedIndex,
    this.lastQuestionQueuedForRetry = false,
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

class LearningSessionNotifier extends StateNotifier<LearningSessionState> {
  final Ref ref;
  final Random _rng = Random();

  LearningSessionNotifier(this.ref) : super(LearningSessionState.loading());

  /// Build a session: pick `count` words from `vocabId`, generate mixed
  /// Build a session that respects the SM-2 memory curve.
  ///
  /// Adaptive sizing: the session size is driven by how many words are
  /// actually due for review right now, not a fixed batch size.
  ///
  ///   - All due words (dueAt <= now) are included first.
  ///   - If due words are fewer than [minSessionSize], pad with new
  ///     words up to [minSessionSize].
  ///   - If due words exceed [maxSessionSize], cap at [maxSessionSize]
  ///     (user can start another session after).
  ///   - New words are only added when there is room after due words.
  Future<void> start({
    required String vocabId,
    int minSessionSize = 5,
    int maxSessionSize = 20,
  }) async {
    state = LearningSessionState.loading();
    final raw = await ref.read(vocabCacheProvider(vocabId).future);
    final removed = _removedWordIds();
    final all = raw.where((w) => !removed.contains(w.id)).toList();
    if (all.isEmpty) {
      state = const LearningSessionState(
        phase: SessionPhase.finished,
        questions: [],
        currentIndex: 0,
        correctCount: 0,
      );
      return;
    }

    final now = DateTime.now();
    final reviewMap = ref.read(reviewStateProvider);
    final allWordIds = all.map((w) => w.id).toSet();
    final seenIds = reviewMap.keys.where(allWordIds.contains).toSet();

    // Due = has dueAt <= now. These are the highest priority.
    final dueWords =
        all
            .where(
              (w) =>
                  seenIds.contains(w.id) &&
                  reviewMap[w.id]!.dueAt != null &&
                  !reviewMap[w.id]!.dueAt!.isAfter(now),
            )
            .toList()
          ..shuffle(_rng);

    // New = never seen.
    final newWords = all.where((w) => !seenIds.contains(w.id)).toList()
      ..shuffle(_rng);

    // Adaptive sizing:
    // 1. Take ALL due words (capped at maxSessionSize).
    // 2. Pad with new words up to minSessionSize, or up to maxSessionSize
    //    if there is still room.
    final pickedDue = dueWords.take(maxSessionSize).toList();
    final remainingSlots = (pickedDue.length >= minSessionSize)
        ? (maxSessionSize - pickedDue.length)
        : (minSessionSize - pickedDue.length);
    final pickedNew = newWords
        .take(remainingSlots.clamp(0, maxSessionSize))
        .toList();

    final picked = [
      for (final w in pickedDue) _PickedWord(w, SessionQuestionSource.due),
      for (final w in pickedNew) _PickedWord(w, SessionQuestionSource.newWord),
    ]..shuffle(_rng);

    if (picked.isEmpty) {
      state = const LearningSessionState(
        phase: SessionPhase.finished,
        questions: [],
        currentIndex: 0,
        correctCount: 0,
      );
      return;
    }

    final types = QuestionType.values;
    final questions = picked.asMap().entries.map((entry) {
      final picked = entry.value;
      final w = picked.word;
      final t = types[entry.key % types.length];
      return _buildQuestion(w, t, all, source: picked.source);
    }).toList();

    state = LearningSessionState(
      phase: SessionPhase.asking,
      questions: questions,
      currentIndex: 0,
      correctCount: 0,
    );
  }

  Set<String> _removedWordIds() {
    try {
      return ReviewRepository.instance.removed;
    } catch (_) {
      return const {};
    }
  }

  LearningQuestion _buildQuestion(
    VocabWord w,
    QuestionType type,
    List<VocabWord> all, {
    SessionQuestionSource source = SessionQuestionSource.newWord,
    int attemptNo = 0,
  }) {
    final pool = all.where((o) => o.id != w.id).toList()..shuffle(_rng);
    switch (type) {
      case QuestionType.seeWordPickMeaning:
        // Deduplicate distractors by translation so two options never
        // share the same correct answer text.
        final seen = <String>{w.translation};
        final distractors = <String>[];
        for (final o in pool) {
          if (!seen.contains(o.translation) && distractors.length < 3) {
            distractors.add(o.translation);
            seen.add(o.translation);
          }
        }
        // If we couldn't fill 3 distractors, pad with placeholder text.
        while (distractors.length < 3) {
          distractors.add('—');
        }
        final options = [...distractors, w.translation]..shuffle(_rng);
        return LearningQuestion(
          word: w,
          type: type,
          options: options,
          correctIndex: options.indexOf(w.translation),
          prompt: w.word,
          source: source,
          attemptNo: attemptNo,
        );
      case QuestionType.seeMeaningPickWord:
        final seen = <String>{w.word};
        final distractors = <String>[];
        for (final o in pool) {
          if (!seen.contains(o.word) && distractors.length < 3) {
            distractors.add(o.word);
            seen.add(o.word);
          }
        }
        while (distractors.length < 3) {
          distractors.add('—');
        }
        final options = [...distractors, w.word]..shuffle(_rng);
        return LearningQuestion(
          word: w,
          type: type,
          options: options,
          correctIndex: options.indexOf(w.word),
          prompt: w.translation,
          source: source,
          attemptNo: attemptNo,
        );
      case QuestionType.listenPickMeaning:
        final seen = <String>{w.translation};
        final distractors = <String>[];
        for (final o in pool) {
          if (!seen.contains(o.translation) && distractors.length < 3) {
            distractors.add(o.translation);
            seen.add(o.translation);
          }
        }
        while (distractors.length < 3) {
          distractors.add('—');
        }
        final options = [...distractors, w.translation]..shuffle(_rng);
        return LearningQuestion(
          word: w,
          type: type,
          options: options,
          correctIndex: options.indexOf(w.translation),
          prompt: w.word,
          source: source,
          attemptNo: attemptNo,
        );
      case QuestionType.seeContextPickWord:
        final seen = <String>{w.word};
        final distractors = <String>[];
        for (final o in pool) {
          if (!seen.contains(o.word) && distractors.length < 3) {
            distractors.add(o.word);
            seen.add(o.word);
          }
        }
        while (distractors.length < 3) {
          distractors.add('—');
        }
        final options = [...distractors, w.word]..shuffle(_rng);
        return LearningQuestion(
          word: w,
          type: type,
          options: options,
          correctIndex: options.indexOf(w.word),
          prompt: w.exampleEn,
          source: source,
          attemptNo: attemptNo,
        );
    }
  }

  LearningQuestion _buildRetryQuestion(LearningQuestion q) {
    final types = QuestionType.values;
    final nextType = types[(types.indexOf(q.type) + 1) % types.length];
    final pool = state.questions.map((item) => item.word).toList();
    return _buildQuestion(
      q.word,
      nextType,
      pool,
      source: SessionQuestionSource.retry,
      attemptNo: q.attemptNo + 1,
    );
  }

  /// User picks an option; correct → immediately next, wrong → wrongDetail.
  void answer(int optionIndex) {
    if (state.phase != SessionPhase.asking) return;
    final q = state.currentQuestion!;
    final correct = optionIndex == q.correctIndex;
    final quality = correct
        ? (q.source == SessionQuestionSource.retry
              ? AnswerQuality.hard
              : AnswerQuality.good)
        : AnswerQuality.again;
    ref
        .read(reviewStateProvider.notifier)
        .recordAnswer(wordId: q.word.id, quality: quality.toSm2Quality());
    if (correct) {
      final nextIndex = state.currentIndex + 1;
      state = LearningSessionState(
        phase: nextIndex >= state.questions.length
            ? SessionPhase.finished
            : SessionPhase.asking,
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
        lastQuestionQueuedForRetry: true,
      );
    }
  }

  /// Advance from wrong-detail to next question (or finish).
  void next({bool skipRetry = false}) {
    if (state.phase != SessionPhase.wrongDetail) return;
    final current = state.currentQuestion!;
    final questions = skipRetry
        ? state.questions
        : [...state.questions, _buildRetryQuestion(current)];
    final nextIndex = state.currentIndex + 1;
    if (nextIndex >= questions.length) {
      state = LearningSessionState(
        phase: SessionPhase.finished,
        questions: questions,
        currentIndex: nextIndex,
        correctCount: state.correctCount,
      );
      return;
    }
    state = LearningSessionState(
      phase: SessionPhase.asking,
      questions: questions,
      currentIndex: nextIndex,
      correctCount: state.correctCount,
    );
  }
}

class _PickedWord {
  final VocabWord word;
  final SessionQuestionSource source;

  const _PickedWord(this.word, this.source);
}

final learningSessionProvider =
    StateNotifierProvider.autoDispose<
      LearningSessionNotifier,
      LearningSessionState
    >((ref) => LearningSessionNotifier(ref));
