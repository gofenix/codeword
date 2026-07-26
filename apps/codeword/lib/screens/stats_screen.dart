import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lib_ui/lib_ui.dart';

import '../state/learning_session.dart';

enum _TrendMetric { answers, minutes }

class StatsScreen extends ConsumerStatefulWidget {
  final bool isActive;
  final VoidCallback? onGoWords;
  final VoidCallback? onGoLibrary;

  const StatsScreen({
    super.key,
    this.isActive = true,
    this.onGoWords,
    this.onGoLibrary,
  });

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  _TrendMetric _metric = _TrendMetric.answers;
  int _selectedDay = 13;

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) return const SizedBox.expand();
    ref.watch(reviewStateProvider);
    final catalog = ref.watch(qwertyCatalogProvider);
    final selectedVocab = ref.watch(selectedVocabProvider);
    final stats = ref
        .read(reviewStateProvider.notifier)
        .stats(catalog: catalog);
    final progress = vocabProgressFor(stats, selectedVocab);
    final matchingVocab = catalog.where((item) => item.id == selectedVocab);
    final vocab = matchingVocab.isEmpty ? null : matchingVocab.first;

    final palette = AppColors.of(context);
    final distribution = [
      _MasteryPart('稳固', progress?.mastered ?? 0, AppColors.masteryFamiliar),
      _MasteryPart(
        '学习中',
        max(0, (progress?.learned ?? 0) - (progress?.mastered ?? 0)),
        AppColors.masteryRecognized,
      ),
      _MasteryPart(
        '待巩固',
        max(0, (progress?.seen ?? 0) - (progress?.learned ?? 0)),
        AppColors.masteryVague,
      ),
      _MasteryPart('未学习', progress?.unseenWords ?? 0, palette.surfaceMuted),
    ];

    final words = stats.last30Days
        .skip(max(0, stats.last30Days.length - 14))
        .toList();
    final minutes = stats.last30DaysMinutes
        .skip(max(0, stats.last30DaysMinutes.length - 14))
        .toList();

    return TabPageScaffold(
      title: '图表',
      scrollKey: const PageStorageKey('stats-scroll'),
      slivers: [
        SliverList.list(
          children: [
            Text(
              '学习统计',
              key: const ValueKey('stats-first-content'),
              style: AppTheme.sectionLabel(context: context),
            ),
            const SizedBox(height: AppSpacing.x4),
            _TodayAction(
              hasLearningData: stats.totalSeen > 0,
              due: stats.totalDue,
              newToday: stats.newToday,
              minutes: stats.studyMinutesToday,
              onContinue: widget.onGoWords,
            ),
            const SizedBox(height: AppSpacing.x4),
            _MasteryCard(
              vocabName: vocab?.name ?? '暂无词书',
              mastered: progress?.mastered ?? 0,
              total: progress?.availableWords ?? vocab?.wordCount ?? 0,
              distribution: distribution,
              onOpenLibrary: widget.onGoLibrary,
            ),
            const SizedBox(height: AppSpacing.x4),
            _TrendCard(
              metric: _metric,
              selectedDay: _selectedDay,
              words: words,
              minutes: minutes,
              onMetricChanged: (value) => setState(() => _metric = value),
              onDaySelected: (value) => setState(() => _selectedDay = value),
            ),
            const SizedBox(height: AppSpacing.x4),
            _HeatmapCard(
              activity: stats.last90DaysActivity,
              streakDays: stats.streakDays,
            ),
          ],
        ),
      ],
    );
  }
}

class _TodayAction extends StatelessWidget {
  final bool hasLearningData;
  final int due;
  final int newToday;
  final int minutes;
  final VoidCallback? onContinue;

  const _TodayAction({
    required this.hasLearningData,
    required this.due,
    required this.newToday,
    required this.minutes,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final estimate = (due / 3).ceil().clamp(1, 20);
    final title = !hasLearningData
        ? '从第一个词开始'
        : due > 0
        ? '还有 $due 个词该复习了'
        : '记忆状态很好';
    final detail = !hasLearningData
        ? '开始学习后，这里会记录你的掌握变化'
        : due > 0
        ? '今日新学 $newToday · 已学习 $minutes 分钟 · 约 $estimate 分钟'
        : '今日新学 $newToday · 已学习 $minutes 分钟';
    return AppCard(
      onTap: onContinue,
      padding: const EdgeInsets.all(AppSpacing.x4),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primaryContainerOf(context),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Icon(
              Icons.arrow_forward_rounded,
              color: AppColors.onPrimaryContainerOf(context),
            ),
          ),
          const SizedBox(width: AppSpacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTheme.rowTitle(context: context)),
                const SizedBox(height: AppSpacing.x1),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.mutedCaption(size: 12, context: context),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.x2),
          const Icon(Icons.chevron_right_rounded, color: AppColors.primary),
        ],
      ),
    );
  }
}

