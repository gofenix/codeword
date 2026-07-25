import 'package:flutter/material.dart';

/// CodeWord editorial design tokens.
///
/// Warm paper surfaces, deep ink, restrained bronze and sage accents. English
/// display copy uses a bundled serif while Chinese UI keeps the system font.
///
/// All colours are light theme. For the dark theme tokens (paired with
/// [AppTheme.dark()]) see the `darkXxx` variants below — they are used by
/// the theme layer when [Theme.of(context).brightness] is dark.
class AppColors {
  AppColors._();

  // Surfaces (warm paper)
  static const Color background = Color(0xFFF4F0E7);
  static const Color surface = Color(0xFFFBF9F3);
  static const Color surfaceMuted = Color(0xFFEEE8DC);
  // Dark bezel painted around the phone-shaped column when the app
  // runs in a desktop window. Reads as a phone sitting on a desk.
  static const Color bezel = Color(0xFF1A1A1F);
  // Light cream wall behind the phone bezel on desktop.
  static const Color desktopWall = Color(0xFFE4DED2);

  // Dark-mode surfaces
  static const Color backgroundDark = Color(0xFF181714);
  static const Color surfaceDark = Color(0xFF22201C);
  static const Color surfaceMutedDark = Color(0xFF2D2A25);
  static const Color desktopWallDark = Color(0xFF100F0D);

  // Text (light)
  static const Color ink = Color(0xFF20211E);
  static const Color inkMuted = Color(0xFF77746C);
  static const Color inkSubtle = Color(0xFFA39D91);

  // Text (dark)
  static const Color inkDark = Color(0xFFF2EDE3);
  static const Color inkMutedDark = Color(0xFFB8B0A2);
  static const Color inkSubtleDark = Color(0xFF857E72);

  // Foreground on top of primary/accent fills.
  static const Color onPrimary = Color(0xFFFFFFFF);

  // Generic divider used in ThemeData.
  static const Color divider = Color(0xFFD8D0C2);
  static const Color dividerDark = Color(0xFF484238);

  // Idle state for the favorite star (replaces Colors.amber default).
  static const Color starIdle = Color(0xFFE5E7EB);

  // Accent — muted bronze. Sage remains a distinct semantic learning colour.
  static const Color primary = Color(0xFF806A46);
  static const Color primaryDark = Color(0xFF604D31);
  static const Color primarySoft = Color(0xFFEEE6D8);
  static const Color sage = Color(0xFF65775F);
  static const Color sageSoft = Color(0xFFE5ECE1);
  static const Color target = Color(0xFFF2D96B);
  // Tertiary — sage, used for mastery and learning progress.
  static const Color tertiary = sage;
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color tertiarySoft = sageSoft;
  // Inverse surface + inverse primary used by SnackBar / scrim / dialogs.
  static const Color inverseSurface = ink;
  static const Color onInverseSurface = surface;
  static const Color inversePrimary = Color(0xFFD8C39E);

  // Status
  static const Color success = Color(0xFF16A34A); // deeper — WCAG AA on white
  static const Color warning = Color(0xFFC28A2C);
  static const Color danger = Color(0xFFB95745);
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

  // Idle star for the dark theme (paired with [starIdle]).
  static const Color starIdleDark = Color(0xFF3A4042);

  // ── Brightness-aware resolution ──────────────────────────────────
  //
  // Widgets historically referenced the light constants directly
  // (`AppColors.ink`, `AppColors.surface`, …), which broke dark mode:
  // white cards + near-black text rendered on the dark scaffold. Use
  // [AppColors.of] to pull the surface/text tokens that match the
  // current [Theme]'s brightness. Brand/semantic colours (primary,
  // danger, palette …) are intentionally NOT resolved — they read
  // correctly on both backgrounds.
  static const AppPalette _light = AppPalette(
    ink: ink,
    inkMuted: inkMuted,
    inkSubtle: inkSubtle,
    surface: surface,
    surfaceMuted: surfaceMuted,
    background: background,
    divider: divider,
    starIdle: starIdle,
  );

  static const AppPalette _dark = AppPalette(
    ink: inkDark,
    inkMuted: inkMutedDark,
    inkSubtle: inkSubtleDark,
    surface: surfaceDark,
    surfaceMuted: surfaceMutedDark,
    background: backgroundDark,
    divider: dividerDark,
    starIdle: starIdleDark,
  );

  /// Resolve the brightness-dependent surface/text palette for [context].
  static AppPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? _dark : _light;

