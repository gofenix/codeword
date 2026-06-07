import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:codeword/main.dart';
import 'package:codeword/state/learning_session.dart';

void main() {
  testWidgets('App boots into 5-tab home with Today selected', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: CodewordApp()));
    await tester.pump();
    expect(find.text('今日'), findsWidgets);
    expect(find.text('词库'), findsOneWidget);
    expect(find.text('复习'), findsOneWidget);
    expect(find.text('统计'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('开始今日学习  ·  AI 核心'), findsOneWidget);
  });

  testWidgets('Start learning navigates to session and shows first question',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: CodewordApp()));
    await tester.pump();
    await tester.tap(find.text('开始今日学习  ·  AI 核心'));
    // Pump twice: once for navigation, once for session.load to resolve.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('选义'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
    expect(find.text('D'), findsOneWidget);
  });

  test('SM-2 round-trip through notifier records answer', () {
    final notifier = ReviewStateNotifier();
    expect(notifier.totalLearned, 0);
    notifier.recordAnswer(wordId: 'w1', quality: 4);
    expect(notifier.totalLearned, 1);
  });
}
