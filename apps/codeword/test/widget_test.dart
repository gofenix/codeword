import 'package:flutter_test/flutter_test.dart';

import 'package:codeword/main.dart';

void main() {
  testWidgets('App boots into Today tab', (tester) async {
    await tester.pumpWidget(const CodewordApp());
    await tester.pump();
    expect(find.text('今日'), findsWidgets);
    expect(find.text('开始今日学习  ·  12 词'), findsOneWidget);
  });
}
