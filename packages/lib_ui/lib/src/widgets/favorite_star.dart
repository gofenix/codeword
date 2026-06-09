import 'package:flutter/material.dart';

/// A star icon that animates between outlined and filled: the icon
/// rotates 0° → 360° while scaling 0.6 → 1.0 on transition.
///
/// Sized 18px by default. Color follows the [filled] state.
class FavoriteStar extends StatelessWidget {
  final bool filled;
  final Color color;
  final double size;
  const FavoriteStar({
    super.key,
    required this.filled,
    this.color = Colors.amber,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) {
        return ScaleTransition(
          scale: Tween<double>(begin: 0.6, end: 1.0).animate(anim),
          child: RotationTransition(
            turns: Tween<double>(begin: 0.85, end: 1.0).animate(anim),
            child: FadeTransition(opacity: anim, child: child),
          ),
        );
      },
      child: filled
          ? Icon(
              Icons.star_rounded,
              key: const ValueKey('filled'),
              color: color,
              size: size,
            )
          : Icon(
              Icons.star_outline_rounded,
              key: const ValueKey('outlined'),
              color: color,
              size: size,
            ),
    );
  }
}
