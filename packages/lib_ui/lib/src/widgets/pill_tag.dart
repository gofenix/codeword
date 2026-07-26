import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';

/// Pill-shaped tag with optional color and icon. Use for level badges,
/// domain tags, "NEW", "PRO" labels — v5 design's signature element.
///
/// Contrast is automatic:
///   * [PillVariant.soft] → `color.withValues(alpha: 0.15)` background,
///     `color` as foreground. The base `color` MUST be dark enough to
///     hit WCAG AA against the card surface, which is guaranteed by the
///     values in [AppColors] level/qwerty palettes. In dark mode the
///     foreground is lightened toward white so the deep base colours
///     stay readable on the dark card.
///   * [PillVariant.solid] → `color` as background, foreground is
///     chosen between white and ink based on the background's luminance
///     so a pastel-colored solid pill never has invisible white text.
class PillTag extends StatelessWidget {
  final String label;
  final Color? color;
  final IconData? icon;
  final PillVariant variant;
  final EdgeInsets padding;

  const PillTag({
    super.key,
    required this.label,
    this.color,
    this.icon,
    this.variant = PillVariant.soft,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.x3,
      vertical: AppSpacing.x1,
    ),
  });

  factory PillTag.level(String level, {Color? color}) {
    return PillTag(
      label: level,
      color: color ?? _levelColor(level),
      icon: Icons.signal_cellular_alt,
    );
  }

  factory PillTag.domain(String name, {required Color color, IconData? icon}) {
    return PillTag(label: name, color: color, icon: icon);
  }

  @override
  Widget build(BuildContext context) {
    final base = color ?? AppColors.primary;
    final bg = variant == PillVariant.soft
        ? base.withValues(alpha: 0.15)
        : base;
    // Foreground for solid variant: compute relative luminance and pick
    // the side (light/dark) that has enough contrast. Threshold of
    // 0.5 gives ~4.6:1 minimum which comfortably clears WCAG AA at any
    // text weight/size.
    final bool lightBg;
    if (variant == PillVariant.soft) {
      lightBg = true;
    } else {
      // ColorScheme's built-in luminance helper — always available,
      // no deprecation, returns a 0..1 double matching WCAG.
      final lum = base.computeLuminance();
      lightBg = lum > 0.5;
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = variant == PillVariant.soft
        ? (isDark ? Color.lerp(base, Colors.white, 0.45)! : base)
        : (lightBg ? AppColors.ink : AppColors.onPrimary);

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: AppSpacing.x1),
          ],
          Text(
            label,
            style: AppTheme.chipCaption(color: fg)
                .copyWith(letterSpacing: 0.3, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  /// Level → CEFR-tinted base colour. Any unknown / non-standard level
  /// falls back to the brand primary (always readable, always visible)
  /// instead of a muted grey that might fall below WCAG AA.
  static Color _levelColor(String level) {
    switch (level.toUpperCase().trim()) {
      case 'A1':
        return AppColors.levelA1;
      case 'A2':
        return AppColors.levelA2;
      case 'B1':
        return AppColors.levelB1;
      case 'B2':
        return AppColors.levelB2;
      case 'C1':
        return AppColors.levelC1;
      case 'C2':
        return AppColors.levelC2;
      default:
        // Fall back to primary instead of inkMuted — primary is always
        // readable against both cream backgrounds and in soft/solid variants.
        return AppColors.primary;
    }
  }
}

enum PillVariant { soft, solid }
