import 'package:flutter/material.dart';

import '../tokens.dart';

/// Pill-shaped tag with optional color and icon. Use for level badges,
/// domain tags, "NEW", "PRO" labels — v5 design's signature element.
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
      vertical: 4,
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
    final fg = color ?? AppColors.primary;
    final bg = variant == PillVariant.soft ? fg.withValues(alpha: 0.12) : fg;
    final textColor =
        variant == PillVariant.soft ? fg : Colors.white;

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
            Icon(icon, size: 12, color: textColor),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textColor,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  static Color _levelColor(String level) {
    switch (level.toUpperCase()) {
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
        return AppColors.inkMuted;
    }
  }
}

enum PillVariant { soft, solid }
