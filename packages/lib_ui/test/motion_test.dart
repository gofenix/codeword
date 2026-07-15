import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lib_ui/lib_ui.dart';

void main() {
  group('AppMotion tokens', () {
    test('UI durations stay within the craft budget', () {
      // Press feedback is snappy (100-160ms); everything the user sees
      // often stays under ~300ms. Sheets/holds may go slower.
      expect(AppMotion.press.inMilliseconds, inInclusiveRange(100, 160));
      expect(AppMotion.fast.inMilliseconds, lessThanOrEqualTo(300));
      expect(AppMotion.medium.inMilliseconds, lessThanOrEqualTo(300));
    });

    test('easeOut is a strong curve that starts fast, not ease-in', () {
      // A strong ease-out has already covered most of the distance by the
      // time it is a third of the way through — the opposite of ease-in,
      // which would sit near zero and read as sluggish.
      expect(AppMotion.easeOut.transform(0.33), greaterThan(0.5));
    });
  });

  group('PressableScale', () {
    AnimatedScale scaleWidget(WidgetTester tester) => tester.widget<AnimatedScale>(
      find.descendant(
        of: find.byType(PressableScale),
        matching: find.byType(AnimatedScale),
      ),
    );

    AnimatedOpacity opacityWidget(WidgetTester tester) =>
        tester.widget<AnimatedOpacity>(
          find.descendant(
            of: find.byType(PressableScale),
            matching: find.byType(AnimatedOpacity),
          ),
        );

    Future<TestGesture> pressAndHold(WidgetTester tester) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PressableScale)),
      );
      // Hold long enough for the tap recognizer to fire onTapDown
      // (deferred by kPressTimeout) and the tween to settle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      return gesture;
    }

    testWidgets('tweens the press with the press motion tokens', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PressableScale(
                onTap: () {},
                haptic: false,
                child: const SizedBox(width: 100, height: 100),
              ),
            ),
          ),
        ),
      );

      // The feedback is animated (not an instant Transform/Opacity snap)
      // and uses the shared, responsive press tokens.
      expect(scaleWidget(tester).duration, AppMotion.press);
      expect(scaleWidget(tester).curve, AppMotion.easeOut);
      expect(opacityWidget(tester).duration, AppMotion.press);

      // At rest, no transform and full opacity.
      expect(scaleWidget(tester).scale, 1.0);
      expect(opacityWidget(tester).opacity, 1.0);

      // While held, it scales down and dims — the press was heard.
      final gesture = await pressAndHold(tester);
      expect(scaleWidget(tester).scale, 0.97);
      expect(opacityWidget(tester).opacity, lessThan(1.0));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(scaleWidget(tester).scale, 1.0);
      expect(opacityWidget(tester).opacity, 1.0);
    });

    testWidgets('drops the scale but keeps opacity under reduced motion', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: Center(
                child: PressableScale(
                  onTap: () {},
                  haptic: false,
                  child: const SizedBox(width: 100, height: 100),
                ),
              ),
            ),
          ),
        ),
      );

      final gesture = await pressAndHold(tester);
      // No vestibular motion: the scale target stays 1.0 while pressed,
      // but the opacity feedback (which aids comprehension) is kept.
      expect(scaleWidget(tester).scale, 1.0);
      expect(opacityWidget(tester).opacity, lessThan(1.0));

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });
}