class _MasteryPart {
  final String label;
  final int count;
  final Color color;

  const _MasteryPart(this.label, this.count, this.color);
}

class _MasteryCard extends StatelessWidget {
  final String vocabName;
  final int mastered;
  final int total;
  final List<_MasteryPart> distribution;
  final VoidCallback? onOpenLibrary;

  const _MasteryCard({
    required this.vocabName,
    required this.mastered,
    required this.total,
    required this.distribution,
    required this.onOpenLibrary,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : mastered / total;
    final largeText = MediaQuery.textScalerOf(context).scale(16) >= 25.6;
    final distributionTotal = distribution.fold<int>(
      0,
      (sum, item) => sum + item.count,
    );
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onOpenLibrary == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onOpenLibrary!();
                  },
            borderRadius: BorderRadius.circular(AppRadii.md),
            child: largeText
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _MasteryTitle(vocabName: vocabName),
                      const SizedBox(height: AppSpacing.x2),
                      _MasteryRatio(ratio: ratio),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: _MasteryTitle(vocabName: vocabName)),
                      Flexible(child: _MasteryRatio(ratio: ratio)),
                    ],
                  ),
          ),
          const SizedBox(height: AppSpacing.x4),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  for (final item in distribution)
                    if (item.count > 0)
                      Expanded(
                        flex: item.count,
                        child: ColoredBox(color: item.color),
                      )
                    else if (distributionTotal == 0)
                      Expanded(
                        child: ColoredBox(
                          color: AppColors.of(context).surfaceMuted,
                        ),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.x3),
          Wrap(
            spacing: AppSpacing.x3,
            runSpacing: AppSpacing.x2,
            children: [
              for (final item in distribution)
                _Legend(
                  label: item.label,
                  count: item.count,
                  color: item.color,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MasteryTitle extends StatelessWidget {
  final String vocabName;

  const _MasteryTitle({required this.vocabName});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('当前词书掌握', style: AppTheme.cardTitle(context: context)),
        const SizedBox(height: AppSpacing.x1),
        Text(
          vocabName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.mutedCaption(size: 12, context: context),
        ),
      ],
    );
  }
}

class _MasteryRatio extends StatelessWidget {
  final double ratio;

  const _MasteryRatio({required this.ratio});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '${(ratio * 100).toStringAsFixed(1)}%',
              maxLines: 1,
              style: AppTheme.editorial(
                size: 34,
                color: AppColors.masteryFamiliar,
                weight: FontWeight.w700,
                context: context,
              ),
            ),
          ),
        ),
        Icon(
          Icons.chevron_right_rounded,
          color: AppColors.of(context).inkSubtle,
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _Legend({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.x1),
        Text(
          '$label $count',
          style: AppTheme.mutedCaption(size: 11, context: context),
        ),
      ],
    );
  }
}

class _TrendCard extends StatelessWidget {
  final _TrendMetric metric;
  final int selectedDay;
  final List<int> words;
  final List<int> minutes;
  final ValueChanged<_TrendMetric> onMetricChanged;
  final ValueChanged<int> onDaySelected;

  const _TrendCard({
    required this.metric,
    required this.selectedDay,
    required this.words,
    required this.minutes,
    required this.onMetricChanged,
    required this.onDaySelected,
  });

