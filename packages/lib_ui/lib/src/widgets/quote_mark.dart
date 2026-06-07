import 'package:flutter/material.dart';

import '../tokens.dart';

/// Decorative oversized opening quote — a v5 signature mark on the learning
/// card. Renders in soft primary color behind the content.
class QuoteMark extends StatelessWidget {
  final double size;
  final Color color;
  final TextAlign align;

  const QuoteMark({
    super.key,
    this.size = 96,
    this.color = AppColors.primary,
    this.align = TextAlign.left,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Text(
        '\u201C',
        textAlign: align,
        style: TextStyle(
          fontSize: size,
          height: 0.7,
          color: color.withValues(alpha: 0.18),
          fontWeight: FontWeight.w900,
          fontFamily: 'Georgia',
        ),
      ),
    );
  }
}
