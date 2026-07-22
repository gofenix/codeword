import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lib_core/lib_core.dart';
import 'package:lib_content/lib_content.dart';

import 'learning_preferences.dart';

/// Curated first-run list. Existing users keep their persisted selection.
const String kDefaultVocabId = 'qwerty_coder_core';

/// Extract the full vocab id (matching `VocabList.id` in the manifest)
/// from a qwerty word id.
///
/// `qwerty_<slug>_<5digit>` → `qwerty_<slug>`. Old `cs_001` / `ai_022` ids
/// from the pre-qwerty era are wiped by ReviewRepository's schemaVersion
/// gate, so we don't need to handle them here.
String _extractVocabIdFromWordId(String wid) {
  final parts = wid.split('_');
  if (parts.length < 3 || parts[0] != 'qwerty') return wid;
  return 'qwerty_${parts.sublist(1, parts.length - 1).join('_')}';
}

/// Whether the selected vocab still has words to study (due or unseen).
/// Mirrors [LearningSessionNotifier.start] — excludes removed words and
/// treats a vocab as done only when every non-removed word is seen and
/// nothing eligible is currently due.
bool canStartLearningForVocab(ReviewStats stats, String vocabId) {
  for (final v in stats.perVocab) {
    if (v.vocabId == vocabId) {
      return v.due > 0 || v.unseenWords > 0;
    }
  }
  return false;
}

/// Vocab-scoped progress for the home card. Returns null when [vocabId]
/// is absent from [stats.perVocab] (e.g. empty catalog in tests).
VocabProgress? vocabProgressFor(ReviewStats stats, String vocabId) {
  for (final v in stats.perVocab) {
    if (v.vocabId == vocabId) return v;
  }
  return null;
}

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

  int get rank => MasteryLevel.values.length - 1 - index;
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
  final int removedWords; // user-marked removed in this list
  final int seen; // non-removed words with a review state
  final int learned; // words with repetitions >= 1
  final int mastered; // familiar or recognized by the mastery classifier
  final int due; // non-removed words due for review
  final double averageEasiness;

  const VocabProgress({
    required this.vocabId,
    required this.name,
    required this.emoji,
    required this.totalWords,
    this.removedWords = 0,
    required this.seen,
    required this.learned,
    this.mastered = 0,
    required this.due,
    required this.averageEasiness,
  });

  int get availableWords => max(0, totalWords - removedWords);

  int get unseenWords => max(0, availableWords - seen);

  double get coverage => availableWords == 0 ? 0 : learned / availableWords;

  double get masteryCoverage =>
      availableWords == 0 ? 0 : mastered / availableWords;
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

