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
///
/// A transparent [Material] sits between the decoration and [child] so
/// descendant [InkWell]s (settings rows, list rows, segmented controls)
/// paint their ripple *on the card* instead of on a distant ancestor
/// Material behind the card's opaque paper fill — where it would be
/// invisible.
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
    final palette = AppColors.of(context);
    final brightness = Theme.of(context).brightness;
    final isLight = brightness == Brightness.light;
    final usePaperMaterial =
        (color == null || color == palette.surface);
    final card = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: usePaperMaterial ? null : color ?? palette.surface,
        gradient: usePaperMaterial
            ? (isLight ? AppMaterials.paper : AppMaterials.paperDark)
            : null,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(
          color: palette.divider.withValues(alpha: 0.82),
          width: AppBorders.hairline,
        ),
        boxShadow: shadow ??
            (isLight ? AppShadows.paper : AppShadows.paperDark),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Padding(padding: padding, child: child),
      ),
    );

    if (onTap == null) return card;

    // Wrap the tappable card with a button semantics node so screen
    // readers announce it as interactive.
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
