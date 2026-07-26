import 'dart:ui';

import 'package:flutter/material.dart';

import '../tokens.dart';

/// Shared "coloured glass" tint gradient. A little thinner than a near-opaque
/// frost so the (already saturated) blurred backdrop reads through the
/// material, with the tint carried heavier at the far corner so it looks like
/// *coloured* glass rather than milky plastic. The white floor is kept
/// deliberately high in light mode because 10px labels can sit on this
/// surface — legibility beats a stronger effect, and the increase-contrast
/// branches drop translucency entirely.
LinearGradient _glassTint(bool isDark, AppPalette palette, Color tint) {
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: isDark
        ? [
            Colors.white.withValues(alpha: 0.16),
            palette.surface.withValues(alpha: 0.66),
            tint.withValues(alpha: 0.18),
          ]
        : [
            Colors.white.withValues(alpha: 0.70),
            palette.surface.withValues(alpha: 0.48),
            tint.withValues(alpha: 0.15),
          ],
    stops: const [0, 0.55, 1],
  );
}

/// A specular rim highlight: a bright glint concentrated in the top-left
/// corner that fades out quickly, so the glass reads as if catching light
/// from above-left (the classic iOS "liquid glass" specular). Painted as an
/// [IgnorePointer] overlay so it never intercepts taps and only tints the
/// edge, keeping content underneath legible.
///
/// The gradient is compressed into the first ~12% of the diagonal so it
/// reads as a sharp corner catch rather than a wash over the content —
/// on small 44px buttons this keeps the icon from being bleached out (§12).
Widget _specularHighlight(bool isDark) {
  return Positioned.fill(
    child: IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: isDark ? 0.14 : 0.30),
              Colors.transparent,
            ],
            stops: const [0, 0.12],
          ),
        ),
      ),
    ),
  );
}

/// Platform-neutral fallback for iOS-style Liquid Glass chrome.
///
/// Keep this on navigation and floating controls. Content surfaces should
/// remain opaque enough for sustained reading.
///
/// A transparent [Material] sits above the tint so descendant buttons and
/// [InkWell]s paint their ripple on the glass itself — otherwise the
/// ripple lands on a distant ancestor Material *behind* the blur and is
/// invisible.
class AppGlassSurface extends StatelessWidget {
  /// Shared blur radius for all glass chrome (surfaces, nav bar). Kept as
  /// a single constant so the whole chrome layer frosts identically.
  static const double kBlurSigma = 24;

  /// Tighter blur for small glass controls (icon buttons, chips) where a
  /// full 24px frost would swallow the icon. Still reads as glass, just
  /// less diffused — the same material, a different weight (§12).
  static const double kBlurSigmaCompact = 16;

  final Widget child;
  final BorderRadius borderRadius;
  final Color? tint;
  final double blurSigma;

  const AppGlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(AppRadii.xxl)),
    this.tint,
    this.blurSigma = kBlurSigma,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = AppColors.of(context);
    final resolvedTint = tint ?? AppColors.primary;

    // Accessibility: honour the OS "increase contrast" setting. Translucent
    // chrome floating over scrolling content is exactly what the web
    // `prefers-contrast: more` / `prefers-reduced-transparency` rules ask us
    // to defuse — so fall back to a solid surface with a defined, contrasting
    // border and no blur. Legibility wins over the material effect.
    final highContrast = MediaQuery.maybeOf(context)?.highContrast ?? false;
    if (highContrast) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          color: palette.surface,
          border: Border.all(
            color: palette.ink.withValues(alpha: isDark ? 0.55 : 0.45),
            width: 1,
          ),
          boxShadow: AppShadows.glass(isDark: isDark),
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: Material(
            type: MaterialType.transparency,
            child: child,
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: AppShadows.glass(isDark: isDark),
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              // Flutter's BackdropFilter cannot saturate the backdrop directly
              // (ImageFilter has no colour matrix), so letting the real
              // backdrop show through this thin tint is how we get the
              // liquid-glass read.
              gradient: _glassTint(isDark, palette, resolvedTint),
              border: Border.all(
                color: Colors.white.withValues(alpha: isDark ? 0.22 : 0.72),
                width: AppBorders.hairline,
              ),
            ),
            // Stack the specular rim over the child. Non-positioned [child]
            // sizes the stack; the rim fills it without intercepting taps.
            child: Stack(
              children: [
                Material(type: MaterialType.transparency, child: child),
                _specularHighlight(isDark),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Frosted-glass navigation bar, the chrome-layer counterpart to the opaque
/// paper content beneath it. Renders a centered title with an optional
/// [leading] widget and trailing [actions], a blurred coloured-glass fill, a
/// specular top-corner glint and a hairline bottom separator.
///
/// Implements [PreferredSizeWidget] so it can be dropped straight into
/// `Scaffold.appBar`; it consumes the top safe-area inset itself (like the
/// framework [AppBar]) so `Scaffold` reserves `[barHeight] + topInset`.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// Centered title.
  final String title;

  /// Optional leading widget (e.g. a back button). A 56px slot is reserved on
  /// each side so the title stays optically centered.
  final Widget? leading;

  /// Optional trailing actions.
  final List<Widget>? actions;

  /// Overrides the default iOS-style 17px/w600 centered title style. The main
  /// content tabs pass a larger 22px/w700 style here; secondary navigation
  /// bars leave it null.
  final TextStyle? titleStyle;

  /// The toolbar row height, excluding the top safe-area inset.
  static const double barHeight = 52;

  const GlassAppBar({
    super.key,
    required this.title,
    this.leading,
    this.actions,
    this.titleStyle,
  });

  @override
  Size get preferredSize => const Size.fromHeight(barHeight);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = AppColors.of(context);
    final highContrast = MediaQuery.maybeOf(context)?.highContrast ?? false;
    final topInset = MediaQuery.paddingOf(context).top;

    final row = Material(
      type: MaterialType.transparency,
      child: SizedBox(
        height: barHeight,
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 56),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: titleStyle ??
                      TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: palette.ink,
                      ),
                ),
              ),
            ),
            if (leading != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: leading,
                ),
              ),
            if (actions != null && actions!.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child:
                      Row(mainAxisSize: MainAxisSize.min, children: actions!),
                ),
              ),
          ],
        ),
      ),
    );

    if (highContrast) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surface,
          border: Border(
            bottom: BorderSide(
              color: palette.ink.withValues(alpha: isDark ? 0.55 : 0.45),
            ),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.only(top: topInset),
          child: row,
        ),
      );
    }

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: AppGlassSurface.kBlurSigma,
          sigmaY: AppGlassSurface.kBlurSigma,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: _glassTint(isDark, palette, AppColors.primary),
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.black.withValues(alpha: 0.06),
              ),
            ),
          ),
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.only(top: topInset),
                child: row,
              ),
              _specularHighlight(isDark),
            ],
          ),
        ),
      ),
    );
  }
}

/// Frosted floating toolbar for the bottom of a detail page (e.g. the reading
/// article actions). Owns the bottom safe-area inset and an outer margin so it
/// reads as a pill of glass hovering above the content.
class GlassBottomBar extends StatelessWidget {
  final Widget child;
  final EdgeInsets margin;
  final EdgeInsets padding;

  const GlassBottomBar({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.fromLTRB(
      AppSpacing.x5,
      AppSpacing.x2,
      AppSpacing.x5,
      AppSpacing.x2,
    ),
    this.padding = const EdgeInsets.all(AppSpacing.x2),
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: margin,
      child: AppGlassSurface(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Padding(padding: padding, child: child),
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
        blurSigma: AppGlassSurface.kBlurSigmaCompact,
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
