import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lib_content/lib_content.dart';
import 'package:lib_core/lib_core.dart';
import 'package:lib_ui/lib_ui.dart';

import 'screens/discovery_screen.dart';
import 'screens/learning_session_screen.dart';
import 'screens/reading_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/stats_screen.dart';
import 'state/learning_session.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ReviewRepository.init();
  try {
    await ReviewRepository.instance.recordOpen(DateTime.now());
  } catch (_) {}
  // Pre-load the qwerty catalog so all consumers (me screen, learning
  // session, stats) can read vocabMetaProvider synchronously. If the
  // manifest asset is missing or corrupt, fall back to an empty list
  // rather than crashing the app.
  List<VocabList> catalog = const [];
  try {
    catalog = await loadQwertyCatalog();
  } catch (e, st) {
    developer.log('Failed to load qwerty catalog: $e\n$st',
        name: 'main', error: e, stackTrace: st);
  }
  runApp(
    ProviderScope(
      overrides: [
        qwertyCatalogProvider.overrideWithValue(catalog),
      ],
      child: const CodewordApp(),
    ),
  );
}

class CodewordApp extends StatelessWidget {
  const CodewordApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CodeWord · 码词',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  void _goToTab(int index) {
    if (index < 0 || index >= _pages.length) return;
    HapticFeedback.selectionClick();
    setState(() => _index = index);
  }

  // 5 tabs: 单词 (today/learning) | 阅读 (AI articles, BYOK) |
  // 发现 (library search + catalog) | 图表 (stats) | 设置.
  // 复习 is intentionally removed — due-for-review words are folded
  // into the learning flow itself.
  static const _pages = <Widget>[
    TodayPage(),        // 单词
    ReadingScreen(),    // 阅读
    DiscoveryScreen(),  // 发现
    StatsScreen(),      // 图表
    SettingsScreen(),   // 设置
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _index,
        children: _pages,
      ),
      bottomNavigationBar: _DeskBottomNav(
        index: _index,
        onTap: (i) {
          HapticFeedback.selectionClick();
          setState(() => _index = i);
        },
      ),
    );
  }
}

/// Bottom navigation. Full window width, tall enough to feel like a
/// real desktop app shelf rather than a phone bar.
class _DeskBottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;

  const _DeskBottomNav({required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: index,
      onDestinationSelected: onTap,
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.primarySoft,
      surfaceTintColor: Colors.transparent,
      elevation: 1,
      height: 72,
      labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.style_outlined, size: 26),
          selectedIcon: Icon(Icons.style, color: AppColors.primary, size: 26),
          label: '单词',
        ),
        NavigationDestination(
          icon: Icon(Icons.menu_book_outlined, size: 26),
          selectedIcon: Icon(Icons.menu_book, color: AppColors.primary, size: 26),
          label: '阅读',
        ),
        NavigationDestination(
          icon: Icon(Icons.explore_outlined, size: 26),
          selectedIcon: Icon(Icons.explore, color: AppColors.primary, size: 26),
          label: '发现',
        ),
        NavigationDestination(
          icon: Icon(Icons.insert_chart_outlined, size: 26),
          selectedIcon: Icon(Icons.insert_chart, color: AppColors.primary, size: 26),
          label: '图表',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined, size: 26),
          selectedIcon: Icon(Icons.settings, color: AppColors.primary, size: 26),
          label: '设置',
        ),
      ],
    );
  }
}

/// Placeholder for tabs that aren't built yet. Kept for future use
/// when we add a 6th tab and want to gate it before content lands.
/// (Currently unused — 5 tabs all have real content.)
// ignore: unused_element
class _ComingSoonPage extends StatelessWidget {
  final String title;
  final IconData icon;
  const _ComingSoonPage({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: AppCard(
            child: SizedBox(
              width: 240,
              height: 180,
              child: Center(
                child: Icon(icon, size: 56, color: AppColors.inkSubtle),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TodayPage extends ConsumerWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(reviewStateProvider.notifier).stats(
          catalog: ref.watch(qwertyCatalogProvider),
        );
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.x8,
              AppSpacing.x6,
              AppSpacing.x8,
              AppSpacing.x10,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Greeting(newToday: stats.newToday),
                const SizedBox(height: AppSpacing.x6),
                _TodayTaskCard(stats: stats),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  final int newToday;
  const _Greeting({required this.newToday});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Hi, 极客 👋',
          style: TextStyle(
            fontSize: 18,
            color: AppColors.inkMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: AppSpacing.x2),
        Text(
          newToday == 0 ? '今天还没开始' : '今天学了 $newToday 个新词',
          style: const TextStyle(
            fontSize: 44,
            color: AppColors.ink,
            fontWeight: FontWeight.w800,
            height: 1.15,
            letterSpacing: -1,
          ),
        ),
      ],
    );
  }
}

/// The single today-task card: one clear action and the two numbers
/// that matter (due + new). Nothing else competes for attention.
class _TodayTaskCard extends StatelessWidget {
  final ReviewStats stats;
  const _TodayTaskCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final allDone = stats.totalDue == 0 && stats.newToday == 0;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.x6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '今日任务',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const Spacer(),
              _StreakPill(streak: stats.streakDays),
            ],
          ),
          const SizedBox(height: AppSpacing.x5),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: '待复习',
                  value: '${stats.totalDue}',
                  color: AppColors.info,
                ),
              ),
              const SizedBox(width: AppSpacing.x4),
              Expanded(
                child: _MiniStat(
                  label: '今日新词',
                  value: '${stats.newToday}',
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x5),
          Text(
            allDone ? '今天已经完成啦，明天见 👋' : '优先复习到期的词，再学新词',
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.inkMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.x5),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: allDone
                  ? null
                  : () {
                      HapticFeedback.lightImpact();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const LearningSessionScreen(
                            vocabId: kDefaultVocabId,
                          ),
                        ),
                      );
                    },
              icon: const Icon(Icons.play_arrow_rounded, size: 24),
              label: const Text('开始学习'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.x4),
                textStyle: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.x2),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () {
                HapticFeedback.selectionClick();
                final shell = context.findAncestorStateOfType<_HomeShellState>();
                shell?._goToTab(2); // 发现
              },
              child: const Text(
                '选择其他词书',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: AppTheme.wordDisplay(
              size: 44,
              color: color,
              weight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: color.withValues(alpha: 0.85),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StreakPill extends StatelessWidget {
  final int streak;
  const _StreakPill({required this.streak});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x3,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: streak > 0
            ? AppColors.warning.withValues(alpha: 0.12)
            : AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            streak > 0
                ? Icons.local_fire_department
                : Icons.local_fire_department_outlined,
            size: 16,
            color: streak > 0 ? AppColors.warning : AppColors.inkSubtle,
          ),
          const SizedBox(width: 4),
          Text(
            streak == 0 ? '开始连续' : '连续 $streak 天',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: streak > 0 ? AppColors.warning : AppColors.inkSubtle,
            ),
          ),
        ],
      ),
    );
  }
}
