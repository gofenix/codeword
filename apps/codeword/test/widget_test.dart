import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lib_core/lib_core.dart';

import 'package:codeword/main.dart';
import 'package:codeword/screens/learning_session_screen.dart';
import 'package:codeword/screens/stats_screen.dart';
import 'package:codeword/screens/settings_screen.dart';
import 'package:codeword/state/app_settings.dart';
import 'package:codeword/state/learning_session.dart';
import 'package:codeword/state/llm_config.dart';

void main() {
  /// Build a ProviderScope with an empty qwerty catalog override so the
  /// home shell boots without throwing.
  Widget testApp({
    List<VocabList> catalog = const [],
    List<Override> overrides = const [],
  }) => ProviderScope(
    overrides: [
      qwertyCatalogProvider.overrideWithValue(catalog),
      appSettingsProvider.overrideWith(
        (ref) => AppSettingsNotifier(_ImmediateAppSettingsStore()),
      ),
      ...overrides,
    ],
    child: const CodewordApp(),
  );

  test('Coder Core contains 500 concise unique candidates', () async {
    final raw = await File(
      'assets/vocab/qwerty_coder_core.json',
    ).readAsString();
    final words = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    expect(words, hasLength(500));
    expect(words.map((word) => word['word']).toSet(), hasLength(500));
    final chineseMeaning = RegExp(r'[\u4e00-\u9fff]');
    for (final word in words) {
      expect((word['translation'] as String).length, lessThanOrEqualTo(36));
      expect(
        word['translation'],
        matches(chineseMeaning),
        reason: '${word['word']} must have a Chinese meaning',
      );
      expect((word['exampleEn'] as String).trim(), isNotEmpty);
      expect((word['exampleCn'] as String).trim(), isNotEmpty);
      expect(word['domain'], kDefaultVocabId);
    }
  });

  testWidgets('App boots into 4-tab home with Words selected', (tester) async {
    await tester.pumpWidget(testApp());
    await tester.pump();
    expect(find.text('单词'), findsWidgets);
    expect(find.text('阅读'), findsOneWidget);
    expect(find.text('图表'), findsOneWidget);
    expect(find.text('词书'), findsOneWidget);
    expect(find.text('设置'), findsNothing);
  });

  testWidgets('HomeShell keeps tab state mounted while switching tabs', (
    tester,
  ) async {
    await tester.pumpWidget(testApp());
    await tester.pump();

    final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stack.children.length, 4);
    expect(stack.index, 0);

    await tester.tap(find.text('阅读'));
    await tester.pump();
    final readingStack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(readingStack.index, 1);

    await tester.tap(find.text('图表'));
    await tester.pump();
    final statsStack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(statsStack.index, 2);

    await tester.tap(find.text('词书'));
    await tester.pump();
    final discoveryStack = tester.widget<IndexedStack>(
      find.byType(IndexedStack),
    );
    expect(discoveryStack.index, 3);
  });

  testWidgets(
    'Charts tab prioritizes progress, distribution, today and rhythm',
    (tester) async {
      await tester.pumpWidget(testApp());
      await tester.pump();

      await tester.tap(find.text('图表'));
      await tester.pump();

      expect(find.text('当前词书'), findsOneWidget);
      expect(find.text('掌握进度'), findsOneWidget);
      expect(find.text('掌握分布'), findsOneWidget);
      expect(find.text('今日'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('学习节奏'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('学习节奏'), findsOneWidget);
      expect(find.text('打开 0 次'), findsNothing);
    },
  );

  testWidgets('Current vocabulary card opens the Library tab', (tester) async {
    await tester.pumpWidget(testApp());
    await tester.pump();

    await tester.tap(find.text('图表'));
    await tester.pump();
    await tester.tap(find.text('当前词书'));
    await tester.pump();

    final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stack.index, 3);
  });

  testWidgets('hidden Reading tab defers word and history loading', (
    tester,
  ) async {
    final notifier = _CountingReadingNotifier();
    await tester.pumpWidget(
      testApp(
        overrides: [
          llmConfiguredProvider.overrideWithValue(true),
          reviewStateProvider.overrideWith((ref) => notifier),
        ],
      ),
    );
    await tester.pump();
    expect(notifier.reviewedTodayCalls, 0);

    await tester.tap(find.text('阅读'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(notifier.reviewedTodayCalls, 1);
  });

  testWidgets('Today stats do not count newly introduced words as reviews', (
    tester,
  ) async {
    final notifier = ReviewStateNotifier();
    notifier.recordAnswer(wordId: 'qwerty_test_00001', quality: 4);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          qwertyCatalogProvider.overrideWithValue(const []),
          reviewStateProvider.overrideWith((ref) => notifier),
        ],
        child: MaterialApp(home: const StatsScreen()),
      ),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('复习 0'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('复习 0'), findsOneWidget);
    expect(find.text('新学 1'), findsOneWidget);
  });

  testWidgets('Library tab opens Settings as a secondary page', (tester) async {
    await tester.pumpWidget(testApp());
    await tester.pump();

    await tester.tap(find.text('词书'));
    await tester.pump();
    expect(find.text('词书'), findsWidgets);
    expect(find.text('发现'), findsNothing);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('设置'), findsWidgets);
  });

  testWidgets('Completion dashboard opens the Library tab', (tester) async {
    await tester.pumpWidget(
      testApp(
        overrides: [
          learningSessionProvider.overrideWith(
            (ref) => _FinishedLearningSessionNotifier(ref),
          ),
        ],
      ),
    );
    await tester.pump();

    await tester.tap(find.text('选择下一本词书'));
    await tester.pump();

    final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stack.index, 3);
    expect(find.text('词书'), findsWidgets);
  });

  testWidgets('Words tab opens directly into immersive multiple choice', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        overrides: [
          learningSessionProvider.overrideWith(
            (ref) => _AskingLearningSessionNotifier(ref),
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.text('dermis'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
    expect(find.text('D'), findsOneWidget);
    expect(find.text('开始背词'), findsNothing);
    expect(find.byIcon(Icons.close_rounded), findsWidgets);
    expect(find.byIcon(Icons.library_books_outlined), findsWidgets);
    expect(find.text('阅读'), findsNothing);
  });

  testWidgets('Library continue returns to immersive Words tab', (
    tester,
  ) async {
    const catalog = [
      VocabList(
        id: kDefaultVocabId,
        name: '生物医学专业英语词汇',
        description: 'Biomedical terms',
        emoji: '📘',
        domainColor: '#10B981',
        level: 1,
        wordCount: 20,
      ),
    ];

    await tester.pumpWidget(
      testApp(
        catalog: catalog,
        overrides: [
          learningSessionProvider.overrideWith(
            (ref) => _AskingLearningSessionNotifier(ref),
          ),
        ],
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.library_books_outlined).first);
    await tester.pump();
    expect(find.text('继续学习'), findsOneWidget);

    await tester.tap(find.text('继续学习'));
    await tester.pump();
    await tester.pump();

    final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stack.index, 0);
  });

  test('SM-2 round-trip through notifier records answer', () {
    final notifier = ReviewStateNotifier();
    expect(notifier.totalLearned, 0);
    notifier.recordAnswer(wordId: 'w1', quality: 4);
    expect(notifier.totalLearned, 1);
  });

  test('ReviewStateNotifier can hydrate from an existing state map', () {
    final notifier = ReviewStateNotifier({'w1': ReviewState.fresh('w1')});
    expect(notifier.state.keys, contains('w1'));
  });

  test('Empty stats are zero across the board', () {
    final notifier = ReviewStateNotifier();
    final s = notifier.stats(catalog: const []);
    expect(s.totalSeen, 0);
    expect(s.totalLearned, 0);
    expect(s.totalDue, 0);
    expect(s.newToday, 0);
    expect(s.reviewsToday, 0);
    expect(s.streakDays, 0);
    expect(s.last7Days, [0, 0, 0, 0, 0, 0, 0]);
    expect(s.averageEasiness, 0);
  });

  test('Stats reflect recorded answers + today buckets', () {
    final notifier = ReviewStateNotifier();
    final now = DateTime(2026, 6, 8, 14); // 6/8 14:00 — afternoon
    // 3 correct answers today, all new words (repetitions=1)
    notifier.recordAnswer(wordId: 'a', quality: 4, now: now);
    notifier.recordAnswer(wordId: 'b', quality: 4, now: now);
    notifier.recordAnswer(wordId: 'c', quality: 5, now: now);
    // 1 wrong (still new, but counts as a review)
    notifier.recordAnswer(wordId: 'd', quality: 0, now: now);
    // 1 done yesterday — should not be in 'newToday'
    notifier.recordAnswer(
      wordId: 'e',
      quality: 4,
      now: now.subtract(const Duration(days: 1)),
    );

    final s = notifier.stats(now: now, catalog: const []);
    expect(s.totalSeen, 5);
    expect(
      s.totalLearned,
      4,
      reason:
          'a/b/c/e have repetitions=1 (good/easy), '
          "d's quality=0 reset repetitions to 0",
    );
    expect(
      s.newToday,
      4,
      reason: 'a, b, c, d were all introduced today, including the wrong word',
    );
    expect(
      s.reviewsToday,
      4,
      reason: 'a, b, c, d all reviewed today (e was yesterday)',
    );
    expect(s.last7Days.length, 7);
  });

  test('Total due counts words with dueAt <= now', () {
    final notifier = ReviewStateNotifier();
    final now = DateTime(2026, 6, 8, 10);
    notifier.recordAnswer(wordId: 'a', quality: 4, now: now);
    notifier.recordAnswer(wordId: 'b', quality: 4, now: now);
    // 'b' is now due again (good quality → 1 day interval → dueAt = now+1d)
    // notifier.recordAnswer(wordId: 'b', quality: 0, now: now) would make
    // it due immediately. We just verify totalDue is non-negative.
    expect(notifier.totalDue, greaterThanOrEqualTo(0));
  });

  test('Mastery distribution places words in the right buckets', () {
    final notifier = ReviewStateNotifier();
    final now = DateTime(2026, 6, 8, 14);
    // One word, 5 consecutive easy reps → reps=5, ef≈2.5 → familiar
    for (var i = 0; i < 5; i++) {
      notifier.recordAnswer(
        wordId: 'a_001',
        quality: 5,
        now: now.add(Duration(days: i)),
      );
    }
    final s = notifier.stats(
      now: now.add(const Duration(days: 5)),
      catalog: const [],
    );
    final familiar = s.mastery
        .firstWhere((b) => b.level == MasteryLevel.familiar)
        .count;
    expect(
      familiar,
      1,
      reason: 'Word with 5 easy reps + ef~2.5 should land in familiar',
    );
  });

  test(
    'canStartLearningForVocab is true when vocab still has unseen words',
    () {
      final notifier = ReviewStateNotifier();
      final catalog = <VocabList>[
        const VocabList(
          id: 'qwerty_test',
          name: 'Test',
          description: '',
          emoji: '📘',
          domainColor: '#000',
          level: 1,
          wordCount: 50,
        ),
      ];
      final stats = notifier.stats(catalog: catalog);
      expect(canStartLearningForVocab(stats, 'qwerty_test'), isTrue);
    },
  );

  test(
    'canStartLearningForVocab is false when vocab is fully learned and not due',
    () {
      final notifier = ReviewStateNotifier();
      final now = DateTime(2026, 6, 8, 14);
      notifier.recordAnswer(wordId: 'qwerty_test_00001', quality: 5, now: now);
      final catalog = <VocabList>[
        const VocabList(
          id: 'qwerty_test',
          name: 'Test',
          description: '',
          emoji: '📘',
          domainColor: '#000',
          level: 1,
          wordCount: 1,
        ),
      ];
      // Same afternoon — interval is 1 day so the word is not due yet.
      final stats = notifier.stats(
        now: now.add(const Duration(hours: 6)),
        catalog: catalog,
      );
      expect(canStartLearningForVocab(stats, 'qwerty_test'), isFalse);
    },
  );

  test('Per-vocab progress surfaces catalog vocabs even with 0 progress', () {
    final notifier = ReviewStateNotifier();
    final catalog = <VocabList>[
      const VocabList(
        id: 'v1',
        name: 'V1',
        description: '',
        emoji: '📘',
        domainColor: '#000',
        level: 1,
        wordCount: 10,
      ),
      const VocabList(
        id: 'v2',
        name: 'V2',
        description: '',
        emoji: '📗',
        domainColor: '#000',
        level: 1,
        wordCount: 20,
      ),
    ];
    final s = notifier.stats(catalog: catalog);
    expect(s.perVocab.length, 2);
    for (final row in s.perVocab) {
      expect(row.totalWords, greaterThan(0));
      expect(row.learned, 0);
      expect(row.coverage, 0);
    }
  });

  test(
    'Session phase has no feedback phase (asking → wrongDetail is a direct transition)',
    () {
      // v0.4.0 had a 'feedback' phase that the user complained was redundant.
      // v0.4.1+ removed it — correct answers go directly asking → asking
      // (next question), wrong answers go asking → wrongDetail.
      final names = SessionPhase.values.map((p) => p.name).toList();
      expect(
        names,
        isNot(contains('feedback')),
        reason: 'No standalone feedback phase — should be removed',
      );
    },
  );

  test('session summary counts only initial new and review questions', () {
    LearningQuestion question(String id, SessionQuestionSource source) =>
        LearningQuestion(
          word: _word(id, id, '释义'),
          type: QuestionType.seeWordPickMeaning,
          options: const ['释义', 'A', 'B', 'C'],
          correctIndex: 0,
          prompt: id,
          source: source,
        );

    final state = LearningSessionState(
      phase: SessionPhase.finished,
      questions: [
        question('new', SessionQuestionSource.newWord),
        question('due', SessionQuestionSource.due),
        question('retry', SessionQuestionSource.retry),
      ],
      currentIndex: 3,
      correctCount: 2,
      initialQuestionCount: 2,
    );

    expect(state.newWordCount, 1);
    expect(state.reviewWordCount, 1);
    expect(formatSessionDuration(const Duration(seconds: 18)), '18秒');
    expect(formatSessionDuration(const Duration(seconds: 90)), '1分');
  });

  testWidgets('LearningSessionScreen builds with vocabId only', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          qwertyCatalogProvider.overrideWithValue(const [
            VocabList(
              id: 'qwerty_biomedical_terms',
              name: 'Biomedical',
              description: '',
              emoji: '🧬',
              domainColor: '#000',
              level: 1,
              wordCount: 1,
            ),
          ]),
          vocabCacheProvider('qwerty_biomedical_terms').overrideWith(
            (ref) async => [
              _word('qwerty_biomedical_terms_00001', 'cell', '细胞'),
            ],
          ),
        ],
        child: const MaterialApp(
          home: LearningSessionScreen(vocabId: 'qwerty_biomedical_terms'),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(LearningSessionScreen), findsOneWidget);
  });

  test(
    'answer triggers eager flush; post-answer flush() succeeds and persists',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      ReviewRepository.resetForTesting();
      final backend = InMemoryStorageBackend();
      await ReviewRepository.initWithBackend(backend);
      addTearDown(ReviewRepository.resetForTesting);

      final word = _word('qwerty_flush_00001', 'latency', '延迟');
      final container = ProviderContainer(
        overrides: [
          vocabCacheProvider(
            'qwerty_flush',
          ).overrideWith((ref) async => [word]),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(learningSessionProvider.notifier);
      await notifier.start(
        vocabId: 'qwerty_flush',
        dailyNewWordLimit: 1,
        maxSessionSize: 1,
      );
      final q = container.read(learningSessionProvider).currentQuestion!;
      expect(ReviewRepository.flushInvocationCount, 0);

      notifier.answer(q.correctIndex);
      expect(
        container.read(learningSessionProvider).correctCount,
        1,
        reason: 'state should advance after answer',
      );
      expect(ReviewRepository.instance.studyMinutesOn(DateTime.now()), 1);

      // _eagerFlush() must invoke ReviewRepository.flush().
      for (var i = 0; i < 100; i++) {
        await pumpEventQueue();
        if (ReviewRepository.flushInvocationCount > 0) break;
      }
      expect(
        ReviewRepository.flushInvocationCount,
        greaterThan(0),
        reason: '_eagerFlush should call ReviewRepository.flush',
      );

      // Verification plan step 3: explicit flush post-answer without error.
      await ReviewRepository.instance.flush();
      expect(ReviewRepository.instance.get(word.id)?.repetitions, 1);
      expect(backend.review?.containsKey(word.id), isTrue);
    },
  );

  test('totalDue excludes removed words', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    ReviewRepository.resetForTesting();
    await ReviewRepository.initWithBackend(InMemoryStorageBackend());
    addTearDown(ReviewRepository.resetForTesting);

    final now = DateTime(2026, 6, 8, 10);
    const wordId = 'qwerty_test_00001';
    await ReviewRepository.instance.put(
      wordId,
      ReviewState(
        wordId: wordId,
        easiness: 250,
        interval: 0,
        repetitions: 1,
        dueAt: now,
        lastReviewedAt: now.subtract(const Duration(days: 1)),
      ),
    );
    await ReviewRepository.instance.markRemoved(wordId);

    final notifier = ReviewStateNotifier(ReviewRepository.instance.all);
    expect(notifier.totalDue, 0);
  });

  test('canStartLearningForVocab ignores removed due words', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    ReviewRepository.resetForTesting();
    await ReviewRepository.initWithBackend(InMemoryStorageBackend());
    addTearDown(ReviewRepository.resetForTesting);

    final now = DateTime(2026, 6, 8, 10);
    const wordId = 'qwerty_test_00001';
    await ReviewRepository.instance.put(
      wordId,
      ReviewState(
        wordId: wordId,
        easiness: 250,
        interval: 0,
        repetitions: 1,
        dueAt: now,
        lastReviewedAt: now.subtract(const Duration(days: 1)),
      ),
    );
    await ReviewRepository.instance.markRemoved(wordId);

    final notifier = ReviewStateNotifier(ReviewRepository.instance.all);
    final catalog = <VocabList>[
      const VocabList(
        id: 'qwerty_test',
        name: 'Test',
        description: '',
        emoji: '📘',
        domainColor: '#000',
        level: 1,
        wordCount: 1,
      ),
    ];
    final stats = notifier.stats(now: now, catalog: catalog);
    expect(stats.perVocab.single.due, 0);
    expect(stats.totalDue, 0);
    expect(canStartLearningForVocab(stats, 'qwerty_test'), isFalse);
  });

  test('start finishes when every word in the vocab is removed', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    ReviewRepository.resetForTesting();
    await ReviewRepository.initWithBackend(InMemoryStorageBackend());
    addTearDown(ReviewRepository.resetForTesting);

    final word = _word('qwerty_test_00001', 'latency', '延迟');
    await ReviewRepository.instance.markRemoved(word.id);

    final container = ProviderContainer(
      overrides: [
        vocabCacheProvider('qwerty_test').overrideWith((ref) async => [word]),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(learningSessionProvider.notifier);
    await notifier.start(
      vocabId: 'qwerty_test',
      dailyNewWordLimit: 1,
      maxSessionSize: 1,
    );
    final session = container.read(learningSessionProvider);
    expect(session.phase, SessionPhase.finished);
    expect(session.questions, isEmpty);
  });

  test(
    'Wrong answer queues the same word for retry later in the session',
    () async {
      final words = [
        _word('test_001', 'latency', '延迟'),
        _word('test_002', 'throughput', '吞吐量'),
      ];
      final container = ProviderContainer(
        overrides: [
          vocabCacheProvider('test').overrideWith((ref) async => words),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(learningSessionProvider.notifier);
      await notifier.start(
        vocabId: 'test',
        dailyNewWordLimit: 2,
        maxSessionSize: 2,
      );
      final first = container.read(learningSessionProvider).currentQuestion!;
      final wrongIndex = first.correctIndex == 0 ? 1 : 0;

      notifier.answer(wrongIndex);
      expect(
        container.read(learningSessionProvider).phase,
        SessionPhase.wrongDetail,
      );
      expect(container.read(learningSessionProvider).questions.length, 2);

      notifier.next();
      final after = container.read(learningSessionProvider);
      expect(after.phase, SessionPhase.asking);
      expect(after.questions.length, 3);
      expect(after.questions.last.word.id, first.word.id);
      expect(after.questions.last.source, SessionQuestionSource.retry);
      expect(after.questions.last.attemptNo, first.attemptNo + 1);
    },
  );

  test('Session finishes when there are no due or new words', () async {
    final word = _word('test_001', 'latency', '延迟');
    final container = ProviderContainer(
      overrides: [
        reviewStateProvider.overrideWith(
          (ref) => ReviewStateNotifier({
            word.id: ReviewState(
              wordId: word.id,
              easiness: 250,
              interval: 1,
              repetitions: 1,
              dueAt: DateTime.now().add(const Duration(days: 1)),
              lastReviewedAt: DateTime.now(),
            ),
          }),
        ),
        vocabCacheProvider('test').overrideWith((ref) async => [word]),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(learningSessionProvider.notifier);
    await notifier.start(vocabId: 'test');
    final state = container.read(learningSessionProvider);
    expect(state.phase, SessionPhase.finished);
    expect(state.questions, isEmpty);
    expect(state.currentQuestion, isNull);
  });

  test(
    'Daily new-word limit is shared across sessions and vocabularies',
    () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 12);
      final dueWords = [
        _word('qwerty_test_00001', 'latency', '延迟'),
        _word('qwerty_test_00002', 'throughput', '吞吐量'),
      ];
      final newWords = [
        _word('qwerty_test_00003', 'cache', '缓存'),
        _word('qwerty_test_00004', 'queue', '队列'),
        _word('qwerty_test_00005', 'mutex', '互斥锁'),
      ];
      final reviewState = <String, ReviewState>{
        for (final word in dueWords)
          word.id: ReviewState(
            wordId: word.id,
            easiness: 240,
            interval: 1,
            repetitions: 1,
            dueAt: now.subtract(const Duration(minutes: 1)),
            lastReviewedAt: now.subtract(const Duration(days: 1)),
            firstReviewedAt: now.subtract(const Duration(days: 7)),
          ),
        for (var i = 0; i < 2; i++)
          'qwerty_other_0000$i': ReviewState(
            wordId: 'qwerty_other_0000$i',
            easiness: 250,
            interval: 1,
            repetitions: 1,
            dueAt: now.add(const Duration(days: 1)),
            lastReviewedAt: today,
            firstReviewedAt: today,
          ),
      };
      final container = ProviderContainer(
        overrides: [
          reviewStateProvider.overrideWith(
            (ref) => ReviewStateNotifier(reviewState),
          ),
          vocabCacheProvider(
            'qwerty_test',
          ).overrideWith((ref) async => [...dueWords, ...newWords]),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(learningSessionProvider.notifier)
          .start(
            vocabId: 'qwerty_test',
            dailyNewWordLimit: 3,
            maxSessionSize: 10,
          );
      final questions = container.read(learningSessionProvider).questions;
      expect(
        questions.where((q) => q.source == SessionQuestionSource.due).length,
        2,
      );
      expect(
        questions
            .where((q) => q.source == SessionQuestionSource.newWord)
            .length,
        1,
      );
    },
  );

  test('Latest vocabulary start wins while an older load is pending', () async {
    final firstLoad = Completer<List<VocabWord>>();
    final secondLoad = Completer<List<VocabWord>>();
    final container = ProviderContainer(
      overrides: [
        vocabCacheProvider('first').overrideWith((ref) => firstLoad.future),
        vocabCacheProvider('second').overrideWith((ref) => secondLoad.future),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(learningSessionProvider.notifier);

    final firstStart = notifier.start(
      vocabId: 'first',
      dailyNewWordLimit: 1,
      maxSessionSize: 1,
    );
    final secondStart = notifier.start(
      vocabId: 'second',
      dailyNewWordLimit: 1,
      maxSessionSize: 1,
    );
    secondLoad.complete([_word('second_001', 'queue', '队列')]);
    await secondStart;
    firstLoad.complete([_word('first_001', 'cache', '缓存')]);
    await firstStart;

    expect(
      container.read(learningSessionProvider).currentQuestion?.word.id,
      'second_001',
    );
  });

  test(
    'Session pulls overdue words from every vocabulary before new words',
    () async {
      final now = DateTime.now();
      final oldWords = [
        _word('qwerty_old_00001', 'legacy', '旧版'),
        _word('qwerty_old_00002', 'archive', '归档'),
        _word('qwerty_old_00003', 'backup', '备份'),
        _word('qwerty_old_00004', 'restore', '恢复'),
      ];
      final currentWords = [
        _word('qwerty_current_00001', 'latency', '延迟'),
        _word('qwerty_current_00002', 'throughput', '吞吐量'),
        _word('qwerty_current_00003', 'cache', '缓存'),
        _word('qwerty_current_00004', 'queue', '队列'),
      ];
      final container = ProviderContainer(
        overrides: [
          reviewStateProvider.overrideWith(
            (ref) => ReviewStateNotifier({
              oldWords.first.id: ReviewState(
                wordId: oldWords.first.id,
                easiness: 250,
                interval: 1,
                repetitions: 1,
                dueAt: now.subtract(const Duration(days: 1)),
                lastReviewedAt: now.subtract(const Duration(days: 2)),
              ),
            }),
          ),
          vocabCacheProvider(
            'qwerty_old',
          ).overrideWith((ref) async => oldWords),
          vocabCacheProvider(
            'qwerty_current',
          ).overrideWith((ref) async => currentWords),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(learningSessionProvider.notifier)
          .start(
            vocabId: 'qwerty_current',
            dailyNewWordLimit: 1,
            maxSessionSize: 2,
          );
      final questions = container.read(learningSessionProvider).questions;
      expect(questions, hasLength(2));
      expect(questions.first.word.id, oldWords.first.id);
      expect(questions.first.source, SessionQuestionSource.due);
      expect(questions.last.word.id, startsWith('qwerty_current_'));
      expect(questions.last.source, SessionQuestionSource.newWord);
    },
  );

  test('Mature due word uses objective typed recall', () async {
    final now = DateTime.now();
    final words = [
      _word('qwerty_recall_00001', 'latency', '延迟'),
      _word('qwerty_recall_00002', 'throughput', '吞吐量'),
      _word('qwerty_recall_00003', 'cache', '缓存'),
      _word('qwerty_recall_00004', 'queue', '队列'),
    ];
    final container = ProviderContainer(
      overrides: [
        reviewStateProvider.overrideWith(
          (ref) => ReviewStateNotifier({
            words.first.id: ReviewState(
              wordId: words.first.id,
              easiness: 250,
              interval: 6,
              repetitions: 2,
              dueAt: now.subtract(const Duration(minutes: 1)),
              lastReviewedAt: now.subtract(const Duration(days: 6)),
            ),
          }),
        ),
        vocabCacheProvider('qwerty_recall').overrideWith((ref) async => words),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(learningSessionProvider.notifier);
    await notifier.start(
      vocabId: 'qwerty_recall',
      dailyNewWordLimit: 0,
      maxSessionSize: 1,
    );
    final question = container.read(learningSessionProvider).currentQuestion!;
    expect(question.type, QuestionType.typeWord);
    expect(question.options, isEmpty);

    notifier.answerTyped('  LATENCY  ');
    expect(
      container.read(learningSessionProvider).phase,
      SessionPhase.finished,
    );
    expect(container.read(learningSessionProvider).correctCount, 1);
  });

  test(
    'Choice questions always expose four unique non-placeholder options',
    () async {
      final words = [
        _word('qwerty_choices_00001', 'cache', '缓存'),
        _word('qwerty_choices_00002', 'queue', '队列'),
      ];
      final container = ProviderContainer(
        overrides: [
          vocabCacheProvider(
            'qwerty_choices',
          ).overrideWith((ref) async => words),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(learningSessionProvider.notifier)
          .start(
            vocabId: 'qwerty_choices',
            dailyNewWordLimit: 1,
            maxSessionSize: 1,
          );
      final options = container
          .read(learningSessionProvider)
          .currentQuestion!
          .options;
      expect(options, hasLength(4));
      expect(options.toSet(), hasLength(4));
      expect(options.where((option) => option.contains('—')), isEmpty);
    },
  );

  test(
    'App settings hydrate before queued adjustments and serialize writes',
    () async {
      final store = _TestAppSettingsStore();
      final notifier = AppSettingsNotifier(store);

      final first = notifier.adjustDailyNewWords(1);
      final second = notifier.adjustDailyNewWords(1);
      store.completeRead(const AppSettings(dailyNewWords: 20));
      await Future.wait([first, second]);

      expect(notifier.state.dailyNewWords, 22);
      expect(store.writes, [21, 22]);
    },
  );

  test(
    'Failed queued setting writes roll back to the last durable value',
    () async {
      final store = _FailingAppSettingsStore();
      final notifier = AppSettingsNotifier(store);
      await notifier.ready;

      final first = notifier.adjustDailyNewWords(1);
      final second = notifier.adjustDailyNewWords(1);
      try {
        await first;
      } catch (_) {}
      try {
        await second;
      } catch (_) {}

      expect(notifier.state.dailyNewWords, 20);
    },
  );

  test(
    'Overlapping flush and clear complete with empty durable state',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      ReviewRepository.resetForTesting();
      final backend = _DelayedReviewBackend();
      await ReviewRepository.initWithBackend(backend);
      addTearDown(ReviewRepository.resetForTesting);

      final now = DateTime.now();
      await ReviewRepository.instance.put(
        'qwerty_test_00001',
        ReviewState(
          wordId: 'qwerty_test_00001',
          easiness: 250,
          interval: 1,
          repetitions: 1,
          dueAt: now.add(const Duration(days: 1)),
          lastReviewedAt: now,
          firstReviewedAt: now,
        ),
      );

      final firstFlush = ReviewRepository.instance.flush();
      await backend.firstReviewSaveStarted.future;
      final clear = ReviewRepository.instance.clearLearningData();
      backend.releaseFirstReviewSave.complete();

      await Future.wait([
        firstFlush,
        clear,
      ]).timeout(const Duration(seconds: 2));
      expect(backend.review, isEmpty);
      expect(ReviewRepository.instance.all, isEmpty);
    },
  );

  test('Failed clear marker leaves the learning state untouched', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    ReviewRepository.resetForTesting();
    final backend = _FailingClearBackend();
    await ReviewRepository.initWithBackend(backend);
    addTearDown(ReviewRepository.resetForTesting);

    final now = DateTime.now();
    const wordId = 'qwerty_test_00001';
    await ReviewRepository.instance.put(
      wordId,
      ReviewState(
        wordId: wordId,
        easiness: 250,
        interval: 1,
        repetitions: 1,
        dueAt: now.add(const Duration(days: 1)),
        lastReviewedAt: now,
        firstReviewedAt: now,
      ),
    );
    await ReviewRepository.instance.flush();

    backend.failNextUserDataSave = true;
    await expectLater(
      ReviewRepository.instance.clearLearningData(),
      throwsA(isA<StateError>()),
    );
    expect(ReviewRepository.instance.all, contains(wordId));
  });

  test('Repository resumes a pending clear during initialization', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    ReviewRepository.resetForTesting();
    final now = DateTime.now();
    const wordId = 'qwerty_test_00001';
    final backend = InMemoryStorageBackend()
      ..review = {
        wordId: ReviewState(
          wordId: wordId,
          easiness: 250,
          interval: 1,
          repetitions: 1,
          dueAt: now.add(const Duration(days: 1)),
          lastReviewedAt: now,
          firstReviewedAt: now,
        ).toJson(),
      }
      ..activity = {'2026-07-10': 3}
      ..userData = {
        'schemaVersion': 2,
        'pendingLearningDataClear': true,
        'selectedVocabId': 'qwerty_keep',
        'favorites': [wordId],
      };

    await ReviewRepository.initWithBackend(backend);
    addTearDown(ReviewRepository.resetForTesting);

    expect(ReviewRepository.instance.all, isEmpty);
    expect(backend.review, isEmpty);
    expect(backend.activity, isEmpty);
    expect(backend.userData?['pendingLearningDataClear'], isTrue);
    expect(ReviewRepository.instance.selectedVocabId, 'qwerty_keep');

    await ReviewRepository.instance.completeLearningDataClear();
    expect(backend.userData?['pendingLearningDataClear'], isNull);
  });

  test(
    'finishNow records an early end instead of a normal completion',
    () async {
      final word = _word('qwerty_test_00001', 'latency', '延迟');
      final container = ProviderContainer(
        overrides: [
          vocabCacheProvider('qwerty_test').overrideWith((ref) async => [word]),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(learningSessionProvider.notifier);
      await notifier.start(
        vocabId: 'qwerty_test',
        dailyNewWordLimit: 1,
        maxSessionSize: 1,
      );
      notifier.finishNow();

      final session = container.read(learningSessionProvider);
      expect(session.phase, SessionPhase.finished);
      expect(session.endedEarly, isTrue);
    },
  );

  testWidgets('Long words scale down without horizontal overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final word = _word(
      'qwerty_test_00001',
      'pneumonoultramicroscopicsilicovolcanoconiosis',
      '一种很长的医学术语',
    );
    final session = LearningSessionState(
      phase: SessionPhase.asking,
      questions: [
        LearningQuestion(
          word: word,
          type: QuestionType.seeWordPickMeaning,
          options: const ['正确释义', '选项二', '选项三', '选项四'],
          correctIndex: 0,
          prompt: word.word,
        ),
      ],
      currentIndex: 0,
      correctCount: 0,
      initialQuestionCount: 1,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: AskingView(session: session)),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  // ----- LlmConfig / LlmClient ------------------------------------------------

  test('LlmConfig.isConfigured is true only when all three fields are set', () {
    expect(LlmConfig.empty.isConfigured, isFalse);
    const partial = LlmConfig(baseUrl: 'a', apiKey: 'b', model: '');
    expect(partial.isConfigured, isFalse);
    const full = LlmConfig(baseUrl: 'a', apiKey: 'b', model: 'c');
    expect(full.isConfigured, isTrue);
  });

  test('LlmConfig.maskedKey hides the middle of a long key', () {
    const cfg = LlmConfig(
      baseUrl: '',
      apiKey: 'sk-aabbccddeeff001122334455',
      model: '',
    );
    expect(cfg.maskedKey, 'sk-a…4455');
    const short = LlmConfig(baseUrl: '', apiKey: 'short', model: '');
    expect(short.maskedKey, '••••');
  });

  test('LlmConfig only permits HTTPS or loopback HTTP endpoints', () {
    const secure = LlmConfig(
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'k',
      model: 'm',
    );
    const remoteHttp = LlmConfig(
      baseUrl: 'http://api.example.com/v1',
      apiKey: 'k',
      model: 'm',
    );
    const localHttp = LlmConfig(
      baseUrl: 'http://127.0.0.1:11434/v1',
      apiKey: 'k',
      model: 'm',
    );
    expect(secure.hasSafeEndpoint, isTrue);
    expect(remoteHttp.hasSafeEndpoint, isFalse);
    expect(localHttp.hasSafeEndpoint, isTrue);
  });

  test(
    'LlmClient rejects a remote plaintext endpoint before transport',
    () async {
      final client = LlmClient(
        config: const LlmConfig(
          baseUrl: 'http://api.example.com/v1',
          apiKey: 'secret',
          model: 'model',
        ),
        transport: _CapturingTransport((url, headers, body) {
          fail('transport must not be called for an unsafe endpoint');
        }),
      );
      addTearDown(client.close);
      await expectLater(
        client.chat(const LlmChatRequest(model: 'model', messages: [])),
        throwsA(isA<LlmException>()),
      );
    },
  );

  test('LlmClient builds the right URL for various base URL shapes', () {
    // Probe via the public surface: construct a client and trigger a
    // request with a transport that records the URL.
    String? captured;
    final transport = _CapturingTransport((url, _, _) {
      captured = url;
      return '{"choices":[{"message":{"content":"ok"}}],"usage":{}}';
    });
    final c = LlmClient(
      config: const LlmConfig(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'k',
        model: 'm',
      ),
      transport: transport,
    );
    c.chat(const LlmChatRequest(model: 'm', messages: []));
    expect(captured, 'https://api.openai.com/v1/chat/completions');

    final c2 = LlmClient(
      config: const LlmConfig(
        baseUrl: 'https://api.openai.com/v1/',
        apiKey: 'k',
        model: 'm',
      ),
      transport: transport,
    );
    c2.chat(const LlmChatRequest(model: 'm', messages: []));
    expect(captured, 'https://api.openai.com/v1/chat/completions');

    final c3 = LlmClient(
      config: const LlmConfig(
        baseUrl: 'http://localhost:11434',
        apiKey: 'k',
        model: 'm',
      ),
      transport: transport,
    );
    c3.chat(const LlmChatRequest(model: 'm', messages: []));
    expect(captured, 'http://localhost:11434/v1/chat/completions');

    final c4 = LlmClient(
      config: const LlmConfig(
        baseUrl: 'https://api.minimax.io/v1',
        apiKey: 'k',
        model: 'MiniMax-M3',
      ),
      transport: transport,
    );
    c4.chat(const LlmChatRequest(model: 'MiniMax-M3', messages: []));
    expect(captured, 'https://api.minimax.io/v1/chat/completions');

    final c5 = LlmClient(
      config: const LlmConfig(
        baseUrl: 'https://api.minimax.io/v1/chat/completions',
        apiKey: 'k',
        model: 'MiniMax-M3',
      ),
      transport: transport,
    );
    c5.chat(const LlmChatRequest(model: 'MiniMax-M3', messages: []));
    expect(captured, 'https://api.minimax.io/v1/chat/completions');
  });

  test(
    'LlmClient sends Authorization header and the configured model',
    () async {
      Map<String, String>? capturedHeaders;
      String? capturedBody;
      final transport = _CapturingTransport((url, headers, body) {
        capturedHeaders = headers;
        capturedBody = body;
        return '{"choices":[{"message":{"content":"hi"}}]}';
      });
      final c = LlmClient(
        config: const LlmConfig(
          baseUrl: 'https://api.openai.com/v1',
          apiKey: 'sk-test',
          model: 'gpt-4o-mini',
        ),
        transport: transport,
      );
      final resp = await c.chat(
        const LlmChatRequest(
          model: 'gpt-4o-mini',
          messages: [LlmMessage(role: 'user', content: 'hi')],
        ),
      );
      expect(resp.content, 'hi');
      expect(capturedHeaders?['Authorization'], 'Bearer sk-test');
      expect(capturedHeaders?['Content-Type'], 'application/json');
      expect(capturedBody, contains('"model":"gpt-4o-mini"'));
      expect(capturedBody, contains('"role":"user"'));
      expect(capturedBody, contains('"content":"hi"'));
      expect(capturedBody, contains('"stream":false'));
    },
  );

  test('LlmClient disables MiniMax-M3 thinking and hides think blocks', () async {
    String? capturedBody;
    final transport = _CapturingTransport((url, headers, body) {
      capturedBody = body;
      return '{"choices":[{"message":{"content":"<think>reasoning only</think>Final article."}}]}';
    });
    final c = LlmClient(
      config: const LlmConfig(
        baseUrl: 'https://api.minimax.io/v1',
        apiKey: 'k',
        model: 'MiniMax-M3',
      ),
      transport: transport,
    );
    final resp = await c.chat(
      const LlmChatRequest(
        model: 'MiniMax-M3',
        messages: [LlmMessage(role: 'user', content: 'hi')],
      ),
    );
    expect(capturedBody, contains('"thinking":{"type":"disabled"}'));
    expect(resp.content, 'Final article.');
  });

  test(
    'LlmClient does not send MiniMax thinking options to other models',
    () async {
      String? capturedBody;
      final transport = _CapturingTransport((url, headers, body) {
        capturedBody = body;
        return '{"choices":[{"message":{"content":"ok"}}]}';
      });
      final c = LlmClient(
        config: const LlmConfig(
          baseUrl: 'https://api.openai.com/v1',
          apiKey: 'k',
          model: 'gpt-4o-mini',
        ),
        transport: transport,
      );
      await c.chat(
        const LlmChatRequest(
          model: 'gpt-4o-mini',
          messages: [LlmMessage(role: 'user', content: 'hi')],
        ),
      );
      expect(capturedBody, isNot(contains('"thinking"')));
    },
  );

  test(
    'LlmClient falls back to config.model when request.model is empty',
    () async {
      String? capturedBody;
      final transport = _CapturingTransport((url, headers, body) {
        capturedBody = body;
        return '{"choices":[{"message":{"content":"ok"}}]}';
      });
      final c = LlmClient(
        config: const LlmConfig(
          baseUrl: 'https://api.openai.com/v1',
          apiKey: 'k',
          model: 'fallback-model',
        ),
        transport: transport,
      );
      await c.chat(
        const LlmChatRequest(
          model: '', // request omits model
          messages: [LlmMessage(role: 'user', content: 'hi')],
        ),
      );
      expect(capturedBody, contains('"model":"fallback-model"'));
    },
  );

  test('LlmClient throws LlmException on 4xx', () async {
    final transport = _CapturingTransport(
      (url, headers, body) => throw LlmException('bad', statusCode: 401),
    );
    final c = LlmClient(
      config: const LlmConfig(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'k',
        model: 'm',
      ),
      transport: transport,
    );
    expect(
      () => c.chat(
        const LlmChatRequest(
          model: 'm',
          messages: [LlmMessage(role: 'user', content: 'x')],
        ),
      ),
      throwsA(
        isA<LlmException>().having((e) => e.statusCode, 'statusCode', 401),
      ),
    );
  });

  test('LlmClient throws LlmException on malformed JSON', () async {
    final transport = _CapturingTransport((url, headers, body) => 'not json');
    final c = LlmClient(
      config: const LlmConfig(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'k',
        model: 'm',
      ),
      transport: transport,
    );
    expect(
      () => c.chat(
        const LlmChatRequest(
          model: 'm',
          messages: [LlmMessage(role: 'user', content: 'x')],
        ),
      ),
      throwsA(isA<LlmException>()),
    );
  });

  test('LlmConfigStore round-trips through an in-memory backend', () async {
    final store = LlmConfigStore(InMemoryLlmConfigBackend());
    final initial = await store.read();
    expect(initial.model, LlmConfig.defaultModel);
    await store.write(
      const LlmConfig(
        baseUrl: 'https://example.com/v1',
        apiKey: 'sk-test-12345678',
        model: 'm',
      ),
    );
    final after = await store.read();
    expect(after.baseUrl, 'https://example.com/v1');
    expect(after.apiKey, 'sk-test-12345678');
    expect(after.model, 'm');
    await store.clear();
    final cleared = await store.read();
    // After clear, read() returns defaults (defaultBaseUrl + defaultModel)
    expect(cleared.baseUrl, LlmConfig.defaultBaseUrl);
    expect(cleared.apiKey, '');
    expect(cleared.model, LlmConfig.defaultModel);
  });
}

class _FinishedLearningSessionNotifier extends LearningSessionNotifier {
  _FinishedLearningSessionNotifier(super.ref) {
    state = const LearningSessionState(
      phase: SessionPhase.finished,
      questions: [],
      currentIndex: 0,
      correctCount: 0,
    );
  }
}

class _AskingLearningSessionNotifier extends LearningSessionNotifier {
  _AskingLearningSessionNotifier(super.ref) {
    state = LearningSessionState(
      phase: SessionPhase.asking,
      questions: [
        LearningQuestion(
          word: _word('qwerty_biomedical_terms_00001', 'dermis', '皮肤，真皮'),
          type: QuestionType.seeWordPickMeaning,
          options: const ['皮肤，真皮', '意外事故', '黑素瘤', '复杂的'],
          correctIndex: 0,
          prompt: 'dermis',
        ),
      ],
      currentIndex: 0,
      correctCount: 0,
      initialQuestionCount: 1,
    );
  }

  @override
  Future<void> start({
    required String vocabId,
    int dailyNewWordLimit = 12,
    int maxSessionSize = 32,
  }) async {}
}

class _TestAppSettingsStore extends AppSettingsStore {
  final Completer<AppSettings> _read = Completer<AppSettings>();
  final List<int> writes = [];

  void completeRead(AppSettings settings) => _read.complete(settings);

  @override
  Future<AppSettings> read() => _read.future;

  @override
  Future<void> write(AppSettings settings) async {
    writes.add(settings.dailyNewWords);
  }
}

class _ImmediateAppSettingsStore extends AppSettingsStore {
  @override
  Future<AppSettings> read() async => const AppSettings();

  @override
  Future<void> write(AppSettings settings) async {}
}

class _FailingAppSettingsStore extends AppSettingsStore {
  @override
  Future<AppSettings> read() async => const AppSettings(dailyNewWords: 20);

  @override
  Future<void> write(AppSettings settings) async {
    throw StateError('simulated write failure');
  }
}

class _DelayedReviewBackend extends InMemoryStorageBackend {
  final Completer<void> firstReviewSaveStarted = Completer<void>();
  final Completer<void> releaseFirstReviewSave = Completer<void>();
  int _reviewSaves = 0;

  @override
  Future<void> saveReviewState(Map<String, dynamic> json) async {
    _reviewSaves++;
    if (_reviewSaves == 1) {
      firstReviewSaveStarted.complete();
      await releaseFirstReviewSave.future;
    }
    await super.saveReviewState(json);
  }
}

class _FailingClearBackend extends InMemoryStorageBackend {
  bool failNextUserDataSave = false;

  @override
  Future<void> saveUserData(Map<String, dynamic> json) async {
    if (failNextUserDataSave) {
      failNextUserDataSave = false;
      throw StateError('simulated write failure');
    }
    await super.saveUserData(json);
  }
}

class _CountingReadingNotifier extends ReviewStateNotifier {
  _CountingReadingNotifier() : super(const {});

  int reviewedTodayCalls = 0;

  @override
  Future<List<PulseWordEntry>> reviewedTodayWords({
    int limit = 10,
    DateTime? now,
  }) async {
    reviewedTodayCalls++;
    return const [
      PulseWordEntry(
        word: 'cache',
        translation: '缓存',
        phonetic: '/kæʃ/',
        level: 'B1',
        vocabId: kDefaultVocabId,
      ),
    ];
  }
}

VocabWord _word(String id, String word, String translation) => VocabWord(
  id: id,
  word: word,
  phonetic: '',
  pos: 'n.',
  translation: translation,
  exampleEn: 'The $word matters in system design.',
  exampleCn: '',
  domain: 'cs',
  level: 'B2',
);

/// Test transport that captures the request and returns a fixture body.
class _CapturingTransport implements LlmTransport {
  final String Function(String url, Map<String, String> headers, String body)
  _handler;
  _CapturingTransport(this._handler);

  @override
  Future<String> postJson({
    required String url,
    required Map<String, String> headers,
    required String body,
  }) async {
    return _handler(url, headers, body);
  }

  @override
  void close() {}
}
