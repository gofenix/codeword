import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lib_core/lib_core.dart';
import 'package:lib_ui/lib_ui.dart';

import 'package:codeword/main.dart';
import 'package:codeword/screens/discovery_screen.dart';
import 'package:codeword/state/learning_session.dart';

/// Regression guards for the HIG + liquid-glass polish pass:
///   * category filter chips clear the 44px minimum tap target,
///   * switching main tabs fades the (single, persistent) IndexedStack in
///     rather than hard-cutting.
VocabList _list(String id, String name, String category) => VocabList(
  id: id,
  name: name,
  description: name,
  emoji: '📘',
  domainColor: '#10B981',
  level: 1,
  wordCount: 5,
  category: category,
);

void main() {
  testWidgets('category filter chips keep a >=44px tap target', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          qwertyCatalogProvider.overrideWithValue([
            _list('qwerty_a', 'Book Alpha', '编程'),
            _list('qwerty_b', 'Book Bravo', '考试英语'),
          ]),
        ],
        child: MaterialApp(home: DiscoveryScreen(onGoWords: () {})),
      ),
    );
    await tester.pump();

    // The "全部" chip is the always-present first filter chip.
    final chip = find.widgetWithText(ChoiceChip, '全部');
    expect(chip, findsOneWidget);
    final size = tester.getSize(chip);
    expect(
      size.height,
      greaterThanOrEqualTo(44),
      reason: 'filter chips must clear the 44px HIG tap target',
    );
  });

  testWidgets('switching main tabs fades a single persistent IndexedStack', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [qwertyCatalogProvider.overrideWithValue(const [])],
        child: const CodewordApp(),
      ),
    );
    await tester.pump();

    // Exactly one persistent IndexedStack backs all five tabs (its state is
    // preserved across switches — the reason it is not wrapped in an
    // AnimatedSwitcher, which would rebuild and drop that state).
    expect(find.byType(IndexedStack), findsOneWidget);
    // The body is faded in on tab change via a keyed FadeTransition wrapper.
    final fade = find.byKey(const ValueKey('tab-fade'));
    expect(fade, findsOneWidget);

    double fadeOpacity() => tester.widget<FadeTransition>(fade).opacity.value;

    await tester.tap(find.text('图表'));
    await tester.pump(); // start of fade
    expect(fadeOpacity(), lessThan(1.0));

    // Pump past the fade duration. pumpAndSettle is avoided on purpose: the
    // persistent IndexedStack keeps every tab mounted, so a sibling tab's
    // ongoing indicator would make "settle" never terminate.
    await tester.pump(AppMotion.medium + const Duration(milliseconds: 16));
    expect(
      tester.widget<IndexedStack>(find.byType(IndexedStack)).index,
      2,
    );
    expect(fadeOpacity(), 1.0);
  });

  testWidgets('reduced motion skips the tab fade', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [qwertyCatalogProvider.overrideWithValue(const [])],
        child: const CodewordApp(),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('词书'));
    await tester.pump();
    // With animations disabled the newly-shown tab is already fully opaque.
    final opacity = tester
        .widget<FadeTransition>(find.byKey(const ValueKey('tab-fade')))
        .opacity
        .value;
    expect(opacity, 1.0);
    expect(
      tester.widget<IndexedStack>(find.byType(IndexedStack)).index,
      3,
    );
  });
}
