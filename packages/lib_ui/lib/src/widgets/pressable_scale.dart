import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps a child with a subtle press interaction:
///   - scale to [scaleFactor] (default 0.97) on tap down
///   - opacity to [pressedOpacity] (default 0.85) on tap down
///   - light haptic impact on tap release
///   - smooth ease-out-cubic, 120ms
///
/// Use this anywhere a tap should *feel* tappable without being noisy.
/// The underlying widget's own InkWell / Material is preserved (or you
/// can omit onTap to make the wrapper visually inert but still respond
/// to gestures if you want a press-only feedback).
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleFactor;
  final double pressedOpacity;
  final Duration duration;
  final Curve curve;
  final HitTestBehavior behavior;
  final bool haptic;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.scaleFactor = 0.97,
    this.pressedOpacity = 0.85,
    this.duration = const Duration(milliseconds: 120),
    this.curve = Curves.easeOutCubic,
    this.behavior = HitTestBehavior.opaque,
    this.haptic = true,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  void _setDown(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  void _onTap() {
    if (widget.haptic) HapticFeedback.lightImpact();
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final hasOnTap = widget.onTap != null;
    final scale = _down ? widget.scaleFactor : 1.0;
    final opacity = _down ? widget.pressedOpacity : 1.0;
    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: hasOnTap ? (_) => _setDown(true) : null,
      onTapUp: hasOnTap ? (_) => _setDown(false) : null,
      onTapCancel: hasOnTap ? () => _setDown(false) : null,
      onTap: hasOnTap ? _onTap : null,
      child: AnimatedScale(
        scale: scale,
        duration: widget.duration,
        curve: widget.curve,
        child: AnimatedOpacity(
          opacity: opacity,
          duration: widget.duration,
          curve: widget.curve,
          child: widget.child,
        ),
      ),
    );
  }
}
