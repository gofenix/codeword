import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lib_ui/lib_ui.dart';

import 'package:codeword/screens/update_dialog.dart';
import 'package:codeword/services/update_service.dart';

void main() {
  Future<void> pumpDialog(WidgetTester tester, AppUpdateInfo info) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => UpdateDialog.show(
                  context,
                  info: info,
                  currentVersion: '1.2.8',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('renders markdown release notes as formatted widgets, not raw text',
      (tester) async {
    const info = AppUpdateInfo(
      version: '1.2.9',
      apkUrl: 'https://example.com/app.apk',
      releaseNotes: '## 更新内容\n\n- 修复了 `安装` 问题\n- 优化滑动动画',
    );
    await pumpDialog(tester, info);

    // The markdown body is rendered (not shown as a raw Text with #/- markers).
    expect(find.byType(MarkdownBody), findsOneWidget);
    // Header + primary action are present.
    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('立即更新'), findsOneWidget);
    // The raw markdown string is never dumped verbatim into a Text widget.
    expect(find.text('## 更新内容\n\n- 修复了 `安装` 问题\n- 优化滑动动画'),
        findsNothing);
  });

  testWidgets('falls back to a plain message when release notes are empty',
      (tester) async {
    const info = AppUpdateInfo(version: '1.2.9', apkUrl: 'https://x/app.apk');
    await pumpDialog(tester, info);

    expect(find.byType(MarkdownBody), findsNothing);
    expect(find.text('本次更新包含若干改进与修复。'), findsOneWidget);
  });
}
