import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lib_ui/lib_ui.dart';

/// Liquid-glass chrome invariants. The floating chrome layer (nav bars,
/// bottom toolbars) must actually frost the content behind it — a
/// [BackdropFilter] — in BOTH themes, and expose a centered title. These are
/// easy to regress into a flat opaque bar, so they are pinned here.
void main() {
  Widget host({required Brightness brightness, required Widget child}) {
    return MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      home: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: child as PreferredSizeWidget,
        body: const SizedBox.expand(),
      ),
    );
  }

  for (final brightness in Brightness.values) {
    testWidgets('GlassAppBar frosts the backdrop in $brightness', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          brightness: brightness,
          child: const GlassAppBar(title: '阅读'),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(GlassAppBar),
          matching: find.byType(BackdropFilter),
        ),
        findsOneWidget,
      );
      expect(find.text('阅读'), findsOneWidget);
    });
  }

  testWidgets('GlassAppBar renders leading and actions', (tester) async {
    var backTaps = 0;
    await tester.pumpWidget(
      host(
        brightness: Brightness.light,
        child: GlassAppBar(
          title: '生成阅读',
          leading: IconButton(
            tooltip: '返回',
            onPressed: () => backTaps++,
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
          ),
          actions: const [Icon(Icons.more_vert_rounded)],
        ),
      ),
    );
    await tester.tap(find.byTooltip('返回'));
    expect(backTaps, 1);
    expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
  });

  testWidgets('GlassAppBar drops the blur under increase-contrast', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(highContrast: true),
          child: const Scaffold(
            appBar: GlassAppBar(title: '阅读'),
            body: SizedBox.expand(),
          ),
        ),
      ),
    );
    // Legibility beats the material effect: no translucent blur when the OS
    // asks for increased contrast.
    expect(
      find.descendant(
        of: find.byType(GlassAppBar),
        matching: find.byType(BackdropFilter),
      ),
      findsNothing,
    );
    expect(find.text('阅读'), findsOneWidget);
  });

  testWidgets('GlassBottomBar frosts the backdrop', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: SizedBox.expand(),
          bottomNavigationBar: GlassBottomBar(child: SizedBox(height: 48)),
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(GlassBottomBar),
        matching: find.byType(BackdropFilter),
      ),
      findsOneWidget,
    );
  });
}
