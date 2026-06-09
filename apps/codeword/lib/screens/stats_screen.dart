import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lib_ui/lib_ui.dart';

import '../state/learning_session.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the review state map so this rebuilds on every answer.
    ref.watch(reviewStateProvider);
    final stats = ref.read(reviewStateProvider.notifier).stats();

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x5,
          AppSpacing.x4,
          AppSpacing.x5,
          AppSpacing.x6,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '统计',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              '看你与单词的相处',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.inkMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: AppSpacing.x5),
            AppCard(
              child: Row(
                children: [
                  Expanded(
                    child: _Stat(
                      label: '已学过',
                      value: '${stats.totalLearned}',
                      color: AppColors.primary,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 36,
                    color: AppColors.inkSubtle.withValues(alpha: 0.2),
                  ),
                  Expanded(
                    child: _Stat(
                      label: '看过',
                      value: '${stats.totalSeen}',
                      color: AppColors.info,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 36,
                    color: AppColors.inkSubtle.withValues(alpha: 0.2),
                  ),
                  Expanded(
                    child: _Stat(
                      label: '平均 EF',
                      value: stats.averageEasiness == 0
                          ? '—'
                          : stats.averageEasiness.toStringAsFixed(2),
                      color: AppColors.warning,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.x5),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        '本周热力',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        stats.totalSeen == 0
                            ? '还没数据'
                            : '本周 ${_sum(stats.last7Days)} 次答题',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.inkMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.x4),
                  _Heatmap(activity: stats.last7Days),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.x5),
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.x5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'v0.4.6 · 本期',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.inkMuted,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  const Text(
                    '✅ 真实统计 · 5 词库 500 词\n✅ 本地预生成 OGG 发音\n✅ SM-2 间隔重复 + JSON 持久化\n✅ macOS + Android 双端\n✅ 本地-first 原则(无云/无登录/无同步)',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.ink,
                      height: 1.7,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _sum(List<int> xs) => xs.fold(0, (a, b) => a + b);
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Stat({
    required this.label,
    required this.value,
    required this.color,
  });
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: AppTheme.wordDisplay(
            size: 22,
            color: color,
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

class _Heatmap extends StatelessWidget {
  final List<int> activity; // 7 days, oldest → today
  const _Heatmap({required this.activity});

  int _heatLevel(int n) {
    if (n <= 0) return 0;
    if (n <= 5) return 1;
    if (n <= 15) return 2;
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final mondayBasedToday =
        (now.weekday == DateTime.sunday) ? 6 : now.weekday - 1;
    final dayLabels = List<String>.generate(7, (i) {
      final idx = (i + mondayBasedToday) % 7;
      return const ['一', '二', '三', '四', '五', '六', '日'][idx];
    });
    return Row(
      children: List.generate(7, (i) {
        final n = i < activity.length ? activity[i] : 0;
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
    );
  }
}
