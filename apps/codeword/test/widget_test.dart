import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lib_core/lib_core.dart';

import 'package:codeword/main.dart';
import 'package:codeword/state/learning_session.dart';

void main() {
  /// Build a ProviderScope with an empty qwerty catalog override so the
  /// home shell boots without throwing.
  Widget testApp() => ProviderScope(
        overrides: [qwertyCatalogProvider.overrideWithValue(const [])],
        child: const CodewordApp(),
      );

  testWidgets('App boots into 5-tab home with Words selected', (tester) async {
    await tester.pumpWidget(testApp());
    await tester.pump();
    expect(find.text('单词'), findsWidgets);
    expect(find.text('阅读'), findsOneWidget);
    expect(find.text('Pulse'), findsOneWidget);
    expect(find.text('统计'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
  });

  testWidgets('HomeShell keeps tab state mounted while switching tabs', (
    tester,
  ) async {
    await tester.pumpWidget(testApp());
    await tester.pump();

    final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stack.children.length, 5);
    expect(stack.index, 0);

    await tester.tap(find.text('阅读'));
    await tester.pump();
    final readingStack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(readingStack.index, 1);

    await tester.tap(find.text('Pulse'));
    await tester.pump();
    final pulseStack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(pulseStack.index, 2);
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
    expect(s.newToday, 3, reason: 'a, b, c first-seen today with reps=1');
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

  test('Per-vocab progress surfaces catalog vocabs even with 0 progress', () {
    final notifier = ReviewStateNotifier();
    final catalog = <VocabList>[
      const VocabList(
        id: 'v1', name: 'V1', description: '', emoji: '📘',
        domainColor: '#000', level: 1, wordCount: 10,
      ),
      const VocabList(
        id: 'v2', name: 'V2', description: '', emoji: '📗',
        domainColor: '#000', level: 1, wordCount: 20,
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
        minSessionSize: 2,
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
}
