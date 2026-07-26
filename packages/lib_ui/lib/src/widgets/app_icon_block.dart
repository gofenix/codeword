import 'package:flutter/material.dart';

import '../tokens.dart';

/// A tinted rounded square that holds an icon or single letter — the
/// "monogram block" pattern repeated across list rows, settings tiles,
/// and stat cards. Centralising it keeps the fill alpha, radius, and
/// size rhythm consistent (§16 — craft, nothing is random).
///
/// The [color] is rendered at a low alpha as the fill, with the child
/// (icon/letter) drawn in the full-strength [color] on top — the same
/// recipe every call site previously inlined by hand.
class AppIconBlock extends StatelessWidget {
  final Color color;
  final Widget child;
  final double size;
  final double radius;

  const AppIconBlock({
    super.key,
    required this.color,
    required this.child,
    this.size = 44,
    this.radius = AppRadii.md,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // In dark mode the tint blends toward the dark surface so it
        // reads as a soft wash rather than a glowing pastel (same logic
        // as the category monogram and settings icon blocks).
        color: Color.lerp(color, AppColors.surfaceDark, isDark ? 0.4 : 0.0)!
            .withValues(alpha: isDark ? 0.20 : 0.14),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: color),
        child: IconTheme.merge(
          data: IconThemeData(color: color, size: size * 0.45),
          child: child,
        ),
      ),
    );
  }
}