final learningDataClearInProgressProvider = StateProvider<bool>((ref) {
  try {
    return ReviewRepository.instance.pendingLearningDataClear;
  } catch (_) {
    return false;
  }
});

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
    // Fire-and-forget: these return immediately (just schedule a flush),
    // but we must NOT swallow their Future errors — if the scheduler or
    // storage backend throws we want it to surface via the uncaught
    // handler / zone rather than silently dropping the mutation.
    try {
      ReviewRepository.instance.put(wordId, next);
      ReviewRepository.instance.recordActivity(at);
    } catch (_) {
      // In-app memory state (state map) is already updated; storage
      // failures are reported but don't fail the call. A failing
      // put()/recordActivity() here simply means the debounced flush
      // will retry on the next mutation.
    }
    return next;
  }

  Future<void> clearLearningData() async {
    await ReviewRepository.instance.clearLearningData();
    state = const {};
  }

  int get totalLearned {
    final removed = _removedWordIds();
    return state.entries
        .where((e) => !removed.contains(e.key) && e.value.repetitions >= 1)
        .length;
  }

  int get totalDue {
    final now = DateTime.now();
    final removed = _removedWordIds();
    return state.entries
        .where(
          (e) =>
              !removed.contains(e.key) &&
              e.value.dueAt != null &&
              !e.value.dueAt!.isAfter(now),
        )
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

  /// Most recently answered words today, used to reinforce the actual
  /// learning session in AI reading instead of introducing unrelated terms.
  Future<List<PulseWordEntry>> reviewedTodayWords({
    int limit = 10,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final start = DateTime(at.year, at.month, at.day);
    final removed = _removedWordIds();
    final entries =
        state.entries
            .where(
              (entry) =>
                  !removed.contains(entry.key) &&
                  entry.value.lastReviewedAt != null &&
                  !entry.value.lastReviewedAt!.isBefore(start),
            )
            .toList()
          ..sort(
            (a, b) =>
                b.value.lastReviewedAt!.compareTo(a.value.lastReviewedAt!),
          );
    return _hydrate(entries: entries.take(limit).toList(), at: at);
  }

  /// Top-N recommended new words. Picks the vocab with the lowest
  /// coverage that still has unseen words, then returns the first few
  /// of those.
  ///
  /// Falls back to the curated Coder Core list if every vocab is learned.
  Future<List<PulseWordEntry>> recommendedNewWords({
    int limit = 3,
    required List<VocabList> catalog,
  }) async {
    final stats = this.stats(catalog: catalog);
    String? targetId;
    double lowestCoverage = double.infinity;
    for (final v in stats.perVocab) {
      final unseen = v.unseenWords;
      if (unseen > 0 && v.coverage < lowestCoverage) {
        lowestCoverage = v.coverage;
        targetId = v.vocabId;
      }
    }
    targetId ??= kDefaultVocabId;
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
      final vid = _extractVocabIdFromWordId(e.key);
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
          // State may have changed during the async suspension above
          // (e.g. a concurrent learning session recorded an answer).
          // Use null-aware access instead of `!` to stay safe.
          final s = state[wid];
          if (s == null) continue;
          final due = s.dueAt;
          final overdue = due == null ? 0 : at.difference(due).inDays;
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
  /// [catalog] is the qwerty vocab list manifest — passed in because
  /// StateNotifier doesn't have access to a Riverpod `ref`.
  ReviewStats stats({DateTime? now, required List<VocabList> catalog}) {
    final at = now ?? DateTime.now();
    final today = DateTime(at.year, at.month, at.day);
    final tomorrow = today.add(const Duration(days: 1));

    int reviewsToday = 0;
    int newToday = 0;
    int due = 0;
    int sumEf = 0;
    int activeSeen = 0;
    int activeLearned = 0;
    final masteryCount = <MasteryLevel, int>{
      for (final l in MasteryLevel.values) l: 0,
    };
    final perVocabStats = <String, _MutableVocabStats>{};
    var removedIds = <String>{};
    try {
      removedIds = ReviewRepository.instance.removed;
    } catch (_) {
      // Repository not initialised — treat as no removals.
    }

    void accumulate(String wordId, String vocabId, ReviewState s) {
      if (s.lastReviewedAt != null &&
          !s.lastReviewedAt!.isBefore(today) &&
          s.lastReviewedAt!.isBefore(tomorrow)) {
        reviewsToday++;
      }
      if (s.firstReviewedAt != null &&
          !s.firstReviewedAt!.isBefore(today) &&
          s.firstReviewedAt!.isBefore(tomorrow)) {
        newToday++;
      }
      if (removedIds.contains(wordId)) return;
      activeSeen++;
      sumEf += s.easiness;
      if (s.dueAt != null && !s.dueAt!.isAfter(at)) due++;
      final ef = s.easiness / 100.0;
      final bucket = _classify(ef, s.repetitions);
      masteryCount[bucket] = (masteryCount[bucket] ?? 0) + 1;
      final v = perVocabStats.putIfAbsent(vocabId, () => _MutableVocabStats());
      if (bucket == MasteryLevel.familiar ||
          bucket == MasteryLevel.recognized) {
        v.mastered++;
      }
      v.seen++;
      v.sumEf += s.easiness;
      if (s.repetitions >= 1) {
        v.learned++;
        activeLearned++;
      }
      if (s.dueAt != null && !s.dueAt!.isAfter(at)) v.due++;
    }

    for (final entry in state.entries) {
      final vocabId = _extractVocabIdFromWordId(entry.key);
      accumulate(entry.key, vocabId, entry.value);
    }

    final avg = activeSeen == 0 ? 0.0 : sumEf / activeSeen / 100.0;

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

    final removedPerVocab = <String, int>{};
    for (final id in removedIds) {
      final vid = _extractVocabIdFromWordId(id);
      removedPerVocab[vid] = (removedPerVocab[vid] ?? 0) + 1;
    }

    final meta = catalog;
    final perVocabOut = <VocabProgress>[];
    for (final list in meta) {
      final total = list.wordCount;
      final removedInVocab = removedPerVocab[list.id] ?? 0;
      final available = max(0, total - removedInVocab);
      final m = perVocabStats[list.id] ?? _MutableVocabStats();
      masteryCount[MasteryLevel.unseen] =
          (masteryCount[MasteryLevel.unseen] ?? 0) + max(0, available - m.seen);
      perVocabOut.add(
        VocabProgress(
          vocabId: list.id,
          name: list.name,
          emoji: list.emoji,
          totalWords: total,
          removedWords: removedInVocab,
          seen: m.seen,
          learned: m.learned,
          mastered: m.mastered,
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
      totalSeen: activeSeen,
      totalLearned: activeLearned,
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
}

class _MutableVocabStats {
  int seen = 0;
  int learned = 0;
  int mastered = 0;
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

/// qwerty-learner derived catalog. Loaded once from
/// `assets/vocab/_qwerty_index.json`. The `main()` bootstrap awaits this
/// and injects the resolved list via [ProviderScope.overrides] so that
/// downstream providers can read it synchronously.
final qwertyCatalogProvider = Provider<List<VocabList>>((ref) {
  throw UnimplementedError(
    'qwertyCatalogProvider must be overridden in main() after awaiting '
    'loadQwertyCatalog().',
  );
});

/// Metadata for a vocabulary (synchronous, no asset load needed).
final vocabMetaProvider = Provider<Map<String, VocabList>>((ref) {
  return {for (final l in ref.watch(qwertyCatalogProvider)) l.id: l};
});

/// The vocab the user has selected as their "current" book.
/// Persisted in ReviewRepository so it survives app restarts.
/// Falls back to [kDefaultVocabId] if the user hasn't picked one.
///
/// A note on ordering: the main() bootstrap awaits ReviewRepository.init()
/// BEFORE runApp, so read-through-to-instance is always safe for the
/// initial build. If hot-restart / testing ever bypasses init, the
/// catch fallback returns the default.
final selectedVocabProvider = StateProvider<String>((ref) {
  try {
    return ReviewRepository.instance.selectedVocabId ?? kDefaultVocabId;
  } catch (_) {
    return kDefaultVocabId;
  }
});

enum QuestionType {
  seeWordPickMeaning,
  seeMeaningPickWord,
  listenPickMeaning,
  typeWord,
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
  final QuestionType? retryOfType;

  const LearningQuestion({
    required this.word,
    required this.type,
    required this.options,
    required this.correctIndex,
    this.prompt = '',
    this.source = SessionQuestionSource.newWord,
    this.attemptNo = 0,
    this.retryOfType,
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

  bool get isCorrect => lastAnswer != null && lastAnswer != AnswerQuality.again;
}

class LearningSessionNotifier extends StateNotifier<LearningSessionState> {
  static const _bufferSize = 16;
  static const _refillThreshold = 5;

  final Ref ref;
  final Random _rng = Random();

  /// Stale-call guard. Incremented per [start()]; any pending async
  /// work that returns with a mismatched counter is discarded.
  int _startGen = 0;
  int? _refillingForGen;
  int _questionSerial = 0;
  int _activeSeconds = 0;
  DateTime? _lastInteractionAt;
  String? _activeVocabId;

  /// Full owning-vocabulary pools for mixed cross-book review questions.
  final Map<String, List<VocabWord>> _vocabPools = {};

  LearningSessionNotifier(this.ref) : super(LearningSessionState.loading());

  /// Starts an endless, memory-curve-driven learning queue.
  Future<void> start({required String vocabId}) async {
    final gen = ++_startGen;
    _activeVocabId = vocabId;
    _refillingForGen = null;
    _questionSerial = 0;
    _activeSeconds = 0;
    _lastInteractionAt = DateTime.now();
    state = LearningSessionState.loading();
    await ref.read(learningPreferencesProvider.notifier).ready;
    if (gen != _startGen) return;
    final raw = await ref.read(vocabCacheProvider(vocabId).future);
    if (gen != _startGen) return;
    final removed = _removedWordIds();
    final all = raw.where((w) => !removed.contains(w.id)).toList();
    _vocabPools
      ..clear()
      ..[vocabId] = all;
    await _ensureBuffer(force: true, gen: gen);
  }

  Future<void> _ensureBuffer({bool force = false, int? gen}) async {
    final activeGen = gen ?? _startGen;
    if (activeGen != _startGen || _activeVocabId == null) return;
    final remaining = state.questions.length - state.currentIndex;
    if (!force && remaining > _refillThreshold) return;
    if (_refillingForGen == activeGen) return;
    _refillingForGen = activeGen;
    try {
      _compactConsumed();
      final excluded = state.questions.map((q) => q.word.id).toSet();
      final needed = max(0, _bufferSize - state.questions.length);
      final additions = await _buildEligibleQuestions(
        vocabId: _activeVocabId!,
        limit: needed,
        excludedIds: excluded,
        gen: activeGen,
      );
      if (activeGen != _startGen) return;

      final pendingIds = state.questions.map((q) => q.word.id).toSet();
      final fresh = additions.where((q) => pendingIds.add(q.word.id)).toList();
      final questions = [...state.questions, ...fresh];
      final hasCurrent = state.currentIndex < questions.length;
      state = LearningSessionState(
        phase: hasCurrent
            ? (state.phase == SessionPhase.wrongDetail
                  ? SessionPhase.wrongDetail
                  : SessionPhase.asking)
            : SessionPhase.finished,
        questions: questions,
        currentIndex: hasCurrent ? state.currentIndex : questions.length,
        correctCount: state.correctCount,
        lastAnswer: state.lastAnswer,
        lastSelectedIndex: state.lastSelectedIndex,
        lastQuestionQueuedForRetry: state.lastQuestionQueuedForRetry,
      );
    } finally {
      if (_refillingForGen == activeGen) _refillingForGen = null;
    }
  }

  Future<List<LearningQuestion>> _buildEligibleQuestions({
    required String vocabId,
    required int limit,
    required Set<String> excludedIds,
    required int gen,
  }) async {
    if (limit <= 0) return const [];
    final removed = _removedWordIds();
    final reviewMap = ref.read(reviewStateProvider);
    final now = DateTime.now();
    final dueEntries = reviewMap.entries.where((entry) {
      final dueAt = entry.value.dueAt;
      return !removed.contains(entry.key) &&
          !excludedIds.contains(entry.key) &&
          dueAt != null &&
          !dueAt.isAfter(now);
    }).toList()..sort((a, b) => a.value.dueAt!.compareTo(b.value.dueAt!));

    final dueIdsByVocab = <String, Set<String>>{};
    for (final entry in dueEntries) {
      dueIdsByVocab
          .putIfAbsent(_extractVocabIdFromWordId(entry.key), () => <String>{})
          .add(entry.key);
    }
    final dueById = <String, VocabWord>{};
    for (final entry in dueIdsByVocab.entries) {
      try {
        final words =
            _vocabPools[entry.key] ??
            (await ref.read(
              vocabCacheProvider(entry.key).future,
            )).where((word) => !removed.contains(word.id)).toList();
        if (gen != _startGen) return const [];
        _vocabPools[entry.key] = words;
        for (final word in words) {
          if (entry.value.contains(word.id)) dueById[word.id] = word;
        }
      } catch (_) {
        // One unavailable optional list must not block the rest of the queue.
      }
    }

    final picked = <_PickedWord>[];
    for (final entry in dueEntries) {
      final word = dueById[entry.key];
      if (word == null) continue;
      picked.add(_PickedWord(word, SessionQuestionSource.due));
      if (picked.length == limit) break;
    }
    if (picked.length < limit) {
      final currentWords = _vocabPools[vocabId] ?? const <VocabWord>[];
      for (final word in currentWords) {
        if (reviewMap.containsKey(word.id) ||
            removed.contains(word.id) ||
            excludedIds.contains(word.id)) {
          continue;
        }
        picked.add(_PickedWord(word, SessionQuestionSource.newWord));
        if (picked.length == limit) break;
      }
    }

    final preferences = ref.read(learningPreferencesProvider);
    return picked.map((pickedWord) {
      final type = _nextQuestionType(preferences);
      return _buildQuestion(
        pickedWord.word,
        type,
        _candidatePool(pickedWord.word),
        source: pickedWord.source,
      );
    }).toList();
  }

  void _compactConsumed() {
    if (state.currentIndex == 0 || state.phase == SessionPhase.wrongDetail) {
      return;
    }
    final remaining = state.questions.sublist(state.currentIndex);
    state = LearningSessionState(
      phase: remaining.isEmpty ? SessionPhase.loading : state.phase,
      questions: remaining,
      currentIndex: 0,
      correctCount: state.correctCount,
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
    QuestionType? retryOfType,
  }) {
    final pool = all.where((o) => o.id != w.id).toList();
    switch (type) {
      case QuestionType.seeWordPickMeaning:
        final correct = _compactMeaning(w.translation);
        final ranked = [...pool]
          ..sort((a, b) => _meaningScore(w, a).compareTo(_meaningScore(w, b)));
        final distractors = _uniqueOptions(
          ranked.map((word) => _compactMeaning(word.translation)),
          correct,
          fallbacks: _fallbackMeanings,
        );
        final allOptions = <String>[...distractors, correct]..shuffle(_rng);
        final idx = allOptions.indexOf(correct);
        return LearningQuestion(
          word: w,
          type: type,
          options: allOptions,
          correctIndex: idx < 0 ? allOptions.length - 1 : idx,
          prompt: w.word,
          source: source,
          attemptNo: attemptNo,
          retryOfType: retryOfType,
        );
      case QuestionType.seeMeaningPickWord:
        final ranked = [...pool]
          ..sort(
            (a, b) => _wordScore(
              w.word,
              a.word,
            ).compareTo(_wordScore(w.word, b.word)),
          );
        final correctW = w.word;
        final distractorsW = _uniqueOptions(
          ranked.map((word) => word.word),
          correctW,
          fallbacks: _fallbackWords,
        );
        final optsW = <String>[...distractorsW, correctW]..shuffle(_rng);
        final idxW = optsW.indexOf(correctW);
        return LearningQuestion(
          word: w,
          type: type,
          options: optsW,
          correctIndex: idxW < 0 ? optsW.length - 1 : idxW,
          prompt: _compactMeaning(w.translation),
          source: source,
          attemptNo: attemptNo,
          retryOfType: retryOfType,
        );
      case QuestionType.listenPickMeaning:
        final correctL = _compactMeaning(w.translation);
        final ranked = [...pool]
          ..sort((a, b) => _meaningScore(w, a).compareTo(_meaningScore(w, b)));
        final distractorsL = _uniqueOptions(
          ranked.map((word) => _compactMeaning(word.translation)),
          correctL,
          fallbacks: _fallbackMeanings,
        );
        final optsL = <String>[...distractorsL, correctL]..shuffle(_rng);
        final idxL = optsL.indexOf(correctL);
        return LearningQuestion(
          word: w,
          type: type,
          options: optsL,
          correctIndex: idxL < 0 ? optsL.length - 1 : idxL,
          prompt: w.word,
          source: source,
          attemptNo: attemptNo,
          retryOfType: retryOfType,
        );
      case QuestionType.typeWord:
        return LearningQuestion(
          word: w,
          type: type,
          options: const [],
          correctIndex: -1,
          prompt: _compactMeaning(w.translation),
          source: source,
          attemptNo: attemptNo,
          retryOfType: retryOfType,
        );
    }
  }

  List<VocabWord> _candidatePool(VocabWord word) {
    final own = _vocabPools[_extractVocabIdFromWordId(word.id)] ?? const [];
    if (own.length >= 4) return own;
    return _vocabPools.values.expand((items) => items).toList();
  }

  static const _fallbackMeanings = [
    '文件或数据集合',
    '执行操作的指令',
    '程序中的输入值',
    '系统返回的结果',
    '可复用的代码单元',
  ];

  static const _fallbackWords = [
    'input',
    'output',
    'buffer',
    'module',
    'runtime',
  ];

  List<String> _uniqueOptions(
    Iterable<String> candidates,
    String correct, {
    required List<String> fallbacks,
  }) {
    final normalizedCorrect = correct.trim().toLowerCase();
    final seen = <String>{normalizedCorrect};
    final result = <String>[];
    for (final candidate in candidates) {
      final value = candidate.trim();
      final normalized = value.toLowerCase();
      if (value.isEmpty || !seen.add(normalized)) continue;
      result.add(value);
      if (result.length == 3) break;
    }
    for (final fallback in fallbacks) {
      if (result.length == 3) break;
      final normalized = fallback.toLowerCase();
      if (seen.add(normalized)) result.add(fallback);
    }
    return result;
  }

  int _meaningScore(VocabWord target, VocabWord candidate) {
    final targetMeaning = _compactMeaning(target.translation);
    final candidateMeaning = _compactMeaning(candidate.translation);
    final posPenalty = _normalizedPos(target) == _normalizedPos(candidate)
        ? 0
        : 80;
    return posPenalty + (targetMeaning.length - candidateMeaning.length).abs();
  }

  String _normalizedPos(VocabWord word) {
    final explicit = word.pos.trim().toLowerCase();
    if (explicit.isNotEmpty) return explicit;
    final match = RegExp(
      r'^(n|v|vt|vi|adj|adv|prep|conj|pron)\.',
    ).firstMatch(word.translation.trim().toLowerCase());
    return match?.group(0) ?? '';
  }

  String _compactMeaning(String raw) {
    var value = raw.split('【').first.trim();
    final parts = value
        .split(RegExp(r'[;；]'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isNotEmpty) value = parts.first;
    if (value.length > 48) value = '${value.substring(0, 47).trimRight()}…';
    return value;
  }

  int _wordScore(String target, String candidate) {
    final a = target.toLowerCase();
    final b = candidate.toLowerCase();
    final prefixBonus = a.isNotEmpty && b.isNotEmpty && a[0] == b[0] ? -3 : 0;
    final suffixBonus =
        a.length > 2 && b.length > 2 && a.endsWith(b.substring(b.length - 2))
        ? -2
        : 0;
    return _editDistance(a, b) * 4 +
        (a.length - b.length).abs() +
        prefixBonus +
        suffixBonus;
  }

  int _editDistance(String a, String b) {
    var previous = List<int>.generate(b.length + 1, (index) => index);
    for (var i = 0; i < a.length; i++) {
      final current = <int>[i + 1];
      for (var j = 0; j < b.length; j++) {
        current.add(
          min(
            min(current[j] + 1, previous[j + 1] + 1),
            previous[j] + (a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1),
          ),
        );
      }
      previous = current;
    }
    return previous.last;
  }

  List<QuestionType> _enabledQuestionTypes(LearningPreferences preferences) {
    return [
      QuestionType.seeWordPickMeaning,
      QuestionType.seeMeaningPickWord,
      if (preferences.listeningEnabled) QuestionType.listenPickMeaning,
      if (preferences.spellingEnabled) QuestionType.typeWord,
    ];
  }

  QuestionType _nextQuestionType(
    LearningPreferences preferences, {
    QuestionType? excluded,
  }) {
    final enabled = _enabledQuestionTypes(preferences);
    final candidates = excluded == null
        ? enabled
        : enabled.where((type) => type != excluded).toList();
    final pool = candidates.isEmpty ? enabled : candidates;
    return pool[_questionSerial++ % pool.length];
  }

  void applyPreferences(LearningPreferences preferences) {
    if (state.questions.isEmpty ||
        state.currentIndex >= state.questions.length) {
      return;
    }
    final questions = <LearningQuestion>[];
    for (var i = 0; i < state.questions.length; i++) {
      final question = state.questions[i];
      if (i <= state.currentIndex) {
        questions.add(question);
        continue;
      }
      final type = _nextQuestionType(
        preferences,
        excluded: question.retryOfType,
      );
      questions.add(
        _buildQuestion(
          question.word,
          type,
          _candidatePool(question.word),
          source: question.source,
          attemptNo: question.attemptNo,
          retryOfType: question.retryOfType,
        ),
      );
    }
    state = LearningSessionState(
      phase: state.phase,
      questions: questions,
      currentIndex: state.currentIndex,
      correctCount: state.correctCount,
      lastAnswer: state.lastAnswer,
      lastSelectedIndex: state.lastSelectedIndex,
      lastQuestionQueuedForRetry: state.lastQuestionQueuedForRetry,
    );
  }

  LearningQuestion _buildRetryQuestion(LearningQuestion q) {
    final nextType = _nextQuestionType(
      ref.read(learningPreferencesProvider),
      excluded: q.type,
    );
    return _buildQuestion(
      q.word,
      nextType,
      _candidatePool(q.word),
      source: SessionQuestionSource.retry,
      attemptNo: q.attemptNo + 1,
      retryOfType: q.type,
    );
  }

  /// Best-effort durable write after each answer. Complements the
  /// 300 ms debounce in [ReviewRepository.put] so a force-quit right
  /// after answering still lands progress on disk.
  Future<void> _eagerFlush() async {
    try {
      await ReviewRepository.instance.flush();
    } catch (_) {
      // Repository not initialised (tests / degraded launch).
    }
  }

  /// User picks an option; correct → immediately next, wrong → wrongDetail.
  void answer(int optionIndex) {
    if (state.phase != SessionPhase.asking) return;
    final q = state.currentQuestion;
    if (q == null) return; // defensive: shouldn't happen in asking phase
    _recordAnswer(
      correct: optionIndex == q.correctIndex,
      selectedIndex: optionIndex,
    );
  }

  /// Objective active recall: whitespace and letter case are ignored.
  void answerTyped(String value) {
    if (state.phase != SessionPhase.asking) return;
    final q = state.currentQuestion;
    if (q == null || q.type != QuestionType.typeWord) return;
    _recordAnswer(
      correct: value.trim().toLowerCase() == q.word.word.trim().toLowerCase(),
      selectedIndex: null,
    );
  }

  void _recordAnswer({required bool correct, required int? selectedIndex}) {
    final q = state.currentQuestion;
    if (q == null) return;
    final quality = correct
        ? (q.source == SessionQuestionSource.retry
              ? AnswerQuality.hard
              : AnswerQuality.good)
        : AnswerQuality.again;
    ref
        .read(reviewStateProvider.notifier)
        .recordAnswer(wordId: q.word.id, quality: quality.toSm2Quality());
    _recordActiveStudyTime();
    unawaited(_eagerFlush());
    if (correct) {
      final nextIndex = state.currentIndex + 1;
      state = LearningSessionState(
        phase: nextIndex >= state.questions.length
            ? SessionPhase.loading
            : SessionPhase.asking,
        questions: state.questions,
        currentIndex: nextIndex,
        correctCount: state.correctCount + 1,
      );
      _compactConsumed();
      unawaited(_ensureBuffer(force: state.questions.isEmpty));
    } else {
      state = LearningSessionState(
        phase: SessionPhase.wrongDetail,
        questions: state.questions,
        currentIndex: state.currentIndex,
        correctCount: state.correctCount,
        lastAnswer: quality,
        lastSelectedIndex: selectedIndex,
        lastQuestionQueuedForRetry: true,
      );
      unawaited(_ensureBuffer(force: true));
    }
  }

  /// Advance from wrong-detail and place a changed retry 3–5 items later.
  Future<void> next({bool skipRetry = false}) async {
    if (state.phase != SessionPhase.wrongDetail) return;
    await _ensureBuffer(force: true);
    if (state.phase != SessionPhase.wrongDetail) return;
    final current = state.currentQuestion;
    if (current == null) return;
    final questions = [...state.questions];
    if (!skipRetry) {
      final retryIndex = min(
        questions.length,
        state.currentIndex + 4 + _rng.nextInt(3),
      );
      questions.insert(retryIndex, _buildRetryQuestion(current));
    }
    final nextIndex = state.currentIndex + 1;
    state = LearningSessionState(
      phase: nextIndex < questions.length
          ? SessionPhase.asking
          : SessionPhase.loading,
      questions: questions,
      currentIndex: nextIndex,
      correctCount: state.correctCount,
    );
    _compactConsumed();
    unawaited(_ensureBuffer(force: state.questions.isEmpty));
    unawaited(_eagerFlush());
  }

  void _recordActiveStudyTime() {
    final now = DateTime.now();
    final previous = _lastInteractionAt;
    _lastInteractionAt = now;
    if (previous == null) return;
    _activeSeconds += min(60, max(1, now.difference(previous).inSeconds));
    final minutes = _activeSeconds ~/ 60;
    if (minutes == 0) return;
    _activeSeconds %= 60;
    try {
      unawaited(
        ReviewRepository.instance.addStudyMinutes(DateTime.now(), minutes),
      );
    } catch (_) {}
  }
}

class _PickedWord {
  final VocabWord word;
  final SessionQuestionSource source;

  const _PickedWord(this.word, this.source);
}

final learningSessionProvider =
    StateNotifierProvider<LearningSessionNotifier, LearningSessionState>((ref) {
      final notifier = LearningSessionNotifier(ref);
      ref.listen<LearningPreferences>(learningPreferencesProvider, (
        previous,
        next,
      ) {
        if (previous != null && previous != next) {
          notifier.applyPreferences(next);
        }
      });
      return notifier;
    });
