import 'package:flutter_test/flutter_test.dart';
import 'package:lib_core/lib_core.dart';

void main() {
  group('SM-2 schedule', () {
    test('first correct answer → interval 1 day, easiness stays high', () {
      final now = DateTime(2026, 6, 7, 10);
      final next = Sm2.schedule(
        current: ReviewState.fresh('w1'),
        quality: 4, // good
        now: now,
      );

      expect(next.repetitions, 1);
      expect(next.interval, 1);
      expect(next.easiness, greaterThanOrEqualTo(240));
      expect(next.dueAt, now.add(const Duration(days: 1)));
    });

    test('incorrect answer (quality < 3) → reset reps, due same day', () {
      final now = DateTime(2026, 6, 7, 10);
      const current = ReviewState(
        wordId: 'w1',
        easiness: 250,
        interval: 6,
        repetitions: 2,
        dueAt: null,
        lastReviewedAt: null,
      );
      final next = Sm2.schedule(current: current, quality: 1, now: now);

      expect(next.repetitions, 0);
      expect(next.interval, 0);
      expect(next.dueAt, now);
      expect(next.easiness, lessThan(250));
    });

    test('three consecutive good answers → 1d, 6d, 15d', () {
      var state = ReviewState.fresh('w1');
      final now = DateTime(2026, 6, 7);

      state = Sm2.schedule(current: state, quality: 4, now: now);
      expect(state.interval, 1);

      state = Sm2.schedule(
        current: state,
        quality: 4,
        now: now.add(const Duration(days: 1)),
      );
      expect(state.interval, 6);

      state = Sm2.schedule(
        current: state,
        quality: 4,
        now: now.add(const Duration(days: 7)),
      );
      expect(state.interval, greaterThanOrEqualTo(14));
    });

    test('easiness never drops below 1.3', () {
      var state = ReviewState.fresh('w1');
      final now = DateTime(2026, 6, 7);
      for (var i = 0; i < 10; i++) {
        state = Sm2.schedule(current: state, quality: 0, now: now);
      }
      expect(state.easiness, greaterThanOrEqualTo(130));
    });
  });

  group('VocabWord JSON round-trip', () {
    test('fromJson/toJson preserves fields', () {
      const original = VocabWord(
        id: 'w1',
        word: 'overfitting',
        phonetic: '/test/',
        pos: 'n.',
        translation: '过拟合',
        exampleEn: 'An example.',
        exampleCn: '一个例子。',
        domain: 'ai',
        level: 'C1',
        synonyms: ['over-training'],
        antonyms: ['underfitting'],
      );
      final json = original.toJson();
      final restored = VocabWord.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.word, original.word);
      expect(restored.translation, original.translation);
      expect(restored.synonyms, original.synonyms);
      expect(restored.antonyms, original.antonyms);
    });
  });

  test('containsLegacyWordIds flags pre-qwerty review keys', () {
    expect(ReviewRepository.containsLegacyWordIds(['cs_001', 'ai_022']), isTrue);
    expect(
      ReviewRepository.containsLegacyWordIds(['qwerty_cet4_00001']),
      isFalse,
    );
    expect(ReviewRepository.containsLegacyWordIds(const []), isFalse);
  });
}
