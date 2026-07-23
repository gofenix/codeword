import 'dart:ui';

import 'package:flutter/material.dart';

import '../tokens.dart';

/// Platform-neutral fallback for iOS-style Liquid Glass chrome.
///
/// Keep this on navigation and floating controls. Content surfaces should
/// remain opaque enough for sustained reading.
class AppGlassSurface extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final Color? tint;
  final double blurSigma;

  const AppGlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
    this.tint,
    this.blurSigma = 24,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = AppColors.of(context);
    final resolvedTint = tint ?? AppColors.primary;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: isDark ? const Color(0x52000000) : const Color(0x26362D20),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        Colors.white.withValues(alpha: 0.15),
                        palette.surface.withValues(alpha: 0.72),
                        resolvedTint.withValues(alpha: 0.13),
                      ]
                    : [
                        Colors.white.withValues(alpha: 0.82),
                        palette.surface.withValues(alpha: 0.58),
                        resolvedTint.withValues(alpha: 0.10),
                      ],
                stops: const [0, 0.55, 1],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: isDark ? 0.22 : 0.72),
                width: 0.8,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class AppGlassIconButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;
  final Color? color;
  final double size;

  const AppGlassIconButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    this.color,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 44,
      child: AppGlassSurface(
        borderRadius: BorderRadius.circular(22),
        blurSigma: 18,
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(icon, size: size),
          color: color ?? AppColors.of(context).inkMuted,
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
