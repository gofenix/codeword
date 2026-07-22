import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lib_ui/lib_ui.dart';

import '../state/learning_session.dart';

enum _TrendMetric { words, minutes }

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
  _TrendMetric _metric = _TrendMetric.words;
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

    final distribution = [
      _MasteryPart('稳固', progress?.mastered ?? 0, const Color(0xFF48A868)),
      _MasteryPart(
        '学习中',
        max(0, (progress?.learned ?? 0) - (progress?.mastered ?? 0)),
        const Color(0xFF5E7ED8),
      ),
      _MasteryPart(
        '待巩固',
        max(0, (progress?.seen ?? 0) - (progress?.learned ?? 0)),
        const Color(0xFFF0B53A),
      ),
      _MasteryPart('未学习', progress?.unseenWords ?? 0, const Color(0xFFD9DDDC)),
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
            _TodayAction(
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
  final int due;
  final int newToday;
  final int minutes;
  final VoidCallback? onContinue;

  const _TodayAction({
    required this.due,
    required this.newToday,
    required this.minutes,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final estimate = due == 0 ? 2 : (due / 3).ceil().clamp(1, 20);
    return Material(
      key: const ValueKey('stats-first-content'),
      color: const Color(0xFFEAF7EE),
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        onTap: onContinue == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onContinue!();
              },
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.x4),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: const Icon(Icons.bolt_rounded, color: AppColors.primary),
              ),
              const SizedBox(width: AppSpacing.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      due > 0 ? '还有 $due 个词正在变模糊' : '记忆状态很好',
                      style: AppTheme.rowTitle(context: context),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '今日新学 $newToday · 已学习 $minutes 分钟 · 约 $estimate 分钟',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.mutedCaption(size: 12, context: context),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.x2),
              const Icon(Icons.arrow_forward_rounded, color: AppColors.primary),
            ],
          ),
        ),
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
            onTap: onOpenLibrary,
            borderRadius: BorderRadius.circular(AppRadii.sm),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '当前词书掌握',
                        style: AppTheme.cardTitle(context: context),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        vocabName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.mutedCaption(
                          size: 12,
                          context: context,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${(ratio * 100).toStringAsFixed(1)}%',
                  style: AppTheme.wordDisplay(
                    size: 30,
                    color: AppColors.primary,
                    weight: FontWeight.w800,
                    context: context,
                  ).copyWith(fontFamily: null),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.of(context).inkSubtle,
                ),
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
    final values = metric == _TrendMetric.words ? words : minutes;
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
          const SizedBox(height: AppSpacing.x2),
          Text(
            '${selectedDate.month}月${selectedDate.day}日 · $selectedValue${metric == _TrendMetric.words ? " 词" : " 分钟"}',
            style: AppTheme.mutedCaption(size: 12, context: context),
          ),
          const SizedBox(height: AppSpacing.x4),
          SizedBox(
            height: 128,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < values.length; i++)
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: '第 ${i + 1} 天 ${values[i]}',
                      child: GestureDetector(
                        onTap: () => onDaySelected(i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: AnimatedContainer(
                            duration: AppMotion.fast,
                            height: values[i] == 0
                                ? 5
                                : 14 + values[i] / maxValue * 100,
                            decoration: BoxDecoration(
                              color: i == safeSelected
                                  ? AppColors.primary
                                  : AppColors.primary.withValues(alpha: 0.25),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(AppRadii.xs),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricSwitch extends StatelessWidget {
  final _TrendMetric metric;
  final ValueChanged<_TrendMetric> onChanged;

  const _MetricSwitch({required this.metric, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 132,
      height: 34,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.of(context).surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Row(
        children: [
          for (final value in _TrendMetric.values)
            Expanded(
              child: InkWell(
                onTap: () => onChanged(value),
                borderRadius: BorderRadius.circular(AppRadii.xs),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: metric == value
                        ? AppColors.of(context).surface
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadii.xs),
                  ),
                  child: Text(
                    value == _TrendMetric.words ? '单词数' : '时长',
                    style: AppTheme.mutedCaption(
                      size: 11,
                      color: metric == value
                          ? AppColors.of(context).ink
                          : AppColors.of(context).inkMuted,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
        ],
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
    final cells = buildRhythmCalendar(
      activity: activity,
      now: DateTime.now(),
      weeks: 13,
    );
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '90 天学习节奏',
                  style: AppTheme.cardTitle(context: context),
                ),
              ),
              Text(
                '连续 $streakDays 天',
                style: AppTheme.mutedCaption(size: 12, context: context),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x4),
          LayoutBuilder(
            builder: (context, constraints) {
              final size = (constraints.maxWidth - 12 * 4) / 13;
              return Row(
                children: [
                  for (var col = 0; col < 13; col++) ...[
                    if (col > 0) const SizedBox(width: 4),
                    Column(
                      children: [
                        for (var row = 0; row < 7; row++) ...[
                          if (row > 0) const SizedBox(height: 4),
                          Container(
                            width: size,
                            height: size,
                            decoration: BoxDecoration(
                              color: cells[col * 7 + row] == null
                                  ? Colors.transparent
                                  : cells[col * 7 + row]!
                                  ? AppColors.primary.withValues(alpha: 0.82)
                                  : AppColors.of(context).surfaceMuted,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
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
