import 'package:flutter/material.dart';

import '../tokens.dart';

/// Decorative oversized opening quote — a v5 signature mark on the learning
/// card. Renders in soft primary color behind the content.
///
/// The quote mark is a *decorative* element: it is excluded from both the
/// hit-test tree ([IgnorePointer]) and the semantics tree
/// ([ExcludeSemantics]) so screen readers don't try to pronounce
/// the unicode left-double-quote glyph and screen-tapping doesn't route
/// to the quote instead of its sibling content.
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
    return ExcludeSemantics(
      child: IgnorePointer(
        child: Text(
          '“',
          textAlign: align,
          style: TextStyle(
            fontFamily: 'serif',
            fontSize: size,
            // 0.85 keeps the glyph fully inside the Text's line box while
            // still letting us use negative offset / Stack positioning
            // to push the quote up visually. 0.7 was clipping the tops of
            // the curly quotes on macOS with Lora.
            height: 0.85,
            color: color.withValues(alpha: 0.18),
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
