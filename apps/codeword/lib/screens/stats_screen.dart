import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lib_ui/lib_ui.dart';

import '../state/learning_session.dart';
import 'stats_widgets.dart';

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

            // 1) Top-line overview (existing, but smaller now).
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
                  _vDiv(),
                  Expanded(
                    child: _Stat(
                      label: '看过',
                      value: '${stats.totalSeen}',
                      color: AppColors.info,
                    ),
                  ),
                  _vDiv(),
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

            const SizedBox(height: AppSpacing.x4),

            // 2) Mastery distribution
            MasteryDistribution(buckets: stats.mastery),

            const SizedBox(height: AppSpacing.x4),

            // 3) Per-vocab progress
            VocabProgressList(rows: stats.perVocab),

            const SizedBox(height: AppSpacing.x4),

            // 4) Today snapshot (6 cells)
            TodayActivityGrid(
              reviews: stats.reviewsToday,
              newWords: stats.newToday,
              favorites: stats.favorites,
              removed: stats.removed,
              minutes: stats.studyMinutesToday,
              opens: stats.openCountToday,
            ),

            const SizedBox(height: AppSpacing.x4),

            // 5) Streak schedule
            StreakSchedule(activity: stats.last90DaysActivity),

            const SizedBox(height: AppSpacing.x4),

            // 6) Daily trends
            DailyTrendsChart(daily: stats.last30Days),

            const SizedBox(height: AppSpacing.x4),

            // 7) Daily study time
            DailyStudyTimeChart(minutes: stats.last30DaysMinutes),

            const SizedBox(height: AppSpacing.x4),

            // 8) Cumulative / changelog
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.x5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        '累计',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.inkMuted,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '共 ${stats.totalStudyMinutes} 分钟',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.inkMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  const Text(
                    '✅ 真实统计 · 5 词库 500 词\n✅ 本地预生成 OGG 发音\n✅ 掌握分布 / 词库进度 / Daily Trends\n✅ 学习分钟 + 打开次数 (v0.4.7)\n✅ macOS + Android 双端\n✅ 本地-first 原则 (无云/无登录/无同步)',
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

  Widget _vDiv() => Container(
        width: 1,
        height: 36,
        color: AppColors.inkSubtle.withValues(alpha: 0.2),
      );
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
