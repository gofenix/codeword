import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lib_content/lib_content.dart';
import 'package:lib_core/lib_core.dart';
import 'package:lib_ui/lib_ui.dart';

import 'screens/learning_session_screen.dart';
import 'screens/me_screen.dart';
import 'screens/pulse_screen.dart';
import 'screens/reading_screen.dart';
import 'screens/stats_screen.dart';
import 'state/learning_session.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ReviewRepository.init();
  try {
    await ReviewRepository.instance.recordOpen(DateTime.now());
  } catch (_) {}
  runApp(const ProviderScope(child: CodewordApp()));
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

  // 5 tabs: 单词 (today/learning) | 阅读 (AI articles, BYOK) |
  // Pulse (daily digest) | 统计 | 我的. The 词库 lives inside 我的
  // (Section_VocabSection), and 复习 is intentionally removed — due-for-
  // review words are folded into the learning flow itself.
  static const _pages = <Widget>[
    TodayPage(),       // 单词
    ReadingScreen(),   // 阅读 — AI 生成短文 (BYOK)
    PulseScreen(),     // Pulse — daily digest
    StatsScreen(),     // 统计
    MeScreen(),        // 我的 (词库 在这里)
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          HapticFeedback.selectionClick();
          setState(() => _index = i);
        },
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primarySoft,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.style_outlined),
            selectedIcon: Icon(Icons.style, color: AppColors.primary),
            label: '单词',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book, color: AppColors.primary),
            label: '阅读',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_outline),
            selectedIcon: Icon(Icons.favorite, color: AppColors.primary),
            label: 'Pulse',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart, color: AppColors.primary),
            label: '统计',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: AppColors.primary),
            label: '我的',
          ),
        ],
      ),
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
    final stats = ref.watch(reviewStateProvider.notifier).stats();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x5,
          AppSpacing.x4,
          AppSpacing.x5,
          AppSpacing.x8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Greeting(newToday: stats.newToday, streak: stats.streakDays),
            const SizedBox(height: AppSpacing.x5),
            _TodaySummary(stats: stats),
            const SizedBox(height: AppSpacing.x6),
            const _HeroWordOfTheDay(),
            const SizedBox(height: AppSpacing.x5),
            const _StartLearningButton(),
            const SizedBox(height: AppSpacing.x6),
            _StreakHeatmap(
              last7: stats.last7Days,
              reviewsToday: stats.reviewsToday,
            ),
            const SizedBox(height: AppSpacing.x4),
          ],
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  final int newToday;
  final int streak;
  const _Greeting({required this.newToday, required this.streak});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Hi, 极客 👋',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.inkMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                newToday == 0
                    ? '今天还没开始'
                    : '今天学了 $newToday 个新词',
                style: const TextStyle(
                  fontSize: 28,
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
        Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.x3,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                streak > 0 ? Icons.local_fire_department : Icons.local_fire_department_outlined,
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
        ),
      ],
    );
  }
}

class _TodaySummary extends StatelessWidget {
  final ReviewStats stats;
  const _TodaySummary({required this.stats});
  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: _SummaryCell(
              label: '新词',
              value: '${stats.newToday}',
              icon: Icons.auto_awesome,
              color: AppColors.primary,
            ),
          ),
          const _Divider(),
          Expanded(
            child: _SummaryCell(
              label: '待复习',
              value: '${stats.totalDue}',
              icon: Icons.refresh,
              color: AppColors.info,
            ),
          ),
          const _Divider(),
          Expanded(
            child: _SummaryCell(
              label: '已掌握',
              value: '${stats.totalLearned}',
              icon: Icons.check_circle_outline,
              color: AppColors.success,
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      color: AppColors.inkSubtle.withValues(alpha: 0.2),
    );
  }
}

