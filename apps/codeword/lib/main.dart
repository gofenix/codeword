import 'package:flutter/material.dart';
import 'package:lib_ui/lib_ui.dart';

void main() {
  runApp(const CodewordApp());
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

/// 5-tab shell scaffold — Today / Library / Review / Stats / Me.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _pages = <Widget>[
    TodayPage(),
    Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Text('词库 · W2', style: TextStyle(color: AppColors.inkMuted)),
      ),
    ),
    Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Text('复习 · W2', style: TextStyle(color: AppColors.inkMuted)),
      ),
    ),
    Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Text('统计 · W2', style: TextStyle(color: AppColors.inkMuted)),
      ),
    ),
    Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Text('我的 · W2', style: TextStyle(color: AppColors.inkMuted)),
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primarySoft,
        surfaceTintColor: Colors.transparent,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.wb_sunny_outlined),
            selectedIcon: Icon(Icons.wb_sunny, color: AppColors.primary),
            label: '今日',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book, color: AppColors.primary),
            label: '词库',
          ),
          NavigationDestination(
            icon: Icon(Icons.refresh_outlined),
            selectedIcon: Icon(Icons.refresh, color: AppColors.primary),
            label: '复习',
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

/// 今日 (Today) page — v5 design.
///
/// Layout (top to bottom):
///   1. Greeting + streak chip
///   2. "今日新词 12 · 待复习 8" summary
///   3. Hero word card with quote mark, serif word, phonetic, translation
///   4. "开始学习" pill button
///   5. Heatmap-style 7-day streak preview
class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context) {
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
          children: const [
            _Greeting(),
            SizedBox(height: AppSpacing.x5),
            _TodaySummary(),
            SizedBox(height: AppSpacing.x6),
            _HeroWordCard(
              word: 'overfitting',
              phonetic: '/ˌəʊvəˈfɪtɪŋ/',
              pos: 'n.',
              translation: '过拟合;模型过度贴合训练数据,泛化能力下降',
              domain: 'AI',
              level: 'C1',
            ),
            SizedBox(height: AppSpacing.x5),
            _StartLearningButton(),
            SizedBox(height: AppSpacing.x6),
            _StreakHeatmap(),
            SizedBox(height: AppSpacing.x4),
          ],
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting();

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
                '今天学 12 个新词',
                style: TextStyle(
                  fontSize: 22,
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        const _StreakChip(days: 7),
      ],
    );
  }
}

class _StreakChip extends StatelessWidget {
  final int days;
  const _StreakChip({required this.days});

  @override
  Widget build(BuildContext context) {
    return Container(
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
          const Icon(Icons.local_fire_department, size: 16, color: AppColors.warning),
          const SizedBox(width: 4),
          Text(
            '连续 $days 天',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.warning,
            ),
          ),
        ],
      ),
    );
  }
}

class _TodaySummary extends StatelessWidget {
  const _TodaySummary();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: _SummaryCell(
              label: '新词',
              value: '12',
              icon: Icons.auto_awesome,
              color: AppColors.primary,
            ),
          ),
          Container(
            width: 1,
            height: 36,
            color: AppColors.inkSubtle.withValues(alpha: 0.2),
          ),
          Expanded(
            child: _SummaryCell(
              label: '待复习',
              value: '8',
              icon: Icons.refresh,
              color: AppColors.info,
            ),
          ),
          Container(
            width: 1,
            height: 36,
            color: AppColors.inkSubtle.withValues(alpha: 0.2),
          ),
          Expanded(
            child: _SummaryCell(
              label: '已掌握',
              value: '247',
              icon: Icons.check_circle_outline,
              color: AppColors.success,
            ),
          ),
        ],
      ),
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
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.x5,
        AppSpacing.x5,
        AppSpacing.x5,
        AppSpacing.x5,
      ),
      child: Stack(
        children: [
          // Decorative quote mark, top-right
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('学习流 W2 上线,先打基础 ✨'),
              duration: Duration(seconds: 2),
            ),
          );
        },
        icon: const Icon(Icons.play_arrow_rounded, size: 22),
        label: const Text('开始今日学习  ·  12 词'),
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

/// GitHub-style 7-day heatmap preview row.
class _StreakHeatmap extends StatelessWidget {
  const _StreakHeatmap();

  static const _days = ['一', '二', '三', '四', '五', '六', '日'];
  // Mock activity per day: 0..3
  static const _activity = [3, 2, 1, 3, 3, 2, 0];

  @override
  Widget build(BuildContext context) {
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
                '已学 14 / 20 词',
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
              final level = _activity[i];
              final color = _heatColor(level);
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
                        _days[i],
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

  Color _heatColor(int level) {
    switch (level) {
      case 0:
        return AppColors.surfaceMuted;
      case 1:
        return AppColors.primary.withValues(alpha: 0.3);
      case 2:
        return AppColors.primary.withValues(alpha: 0.6);
      case 3:
        return AppColors.primary;
      default:
        return AppColors.surfaceMuted;
    }
  }
}