  @override
  Widget build(BuildContext context) {
    final values = metric == _TrendMetric.answers ? words : minutes;
    final largeText = MediaQuery.textScalerOf(context).scale(16) >= 25.6;
    final maxValue = values.fold<int>(1, max);
    final safeSelected = selectedDay
        .clamp(0, max(0, values.length - 1))
        .toInt();
    final selectedValue = values.isEmpty ? 0 : values[safeSelected];
    final selectedDate = DateTime.now().subtract(
      Duration(days: max(0, values.length - 1 - safeSelected)),
    );
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (largeText) ...[
            Text('近 14 天', style: AppTheme.cardTitle(context: context)),
            const SizedBox(height: AppSpacing.x2),
            _MetricSwitch(
              metric: metric,
              onChanged: onMetricChanged,
              wide: true,
            ),
          ] else
            Row(
              children: [
                Expanded(
                  child: Text(
                    '近 14 天',
                    style: AppTheme.cardTitle(context: context),
                  ),
                ),
                _MetricSwitch(metric: metric, onChanged: onMetricChanged),
              ],
            ),
          const SizedBox(height: AppSpacing.x1),
          _TrendDayNavigator(
            label:
                '${selectedDate.month}月${selectedDate.day}日 · $selectedValue${metric == _TrendMetric.answers ? " 次" : " 分钟"}',
            canGoPrevious: safeSelected > 0,
            canGoNext: safeSelected < values.length - 1,
            onPrevious: () => onDaySelected(safeSelected - 1),
            onNext: () => onDaySelected(safeSelected + 1),
          ),
          const SizedBox(height: AppSpacing.x2),
          SizedBox(
            height: 128,
            child: Semantics(
              label:
                  '近 14 天${metric == _TrendMetric.answers ? "答题次数" : "学习时长"}趋势',
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // 1:1 direct manipulation: the selected day follows the
                  // finger continuously (onHorizontalDragUpdate), not just on
                  // tap-down. This matches Apple's "touch and content move
                  // together" principle.
                  int indexFromDx(double dx) {
                    if (values.isEmpty || constraints.maxWidth <= 0) return 0;
                    return (dx / constraints.maxWidth * values.length)
                        .floor()
                        .clamp(0, values.length - 1);
                  }

                  final isDark =
                      Theme.of(context).brightness == Brightness.dark;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) =>
                        onDaySelected(indexFromDx(details.localPosition.dx)),
                    onHorizontalDragUpdate: (details) =>
                        onDaySelected(indexFromDx(details.localPosition.dx)),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < values.length; i++)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              child: AnimatedContainer(
                                duration:
                                    MediaQuery.of(context).disableAnimations
                                    ? Duration.zero
                                    : AppMotion.fast,
                                curve: AppMotion.easeOut,
                                height: values[i] == 0
                                    ? 5
                                    : 14 + values[i] / maxValue * 100,
                                decoration: BoxDecoration(
                                  color: i == safeSelected
                                      ? AppColors.primary
                                      : AppColors.sage.withValues(
                                          // Sage at 0.28 sinks into the
                                          // dark card; raise the alpha so
                                          // unselected bars stay visible.
                                          alpha: isDark ? 0.5 : 0.28,
                                        ),
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(AppRadii.xs),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendDayNavigator extends StatelessWidget {
  final String label;
  final bool canGoPrevious;
  final bool canGoNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const _TrendDayNavigator({
    required this.label,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          key: const ValueKey('trend-previous-day'),
          tooltip: '前一天',
          onPressed: canGoPrevious ? onPrevious : null,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppTheme.mutedCaption(size: 12, context: context),
          ),
        ),
        IconButton(
          key: const ValueKey('trend-next-day'),
          tooltip: '后一天',
          onPressed: canGoNext ? onNext : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}

class _MetricSwitch extends StatelessWidget {
  final _TrendMetric metric;
  final ValueChanged<_TrendMetric> onChanged;
  final bool wide;

  const _MetricSwitch({
    required this.metric,
    required this.onChanged,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Container(
      width: wide ? double.infinity : 132,
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.all(AppSpacing.x1),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      // Local Material so the segment InkWells ripple on top of the
      // surfaceMuted track, not on the card far beneath it.
      child: Material(
        type: MaterialType.transparency,
        child: Row(
          children: [
            for (final value in _TrendMetric.values)
              Expanded(
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onChanged(value);
                  },
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.x1_5,
                    ),
                    decoration: BoxDecoration(
                      color: metric == value
                          ? palette.surface
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                      // iOS segmented controls lift the selected segment
                      // off the track with a small shadow.
                      boxShadow: metric == value ? AppShadows.sm : null,
                    ),
                    child: Text(
                      value == _TrendMetric.answers ? '答题数' : '时长',
                      style: AppTheme.mutedCaption(
                        size: 11,
                        color: metric == value ? palette.ink : palette.inkMuted,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HeatmapCard extends StatelessWidget {
  final List<bool> activity;
  final int streakDays;

  const _HeatmapCard({required this.activity, required this.streakDays});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final cells = buildRhythmCalendar(activity: activity, now: now, weeks: 13);
    final dates = buildRhythmCalendarDates(now: now, weeks: 13);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.x3,
            runSpacing: AppSpacing.x1,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('90 天学习节奏', style: AppTheme.cardTitle(context: context)),
              Text(
                '${now.month}月${now.day}日止 · ${streakDays > 0 ? "连续 $streakDays 天" : "今天开始也不晚"}',
                style: AppTheme.mutedCaption(size: 12, context: context),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x4),
          LayoutBuilder(
            builder: (context, constraints) {
              final size =
                  (constraints.maxWidth - 12 * AppSpacing.x1) / 13;
              return Row(
                children: [
                  for (var col = 0; col < 13; col++) ...[
                    if (col > 0) const SizedBox(width: AppSpacing.x1),
                    Column(
                      children: [
                        for (var row = 0; row < 7; row++) ...[
                          if (row > 0) const SizedBox(height: AppSpacing.x1),
                          Container(
                            width: size,
                            height: size,
                            decoration: BoxDecoration(
                              color: cells[col * 7 + row] == null
                                  ? Colors.transparent
                                  : cells[col * 7 + row]!
                                  ? AppColors.sage.withValues(alpha: 0.86)
                                  : AppColors.of(context).surfaceMuted,
                              borderRadius:
                                  BorderRadius.circular(AppRadii.xxs),
                            ),
                          ).withRhythmSemantics(
                            context,
                            date: dates[col * 7 + row],
                            active: cells[col * 7 + row],
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(
            '每列一周 · 周一在上，周日在下',
            style: AppTheme.mutedCaption(size: 11, context: context),
          ),
        ],
      ),
    );
  }
}

extension on Widget {
  Widget withRhythmSemantics(
    BuildContext context, {
    required DateTime? date,
    required bool? active,
  }) {
    if (date == null || active == null) return ExcludeSemantics(child: this);
    final label = '${date.month}月${date.day}日，${active ? "已学习" : "无学习记录"}';
    return Tooltip(
      message: label,
      child: Semantics(label: label, image: true, child: this),
    );
  }
}

@visibleForTesting
List<DateTime?> buildRhythmCalendarDates({
  required DateTime now,
  int weeks = 7,
}) {
  assert(weeks > 0);
  final today = DateUtils.dateOnly(now);
  final currentMonday = today.subtract(Duration(days: today.weekday - 1));
  final gridStart = currentMonday.subtract(Duration(days: (weeks - 1) * 7));
  return List<DateTime?>.generate(weeks * 7, (index) {
    final col = index ~/ 7;
    final row = index % 7;
    final date = gridStart.add(Duration(days: col * 7 + row));
    return date.isAfter(today) ? null : date;
  });
}

@visibleForTesting
List<bool?> buildRhythmCalendar({
  required List<bool> activity,
  required DateTime now,
  int weeks = 7,
}) {
  assert(weeks > 0);
  final today = DateUtils.dateOnly(now);
  final currentMonday = today.subtract(Duration(days: today.weekday - 1));
  final gridStart = currentMonday.subtract(Duration(days: (weeks - 1) * 7));
  final cells = List<bool?>.filled(weeks * 7, null);
  for (var col = 0; col < weeks; col++) {
    for (var row = 0; row < 7; row++) {
      final date = gridStart.add(Duration(days: col * 7 + row));
      if (date.isAfter(today)) continue;
      final sourceIndex = activity.length - 1 - today.difference(date).inDays;
      if (sourceIndex >= 0 && sourceIndex < activity.length) {
        cells[col * 7 + row] = activity[sourceIndex];
      }
    }
  }
  return cells;
}

@visibleForTesting
int activeDaysInCurrentWeek(List<bool> activity, DateTime now) {
  final days = now.weekday;
  final start = activity.length > days ? activity.length - days : 0;
  return activity.skip(start).where((active) => active).length;
}
