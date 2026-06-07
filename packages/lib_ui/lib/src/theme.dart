import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

/// v5 ThemeData: cream background, green accent, Lora serif for word displays,
/// Inter + Noto Sans SC for UI text.
class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: Colors.white,
        secondary: AppColors.primaryDark,
        onSecondary: Colors.white,
        surface: AppColors.surface,
        onSurface: AppColors.ink,
        error: AppColors.danger,
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: AppColors.background,
    );

    // Body / UI: Inter for Latin, Noto Sans SC for CJK
    final uiTextTheme = GoogleFonts.interTextTheme(base.textTheme).copyWith(
      bodyMedium: GoogleFonts.notoSansSc(
        textStyle: base.textTheme.bodyMedium,
        fontWeight: FontWeight.w400,
      ),
      bodyLarge: GoogleFonts.notoSansSc(
        textStyle: base.textTheme.bodyLarge,
        fontWeight: FontWeight.w400,
      ),
      titleMedium: GoogleFonts.notoSansSc(
        textStyle: base.textTheme.titleMedium,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: GoogleFonts.notoSansSc(
        textStyle: base.textTheme.titleLarge,
        fontWeight: FontWeight.w700,
      ),
    );

    return base.copyWith(
      textTheme: uiTextTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
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
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x6,
            vertical: AppSpacing.x4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.pill),
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
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x6,
            vertical: AppSpacing.x4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0x14000000),
        thickness: 1,
        space: 1,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        elevation: 0,
      ),
    );
  }

  /// Serif style for displaying a vocabulary word (Lora).
  /// Use this whenever showing the actual English word as the main hero text.
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
  static TextStyle phonetic({Color color = AppColors.inkMuted}) {
    return GoogleFonts.notoSansSc(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: color,
      letterSpacing: 0.2,
    );
  }
}
