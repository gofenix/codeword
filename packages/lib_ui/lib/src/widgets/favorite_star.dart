import 'package:flutter/material.dart';

import '../tokens.dart';

/// A star icon that swaps instantly between outlined and filled.
/// No rotation, no scale, no fade — per the 无痛单词 zero-noise spec.
///
/// Accessibility: the icon is wrapped in [Semantics] with the correct
/// toggled-state and a localised label so screen readers announce
/// "已收藏, toggle button" instead of just reading the unicode glyph.
///
/// Default size is 20 (up from 18) so it comfortably hits the minimum
/// 44×44px Apple / 48×48dp Material hit target when wrapped in an
/// [IconButton] — a 18px icon inside a zero-padding IconButton is too
/// easy to miss on a phone with fat fingers.
class FavoriteStar extends StatelessWidget {
  final bool filled;
  final Color color;
  final double size;
  final String? semanticLabel;

  const FavoriteStar({
    super.key,
    required this.filled,
    this.color = AppColors.warning,
    this.size = 20,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: filled,
      checked: filled,
      label: semanticLabel ?? (filled ? '已收藏' : '未收藏'),
      excludeSemantics: true,
      child: Icon(
        filled ? Icons.star_rounded : Icons.star_outline_rounded,
        color: color,
        size: size,
      ),
    );
  }
}
