import 'package:flutter/material.dart';

import 'tokens.dart';

/// Editorial ThemeData factory: paper surfaces, bronze accents, system CJK and
/// a bundled Libre Baskerville face for English display copy.
///
/// Material 3 compatibility: both [light] and [dark] fill in the full
/// ColorScheme (tertiary, outline, scrim, inverse*, surfaceContainer* …)
/// so components that rely on these fields (NavigationBar, SnackBar,
/// SearchBar, DatePicker …) render consistently.
class AppTheme {
  AppTheme._();

  // ── Light theme ───────────────────────────────────────────────────
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: _lightScheme(),
      scaffoldBackgroundColor: AppColors.background,
    );
    return base.copyWith(
      textTheme: _uiTextTheme(base.textTheme, Brightness.light),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background.withValues(alpha: 0.7),
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.ink,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x6,
            vertical: AppSpacing.x4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
          textStyle: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          elevation: 2,
          shadowColor: const Color(0x3D3A2E1E),
          surfaceTintColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x6,
            vertical: AppSpacing.x4,
          ),
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        },
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 0.5,
        space: 0.5,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        constraints: const BoxConstraints(maxWidth: 640),
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.inverseSurface,
        contentTextStyle: TextStyle(
          color: AppColors.onInverseSurface,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
        contentTextStyle: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: AppColors.ink,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface.withValues(alpha: 0.7),
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
        iconTheme: const WidgetStatePropertyAll(
          IconThemeData(size: 24),
        ),
      ),
    );
  }

  // ── Dark theme ────────────────────────────────────────────────────
  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: _darkScheme(),
      scaffoldBackgroundColor: AppColors.backgroundDark,
    );
    return base.copyWith(
      textTheme: _uiTextTheme(base.textTheme, Brightness.dark),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.backgroundDark.withValues(alpha: 0.7),
        foregroundColor: AppColors.inkDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.inkDark,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceDark,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.surfaceDark,
          foregroundColor: AppColors.inkDark,
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x6,
            vertical: AppSpacing.x4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
          textStyle: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          elevation: 1,
          shadowColor: const Color(0x66000000),
          surfaceTintColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x6,
            vertical: AppSpacing.x4,
          ),
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        },
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.dividerDark,
        thickness: 0.5,
        space: 0.5,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surfaceDark,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        constraints: const BoxConstraints(maxWidth: 640),
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surface,
        contentTextStyle: TextStyle(
          color: AppColors.ink,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceDark,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.inkDark,
        ),
        contentTextStyle: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: AppColors.inkDark,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surfaceDark.withValues(alpha: 0.7),
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
        iconTheme: const WidgetStatePropertyAll(
          IconThemeData(size: 24),
        ),
      ),
    );
  }

  // ── Shared: full Material 3 ColorScheme ──────────────────────────
  static ColorScheme _lightScheme() {
    return const ColorScheme.light(
      brightness: Brightness.light,
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      primaryContainer: AppColors.primarySoft,
      onPrimaryContainer: AppColors.primaryDark,
      // Secondary: an indigo distinct from primary to break up the green.
      secondary: AppColors.tertiary,
      onSecondary: AppColors.onTertiary,
      secondaryContainer: AppColors.tertiarySoft,
      onSecondaryContainer: AppColors.tertiary,
      tertiary: AppColors.tertiary,
      onTertiary: AppColors.onTertiary,
      tertiaryContainer: AppColors.tertiarySoft,
      onTertiaryContainer: AppColors.tertiary,
      error: AppColors.danger,
      onError: AppColors.onPrimary,
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: Color(0xFF410002),
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      surfaceDim: AppColors.surfaceMuted,
      surfaceBright: AppColors.surface,
      surfaceContainerLowest: Color(0xFFFFFFFF),
      surfaceContainerLow: Color(0xFFF8F7F0),
      surfaceContainer: AppColors.surfaceMuted,
      surfaceContainerHigh: Color(0xFFEFECDF),
      surfaceContainerHighest: Color(0xFFE7E4D5),
      onSurfaceVariant: AppColors.inkMuted,
      outline: AppColors.divider,
      outlineVariant: Color(0x0F1F2421),
      shadow: Color(0x1F000000),
      scrim: Color(0x66000000),
      inverseSurface: AppColors.inverseSurface,
      onInverseSurface: AppColors.onInverseSurface,
      inversePrimary: AppColors.inversePrimary,
      surfaceTint: AppColors.primary,
    );
  }

  static ColorScheme _darkScheme() {
    return const ColorScheme.dark(
      brightness: Brightness.dark,
      primary: Color(0xFFD8C39E),
      onPrimary: Color(0xFF342A1D),
      primaryContainer: Color(0xFF59492F),
      onPrimaryContainer: Color(0xFFF2E4CB),
      secondary: Color(0xFFAFC1A6),
      onSecondary: Color(0xFF20301D),
      secondaryContainer: Color(0xFF394A35),
      onSecondaryContainer: Color(0xFFD7E8D0),
      tertiary: Color(0xFFAFC1A6),
      onTertiary: Color(0xFF20301D),
      tertiaryContainer: Color(0xFF394A35),
      onTertiaryContainer: Color(0xFFD7E8D0),
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      errorContainer: Color(0xFF93000A),
      onErrorContainer: Color(0xFFFFDAD6),
      surface: AppColors.surfaceDark,
      onSurface: AppColors.inkDark,
      surfaceDim: Color(0xFF101314),
      surfaceBright: Color(0xFF36393B),
      surfaceContainerLowest: Color(0xFF0B0D0E),
      surfaceContainerLow: Color(0xFF181B1C),
      surfaceContainer: AppColors.surfaceMutedDark,
      surfaceContainerHigh: Color(0xFF323637),
      surfaceContainerHighest: Color(0xFF3D4142),
      onSurfaceVariant: AppColors.inkMutedDark,
      outline: AppColors.dividerDark,
      outlineVariant: Color(0x33EDECE6),
      shadow: Color(0x66000000),
      scrim: Color(0x99000000),
      inverseSurface: AppColors.surface,
      onInverseSurface: AppColors.ink,
      inversePrimary: AppColors.primaryDark,
      surfaceTint: Color(0xFFD8C39E),
    );
  }

  /// Shared platform text theme. System fonts keep the entire learning flow
  /// available offline and provide native CJK fallback on iOS and Android.
  static TextTheme _uiTextTheme(TextTheme base, Brightness brightness) {
    final ink =
        brightness == Brightness.light ? AppColors.ink : AppColors.inkDark;
    final muted = brightness == Brightness.light
        ? AppColors.inkMuted
        : AppColors.inkMutedDark;
    final inter = base.apply(
      bodyColor: ink,
      displayColor: ink,
    );
    return inter.copyWith(
      bodySmall: inter.bodySmall?.copyWith(color: muted),
      bodyMedium: inter.bodyMedium?.copyWith(fontWeight: FontWeight.w400),
      bodyLarge: inter.bodyLarge?.copyWith(fontWeight: FontWeight.w400),
      labelSmall: inter.labelSmall?.copyWith(color: muted),
      labelMedium: inter.labelMedium,
      labelLarge: inter.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: inter.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      titleMedium: inter.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleLarge: inter.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      headlineSmall: inter.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      headlineMedium:
          inter.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
      headlineLarge: inter.headlineLarge?.copyWith(fontWeight: FontWeight.w800),
    );
  }

  // ── Per-style convenience constructors ────────────────────────────
  //
  // Each ink-defaulting helper accepts an optional [context]. When passed,
  // the default text colour resolves to the brightness-correct ink via
  // [AppColors.of] so the same call renders readably in dark mode. When
  // omitted (or when an explicit [color] is given) behaviour is unchanged,
  // keeping every existing light-theme call site pixel-identical.

  static const String editorialFont = 'packages/lib_ui/LibreBaskerville';

  /// Bundled serif style for vocabulary words and editorial English copy.
  static TextStyle wordDisplay({
    double size = 36,
    FontWeight weight = FontWeight.w700,
    Color? color,
    BuildContext? context,
  }) {
    return TextStyle(
      fontFamily: editorialFont,
      fontSize: size,
      fontWeight: weight,
      color: color ?? _ink(context),
      height: 1.2,
      letterSpacing: _tracking(size),
    );
  }

  /// General editorial serif style (history titles, book monograms,
  /// large stat numerals). Tracking stays neutral: unlike [wordDisplay]
  /// this style also renders CJK (e.g. book names) and is used across a
  /// wide size range, where a baked-in Latin-display negative tracking
  /// would be wrong. Size-aware tracking is reserved for [wordDisplay],
  /// which only ever renders Latin words/numerals.
  static TextStyle editorial({
    double size = 24,
    FontWeight weight = FontWeight.w700,
    Color? color,
    BuildContext? context,
    double height = 1.2,
  }) {
    return TextStyle(
      fontFamily: editorialFont,
      fontSize: size,
      fontWeight: weight,
      color: color ?? _ink(context),
      height: height,
      letterSpacing: 0,
    );
  }

  /// Phonetic style (small grey text like /əˈbændən/).
  static TextStyle phonetic({
    Color? color,
    double fontSize = 14,
    BuildContext? context,
  }) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w400,
      color: color ?? _inkMuted(context),
      letterSpacing: 0,
    );
  }

  /// Big screen header (e.g. "发现", "设置", "图表").
  ///
  /// Tracking stays at 0 here on purpose: this style is used for Chinese
  /// UI headers (system font, CJK glyphs), and several callers override
  /// [TextStyle.fontSize] via `.copyWith` down to 18–28px. Baking a
  /// size-specific Latin tracking value in would be both wrong for CJK and
  /// frozen at the wrong size. Size-aware tracking lives on [wordDisplay]
  /// (the Latin serif hero style) where it belongs.
  static TextStyle screenHeader({Color? color, BuildContext? context}) {
    return TextStyle(
      fontSize: 34,
      fontWeight: FontWeight.w700,
      height: 1.2,
      letterSpacing: 0,
      color: color ?? _ink(context),
    );
  }

  /// Card title (e.g. "今日任务", stats section titles).
  static TextStyle cardTitle({Color? color, BuildContext? context}) {
    return TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w700,
      color: color ?? _ink(context),
    );
  }

  /// Small uppercase section label (e.g. "PROFILE", "AI").
  static TextStyle sectionLabel({Color? color, BuildContext? context}) {
    return TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 2.4,
      color: color ?? AppColors.primary,
    );
  }

  /// Muted caption (descriptive body under titles).
  static TextStyle mutedCaption({
    double size = 13,
    Color? color,
    BuildContext? context,
  }) {
    return TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w500,
      color: color ?? _inkMuted(context),
    );
  }

  /// Chip caption (small bold label on pills / option tags).
  static TextStyle chipCaption({Color color = AppColors.primary}) {
    return TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      color: color,
    );
  }

  /// Setting row title (e.g. "AI 服务商", "清除所有数据").
  static TextStyle rowTitle({Color? color, BuildContext? context}) {
    return TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: color ?? _ink(context),
    );
  }

  /// Monospace text for API keys / code-like strings.
  static TextStyle code(
      {double size = 11, Color? color, BuildContext? context}) {
    return TextStyle(
      fontFamily: 'monospace',
      fontSize: size,
      fontWeight: FontWeight.w500,
      color: color ?? _inkMuted(context),
    );
  }

  // Resolve ink / muted defaults: brightness-aware when [context] is
  // supplied, otherwise the light constant (unchanged legacy behaviour).
  static Color _ink(BuildContext? context) =>
      context == null ? AppColors.ink : AppColors.of(context).ink;
  static Color _inkMuted(BuildContext? context) =>
      context == null ? AppColors.inkMuted : AppColors.of(context).inkMuted;

  /// Size-specific tracking (letter-spacing), following Apple's rule that
  /// tracking is *never* a single fixed value across sizes (WWDC 2020,
  /// "The Details of UI Typography"): large display type reads too loose
  /// as it grows, so it tightens (negative); small text opens up slightly
  /// for legibility; body/subheads stay neutral.
  ///
  /// Flutter's `letterSpacing` is in logical pixels, so the display tier
  /// scales with [size] to approximate an em-based `-0.021em`. The effect
  /// is kept intentionally gentle so it stays invisible on CJK glyphs
  /// (which don't want negative tracking) while pulling the big Latin
  /// serif words — the app's hero elements — visibly tighter.
  static double _tracking(double size) {
    if (size >= 28) return size * -0.021; // display / headline: tighten
    if (size <= 13) return 0.15; // captions / phonetic: nudge apart
    return 0; // body & subheads: neutral
  }
}
