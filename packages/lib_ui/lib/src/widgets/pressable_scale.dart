import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens.dart';

/// Wraps a child with a subtle press interaction:
///   - scale to [scaleFactor] (default 0.97) on tap down
///   - opacity to [pressedOpacity] (default 0.85) on tap down
///   - light haptic impact on pointer-down
///
/// The scale/opacity animate over [AppMotion.press] with [AppMotion.easeOut]
/// so a press gives instant, responsive feedback and the release settles
/// smoothly. [AnimatedScale]/[AnimatedOpacity] retarget on every value
/// change, so a mid-flight re-press (press → release → press) stays
/// continuous with no jump — the interruptibility Apple's fluid
/// interfaces call for.
///
/// When the platform requests reduced motion, the scale transform is
/// dropped and only the opacity dip remains — feedback stays, vestibular
/// motion goes.
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
    if (mounted && _down != v) setState(() => _down = v);
  }

  void _onTapDown() {
    // Haptic on pointer-down, not release, so the tactile confirmation
    // coincides with the visual press — the instant the user acts.
    if (widget.haptic && _isMobilePlatform) {
      HapticFeedback.lightImpact();
    }
  }

  void _onTap() {
    widget.onTap?.call();
  }

  /// Haptic feedback only on mobile platforms.
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
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final scale = _down && !reduceMotion ? widget.scaleFactor : 1.0;
    final opacity = _down ? widget.pressedOpacity : 1.0;
    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: hasOnTap
          ? (_) {
              _setDown(true);
              _onTapDown();
            }
          : null,
      onTapUp: hasOnTap ? (_) => _setDown(false) : null,
      // Reset press state when the gesture is cancelled (e.g. the user
      // drags to scroll and the scrollable wins the arena). Without this
      // the widget stays visually pressed until the next rebuild.
      onTapCancel: hasOnTap ? () => _setDown(false) : null,
      onTap: hasOnTap ? _onTap : null,
      child: AnimatedScale(
        scale: scale,
        duration: AppMotion.press,
        curve: AppMotion.easeOut,
        child: AnimatedOpacity(
          opacity: opacity,
          duration: AppMotion.press,
          curve: AppMotion.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}
