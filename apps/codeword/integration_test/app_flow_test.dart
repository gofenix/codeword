import 'package:codeword/main.dart';
import 'package:codeword/state/learning_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lib_core/lib_core.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('continuous learning exhaustion and BYOK reading gate', (
    tester,
  ) async {
    ReviewRepository.resetForTesting();
    await ReviewRepository.initWithBackend(InMemoryStorageBackend());
    addTearDown(ReviewRepository.resetForTesting);

    const core = VocabList(
      id: kDefaultVocabId,
      name: 'Coder Core',
      description: '程序员核心英语 500 词',
      emoji: '💻',
      domainColor: '#10B981',
      level: 1,
      wordCount: 1,
      category: '精选词书',
    );
    final word = VocabWord(
      id: '${kDefaultVocabId}_00001',
      word: 'cache',
      phonetic: '/kæʃ/',
      pos: 'n.',
      translation: '缓存',
      exampleEn: 'The cache reduces repeated work.',
      exampleCn: '缓存减少重复工作。',
      domain: kDefaultVocabId,
      level: 'B1',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          qwertyCatalogProvider.overrideWithValue(const [core]),
          vocabCacheProvider(
            kDefaultVocabId,
          ).overrideWith((ref) async => [word]),
        ],
        child: const CodewordApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('cache'), findsWidgets);
    await tester.tap(find.text('缓存'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('当前没有待学单词'), findsOneWidget);

    await tester.tap(find.text('阅读'));
    await tester.pumpAndSettle();
    expect(find.text('连接你自己的 AI'), findsOneWidget);
    expect(find.text('配置 AI 阅读'), findsOneWidget);
    expect(find.textContaining('本篇目标词'), findsNothing);

    await tester.tap(find.text('图表'));
    await tester.pumpAndSettle();
    expect(find.text('当前词书掌握'), findsOneWidget);
    expect(find.text('近 14 天'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('90 天学习节奏'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
