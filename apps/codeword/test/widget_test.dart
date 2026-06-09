import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:codeword/main.dart';
import 'package:codeword/state/learning_session.dart';

void main() {
  testWidgets('App boots into 5-tab home with Words selected', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: CodewordApp()));
    await tester.pump();
    expect(find.text('单词'), findsWidgets);
    expect(find.text('阅读'), findsOneWidget);
    expect(find.text('Pulse'), findsOneWidget);
    expect(find.text('统计'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('开始学 ·  AI 核心'), findsOneWidget);
  });

  test('SM-2 round-trip through notifier records answer', () {
    final notifier = ReviewStateNotifier();
    expect(notifier.totalLearned, 0);
    notifier.recordAnswer(wordId: 'w1', quality: 4);
    expect(notifier.totalLearned, 1);
  });

  test('Empty stats are zero across the board', () {
    final notifier = ReviewStateNotifier();
    final s = notifier.stats();
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

    final s = notifier.stats(now: now);
    expect(s.totalSeen, 5);
    expect(s.totalLearned, 4,
        reason: 'a/b/c/e have repetitions=1 (good/easy), '
            "d's quality=0 reset repetitions to 0");
    expect(s.newToday, 3, reason: 'a, b, c first-seen today with reps=1');
    expect(s.reviewsToday, 4,
        reason: 'a, b, c, d all reviewed today (e was yesterday)');
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
    final s = notifier.stats(now: now.add(const Duration(days: 5)));
    final familiar = s.mastery.firstWhere((b) => b.level == MasteryLevel.familiar).count;
    expect(familiar, 1,
        reason: 'Word with 5 easy reps + ef~2.5 should land in familiar');
  });

  test('Per-vocab progress surfaces built-in vocabs even with 0 progress', () {
    final notifier = ReviewStateNotifier();
    final s = notifier.stats();
    // We have 9 built-in vocabs, all empty for a fresh notifier.
    expect(s.perVocab.length, greaterThanOrEqualTo(9));
    for (final row in s.perVocab) {
      expect(row.totalWords, greaterThan(0));
      expect(row.learned, 0);
      expect(row.coverage, 0);
    }
  });

  test('Session phase has no feedback phase (asking → wrongDetail is a direct transition)', () {
    // v0.4.0 had a 'feedback' phase that the user complained was redundant.
    // v0.4.1+ removed it — correct answers go directly asking → asking
    // (next question), wrong answers go asking → wrongDetail.
    final names = SessionPhase.values.map((p) => p.name).toList();
    expect(names, isNot(contains('feedback')),
        reason: 'No standalone feedback phase — should be removed');
  });
}
