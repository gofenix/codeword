import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lib_ui/lib_ui.dart';

void main() {
  group('AppMotion tokens', () {
    test('UI durations stay within the craft budget', () {
      expect(AppMotion.press.inMilliseconds, inInclusiveRange(100, 160));
      expect(AppMotion.fast.inMilliseconds, lessThanOrEqualTo(300));
      expect(AppMotion.medium.inMilliseconds, lessThanOrEqualTo(300));
    });

    test('easeOut is a strong curve that starts fast, not ease-in', () {
      expect(AppMotion.easeOut.transform(0.33), greaterThan(0.5));
    });

    test('springDefault is critically damped (no overshoot)', () {
      // A critically-damped spring has damping = 2*sqrt(mass*stiffness).
      final s = AppMotion.springDefault();
      expect(s.damping, closeTo(2 * sqrt(s.mass * s.stiffness), 0.01));
    });

    test('springMomentum is under-damped (slight bounce)', () {
      final s = AppMotion.springMomentum();
      final critical = 2 * sqrt(s.mass * s.stiffness);
      // damping ratio ~0.8 means damping < critical.
      expect(s.damping, lessThan(critical));
      expect(s.damping / critical, closeTo(0.8, 0.01));
    });

    test('projectMomentum uses Apple exponential-decay form', () {
      // v=1000 px/s, d=0.998 → (1000/1000)*0.998/(1-0.998) = 499
      expect(AppMotion.projectMomentum(1000), closeTo(499, 1));
    });
  });

  group('PressableScale', () {
    AnimatedScale scaleWidget(WidgetTester tester) =>
        tester.widget<AnimatedScale>(
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
      await tester.pump();
      // Hold long enough for the press tween to settle on the target.
      await tester.pump(const Duration(milliseconds: 400));
      return gesture;
    }

    testWidgets('tweens the scale down and dims on press', (tester) async {
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

      expect(scaleWidget(tester).scale, 1.0);
      expect(opacityWidget(tester).opacity, 1.0);

      final gesture = await pressAndHold(tester);
      expect(scaleWidget(tester).scale, 0.97);
      expect(opacityWidget(tester).opacity, 0.85);

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
      // No vestibular motion: scale stays 1.0, but opacity dips.
      expect(scaleWidget(tester).scale, 1.0);
      expect(opacityWidget(tester).opacity, lessThan(1.0));

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });
}
