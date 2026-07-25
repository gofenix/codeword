import 'package:flutter_test/flutter_test.dart';
import 'package:lib_ui/lib_ui.dart';

/// Locks the Apple-style, size-specific tracking rule (WWDC 2020, "The
/// Details of UI Typography"): large Latin display type tightens, small
/// text opens up slightly, and CJK-capable styles never inherit a baked-in
/// negative tracking. These invariants are easy to regress by "just adding
/// a letterSpacing", so they are pinned here.
void main() {
  group('wordDisplay tracking (Latin serif hero)', () {
    test('large display sizes tighten (negative tracking)', () {
      // 40–56px word heroes should read tighter as they grow.
      expect(AppTheme.wordDisplay(size: 56).letterSpacing, lessThan(0));
      expect(AppTheme.wordDisplay(size: 40).letterSpacing, lessThan(0));
      // Bigger = proportionally tighter (px scales with size).
      final big = AppTheme.wordDisplay(size: 56).letterSpacing!;
      final small = AppTheme.wordDisplay(size: 40).letterSpacing!;
      expect(big, lessThan(small));
    });

    test('small text opens up slightly (positive tracking)', () {
      expect(AppTheme.wordDisplay(size: 12).letterSpacing, greaterThan(0));
    });

    test('mid-range body sizes stay neutral', () {
      expect(AppTheme.wordDisplay(size: 20).letterSpacing, 0);
    });
  });

  group('CJK-capable styles never bake in negative tracking', () {
    // screenHeader renders Chinese UI headers (system font) and is often
    // resized down via copyWith; editorial renders CJK book names across a
    // wide size range. Negative tracking is a Latin-display rule and must
    // not leak onto these.
    test('screenHeader tracking is neutral', () {
      expect(AppTheme.screenHeader().letterSpacing ?? 0, 0);
    });

    test('editorial tracking is neutral at every size', () {
      for (final size in <double>[16, 20, 24, 34, 48]) {
        expect(
          AppTheme.editorial(size: size).letterSpacing ?? 0,
          0,
          reason: 'editorial($size) must not tighten — it can hold CJK',
        );
      }
    });
  });
}
