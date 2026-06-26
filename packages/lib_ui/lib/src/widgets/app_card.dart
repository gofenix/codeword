import 'package:flutter/material.dart';

import '../tokens.dart';
import 'pressable_scale.dart';

/// Soft, elevated card with the v5 cream/shadow-md feel.
///
/// Tappable cards ([onTap] != null) wrap themselves in a [PressableScale]
/// for tactile press feedback and announce themselves as buttons to the
/// accessibility tree via [Semantics].
///
/// The container is `antiAlias`-clipped to its rounded border so any
/// child content (images, colored rows, etc.) that exceeds the corners
/// is properly masked instead of bleeding outside the rounded radius.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;
  final List<BoxShadow>? shadow;
  final String? semanticLabel;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.x5),
    this.onTap,
    this.color,
    this.shadow,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: shadow ?? AppShadows.md,
      ),
      child: child,
    );

    if (onTap == null) return card;

    // Wrap the tappable card with a button semantics node so screen
    // readers announce it as interactive. [excludeSemantics: true]
    // prevents duplicate "button" semantics from the PressableScale.
    return Semantics(
      button: true,
      label: semanticLabel,
      child: PressableScale(
        scaleFactor: 0.98,
        onTap: onTap,
        child: card,
      ),
    );
  }
}
