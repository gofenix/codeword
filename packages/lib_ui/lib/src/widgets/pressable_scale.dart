import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps a child with a subtle press interaction:
///   - scale to [scaleFactor] (default 0.97) on tap down
///   - opacity to [pressedOpacity] (default 0.85) on tap down
///   - light haptic impact on tap release
///
/// Transitions are instant (no tweens) per the 无痛单词 zero-noise spec.
/// Use this anywhere a tap should *feel* tappable without being noisy.
///
/// The default [behavior] is [HitTestBehavior.translucent] so children with
/// their own gesture detectors (buttons inside a tappable card) still
/// receive pointer events. Use [HitTestBehavior.opaque] only when the
/// entire card should swallow taps and you know there are no nested
/// buttons.
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleFactor;
  final double pressedOpacity;
  final HitTestBehavior behavior;
  final bool haptic;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.scaleFactor = 0.97,
    this.pressedOpacity = 0.85,
    this.behavior = HitTestBehavior.translucent,
    this.haptic = true,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  void _setDown(bool v) {
    // Only call setState if the widget is still mounted AND the value
    // actually changed. The "mounted" check is critical because
    // onTap?.call() below can push a new route that disposes this
    // widget — if a pointer event (cancel/up) arrives right after, we
    // must not call setState on an unmounted state.
    if (mounted && _down != v) setState(() => _down = v);
  }

  void _onTap() {
    if (widget.haptic && _isMobilePlatform) {
      HapticFeedback.lightImpact();
    }
    widget.onTap?.call();
  }

  /// Haptic feedback only on mobile platforms. On desktop HapticFeedback
  /// is a no-op but on some platforms prints warnings.
  static bool get _isMobilePlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
        return true;
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasOnTap = widget.onTap != null;
    final scale = _down ? widget.scaleFactor : 1.0;
    final opacity = _down ? widget.pressedOpacity : 1.0;
    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: hasOnTap ? (_) => _setDown(true) : null,
      onTapUp: hasOnTap
          ? (_) {
              _setDown(false);
              // _onTap is called via the onTap handler so Flutter's
              // built-in tap-semantics semantics are preserved (tap
              // cancel after drag still works correctly).
            }
          : null,
      onTapCancel: hasOnTap ? () => _setDown(false) : null,
      onTap: hasOnTap ? _onTap : null,
      child: Transform.scale(
        scale: scale,
        child: Opacity(
          opacity: opacity,
          child: widget.child,
        ),
      ),
    );
  }
}
