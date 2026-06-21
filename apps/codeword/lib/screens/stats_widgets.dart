import 'package:flutter/material.dart';
import 'package:lib_ui/lib_ui.dart';

import '../state/learning_session.dart';

/// Mastery distribution: horizontal stacked bar with legend.
///
/// Reads `stats.mastery` and renders 5 colored segments proportional to
/// the count in each bucket. Total count includes the unseen bucket
/// (every bundled word the user has never touched).
class MasteryDistribution extends StatelessWidget {
  final List<MasteryBucket> buckets;
  const MasteryDistribution({super.key, required this.buckets});

  @override
  Widget build(BuildContext context) {
    final total = buckets.fold<int>(0, (a, b) => a + b.count);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '掌握分布',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(
            total == 0
                ? '— · —'
                : '已学 ${total - (buckets.last.count)} · 总量 $total',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.inkMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.x4),
          // Stacked bar
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: SizedBox(
              height: 14,
              child: total == 0
                  ? Container(color: AppColors.surfaceMuted)
                  : Row(
                      children: [
                        for (final b in buckets)
                          if (b.count > 0)
                            Expanded(
                              flex: b.count,
                              child: Container(color: _colorFor(b.level)),
                            ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.x4),
          // Legend
          Wrap(
            spacing: AppSpacing.x3,
            runSpacing: 6,
            children: [
              for (final b in buckets)
                _LegendChip(
                  color: _colorFor(b.level),
                  label: b.level.label,
                  count: b.count,
                ),
            ],
          ),
        ],
      ),
    );
  }

  static Color _colorFor(MasteryLevel l) => switch (l) {
        MasteryLevel.familiar => AppColors.masteryFamiliar,
        MasteryLevel.recognized => AppColors.masteryRecognized,
        MasteryLevel.vague => AppColors.masteryVague,
        MasteryLevel.unfamiliar => AppColors.masteryUnfamiliar,
        MasteryLevel.unseen => AppColors.masteryUnseen,
      };
}

class _LegendChip extends StatelessWidget {
  final Color color;
  final String label;
  final int count;
  const _LegendChip({required this.color, required this.label, required this.count});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$label $count',
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.ink,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Per-vocabulary progress: name + emoji + 进度条 + N 已学 / N 总量.
class VocabProgressList extends StatelessWidget {
  final List<VocabProgress> rows;
  const VocabProgressList({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '词库进度',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: AppSpacing.x4),
          for (final r in rows) ...[
            _VocabRow(row: r),
            if (r != rows.last) const SizedBox(height: AppSpacing.x3),
          ],
        ],
      ),
    );
  }
}

class _VocabRow extends StatelessWidget {
  final VocabProgress row;
  const _VocabRow({required this.row});

  Color _color() {
    // Deterministic color from the vocab id.
    final h = row.vocabId.hashCode.abs();
    return AppColors.qwertyPalette[h % AppColors.qwertyPalette.length];
  }

  @override
  Widget build(BuildContext context) {
    final color = _color();
    final coverage = row.coverage;
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
          child: Text(row.emoji, style: const TextStyle(fontSize: 16)),
        ),
        const SizedBox(width: AppSpacing.x3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    row.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${row.learned} / ${row.totalWords}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.inkMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.pill),
                child: LinearProgressIndicator(
                  value: coverage,
                  minHeight: 6,
                  backgroundColor: AppColors.surfaceMuted,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Today's snapshot: 6-cell grid (review / new / favs / removed / minutes / opens).
class TodayActivityGrid extends StatelessWidget {
  final int reviews;
  final int newWords;
  final int favorites;
  final int removed;
  final int minutes;
  final int opens;
  const TodayActivityGrid({
    super.key,
    required this.reviews,
    required this.newWords,
    required this.favorites,
    required this.removed,
    required this.minutes,
    required this.opens,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '今天',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: AppSpacing.x4),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            mainAxisSpacing: AppSpacing.x3,
            crossAxisSpacing: AppSpacing.x3,
            childAspectRatio: 1.4,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _Cell(label: '复习', value: '$reviews', color: AppColors.primary, icon: Icons.refresh),
              _Cell(label: '新学', value: '$newWords', color: AppColors.info, icon: Icons.auto_awesome),
              _Cell(label: '收藏', value: '$favorites', color: AppColors.warning, icon: Icons.star_rounded),
              _Cell(label: '移除', value: '$removed', color: AppColors.danger, icon: Icons.remove_circle_outline),
              _Cell(label: '分钟', value: '$minutes', color: AppColors.qwertyPalette[1], icon: Icons.schedule),
              _Cell(label: '打开', value: '$opens', color: AppColors.qwertyPalette[5], icon: Icons.bolt),
            ],
          ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const _Cell({required this.label, required this.value, required this.color, required this.icon});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x3,
        vertical: AppSpacing.x3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.inkMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Icon(icon, size: 14, color: color),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTheme.wordDisplay(size: 20, color: color),
          ),
        ],
      ),
    );
  }
}

