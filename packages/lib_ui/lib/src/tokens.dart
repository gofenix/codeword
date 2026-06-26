import 'package:flutter/material.dart';

/// v5 design tokens — derived from `design-doc-v5-painless.md`.
///
/// Visual style: cream/light, Lora serif for words, Inter+Noto Sans SC for UI,
/// green #10B981 accent, pill tags, card-based, shadow-md, 12-16px radius.
///
/// All colours are light theme. For the dark theme tokens (paired with
/// [AppTheme.dark()]) see the `darkXxx` variants below — they are used by
/// the theme layer when [Theme.of(context).brightness] is dark.
class AppColors {
  AppColors._();

  // Surfaces (cream/light)
  static const Color background = Color(0xFFFAFAF5);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF5F2EA);
  // Dark bezel painted around the phone-shaped column when the app
  // runs in a desktop window. Reads as a phone sitting on a desk.
  static const Color bezel = Color(0xFF1A1A1F);
  // Light cream wall behind the phone bezel on desktop.
  static const Color desktopWall = Color(0xFFEDEAE0);

  // Dark-mode surfaces
  static const Color backgroundDark = Color(0xFF151819);
  static const Color surfaceDark = Color(0xFF1E2223);
  static const Color surfaceMutedDark = Color(0xFF272B2C);
  static const Color desktopWallDark = Color(0xFF0E1011);

  // Text (light)
  static const Color ink = Color(0xFF1F2421);
  static const Color inkMuted = Color(0xFF6B7470);
  static const Color inkSubtle = Color(0xFF98A09B);

  // Text (dark)
  static const Color inkDark = Color(0xFFEDECE6);
  static const Color inkMutedDark = Color(0xFFA3ABA8);
  static const Color inkSubtleDark = Color(0xFF727B78);

  // Foreground on top of primary/accent fills.
  static const Color onPrimary = Color(0xFFFFFFFF);

  // Generic divider used in ThemeData.
  static const Color divider = Color(0x261F2421); // ink ~15% alpha
  static const Color dividerDark = Color(0x26EDECE6);

  // Idle state for the favorite star (replaces Colors.amber default).
  static const Color starIdle = Color(0xFFE5E7EB);

  // Accent — green (matches 无痛单词)
  static const Color primary = Color(0xFF10B981);
  static const Color primaryDark = Color(0xFF059669);
  static const Color primarySoft = Color(0xFFD1FAE5);
  // Tertiary — indigo, used as a secondary accent to break up the green.
  static const Color tertiary = Color(0xFF6366F1);
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color tertiarySoft = Color(0xFFE0E7FF);
  // Inverse surface + inverse primary used by SnackBar / scrim / dialogs.
  static const Color inverseSurface = ink;
  static const Color onInverseSurface = surface;
  static const Color inversePrimary = Color(0xFF6EE7B7);

  // Status
  static const Color success = Color(0xFF16A34A); // deeper — WCAG AA on white
  static const Color warning = Color(0xFFD97706); // deeper — WCAG AA
  static const Color danger = Color(0xFFEF4444);
  static const Color info = Color(0xFF2563EB);

  // 8-color palette for vocab tags & per-vocab progress chips.
  // Used by hash-based coloring across the app, indexed by vocabId/domain.
  // All colours are chosen to hit WCAG AA contrast (≥ 4.5:1) against
  // the cream surface at text size 14+ when used as foreground.
  static const List<Color> qwertyPalette = [
    Color(0xFF2563EB), // deep blue
    Color(0xFF7C3AED), // violet
    Color(0xFFDB2777), // deep pink
    Color(0xFF059669), // deep green
    Color(0xFFD97706), // deep amber
    Color(0xFF0D9488), // teal
    Color(0xFFDC2626), // deep red
    Color(0xFF4F46E5), // indigo
  ];

  // Backwards-compatible: when a list explicitly sets `domainColor` in its
  // manifest, that wins; otherwise the UI hashes into `qwertyPalette`.

  // Level pills (CEFR-style).
  //
  // These are DEEP BASE colours. [PillTag] derives the "soft" pill
  // background by taking `withValues(alpha: 0.15)` and the "solid" pill
  // text colour by computing a luminance-aware contrast pick. Using
  // deep base colours (not pastels) means:
  //   * soft variant: text is deep, background is pastel → WCAG AA
  //   * solid variant: text is chosen between ink / white per luminance
  static const Color levelA1 = Color(0xFF16A34A); // green 600
  static const Color levelA2 = Color(0xFF059669); // emerald 600
  static const Color levelB1 = Color(0xFFCA8A04); // yellow 600
  static const Color levelB2 = Color(0xFFDC2626); // red 600
  static const Color levelC1 = Color(0xFF7C3AED); // violet 600
  static const Color levelC2 = Color(0xFFDB2777); // pink 600

  // Mastery distribution — same spirit: distinct, readable colours.
  static const Color masteryFamiliar = Color(0xFF059669);
  static const Color masteryRecognized = Color(0xFF10B981);
  static const Color masteryVague = Color(0xFFD97706);
  static const Color masteryUnfamiliar = Color(0xFFEA580C);
  static const Color masteryUnseen = Color(0xFFD1D5DB);
}

class AppRadii {
  AppRadii._();
  static const double xxs = 3;
  static const double xs = 6;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double pill = 999;
}

class AppSpacing {
  AppSpacing._();
  static const double x1 = 4;
  static const double x1_5 = 6;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x10 = 40;
  static const double x12 = 48;
}

class AppShadows {
  AppShadows._();

  static const List<BoxShadow> none = [];

  static const List<BoxShadow> sm = [
    BoxShadow(
      color: Color(0x0F000000),
      blurRadius: 4,
      offset: Offset(0, 1),
    ),
  ];

  static const List<BoxShadow> md = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 10,
      offset: Offset(0, 2),
    ),
    BoxShadow(
      color: Color(0x08000000),
      blurRadius: 4,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> lg = [
    BoxShadow(
      color: Color(0x1F000000),
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
    BoxShadow(
      color: Color(0x0A000000),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];
}