  // Dark-mode counterpart to [primarySoft]. Matches the Material 3
  // `primaryContainer` used by [AppTheme.dark] so the bronze "soft" fill
  // reads as a warm container on the dark scaffold instead of a bright
  // cream block. Light-theme [primarySoft] is a pale cream that would glow
  // on a dark surface; this is the resolved-per-brightness fill to use
  // wherever [primarySoft] was previously hard-coded as a background.
  static const Color primarySoftDark = Color(0xFF59492F);

  /// Brightness-aware bronze container fill (light: [primarySoft],
  /// dark: [primarySoftDark]). Use for soft bronze pill/tag/badge
  /// backgrounds so they never leak the light cream into dark mode.
  static Color primaryContainerOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? primarySoftDark
      : primarySoft;

  /// Foreground colour that reads correctly on top of
  /// [primaryContainerOf] (light: [primaryDark] on cream, dark: a warm
  /// cream on the dark bronze container — matching the Material 3
  /// `onPrimaryContainer` pairing).
  static const Color onPrimaryContainerDark = Color(0xFFF2E4CB);

  static Color onPrimaryContainerOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? onPrimaryContainerDark
      : primaryDark;
}

/// Brightness-resolved surface/text tokens returned by [AppColors.of].
///
/// Only the tokens that must flip between light and dark live here.
/// Brand and status colours stay on [AppColors] as flat constants.
class AppPalette {
  final Color ink;
  final Color inkMuted;
  final Color inkSubtle;
  final Color surface;
  final Color surfaceMuted;
  final Color background;
  final Color divider;
  final Color starIdle;

  const AppPalette({
    required this.ink,
    required this.inkMuted,
    required this.inkSubtle,
    required this.surface,
    required this.surfaceMuted,
    required this.background,
    required this.divider,
    required this.starIdle,
  });
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

  static const List<BoxShadow> paper = [
    BoxShadow(
      color: Color(0x120F0D09),
      blurRadius: 20,
      offset: Offset(0, 8),
    ),
    BoxShadow(
      color: Color(0x59FFFFFF),
      blurRadius: 1,
      offset: Offset(0, -1),
    ),
  ];
}

class AppMaterials {
  AppMaterials._();

  static const LinearGradient canvas = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF9F6EF), Color(0xFFF1EBDD)],
    stops: [0, 1],
  );

  static const LinearGradient paper = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFFDF8), Color(0xFFF8F3E9)],
    stops: [0, 1],
  );

  static const LinearGradient bronze = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF967E55), Color(0xFF735E3D)],
  );

  static BoxDecoration canvasDecoration(BuildContext context) {
    final palette = AppColors.of(context);
    return BoxDecoration(
      color: palette.background,
      gradient:
          Theme.of(context).brightness == Brightness.light ? canvas : null,
    );
  }
}

/// Motion tokens — shared easing curves and durations so every animation
/// in the app feels like it belongs to the same product (cohesion).
///
/// The curves are translated from the web-oriented design skills into
/// Flutter [Cubic]s. The built-in Material/CSS easings are intentionally
/// too weak; these are the "strong" variants the craft rules call for:
///
///   * [easeOut] — the default for enter/exit and any tap feedback. Starts
///     fast so the interface feels like it responds the instant the user
///     acts. NEVER use ease-in for UI: it delays the initial movement, the
///     exact moment the user is watching, and reads as sluggish.
///   * [easeInOut] — for elements moving/morphing on screen (natural
///     acceleration then deceleration).
///   * [emphasized] — an iOS-style drawer/sheet curve for larger surfaces.
///
/// Durations follow the rule that UI animations stay under ~300ms; slower
/// values are reserved for large surfaces (sheets) or deliberate holds.
class AppMotion {
  AppMotion._();

  // Strong ease-out — cubic-bezier(0.23, 1, 0.32, 1).
  static const Cubic easeOut = Cubic(0.23, 1, 0.32, 1);
  // Strong ease-in-out — cubic-bezier(0.77, 0, 0.175, 1).
  static const Cubic easeInOut = Cubic(0.77, 0, 0.175, 1);
  // iOS-like drawer/sheet curve — cubic-bezier(0.32, 0.72, 0, 1).
  static const Cubic emphasized = Cubic(0.32, 0.72, 0, 1);

  // Press feedback: 100-160ms. Snappy confirmation the tap was heard.
  static const Duration press = Duration(milliseconds: 140);
  // Learning feedback remains visible just long enough to register without
  // slowing the high-frequency question loop.
  static const Duration answerCorrect = Duration(milliseconds: 180);
  static const Duration answerWrong = Duration(milliseconds: 240);
  // Tooltips / small popovers.
  static const Duration fast = Duration(milliseconds: 180);
  // Dropdowns, selects, content crossfades.
  static const Duration medium = Duration(milliseconds: 240);
  // Modals, drawers, larger surfaces.
  static const Duration slow = Duration(milliseconds: 320);
}
