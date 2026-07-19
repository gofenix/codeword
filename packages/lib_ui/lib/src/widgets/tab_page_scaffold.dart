import 'package:flutter/material.dart';

import '../tokens.dart';

/// Shared skeleton for the "content" bottom-nav tabs (阅读 / 图表 / 词书).
///
/// Before this existed each tab re-decided its own layout, so switching
/// tabs produced visible jumps: three header treatments, mismatched
/// horizontal margins, and three different backgrounds (solid / gradient
/// / tri-colour gradient). This owns all of that in one place so every
/// content tab shares:
///
///   * a solid [AppColors.background] fill — no gradients,
///   * a single `SafeArea(bottom: false)` around the whole scroll view
///     (the bottom inset stays owned by the frosted bottom nav), and
///   * a centered 22px title bar with an optional trailing action.
///
/// 单词 (the immersive learning tab) intentionally does NOT use this — it
/// stays full-bleed.
///
/// Callers pass raw body [slivers]. This scaffold groups them under one
/// standard 24px horizontal, 16px top, and 32px bottom inset so pages cannot
/// quietly drift apart.
class TabPageScaffold extends StatelessWidget {
  /// Centered title shown in the header bar.
  final String title;

  /// Optional trailing action (e.g. a settings [IconButton]). Reserved a
  /// 44px slot so the title stays centered whether or not it is present.
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
    // Material keeps the ink/text/canvas ancestor available to the scroll
    // content (StatsScreen relied on this when it wrapped itself in a
    // transparent Material). Transparent so the ColoredBox fill shows.
    return Material(
      type: MaterialType.transparency,
      child: ColoredBox(
        color: AppColors.of(context).background,
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
            key: scrollKey,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.x6,
                  AppSpacing.x3,
                  AppSpacing.x6,
                  0,
                ),
                sliver: SliverToBoxAdapter(
                  child: _TabPageHeader(title: title, trailing: trailing),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.x6,
                  AppSpacing.x4,
                  AppSpacing.x6,
                  AppSpacing.x8,
                ),
                sliver: SliverMainAxisGroup(slivers: slivers),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The single title-bar implementation for content tabs.
///
/// A balanced [Row] — 44px leading spacer · centered title · 44px trailing
/// slot — so the title is truly centered regardless of whether a trailing
/// action is supplied.
class _TabPageHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const _TabPageHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          const SizedBox(width: 44),
          Expanded(
            child: Center(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.of(context).ink,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: trailing == null
                ? null
                : Align(
                    alignment: Alignment.centerRight,
                    child: trailing,
                  ),
          ),
        ],
      ),
    );
  }
}
