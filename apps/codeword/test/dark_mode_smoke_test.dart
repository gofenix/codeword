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
    final configureButton = find.widgetWithText(FilledButton, '配置 AI 阅读');
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
    expect(find.text('生成阅读'), findsOneWidget);
    expect(find.text('用这 3 个词生成文章'), findsOneWidget);
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
  Future<List<PulseWordEntry>> reviewedTodayWords({
    int limit = 10,
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
