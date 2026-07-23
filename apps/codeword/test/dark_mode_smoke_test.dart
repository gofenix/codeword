import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codeword/models/saved_article.dart';
import 'package:codeword/screens/reading_screen.dart';
import 'package:codeword/screens/stats_screen.dart';
import 'package:codeword/state/learning_session.dart';
import 'package:codeword/state/llm_config.dart';
import 'package:lib_core/lib_core.dart';
import 'package:lib_ui/lib_ui.dart';

final _readingConfiguredTestProvider = StateProvider<bool>((ref) => true);

void main() {
  testWidgets('AppColors.of resolves dark palette under dark theme', (
    tester,
  ) async {
    late AppPalette palette;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: Builder(
          builder: (context) {
            palette = AppColors.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(palette.surface, AppColors.surfaceDark);
    expect(palette.ink, AppColors.inkDark);
    expect(palette.background.computeLuminance() < 0.2, isTrue);
  });

  testWidgets('AppColors.of resolves light palette under light theme', (
    tester,
  ) async {
    late AppPalette palette;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        themeMode: ThemeMode.light,
        home: Builder(
          builder: (context) {
            palette = AppColors.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(palette.surface, AppColors.surface);
    expect(palette.ink, AppColors.ink);
    expect(palette.background.computeLuminance() > 0.8, isTrue);
  });

  testWidgets('AppCard paints the dark surface in dark mode', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: const Scaffold(body: AppCard(child: Text('x'))),
      ),
    );
    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(AppCard),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color, AppColors.surfaceDark);
  });

  testWidgets('compact icon buttons keep a >=44px tap target', (tester) async {
    // Mirrors the wrong-detail / reading action buttons: a 20px icon with
    // zero padding and a 48px min-constraint. Note VisualDensity.compact
    // subtracts up to 8px, so these buttons must NOT use compact density if
    // they are to clear the 44px minimum — this test locks that in.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: IconButton(
              onPressed: () {},
              icon: const Icon(Icons.star_rounded, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
          ),
        ),
      ),
    );
    final size = tester.getSize(find.byType(IconButton));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  });

  testWidgets('ReadingScreen BYOK setup keeps a >=44px tap target', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          qwertyCatalogProvider.overrideWithValue(const []),
          reviewStateProvider.overrideWith(
            (ref) => _ReadingSmokeReviewNotifier(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: ThemeMode.dark,
          home: const ReadingScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final configureButton = find.widgetWithText(
      EditorialPrimaryButton,
      '配置 AI 阅读',
    );
    expect(configureButton, findsOneWidget);
    final size = tester.getSize(configureButton);
    expect(size.height, greaterThanOrEqualTo(44));
  });

  testWidgets('configured ReadingScreen shows the contextual reading flow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          llmConfiguredProvider.overrideWithValue(true),
          qwertyCatalogProvider.overrideWithValue(const []),
          reviewStateProvider.overrideWith(
            (ref) => _ReadingSmokeReviewNotifier(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ReadingScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('今日阅读'), findsOneWidget);
    expect(find.textContaining('优先复现'), findsOneWidget);
    expect(find.text('选择目标词并生成'), findsOneWidget);
    expect(find.text('阅读记录'), findsOneWidget);

    await tester.tap(find.text('选择目标词并生成'));
    await tester.pumpAndSettle();
    expect(find.text('选择要在文章中复现的词'), findsOneWidget);
    expect(find.text('生成阅读 · 3 词'), findsOneWidget);
  });

  testWidgets('configured reading flow handles compact large-text layouts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          llmConfiguredProvider.overrideWithValue(true),
          qwertyCatalogProvider.overrideWithValue(const []),
          reviewStateProvider.overrideWith(
            (ref) => _DenseReadingSmokeReviewNotifier(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: const ReadingScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('选择目标词并生成'));
    await tester.pumpAndSettle();
    expect(find.text('选择要在文章中复现的词'), findsOneWidget);
    expect(tester.takeException(), isNull);

    for (var i = 0; i < 3; i++) {
      await tester.drag(
        find.byType(CustomScrollView).last,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
    }
    expect(find.textContaining('生成阅读 ·'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stale word-pool loads cannot overwrite a newer refresh', (
    tester,
  ) async {
    final notifier = _RacingReadingReviewNotifier();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          llmConfiguredProvider.overrideWith(
            (ref) => ref.watch(_readingConfiguredTestProvider),
          ),
          qwertyCatalogProvider.overrideWithValue(const []),
          reviewStateProvider.overrideWith((ref) => notifier),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ReadingScreen(),
        ),
      ),
    );
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ReadingScreen)),
    );

    container.read(_readingConfiguredTestProvider.notifier).state = false;
    await tester.pump();
    container.read(_readingConfiguredTestProvider.notifier).state = true;
    await tester.pump();
    await tester.pump();
    expect(find.text('fresh'), findsOneWidget);

    notifier.firstLoad.complete(const [
      PulseWordEntry(
        word: 'stale',
        translation: '旧结果',
        phonetic: '',
        level: 'B1',
        vocabId: kDefaultVocabId,
      ),
    ]);
    await tester.pump();
    await tester.pump();

    expect(find.text('fresh'), findsOneWidget);
    expect(find.text('stale'), findsNothing);
  });

  testWidgets('reading refresh rotates fillers while keeping due words', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          llmConfiguredProvider.overrideWithValue(true),
          reviewStateProvider.overrideWith(
            (ref) => _RotatingReadingReviewNotifier(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ReadingScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('due'), findsOneWidget);
    expect(find.text('word0'), findsOneWidget);
    await tester.tap(find.byTooltip('换一批目标词'));
    await tester.pump();
    await tester.pump();

    expect(find.text('due'), findsOneWidget);
    expect(find.text('word0'), findsNothing);
    expect(find.text('word4'), findsOneWidget);
  });

  testWidgets('reading requires three learned words before generation', (
    tester,
  ) async {
    var goWordsCalls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          llmConfiguredProvider.overrideWithValue(true),
          reviewStateProvider.overrideWith(
            (ref) => _InsufficientReadingReviewNotifier(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: ReadingScreen(onGoWords: () => goWordsCalls++),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('还差 1 个词'), findsOneWidget);
    expect(find.textContaining('生成 1 词'), findsNothing);
    await tester.tap(find.text('继续背词'));
    expect(goWordsCalls, 1);
  });

  testWidgets('article detail exposes translation and target word list', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final article = SavedArticle(
      id: 'preview',
      createdAt: DateTime(2026, 7, 11),
      title: 'The Cache That Saved Friday',
      articleText: 'A cache reduced latency while the queue recovered.',
      translationText: '缓存降低了延迟，同时队列逐渐恢复。',
      level: 'B1',
      vocabId: kDefaultVocabId,
      vocabName: 'Coder Core',
      wordPool: const [
        {
          'word': 'cache',
          'translation': '缓存',
          'phonetic': '/kæʃ/',
          'level': 'B1',
        },
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: ArticleDetailScreen(article: article),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('The Cache That Saved Friday'), findsOneWidget);
    expect(find.text('朗读'), findsOneWidget);
    expect(find.text('生词表'), findsOneWidget);
    expect(find.text('翻译'), findsOneWidget);

    await tester.tap(find.text('翻译'));
    await tester.pumpAndSettle();
    expect(find.text('缓存降低了延迟，同时队列逐渐恢复。'), findsOneWidget);

    await tester.tap(find.text('生词表'));
    await tester.pumpAndSettle();
    expect(find.text('本篇生词'), findsOneWidget);
    expect(find.text('缓存'), findsOneWidget);
  });

  testWidgets('AI article detail handles long generated content', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final article = SavedArticle(
      id: 'long-preview',
      createdAt: DateTime(2026, 7, 23),
      title:
          'A Very Long Generated Reading Title About Distributed Systems Recovery',
      articleText: List.filled(
        12,
        'A disproportionately-long-identifier remained observable while the distributed queue recovered.',
      ).join(' '),
      translationText: List.filled(8, '这是用于验证长篇 AI 内容布局的中文翻译。').join(),
      level: 'Advanced professional level',
      vocabId: kDefaultVocabId,
      vocabName: 'Coder Core',
      wordPool: const [
        {
          'word': 'disproportionately-long-identifier',
          'translation': '一个非常长的技术词条释义，用来验证生词弹层不会横向溢出',
          'phonetic': '/test/',
          'level': 'C1',
        },
      ],
      questions: const [
        {
          'question': 'What happened to the distributed processing queue?',
          'options': [
            'It recovered while the identifier remained observable.',
            'This intentionally long distractor remains within the available card width.',
            'Nothing happened.',
            'The queue was removed.',
          ],
          'correctIndex': 0,
        },
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: ArticleDetailScreen(article: article),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('生词表'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('SavedArticle keeps old local JSON readable', () {
    final article = SavedArticle.fromJson({
      'id': 'old',
      'createdAt': '2026-07-11T00:00:00.000',
      'articleText': 'Old article.',
      'vocabId': kDefaultVocabId,
      'vocabName': 'Coder Core',
      'wordPool': <Map<String, String>>[],
    });
    expect(article.title, isEmpty);
    expect(article.translationText, isEmpty);
    expect(article.level, isEmpty);
  });

  test('AI reading payload parses article and valid quiz in one response', () {
    final payload = parseGeneratedReadingPayload(
      '{"title":"Cache Story","article":"A cache helped.",'
      '"translation":"缓存提供了帮助。","questions":['
      '{"q":"发生了什么？","options":["A","B","C","D"],"correct":1},'
      '{"q":"坏数据","options":["A"],"correct":9}]}',
    );
    expect(payload.title, 'Cache Story');
    expect(payload.article, 'A cache helped.');
    expect(payload.translation, '缓存提供了帮助。');
    expect(payload.questions, hasLength(1));
    expect(payload.questions.single.correctIndex, 1);
  });

  test('AI reading payload bounds text and rejects ambiguous quizzes', () {
    final payload = parseGeneratedReadingPayload(
      '{"title":"${List.filled(140, 'T').join()}",'
      '"article":"${List.filled(12100, 'A').join()}",'
      '"translation":"ok","questions":['
      '{"q":"duplicate","options":["A","A","C","D"],"correct":0},'
      '{"q":"fractional","options":["A","B","C","D"],"correct":1.5},'
      '{"q":"valid","options":["A","B","C","D"],"correct":2}]}',
    );

    expect(payload.title.runes.length, 120);
    expect(payload.article.runes.length, 12000);
    expect(payload.questions, hasLength(1));
    expect(payload.questions.single.question, 'valid');
  });

  test('learning rhythm aligns today to the real weekday', () {
    final grid = buildRhythmCalendar(
      activity: const [false, false, false, false, false, false, true],
      now: DateTime(2026, 7, 8), // Wednesday
    );
    const currentWeek = 6;
    expect(grid[currentWeek * 7 + 0], isFalse); // Monday
    expect(grid[currentWeek * 7 + 1], isFalse); // Tuesday
    expect(grid[currentWeek * 7 + 2], isTrue); // Today
    expect(grid[currentWeek * 7 + 3], isNull); // Future Thursday
    expect(grid[currentWeek * 7 + 6], isNull); // Future Sunday
  });

  test('weekly activity excludes days from the previous week', () {
    final activeDays = activeDaysInCurrentWeek(
      const [true, true, true, true, true, false, true],
      DateTime(2026, 7, 8), // Wednesday
    );
    expect(activeDays, 2);
  });
}

class _ReadingSmokeReviewNotifier extends ReviewStateNotifier {
  _ReadingSmokeReviewNotifier() : super(const {});

  @override
  Future<List<PulseWordEntry>> readingCandidateWords({
    int limit = 24,
    DateTime? now,
  }) async {
    return const [
      PulseWordEntry(
        word: 'cache',
        translation: '缓存',
        phonetic: '/kæʃ/',
        level: 'B1',
        vocabId: kDefaultVocabId,
      ),
      PulseWordEntry(
        word: 'latency',
        translation: '延迟',
        phonetic: '/ˈleɪtənsi/',
        level: 'B1',
        vocabId: kDefaultVocabId,
      ),
      PulseWordEntry(
        word: 'queue',
        translation: '队列',
        phonetic: '/kjuː/',
        level: 'B1',
        vocabId: kDefaultVocabId,
      ),
    ];
  }

  @override
  Future<List<PulseWordEntry>> dueWords({int limit = 3, DateTime? now}) async {
    return const [];
  }

  @override
  Future<List<PulseWordEntry>> recommendedNewWords({
    int limit = 3,
    required List<VocabList> catalog,
  }) async {
    return const [];
  }
}

class _RacingReadingReviewNotifier extends ReviewStateNotifier {
  _RacingReadingReviewNotifier() : super(const {});

  final firstLoad = Completer<List<PulseWordEntry>>();
  int calls = 0;

  @override
  Future<List<PulseWordEntry>> readingCandidateWords({
    int limit = 24,
    DateTime? now,
  }) {
    calls++;
    if (calls == 1) return firstLoad.future;
    return Future.value(const [
      PulseWordEntry(
        word: 'fresh',
        translation: '新结果',
        phonetic: '',
        level: 'B1',
        vocabId: kDefaultVocabId,
      ),
    ]);
  }
}

class _DenseReadingSmokeReviewNotifier extends _ReadingSmokeReviewNotifier {
  @override
  Future<List<PulseWordEntry>> readingCandidateWords({
    int limit = 24,
    DateTime? now,
  }) async {
    return const [
      PulseWordEntry(
        word: 'serialization',
        translation: '序列化',
        phonetic: '',
        level: 'B2',
        vocabId: kDefaultVocabId,
      ),
      PulseWordEntry(
        word: 'asynchronous',
        translation: '异步的',
        phonetic: '',
        level: 'B2',
        vocabId: kDefaultVocabId,
      ),
      PulseWordEntry(
        word: 'authentication',
        translation: '身份验证',
        phonetic: '',
        level: 'B2',
        vocabId: kDefaultVocabId,
      ),
      PulseWordEntry(
        word: 'virtualization',
        translation: '虚拟化',
        phonetic: '',
        level: 'B2',
        vocabId: kDefaultVocabId,
      ),
      PulseWordEntry(
        word: 'observability',
        translation: '可观测性',
        phonetic: '',
        level: 'B2',
        vocabId: kDefaultVocabId,
      ),
      PulseWordEntry(
        word: 'interoperability',
        translation: '互操作性',
        phonetic: '',
        level: 'B2',
        vocabId: kDefaultVocabId,
      ),
      PulseWordEntry(
        word: 'configuration',
        translation: '配置',
        phonetic: '',
        level: 'B2',
        vocabId: kDefaultVocabId,
      ),
      PulseWordEntry(
        word: 'synchronization',
        translation: '同步',
        phonetic: '',
        level: 'B2',
        vocabId: kDefaultVocabId,
      ),
      PulseWordEntry(
        word: 'infrastructure',
        translation: '基础设施',
        phonetic: '',
        level: 'B2',
        vocabId: kDefaultVocabId,
      ),
      PulseWordEntry(
        word: 'disproportionately-long-identifier',
        translation: '超长标识符',
        phonetic: '',
        level: 'B2',
        vocabId: kDefaultVocabId,
      ),
    ];
  }
}

class _RotatingReadingReviewNotifier extends ReviewStateNotifier {
  _RotatingReadingReviewNotifier() : super(const {});

  @override
  Future<List<PulseWordEntry>> readingCandidateWords({
    int limit = 24,
    DateTime? now,
  }) async {
    return [
      const PulseWordEntry(
        word: 'due',
        translation: '到期',
        phonetic: '',
        level: 'B1',
        vocabId: kDefaultVocabId,
        isDue: true,
      ),
      for (var i = 0; i < 8; i++)
        PulseWordEntry(
          word: 'word$i',
          translation: '释义$i',
          phonetic: '',
          level: 'B1',
          vocabId: kDefaultVocabId,
        ),
    ];
  }
}

class _InsufficientReadingReviewNotifier extends ReviewStateNotifier {
  _InsufficientReadingReviewNotifier() : super(const {});

  @override
  Future<List<PulseWordEntry>> readingCandidateWords({
    int limit = 24,
    DateTime? now,
  }) async {
    return const [
      PulseWordEntry(
        word: 'file',
        translation: '文件',
        phonetic: '',
        level: 'B1',
        vocabId: kDefaultVocabId,
      ),
      PulseWordEntry(
        word: 'command',
        translation: '命令',
        phonetic: '',
        level: 'B1',
        vocabId: kDefaultVocabId,
      ),
    ];
  }
}
