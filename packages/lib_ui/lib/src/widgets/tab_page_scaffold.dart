import 'package:flutter/material.dart';

import '../tokens.dart';
import 'liquid_glass.dart';

/// Shared skeleton for the "content" bottom-nav tabs (阅读 / 图表 / 词书).
///
/// Before this existed each tab re-decided its own layout, so switching
/// tabs produced visible jumps: three header treatments, mismatched
/// horizontal margins, and three different backgrounds (solid / gradient
/// / tri-colour gradient). This owns all of that in one place so every
/// content tab shares:
///
///   * one restrained warm-light canvas material (the opaque *paper* layer),
///   * a persistent frosted [GlassAppBar] title bar (the floating *glass*
///     chrome layer) that the content scrolls up under, and
///   * a single 24px horizontal inset so pages cannot quietly drift apart.
///
/// 单词 (the immersive learning tab) intentionally does NOT use this — it
/// stays full-bleed.
///
/// Callers pass raw body [slivers]. This scaffold groups them under one
/// standard 24px horizontal and 32px bottom inset (plus a top inset that
/// clears the frosted bar) so lazy lists keep their laziness without
/// page-specific geometry.
class TabPageScaffold extends StatelessWidget {
  /// Centered title shown in the frosted header bar.
  final String title;

  /// Optional trailing action (e.g. a settings [IconButton]) placed at the
  /// end of the glass title bar.
  final Widget? trailing;

  /// Page body. Each entry must be a sliver; outer content padding is owned
  /// by this scaffold so lazy lists keep their laziness without page-specific
  /// geometry.
  final List<Widget> slivers;

  /// Key for the [CustomScrollView] so each tab preserves its scroll
  /// offset across [IndexedStack] switches.
  final Key? scrollKey;

  const TabPageScaffold({
    super.key,
    required this.title,
    required this.slivers,
    this.trailing,
    this.scrollKey,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The parent HomeShell scaffold owns the canvas + floating bottom nav;
      // this inner scaffold stays transparent and only adds the frosted top
      // bar, letting content scroll behind it.
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: title,
        titleStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: AppColors.of(context).ink,
        ),
        actions: trailing == null ? null : [trailing!],
      ),
      body: DecoratedBox(
        decoration: AppMaterials.canvasDecoration(context),
        // A transparent Material keeps the ink/text ancestor available to the
        // scroll content (InkWell rows, ListTiles) without tinting the canvas.
        child: Material(
          type: MaterialType.transparency,
          // With extendBodyBehindAppBar the Scaffold rewrites the body's
          // MediaQuery so `padding.top` already covers the status bar AND the
          // frosted bar height, and `padding.bottom` carries the floating
          // bottom-nav inset from the parent shell. So the first content sits
          // just below the bar and its last item clears the nav, both
          // scrolling behind the glass.
          child: Builder(
            builder: (context) {
              final insets = MediaQuery.paddingOf(context);
              return CustomScrollView(
                key: scrollKey,
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.x6,
                      insets.top + AppSpacing.x4,
                      AppSpacing.x6,
                      insets.bottom + AppSpacing.x8,
                    ),
                    sliver: SliverMainAxisGroup(slivers: slivers),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
