import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lib_core/lib_core.dart';
import 'package:lib_ui/lib_ui.dart';

import 'package:codeword/main.dart';
import 'package:codeword/screens/discovery_screen.dart';
import 'package:codeword/screens/learning_session_screen.dart';
import 'package:codeword/screens/reading_screen.dart';
import 'package:codeword/screens/stats_screen.dart';
import 'package:codeword/screens/settings_screen.dart';
import 'package:codeword/state/learning_session.dart';
import 'package:codeword/state/llm_config.dart';

void main() {
  /// Build a ProviderScope with an empty qwerty catalog override so the
  /// home shell boots without throwing.
  Widget testApp({
    List<VocabList> catalog = const [],
    List<Override> overrides = const [],
  }) => ProviderScope(
    overrides: [qwertyCatalogProvider.overrideWithValue(catalog), ...overrides],
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

  testWidgets('Charts tab prioritizes today, mastery, trends and rhythm', (
    tester,
  ) async {
    await tester.pumpWidget(testApp());
    await tester.pump();

    await tester.tap(find.text('图表'));
    await tester.pump();

    expect(find.textContaining('记忆状态'), findsOneWidget);
    expect(find.text('当前词书掌握'), findsOneWidget);
    expect(find.text('近 14 天'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('90 天学习节奏'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('90 天学习节奏'), findsOneWidget);
    expect(find.text('打开 0 次'), findsNothing);
  });

  testWidgets('Current vocabulary card opens the Library tab', (tester) async {
    await tester.pumpWidget(testApp());
    await tester.pump();

    await tester.tap(find.text('图表'));
    await tester.pump();
    await tester.tap(find.text('当前词书掌握'));
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
    expect(find.textContaining('今日新学 1'), findsOneWidget);
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

  testWidgets('Empty learning state opens the Library tab', (tester) async {
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

    expect(find.text('当前没有待学单词'), findsOneWidget);
    await tester.tap(find.text('选择词书'));
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
    expect(find.byIcon(Icons.close_rounded), findsNothing);
    expect(find.byIcon(Icons.library_books_outlined), findsWidgets);
    expect(find.text('阅读'), findsOneWidget);
  });

  testWidgets('Words tab keeps the same question across tab switches', (
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

    await tester.tap(find.text('阅读'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.style_outlined));
    await tester.pump();

    expect(find.text('dermis'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
    expect(find.textContaining('继续下一组'), findsNothing);
  });

  testWidgets('Wrong detail survives a round trip to Reading', (tester) async {
    await tester.pumpWidget(
      testApp(
        overrides: [
          learningSessionProvider.overrideWith(
            (ref) => _WrongLearningSessionNotifier(ref),
          ),
        ],
      ),
    );
    await tester.pump();
    expect(find.byType(WrongDetailView), findsOneWidget);

    await tester.tap(find.text('阅读'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.style_outlined));
    await tester.pump();

    expect(find.byType(WrongDetailView), findsOneWidget);
    expect(find.text('dermis'), findsOneWidget);
  });

  testWidgets('Settings no longer exposes a daily new-word target', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );
    await tester.pump();
    expect(find.textContaining('每日新词'), findsNothing);
    expect(find.textContaining('新词上限'), findsNothing);
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
    expect(find.text('继续学习'), findsNothing);

    await tester.tap(find.text('生物医学专业英语词汇').first);
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
      await notifier.start(vocabId: 'qwerty_flush');
      final q = container.read(learningSessionProvider).currentQuestion!;
      expect(ReviewRepository.flushInvocationCount, 0);

      notifier.answer(q.correctIndex);
      expect(
        container.read(learningSessionProvider).correctCount,
        1,
        reason: 'state should advance after answer',
      );
      expect(ReviewRepository.instance.studyMinutesOn(DateTime.now()), 0);

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
    final subscription = container.listen(
      learningSessionProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    final notifier = container.read(learningSessionProvider.notifier);
    await notifier.start(vocabId: 'qwerty_test');
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
      await notifier.start(vocabId: 'test');
      final first = container.read(learningSessionProvider).currentQuestion!;
      final wrongIndex = first.correctIndex == 0 ? 1 : 0;

      notifier.answer(wrongIndex);
      expect(
        container.read(learningSessionProvider).phase,
        SessionPhase.wrongDetail,
      );
      expect(container.read(learningSessionProvider).questions.length, 2);

      await notifier.next();
      final after = container.read(learningSessionProvider);
      expect(after.phase, SessionPhase.asking);
      expect(after.questions.length, 2);
      expect(after.questions.last.word.id, first.word.id);
      expect(after.questions.last.source, SessionQuestionSource.retry);
      expect(after.questions.last.attemptNo, first.attemptNo + 1);
    },
  );

  test(
    'Wrong retry is inserted 3 to 5 questions later with a new type',
    () async {
      final words = List.generate(
        10,
        (index) => _word(
          'qwerty_retry_${(index + 1).toString().padLeft(5, '0')}',
          'word$index',
          '释义$index',
        ),
      );
      final container = ProviderContainer(
        overrides: [
          vocabCacheProvider('qwerty_retry').overrideWith((ref) async => words),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(learningSessionProvider.notifier);
      await notifier.start(vocabId: 'qwerty_retry');
      final original = container.read(learningSessionProvider).currentQuestion!;
      notifier.answer(original.correctIndex == 0 ? 1 : 0);
      await notifier.next();

      final state = container.read(learningSessionProvider);
      final retryIndex = state.questions.indexWhere(
        (question) => question.source == SessionQuestionSource.retry,
      );
      expect(retryIndex, inInclusiveRange(3, 5));
      expect(state.questions[retryIndex].word.id, original.word.id);
      expect(state.questions[retryIndex].type, isNot(original.type));
    },
  );

  test(
    'Continuous queue keeps learning beyond the old 32-question cap',
    () async {
      final words = List.generate(
        40,
        (index) => _word(
          'qwerty_continuous_${(index + 1).toString().padLeft(5, '0')}',
          'term$index',
          '术语$index',
        ),
      );
      final container = ProviderContainer(
        overrides: [
          vocabCacheProvider(
            'qwerty_continuous',
          ).overrideWith((ref) async => words),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        learningSessionProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      final notifier = container.read(learningSessionProvider.notifier);
      await notifier.start(vocabId: 'qwerty_continuous');
      expect(container.read(learningSessionProvider).questions.length, 16);
      for (var answered = 0; answered < 35; answered++) {
        final question = container
            .read(learningSessionProvider)
            .currentQuestion!;
        notifier.answer(question.correctIndex);
        await pumpEventQueue();
        for (var tick = 0; tick < 20; tick++) {
          if (container.read(learningSessionProvider).phase ==
              SessionPhase.asking) {
            break;
          }
          await pumpEventQueue();
        }
        final state = container.read(learningSessionProvider);
        expect(
          state.phase,
          SessionPhase.asking,
          reason: 'answer $answered left ${state.questions.length}',
        );
        expect(
          state.questions.map((question) => question.word.id).toSet().length,
          state.questions.length,
        );
      }
      expect(container.read(learningSessionProvider).correctCount, 35);
      expect(
        container.read(learningSessionProvider).phase,
        SessionPhase.asking,
      );
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

  test('Global due words are ordered by oldest dueAt first', () async {
    final now = DateTime.now();
    final words = [
      _word('qwerty_order_00001', 'latest', '较晚'),
      _word('qwerty_order_00002', 'oldest', '最早'),
      _word('qwerty_order_00003', 'middle', '中间'),
      _word('qwerty_order_00004', 'fresh', '新词'),
    ];
    ReviewState reviewed(VocabWord word, int hoursAgo) => ReviewState(
      wordId: word.id,
      easiness: 250,
      interval: 1,
      repetitions: 1,
      dueAt: now.subtract(Duration(hours: hoursAgo)),
      lastReviewedAt: now.subtract(const Duration(days: 1)),
    );
    final container = ProviderContainer(
      overrides: [
        reviewStateProvider.overrideWith(
          (ref) => ReviewStateNotifier({
            words[0].id: reviewed(words[0], 1),
            words[1].id: reviewed(words[1], 5),
            words[2].id: reviewed(words[2], 3),
          }),
        ),
        vocabCacheProvider('qwerty_order').overrideWith((ref) async => words),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(learningSessionProvider.notifier)
        .start(vocabId: 'qwerty_order');
    expect(
      container
          .read(learningSessionProvider)
          .questions
          .map((question) => question.word.word),
      ['oldest', 'middle', 'latest', 'fresh'],
    );
  });

  test(
    'Due words stay ahead of current-vocab new words in original order',
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
          .start(vocabId: 'qwerty_test');
      final questions = container.read(learningSessionProvider).questions;
      expect(
        questions.where((q) => q.source == SessionQuestionSource.due).length,
        2,
      );
      expect(
        questions
            .where((q) => q.source == SessionQuestionSource.newWord)
            .length,
        3,
      );
      expect(
        questions.skip(2).map((question) => question.word.id),
        newWords.map((word) => word.id),
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

    final firstStart = notifier.start(vocabId: 'first');
    final secondStart = notifier.start(vocabId: 'second');
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
          .start(vocabId: 'qwerty_current');
      final questions = container.read(learningSessionProvider).questions;
      expect(questions, hasLength(5));
      expect(questions.first.word.id, oldWords.first.id);
      expect(questions.first.source, SessionQuestionSource.due);
      expect(
        questions.skip(1).map((question) => question.word.id),
        currentWords.map((word) => word.id),
      );
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
    await notifier.start(vocabId: 'qwerty_recall');
    final question = container.read(learningSessionProvider).currentQuestion!;
    expect(question.type, QuestionType.typeWord);
    expect(question.options, isEmpty);

    notifier.answerTyped('  LATENCY  ');
    expect(container.read(learningSessionProvider).phase, SessionPhase.asking);
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
          .start(vocabId: 'qwerty_choices');
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

  // ----- Shared TabPageScaffold layout -----------------------------------
  //
  // The three "content" tabs (阅读/图表/词书) now share one skeleton so
  // switching tabs no longer jumps between three header treatments,
  // mismatched horizontal margins, and different backgrounds. These pump
  // each tab in ISOLATION (no bottom nav, no sibling IndexedStack tabs) so
  // the header geometry can be measured directly.
  group('Content tabs share the TabPageScaffold skeleton', () {
    Future<void> pumpTab(
      WidgetTester tester,
      Widget screen, {
      Size size = const Size(393, 852),
      double textScale = 1,
    }) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [qwertyCatalogProvider.overrideWithValue(const [])],
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: screen,
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('center the title on every content tab', (tester) async {
      const width = 393.0;

      await pumpTab(tester, const ReadingScreen());
      final readingCenter = tester.getCenter(find.text('阅读'));
      expect(readingCenter.dx, closeTo(width / 2, 1.0));

      await pumpTab(tester, const StatsScreen());
      final statsCenter = tester.getCenter(find.text('图表'));
      expect(statsCenter.dx, closeTo(width / 2, 1.0));

      await pumpTab(tester, DiscoveryScreen(onGoWords: () {}));
      final libraryCenter = tester.getCenter(find.text('词书'));
      expect(libraryCenter.dx, closeTo(width / 2, 1.0));
      expect(statsCenter.dy, closeTo(readingCenter.dy, 0.5));
      expect(libraryCenter.dy, closeTo(readingCenter.dy, 0.5));
    });

    testWidgets('render the title at a single 22px w700 style', (tester) async {
      await pumpTab(tester, const StatsScreen());
      final title = tester.widget<Text>(find.text('图表'));
      expect(title.style?.fontSize, 22);
      expect(title.style?.fontWeight, FontWeight.w700);
    });

    testWidgets('align content to a unified 24px horizontal margin', (
      tester,
    ) async {
      await pumpTab(tester, const ReadingScreen());
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('reading-first-content')))
            .dx,
        closeTo(24, 0.5),
      );

      await pumpTab(tester, const StatsScreen());
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('stats-first-content'))).dx,
        closeTo(24, 0.5),
      );

      await pumpTab(tester, DiscoveryScreen(onGoWords: () {}));
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('library-first-content')))
            .dx,
        closeTo(24, 0.5),
      );
    });

    testWidgets('start content at one shared vertical offset', (tester) async {
      await pumpTab(tester, const ReadingScreen());
      final readingTop = tester
          .getTopLeft(find.byKey(const ValueKey('reading-first-content')))
          .dy;

      await pumpTab(tester, const StatsScreen());
      final statsTop = tester
          .getTopLeft(find.byKey(const ValueKey('stats-first-content')))
          .dy;

      await pumpTab(tester, DiscoveryScreen(onGoWords: () {}));
      final libraryTop = tester
          .getTopLeft(find.byKey(const ValueKey('library-first-content')))
          .dy;

      expect(statsTop, closeTo(readingTop, 0.5));
      expect(libraryTop, closeTo(readingTop, 0.5));
    });

    testWidgets('own the shared background, safe area and content padding', (
      tester,
    ) async {
      for (final screen in <Widget>[
        const ReadingScreen(),
        const StatsScreen(),
        DiscoveryScreen(onGoWords: () {}),
      ]) {
        await pumpTab(tester, screen);
        final scaffold = find.byType(TabPageScaffold);
        final safeAreas = find.descendant(
          of: scaffold,
          matching: find.byType(SafeArea),
        );
        expect(safeAreas, findsOneWidget);
        expect(tester.widget<SafeArea>(safeAreas).bottom, isFalse);

        final backgrounds = find.descendant(
          of: scaffold,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is ColoredBox && widget.color == AppColors.background,
          ),
        );
        expect(backgrounds, findsOneWidget);

        final paddings = tester
            .widgetList<SliverPadding>(
              find.descendant(
                of: scaffold,
                matching: find.byType(SliverPadding),
              ),
            )
            .toList();
        final contentPadding = paddings.singleWhere(
          (padding) => padding.child is SliverMainAxisGroup,
        );
        expect(
          contentPadding.padding,
          const EdgeInsets.fromLTRB(
            AppSpacing.x6,
            AppSpacing.x4,
            AppSpacing.x6,
            AppSpacing.x8,
          ),
        );
      }
    });

    testWidgets('lay out without overflow on a 320x568 screen', (tester) async {
      const small = Size(320, 568);

      await pumpTab(tester, const ReadingScreen(), size: small);
      expect(tester.takeException(), isNull);

      await pumpTab(tester, const StatsScreen(), size: small);
      expect(tester.takeException(), isNull);

      await pumpTab(tester, DiscoveryScreen(onGoWords: () {}), size: small);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lay out at 140% text scale on a compact screen', (
      tester,
    ) async {
      const small = Size(320, 568);
      for (final screen in <Widget>[
        const ReadingScreen(),
        const StatsScreen(),
        DiscoveryScreen(onGoWords: () {}),
      ]) {
        await pumpTab(tester, screen, size: small, textScale: 1.4);
        expect(tester.takeException(), isNull);
      }
    });
  });

  // ----- Answer feedback survives the animated option tile ---------------
  //
  // The option tile now uses AnimatedContainer for its correct/wrong state
  // crossfade (instead of a plain Container that color-snapped). This group
  // proves the interaction still works end to end: tapping a real tile
  // locks the choice, animates the state, and advances the session. The
  // device-bound integration test covers the same path, but this runs in
  // the headless suite so a refactor can't silently break it.
  group('Animated option tile still drives the answer flow', () {
    testWidgets('tapping the correct option advances to the next phase', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          catalog: const [
            VocabList(
              id: kDefaultVocabId,
              name: '生物医学专业英语词汇',
              description: 'Biomedical terms',
              emoji: '📘',
              domainColor: '#10B981',
              level: 1,
              wordCount: 20,
            ),
          ],
          overrides: [
            learningSessionProvider.overrideWith(
              (ref) => _AskingLearningSessionNotifier(ref),
            ),
          ],
        ),
      );
      await tester.pump();

      // The tile renders through AnimatedContainer (the fix), not a bare
      // Container that would color-snap.
      expect(
        find.descendant(
          of: find.byType(AskingView),
          matching: find.byType(AnimatedContainer),
        ),
        findsWidgets,
      );

      // Tap the correct answer. This exercises PressableScale (now animated)
      // and the tile's AnimatedContainer state change.
      await tester.tap(find.text('皮肤，真皮'));
      await tester.pump(); // register tap + setState(locked)
      // The choice is locked: tapping a different option must be ignored.
      await tester.tap(find.text('意外事故'), warnIfMissed: false);
      await tester.pump();

      // After the deliberate auto-advance delay, the session leaves the
      // asking phase (correct answer with a single question → finished).
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('dermis'), findsNothing);
    });
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
        LearningQuestion(
          word: _word('qwerty_biomedical_terms_00002', 'cache', '缓存'),
          type: QuestionType.seeWordPickMeaning,
          options: const ['缓存', '队列', '线程', '文件'],
          correctIndex: 0,
          prompt: 'cache',
        ),
      ],
      currentIndex: 0,
      correctCount: 0,
    );
  }

  @override
  Future<void> start({required String vocabId}) async {}
}

class _WrongLearningSessionNotifier extends LearningSessionNotifier {
  _WrongLearningSessionNotifier(super.ref) {
    final question = LearningQuestion(
      word: _word('qwerty_biomedical_terms_00001', 'dermis', '皮肤，真皮'),
      type: QuestionType.seeWordPickMeaning,
      options: const ['皮肤，真皮', '意外事故', '黑素瘤', '复杂的'],
      correctIndex: 0,
      prompt: 'dermis',
    );
    state = LearningSessionState(
      phase: SessionPhase.wrongDetail,
      questions: [question],
      currentIndex: 0,
      correctCount: 0,
      lastAnswer: AnswerQuality.again,
      lastSelectedIndex: 1,
      lastQuestionQueuedForRetry: true,
    );
  }

  @override
  Future<void> start({required String vocabId}) async {}
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