/// Streak schedule: 12 weeks × 7 days grid showing which days had activity.
/// Reads `stats.last90DaysActivity` (oldest first, length 90).
class StreakSchedule extends StatelessWidget {
  final List<bool> activity; // length 90, oldest → today
  const StreakSchedule({super.key, required this.activity});

  @override
  Widget build(BuildContext context) {
    // Reorganize 90 days into 13 columns (weeks) × 7 rows (days).
    // 90 / 7 = 12.86 — round up to 13.
    const cols = 13;
    final grid = List.generate(7, (_) => List<bool?>.filled(cols, null));
    for (var i = 0; i < activity.length; i++) {
      final col = i ~/ 7;
      final row = i % 7;
      if (col < cols) grid[row][col] = activity[i];
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '连续记录',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: AppSpacing.x2),
          const Text(
            '过去 90 天 · 每天一个方格,绿色=有学习',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.inkMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.x4),
          // 7 rows × 13 cols
          Column(
            children: List.generate(7, (row) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: List.generate(cols, (col) {
                    final v = grid[row][col];
                    return Expanded(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Container(
                          margin: const EdgeInsets.all(1.5),
                          decoration: BoxDecoration(
                            color: v == null
                                ? AppColors.surfaceMuted.withValues(alpha: 0.2)
                                : (v
                                    ? AppColors.primary
                                    : AppColors.surfaceMuted),
                            borderRadius: BorderRadius.circular(AppRadii.xs),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

/// Bar chart of daily activity counts (last 14 days).
class DailyTrendsChart extends StatelessWidget {
  final List<int> daily; // length 30
  const DailyTrendsChart({super.key, required this.daily});

  @override
  Widget build(BuildContext context) {
    // Show last 14 days for the chart.
    final xs = daily.length <= 14
        ? daily
        : daily.sublist(daily.length - 14);
    final maxV = xs.fold<int>(0, (a, b) => a > b ? a : b);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '每日趋势',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const Spacer(),
              Text(
                '近 14 天 · 峰值 $maxV',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.inkMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x4),
          SizedBox(
            height: 96,
            child: _Bars(
              values: xs,
              color: AppColors.primary,
              emphasizeLast: true,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bar chart of study minutes per day (last 14 days).
class DailyStudyTimeChart extends StatelessWidget {
  final List<int> minutes; // length 30
  const DailyStudyTimeChart({super.key, required this.minutes});

  @override
  Widget build(BuildContext context) {
    final xs = minutes.length <= 14
        ? minutes
        : minutes.sublist(minutes.length - 14);
    final total = xs.fold<int>(0, (a, b) => a + b);
    final maxV = xs.fold<int>(0, (a, b) => a > b ? a : b);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '每日学习时长',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const Spacer(),
              Text(
                '近 14 天 · 合计 ${total}m',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.inkMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x4),
          SizedBox(
            height: 96,
            child: _Bars(
              values: xs,
              color: AppColors.qwertyPalette[1],
              emphasizeLast: true,
            ),
          ),
          if (maxV == 0) ...[
            const SizedBox(height: 4),
            const Text(
              '—',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.inkMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Bars extends StatelessWidget {
  final List<int> values;
  final Color color;
  final bool emphasizeLast;
  const _Bars({
    required this.values,
    required this.color,
    required this.emphasizeLast,
  });

  @override
  Widget build(BuildContext context) {
    final maxV = values.fold<int>(1, (a, b) => a > b ? a : b);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(values.length, (i) {
        final v = values[i];
        final ratio = v / maxV;
        final isLast = emphasizeLast && i == values.length - 1;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  height: (ratio * 80).clamp(2, 80).toDouble(),
                  decoration: BoxDecoration(
                    color: isLast
                        ? color
                        : (v == 0
                            ? AppColors.surfaceMuted
                            : color.withValues(alpha: 0.55)),
                    borderRadius: BorderRadius.circular(3),
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