class _SummaryCell extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _SummaryCell({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTheme.wordDisplay(
            size: 22,
            color: AppColors.ink,
            weight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.inkMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _HeroWordOfTheDay extends StatefulWidget {
  const _HeroWordOfTheDay();

  @override
  State<_HeroWordOfTheDay> createState() => _HeroWordOfTheDayState();
}

class _HeroWordOfTheDayState extends State<_HeroWordOfTheDay> {
  late Future<_HeroEntry?> _future;

  @override
  void initState() {
    super.initState();
    _future = _pickHero();
  }

  /// Pick a stable-per-day entry: hash the date so the user sees the
  /// same "word of the day" all day, but it changes every day.
  Future<_HeroEntry?> _pickHero() async {
    try {
      final container = await ContentLoader.loadList('ai_core');
      if (container.isEmpty) return null;
      final day = DateTime.now();
      final epoch = day.year * 10000 + day.month * 100 + day.day;
      final idx = epoch % container.length;
      final w = container[idx];
      return _HeroEntry(
        word: w.word,
        phonetic: w.phonetic,
        pos: w.pos,
        translation: w.translation,
        domain: w.domain.toUpperCase(),
        level: w.level,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_HeroEntry?>(
      future: _future,
      builder: (context, snap) {
        final h = snap.data;
        if (h == null) {
          // No bundled vocab — render a quiet placeholder. No explanation
          // text; just a card with the same shape so layout doesn't shift.
          return const AppCard(
            child: SizedBox(
              height: 96,
              child: Center(
                child: Icon(Icons.menu_book_outlined,
                    color: AppColors.inkSubtle),
              ),
            ),
          );
        }
        return _HeroWordCard(
          word: h.word,
          phonetic: h.phonetic,
          pos: h.pos,
          translation: h.translation,
          domain: h.domain,
          level: h.level,
        );
      },
    );
  }
}

class _HeroEntry {
  final String word;
  final String phonetic;
  final String pos;
  final String translation;
  final String domain;
  final String level;
  const _HeroEntry({
    required this.word,
    required this.phonetic,
    required this.pos,
    required this.translation,
    required this.domain,
    required this.level,
  });
}

class _HeroWordCard extends StatelessWidget {
  final String word;
  final String phonetic;
  final String pos;
  final String translation;
  final String domain;
  final String level;
  const _HeroWordCard({
    required this.word,
    required this.phonetic,
    required this.pos,
    required this.translation,
    required this.domain,
    required this.level,
  });
  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Stack(
        children: [
          const Positioned(
            top: -16,
            right: 0,
            child: QuoteMark(size: 72, color: AppColors.primary),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  PillTag.domain(
                    domain,
                    color: AppColors.domainAi,
                    icon: Icons.bolt,
                  ),
                  const SizedBox(width: 6),
                  PillTag.level(level),
                ],
              ),
              const SizedBox(height: AppSpacing.x4),
              Text(word, style: AppTheme.wordDisplay(size: 36)),
              const SizedBox(height: 4),
              Text('$phonetic  $pos', style: AppTheme.phonetic()),
              const SizedBox(height: AppSpacing.x4),
              Text(
                translation,
                style: const TextStyle(
                  fontSize: 16,
                  color: AppColors.ink,
                  fontWeight: FontWeight.w500,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StartLearningButton extends StatelessWidget {
  const _StartLearningButton();
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () {
          HapticFeedback.lightImpact();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const LearningSessionScreen(vocabId: 'ai_core'),
            ),
          );
        },
        icon: const Icon(Icons.play_arrow_rounded, size: 22),
        label: const Text('开始学 ·  AI 核心'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.x4),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _StreakHeatmap extends StatelessWidget {
  final List<int> last7; // 7 days, oldest → today
  final int reviewsToday;
  const _StreakHeatmap({required this.last7, required this.reviewsToday});

  /// Map a raw review count to a heat level (0..3).
  /// 0: none, 1: 1-5, 2: 6-15, 3: 16+.
  int _heatLevel(int n) {
    if (n <= 0) return 0;
    if (n <= 5) return 1;
    if (n <= 15) return 2;
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    // Translate each of the 7 days to its correct weekday label.
    final dayLabels = List<String>.generate(7, (i) {
      final day = now.subtract(Duration(days: 6 - i));
      final weekday = day.weekday == DateTime.sunday ? 6 : day.weekday - 1;
      return const ['一', '二', '三', '四', '五', '六', '日'][weekday];
    });

    final totalThisWeek = last7.fold<int>(0, (a, b) => a + b);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '本周学习',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const Spacer(),
              Text(
                totalThisWeek == 0
                    ? '本周还没学'
                    : '本周 $totalThisWeek 次答题 · 今日 $reviewsToday',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.inkMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x4),
          Row(
            children: List.generate(7, (i) {
              final n = i < last7.length ? last7[i] : 0;
              final level = _heatLevel(n);
              final color = switch (level) {
                0 => AppColors.surfaceMuted,
                1 => AppColors.primary.withValues(alpha: 0.3),
                2 => AppColors.primary.withValues(alpha: 0.6),
                _ => AppColors.primary,
              };
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    children: [
                      Container(
                        height: 36,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dayLabels[i],
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
