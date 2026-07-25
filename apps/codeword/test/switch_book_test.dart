import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lib_core/lib_core.dart';

import 'package:codeword/main.dart';
import 'package:codeword/state/learning_session.dart';
import 'package:codeword/state/learning_preferences.dart';

// Regression tests for the "tapping a book no longer updates the home" bug.
//
// Root cause: after a catalogue migration removed some books, a user whose
// persisted `selectedVocabId` pointed at a now-deleted book booted into a
// session for a book whose asset no longer exists. `start()` awaited the
// word-list load with no error handling, so the missing asset threw, the
// session stayed stuck in `loading` (perpetual home spinner), and the
// tap-to-switch flow's `onGoWords()` — which runs only after `await start()`
// completes — never fired.
//
// The fix has two layers, each covered below:
//   1. `selectedVocabProvider` self-heals a stale id against the catalogue.
//   2. `start()` recovers from an asset-load failure instead of hanging.

VocabWord _word(String id, String w, String t) => VocabWord(
  id: id,
  word: w,
  phonetic: '',
  pos: 'n.',
  translation: t,
  translations: [t],
  exampleEn: '',
  exampleCn: '',
  domain: id.split('_').take(2).join('_'),
  level: 'B2',
  synonyms: const [],
  antonyms: const [],
);

VocabList _list(String id, String name) => VocabList(
  id: id,
  name: name,
  description: name,
  emoji: '📘',
  domainColor: '#10B981',
  level: 1,
  wordCount: 5,
  category: '编程',
);

class _MemPrefsBackend implements LearningPreferencesBackend {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async => value = v;
}

List<VocabWord> _bookWords(String slug) => List.generate(
  5,
  (i) => _word('${slug}_${(i + 1).toString().padLeft(5, '0')}', '$slug$i', '译$i'),
);

Future<void> _pump(WidgetTester tester, {int times = 15}) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('tapping a book in 词书 switches the home to that book', (
    tester,
  ) async {
    ReviewRepository.resetForTesting();
    final backend = InMemoryStorageBackend()
      ..userData = {'schemaVersion': 2, 'selectedVocabId': 'qwerty_a'};
    await ReviewRepository.initWithBackend(backend);
    addTearDown(ReviewRepository.resetForTesting);

    final prefs = LearningPreferencesNotifier(
      LearningPreferencesStore(_MemPrefsBackend()),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          qwertyCatalogProvider.overrideWithValue([
            _list('qwerty_a', 'Book Alpha'),
            _list('qwerty_b', 'Book Bravo'),
          ]),
          learningPreferencesProvider.overrideWith((ref) => prefs),
          vocabCacheProvider(
            'qwerty_a',
          ).overrideWith((ref) async => _bookWords('qwerty_a')),
          vocabCacheProvider(
            'qwerty_b',
          ).overrideWith((ref) async => _bookWords('qwerty_b')),
        ],
        child: const CodewordApp(),
      ),
    );
    await _pump(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(IndexedStack)),
    );
    expect(
      container.read(learningSessionProvider).currentQuestion?.word.id,
      startsWith('qwerty_a_'),
      reason: 'boot should start the persisted book A',
    );

    await tester.tap(find.text('词书'));
    await _pump(tester);
    await tester.tap(find.text('Book Bravo').first);
    await _pump(tester, times: 25);

    expect(
      tester.widget<IndexedStack>(find.byType(IndexedStack)).index,
      0,
      reason: 'tapping a book must return to the Words tab',
    );
    expect(
      container.read(learningSessionProvider).currentQuestion?.word.id,
      startsWith('qwerty_b_'),
      reason: 'home must reflect the tapped book',
    );
  });

  testWidgets('a persisted book removed by migration self-heals on boot', (
    tester,
  ) async {
    ReviewRepository.resetForTesting();
    // qwerty_japanese006 is one of the books deleted by the migration.
    final backend = InMemoryStorageBackend()
      ..userData = {
        'schemaVersion': 2,
        'selectedVocabId': 'qwerty_japanese006',
      };
    await ReviewRepository.initWithBackend(backend);
    addTearDown(ReviewRepository.resetForTesting);

    final prefs = LearningPreferencesNotifier(
      LearningPreferencesStore(_MemPrefsBackend()),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Catalogue no longer contains the deleted book.
          qwertyCatalogProvider.overrideWithValue([
            _list('qwerty_b', 'Book Bravo'),
          ]),
          learningPreferencesProvider.overrideWith((ref) => prefs),
          vocabCacheProvider(
            'qwerty_b',
          ).overrideWith((ref) async => _bookWords('qwerty_b')),
        ],
        child: const CodewordApp(),
      ),
    );
    await _pump(tester, times: 25);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(IndexedStack)),
    );
    // The selection self-heals to the only valid book, and the home boots
    // straight into it — no perpetual loading spinner.
    expect(container.read(selectedVocabProvider), 'qwerty_b');
    final session = container.read(learningSessionProvider);
    expect(session.phase, isNot(SessionPhase.loading));
    expect(
      session.currentQuestion?.word.id,
      startsWith('qwerty_b_'),
      reason: 'home must recover onto a valid book after migration',
    );
  });

  testWidgets('start() recovers instead of hanging when a book asset is missing', (
    tester,
  ) async {
    ReviewRepository.resetForTesting();
    await ReviewRepository.initWithBackend(InMemoryStorageBackend());
    addTearDown(ReviewRepository.resetForTesting);

    final prefs = LearningPreferencesNotifier(
      LearningPreferencesStore(_MemPrefsBackend()),
    );

    final container = ProviderContainer(
      overrides: [
        qwertyCatalogProvider.overrideWithValue([_list('qwerty_b', 'Bravo')]),
        learningPreferencesProvider.overrideWith((ref) => prefs),
        vocabCacheProvider(
          'qwerty_gone',
        ).overrideWith((ref) async => throw Exception('asset not found')),
      ],
    );
    addTearDown(container.dispose);

    // Directly starting a book whose asset throws must not hang; the session
    // finishes so the home shows the empty state rather than a stuck spinner.
    await container.read(learningSessionProvider.notifier).start(
      vocabId: 'qwerty_gone',
    );
    final session = container.read(learningSessionProvider);
    expect(session.phase, SessionPhase.finished);
    expect(session.questions, isEmpty);
  });
}
