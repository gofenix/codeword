import 'package:flutter/material.dart';

/// v5 design tokens — derived from `design-doc-v5-painless.md`.
///
/// Visual style: cream/light, Lora serif for words, Inter+Noto Sans SC for UI,
/// green #10B981 accent, pill tags, card-based, shadow-md, 12-16px radius.
class AppColors {
  AppColors._();

  // Surfaces (cream/light)
  static const Color background = Color(0xFFFAFAF5);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF5F2EA);

  // Text
  static const Color ink = Color(0xFF1F2421);
  static const Color inkMuted = Color(0xFF6B7470);
  static const Color inkSubtle = Color(0xFF98A09B);

  // Accent — green (matches 无痛单词)
  static const Color primary = Color(0xFF10B981);
  static const Color primaryDark = Color(0xFF059669);
  static const Color primarySoft = Color(0xFFD1FAE5);

  // Status
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // Domain tag colors (one per built-in vocabulary)
  static const Color domainCs = Color(0xFF6366F1); // CS
  static const Color domainPython = Color(0xFF3776AB); // Python
  static const Color domainAi = Color(0xFF059669); // AI (darker green, distinct from primary)
  static const Color domainLlm = Color(0xFF8B5CF6); // LLM
  static const Color domainWeb = Color(0xFFF59E0B); // Web
  static const Color domainDevops = Color(0xFF14B8A6); // DevOps
  static const Color domainData = Color(0xFFEC4899); // Data
  static const Color domainSecurity = Color(0xFFEF4444); // Security
  static const Color domainProduct = Color(0xFFF97316); // Product (orange, matches catalog)

  // Level pills (CEFR-style)
  static const Color levelA1 = Color(0xFF86EFAC);
  static const Color levelA2 = Color(0xFFA7F3D0);
  static const Color levelB1 = Color(0xFFFDE68A);
  static const Color levelB2 = Color(0xFFFCA5A5);
  static const Color levelC1 = Color(0xFFC4B5FD);
  static const Color levelC2 = Color(0xFFF9A8D4);

  // Mastery distribution
  static const Color masteryFamiliar = Color(0xFF10B981);
  static const Color masteryRecognized = Color(0xFF34D399);
  static const Color masteryVague = Color(0xFFF59E0B);
  static const Color masteryUnfamiliar = Color(0xFFFB923C);
  static const Color masteryUnseen = Color(0xFFE5E7EB);
}

class AppRadii {
  AppRadii._();
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
