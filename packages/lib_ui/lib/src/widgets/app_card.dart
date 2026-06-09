import 'package:flutter/material.dart';

import '../tokens.dart';
import 'pressable_scale.dart';

/// Soft, elevated card with the v5 cream/shadow-md feel.
///
/// Tappable cards ([onTap] != null) wrap themselves in a [PressableScale]
/// so the entire card breathes a little on press. The card's own color
/// and shadow still animate via [AnimatedContainer] for cheap property
/// transitions.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;
  final List<BoxShadow>? shadow;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.x5),
    this.onTap,
    this.color,
    this.shadow,
  });

  @override
  Widget build(BuildContext context) {
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: shadow ?? AppShadows.md,
      ),
      child: child,
    );

    if (onTap == null) return card;
    return PressableScale(
      scaleFactor: 0.98,
      onTap: onTap,
      child: card,
    );
  }
}
