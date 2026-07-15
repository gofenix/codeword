import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lib_ui/lib_ui.dart';

import '../state/learning_session.dart';

class StatsScreen extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isActive) return const SizedBox.expand();
    ref.watch(reviewStateProvider);
    final catalog = ref.watch(qwertyCatalogProvider);
    final selectedVocab = ref.watch(selectedVocabProvider);
    final stats = ref
        .read(reviewStateProvider.notifier)
        .stats(catalog: catalog);
    final progress = vocabProgressFor(stats, selectedVocab);
    final matchingVocab = catalog.where((item) => item.id == selectedVocab);
    final vocab = matchingVocab.isEmpty ? null : matchingVocab.first;

    int count(MasteryLevel level) => stats.mastery
        .where((bucket) => bucket.level == level)
        .fold(0, (sum, bucket) => sum + bucket.count);

    final distribution = <_DistributionItem>[
      _DistributionItem(
        label: '已稳固',
        count: count(MasteryLevel.familiar) + count(MasteryLevel.recognized),
        color: const Color(0xFF72B83E),
      ),
      _DistributionItem(
        label: '学习中',
        count: count(MasteryLevel.vague),
        color: const Color(0xFF7C88DA),
      ),
      _DistributionItem(
        label: '待巩固',
        count: count(MasteryLevel.unfamiliar),
        color: const Color(0xFFF5C33B),
      ),
      _DistributionItem(
        label: '未学习',
        count: count(MasteryLevel.unseen),
        color: const Color(0xFFDADDDC),
      ),
    ];

    return TabPageScaffold(
      title: '图表',
      scrollKey: const PageStorageKey('stats-scroll'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x6,
            AppSpacing.x5,
            AppSpacing.x6,
            AppSpacing.x8,
          ),
          sliver: SliverList.list(
            children: [
              _OverviewCards(
                vocabName: vocab?.name ?? '暂无词书',
                totalWords:
                    progress?.availableWords ?? vocab?.wordCount ?? 0,
                learnedWords: progress?.mastered ?? 0,
                coverage: progress?.masteryCoverage ?? 0,
                onOpenVocab: onGoLibrary,
              ),
              const SizedBox(height: AppSpacing.x4),
              _DistributionCard(items: distribution),
              const SizedBox(height: AppSpacing.x4),
              _TodayCard(
                reviews: stats.reviewsToday > stats.newToday
                    ? stats.reviewsToday - stats.newToday
                    : 0,
                newWords: stats.newToday,
                due: stats.totalDue,
                learned: progress?.mastered ?? stats.totalLearned,
                minutes: stats.studyMinutesToday,
                streakDays: stats.streakDays,
                onContinue: onGoWords,
              ),
              const SizedBox(height: AppSpacing.x4),
              _RhythmCard(
                activity: stats.last90DaysActivity,
                streakDays: stats.streakDays,
                activeDaysThisWeek: activeDaysInCurrentWeek(
                  stats.last90DaysActivity,
                  DateTime.now(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OverviewCards extends StatelessWidget {
  final String vocabName;
  final int totalWords;
  final int learnedWords;
  final double coverage;
  final VoidCallback? onOpenVocab;

  const _OverviewCards({
    required this.vocabName,
    required this.totalWords,
    required this.learnedWords,
    required this.coverage,
    required this.onOpenVocab,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 164,
      child: Row(
        children: [
          Expanded(
            child: AppCard(
              onTap: onOpenVocab,
              semanticLabel: '打开当前词书',
              padding: const EdgeInsets.all(AppSpacing.x4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '当前词书',
                          style: AppTheme.cardTitle(context: context),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.of(context).inkSubtle,
                        size: 22,
                      ),
                    ],
                  ),
                  const Spacer(),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      vocabName,
                      maxLines: 1,
                      style: AppTheme.wordDisplay(
                        size: 26,
                        color: const Color(0xFFF06418),
                        weight: FontWeight.w800,
                        context: context,
                      ).copyWith(fontFamily: null, height: 1.15),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '共 $totalWords 词',
                    style: AppTheme.mutedCaption(context: context),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.x3),
          Expanded(
            child: AppCard(
              padding: const EdgeInsets.all(AppSpacing.x4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('掌握进度', style: AppTheme.cardTitle(context: context)),
                  const Spacer(),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${(coverage * 100).toStringAsFixed(1)}%',
                      style: AppTheme.wordDisplay(
                        size: 42,
                        color: const Color(0xFF58B84C),
                        weight: FontWeight.w800,
                        context: context,
                      ).copyWith(fontFamily: null),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '已掌握 $learnedWords 词',
                    style: AppTheme.mutedCaption(context: context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DistributionItem {
  final String label;
  final int count;
  final Color color;

  const _DistributionItem({
    required this.label,
    required this.count,
    required this.color,
  });
}

class _DistributionCard extends StatelessWidget {
  final List<_DistributionItem> items;

  const _DistributionCard({required this.items});

  @override
  Widget build(BuildContext context) {
    final total = items.fold<int>(0, (sum, item) => sum + item.count);
    final ratios = items
        .map((item) => total == 0 ? 0.0 : item.count / total)
        .toList();
    final maxRatio = ratios.fold<double>(0.01, (a, b) => a > b ? a : b);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('掌握分布', style: AppTheme.cardTitle(context: context)),
          const SizedBox(height: AppSpacing.x4),
          Row(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.x2),
                Expanded(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: items[i].color,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.x1),
                      Flexible(
                        child: Text(
                          items[i].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.mutedCaption(
                            size: 11,
                            context: context,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.x4),
          SizedBox(
            height: 142,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.x3),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '${(ratios[i] * 100).round()}%',
                          style: AppTheme.cardTitle(
                            context: context,
                          ).copyWith(fontSize: 15),
                        ),
                        const SizedBox(height: AppSpacing.x2),
                        Container(
                          height: total == 0
                              ? 8
                              : (28 + ratios[i] / maxRatio * 82),
                          decoration: BoxDecoration(
                            color: items[i].color,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(AppRadii.sm),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  final int reviews;
  final int newWords;
  final int due;
  final int learned;
  final int minutes;
  final int streakDays;
  final VoidCallback? onContinue;

  const _TodayCard({
    required this.reviews,
    required this.newWords,
    required this.due,
    required this.learned,
    required this.minutes,
    required this.streakDays,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final cells = [
      _TodayItem(
        '复习 $reviews',
        Icons.menu_book_outlined,
        const Color(0xFF69B73F),
      ),
      _TodayItem('新学 $newWords', Icons.eco_outlined, const Color(0xFF69B73F)),
      _TodayItem('待巩固 $due', Icons.edit_outlined, const Color(0xFFE5AD18)),
      _TodayItem(
        '已掌握 $learned',
        Icons.verified_outlined,
        const Color(0xFFF0782A),
      ),
      _TodayItem(
        '学习 $minutes 分钟',
        Icons.schedule_outlined,
        const Color(0xFF5B82DE),
      ),
      _TodayItem(
        '连续 $streakDays 天',
        Icons.local_fire_department_outlined,
        const Color(0xFF7967D9),
      ),
    ];

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('今日', style: AppTheme.cardTitle(context: context)),
              const Spacer(),
              Text(
                '${DateTime.now().month}月${DateTime.now().day}日',
                style: AppTheme.mutedCaption(context: context),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x4),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - AppSpacing.x2) / 2;
              return Wrap(
                spacing: AppSpacing.x2,
                runSpacing: AppSpacing.x2,
                children: [
                  for (final cell in cells)
                    SizedBox(
                      width: width,
                      child: _TodayCell(item: cell),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.x3),
          Divider(color: AppColors.of(context).divider, height: 1),
          InkWell(
            onTap: onContinue == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onContinue!();
                  },
            borderRadius: BorderRadius.circular(AppRadii.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.x3),
              child: Row(
                children: [
                  const Icon(Icons.bolt_rounded, color: AppColors.primary),
                  const SizedBox(width: AppSpacing.x2),
                  Expanded(
                    child: Text(
                      due > 0 ? '再巩固 $due 个易忘词' : '继续学习新词',
                      style: AppTheme.rowTitle(context: context),
                    ),
                  ),
                  Text(
                    due > 0 ? '约 ${(due / 2).ceil().clamp(1, 20)} 分钟' : '开始',
                    style: AppTheme.mutedCaption(context: context),
                  ),
                  const SizedBox(width: AppSpacing.x1),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.of(context).inkSubtle,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayItem {
  final String label;
  final IconData icon;
  final Color color;

  const _TodayItem(this.label, this.icon, this.color);
}

class _TodayCell extends StatelessWidget {
  final _TodayItem item;

  const _TodayCell({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x3),
      decoration: BoxDecoration(
        color: item.color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Row(
        children: [
          Icon(item.icon, color: item.color, size: 20),
          const SizedBox(width: AppSpacing.x2),
          Expanded(
            child: Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.rowTitle(context: context).copyWith(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _RhythmCard extends StatelessWidget {
  final List<bool> activity;
  final int streakDays;
  final int activeDaysThisWeek;

  const _RhythmCard({
    required this.activity,
    required this.streakDays,
    required this.activeDaysThisWeek,
  });

  @override
  Widget build(BuildContext context) {
    final recent = buildRhythmCalendar(activity: activity, now: DateTime.now());

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('学习节奏', style: AppTheme.cardTitle(context: context)),
          const SizedBox(height: AppSpacing.x3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '连续 $streakDays 天',
                style: AppTheme.mutedCaption(size: 14, context: context),
              ),
              const SizedBox(width: AppSpacing.x5),
              Container(
                width: 1,
                height: 18,
                color: AppColors.of(context).divider,
              ),
              const SizedBox(width: AppSpacing.x5),
              Text(
                '本周学习 $activeDaysThisWeek 天',
                style: AppTheme.mutedCaption(size: 14, context: context),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x4),
          for (var row = 0; row < 7; row++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.x1),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    child: Text(
                      switch (row) {
                        0 => '一',
                        2 => '三',
                        4 => '五',
                        6 => '日',
                        _ => '',
                      },
                      style: AppTheme.mutedCaption(size: 10, context: context),
                    ),
                  ),
                  for (var col = 0; col < 7; col++)
                    Expanded(
                      child: AspectRatio(
                        aspectRatio: 1.5,
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: recent[col * 7 + row] == null
                                ? AppColors.of(
                                    context,
                                  ).surfaceMuted.withValues(alpha: 0.35)
                                : recent[col * 7 + row]!
                                ? Color.lerp(
                                    const Color(0xFFCFE9B9),
                                    const Color(0xFF58A92F),
                                    col / 6,
                                  )
                                : AppColors.of(context).surfaceMuted,
                            borderRadius: BorderRadius.circular(AppRadii.xs),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.x3),
          Center(
            child: Text(
              '有空就学，完成比完美更重要',
              style: AppTheme.mutedCaption(context: context),
            ),
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
      final daysAgo = today.difference(date).inDays;
      final sourceIndex = activity.length - 1 - daysAgo;
      if (sourceIndex >= 0 && sourceIndex < activity.length) {
        cells[col * 7 + row] = activity[sourceIndex];
      }
    }
  }
  return cells;
}

@visibleForTesting
int activeDaysInCurrentWeek(List<bool> activity, DateTime now) {
  final daysToInclude = now.weekday;
  final start = activity.length > daysToInclude
      ? activity.length - daysToInclude
      : 0;
  return activity.skip(start).where((active) => active).length;
}
