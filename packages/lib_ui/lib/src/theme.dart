import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

/// v5 ThemeData factory: cream/dark background, green accent, Lora serif
/// for word displays, Inter + Noto Sans SC for UI text.
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
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: GoogleFonts.notoSansSc(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.ink,
          elevation: 1,
          surfaceTintColor: Colors.transparent,
          shadowColor: const Color(0x0F000000),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x6,
            vertical: AppSpacing.x4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          textStyle: GoogleFonts.notoSansSc(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x6,
            vertical: AppSpacing.x4,
          ),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        constraints: const BoxConstraints(maxWidth: 640),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        // Use the semantic inverseSurface / onInverseSurface so SnackBars
        // automatically adapt to the current brightness when we switch
        // to dark mode.
        backgroundColor: AppColors.inverseSurface,
        contentTextStyle: TextStyle(
          color: AppColors.onInverseSurface,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          fontFamily: GoogleFonts.notoSansSc().fontFamily,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 4,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        // Use GoogleFonts directly so fallback chains, package references,
        // and font-variation settings are preserved (copyWith(fontFamily:)
        // on TextStyle drops them).
        titleTextStyle: GoogleFonts.notoSansSc(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
        contentTextStyle: GoogleFonts.notoSansSc(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: AppColors.ink,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.primarySoft,
        labelTextStyle: WidgetStatePropertyAll(
          GoogleFonts.notoSansSc(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const WidgetStatePropertyAll(
          IconThemeData(size: 22),
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
        backgroundColor: AppColors.backgroundDark,
        foregroundColor: AppColors.inkDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: GoogleFonts.notoSansSc(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.inkDark,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceDark,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.surfaceDark,
          foregroundColor: AppColors.inkDark,
          elevation: 1,
          shadowColor: const Color(0x30000000),
          surfaceTintColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x6,
            vertical: AppSpacing.x4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          textStyle: GoogleFonts.notoSansSc(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x6,
            vertical: AppSpacing.x4,
          ),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.dividerDark,
        thickness: 1,
        space: 1,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surfaceDark,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        constraints: const BoxConstraints(maxWidth: 640),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surface,
        contentTextStyle: TextStyle(
          color: AppColors.ink,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          fontFamily: GoogleFonts.notoSansSc().fontFamily,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 4,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceDark,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        titleTextStyle: GoogleFonts.notoSansSc(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.inkDark,
        ),
        contentTextStyle: GoogleFonts.notoSansSc(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: AppColors.inkDark,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surfaceDark,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.primary.withValues(alpha: 0.20),
        labelTextStyle: WidgetStatePropertyAll(
          GoogleFonts.notoSansSc(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const WidgetStatePropertyAll(IconThemeData(size: 22)),
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
      primary: Color(0xFF6EE7B7),
      onPrimary: Color(0xFF003827),
      primaryContainer: Color(0xFF006E51),
      onPrimaryContainer: Color(0xFF7AF5C6),
      secondary: Color(0xFFA5B4FC),
      onSecondary: Color(0xFF1E1B4B),
      secondaryContainer: Color(0xFF3730A3),
      onSecondaryContainer: Color(0xFFC7D2FE),
      tertiary: Color(0xFFA5B4FC),
      onTertiary: Color(0xFF1E1B4B),
      tertiaryContainer: Color(0xFF3730A3),
      onTertiaryContainer: Color(0xFFC7D2FE),
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
      surfaceTint: Color(0xFF6EE7B7),
    );
  }

  /// Shared UI text-theme: Inter for Latin, Noto Sans SC for CJK.
  /// Applies the correct text colour for [Brightness] so callers don't
  /// have to override.
  static TextTheme _uiTextTheme(TextTheme base, Brightness brightness) {
    final ink =
        brightness == Brightness.light ? AppColors.ink : AppColors.inkDark;
    final muted = brightness == Brightness.light
        ? AppColors.inkMuted
        : AppColors.inkMutedDark;
    final inter = GoogleFonts.interTextTheme(base).apply(
      bodyColor: ink,
      displayColor: ink,
    );
    return inter.copyWith(
      bodySmall: GoogleFonts.notoSansSc(
        textStyle: inter.bodySmall,
        color: muted,
      ),
      bodyMedium: GoogleFonts.notoSansSc(
        textStyle: inter.bodyMedium,
        fontWeight: FontWeight.w400,
      ),
      bodyLarge: GoogleFonts.notoSansSc(
        textStyle: inter.bodyLarge,
        fontWeight: FontWeight.w400,
      ),
      labelSmall: GoogleFonts.notoSansSc(
        textStyle: inter.labelSmall,
        color: muted,
      ),
      labelMedium: GoogleFonts.notoSansSc(
        textStyle: inter.labelMedium,
      ),
      labelLarge: GoogleFonts.notoSansSc(
        textStyle: inter.labelLarge,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: GoogleFonts.notoSansSc(
        textStyle: inter.titleSmall,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: GoogleFonts.notoSansSc(
        textStyle: inter.titleMedium,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: GoogleFonts.notoSansSc(
        textStyle: inter.titleLarge,
        fontWeight: FontWeight.w700,
      ),
      headlineSmall: GoogleFonts.notoSansSc(
        textStyle: inter.headlineSmall,
        fontWeight: FontWeight.w700,
      ),
      headlineMedium: GoogleFonts.notoSansSc(
        textStyle: inter.headlineMedium,
        fontWeight: FontWeight.w700,
      ),
      headlineLarge: GoogleFonts.notoSansSc(
        textStyle: inter.headlineLarge,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  // ── Per-style convenience constructors ────────────────────────────
  //
  // These are intentionally brightness-agnostic; callers that need
  // dark-mode aware colours should pass [context] and use the
  // Theme.of(context).colorScheme lookups (or the helper below).

  /// Serif style for displaying a vocabulary word (Lora).
  static TextStyle wordDisplay({
    double size = 36,
    FontWeight weight = FontWeight.w700,
    Color color = AppColors.ink,
  }) {
    return GoogleFonts.lora(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: 1.2,
      letterSpacing: -0.5,
    );
  }

  /// Phonetic style (small grey text like /əˈbændən/).
  static TextStyle phonetic({
    Color color = AppColors.inkMuted,
    double fontSize = 14,
  }) {
    return GoogleFonts.notoSansSc(
      fontSize: fontSize,
      fontWeight: FontWeight.w400,
      color: color,
      letterSpacing: 0.2,
    );
  }

  /// Big screen header (e.g. "发现", "设置", "图表").
  static TextStyle screenHeader({Color? color}) {
    return GoogleFonts.notoSansSc(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      height: 1.2,
      letterSpacing: -0.3,
      color: color ?? AppColors.ink,
    );
  }

  /// Card title (e.g. "今日任务", stats section titles).
  static TextStyle cardTitle({Color? color}) {
    return GoogleFonts.notoSansSc(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: color ?? AppColors.ink,
    );
  }

  /// Small uppercase section label (e.g. "PROFILE", "AI").
  static TextStyle sectionLabel({Color? color}) {
    return GoogleFonts.notoSansSc(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
      color: color ?? AppColors.inkMuted,
    );
  }

  /// Muted caption (descriptive body under titles).
  static TextStyle mutedCaption({double size = 12, Color? color}) {
    return GoogleFonts.notoSansSc(
      fontSize: size,
      fontWeight: FontWeight.w500,
      color: color ?? AppColors.inkMuted,
    );
  }

  /// Chip caption (small bold label on pills / option tags).
  static TextStyle chipCaption({Color color = AppColors.primary}) {
    return GoogleFonts.notoSansSc(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.4,
      color: color,
    );
  }

  /// Setting row title (e.g. "AI 服务商", "清除所有数据").
  static TextStyle rowTitle({Color? color}) {
    return GoogleFonts.notoSansSc(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: color ?? AppColors.ink,
    );
  }

  /// Monospace text for API keys / code-like strings.
  static TextStyle code({double size = 11, Color? color}) {
    return TextStyle(
      fontFamily: 'monospace',
      fontSize: size,
      fontWeight: FontWeight.w500,
      color: color ?? AppColors.inkMuted,
    );
  }
}
