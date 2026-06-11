import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lib_ui/lib_ui.dart';

import '../state/learning_session.dart';
import 'learning_session_screen.dart';

/// Pulse — the daily-digest tab.
///
/// Inspired by ChatGPT Pulse: a one-screen "what should I do today"
/// digest. Pure local data (no AI), no cloud, no API key. Surfaces
/// three things:
///   1. Today's headline — streak, new words, reviews, learned count.
///   2. The 3 words most overdue for review (with quick-start CTA).
///   3. The 3 new words to learn next (with quick-start CTA).
/// Plus a 30-day heatmap at the bottom for context.
///
/// All "开始" buttons launch the regular learning session for the
/// owning vocab — so Pulse is the front door, not a separate flow.
class PulseScreen extends ConsumerWidget {
  const PulseScreen({super.key});

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
            const _PulseHeader(),
            const SizedBox(height: AppSpacing.x4),
            _FocusCard(stats: stats),
            const SizedBox(height: AppSpacing.x5),
            const _DueListCard(),
            const SizedBox(height: AppSpacing.x5),
            const _RecommendedNewCard(),
            const SizedBox(height: AppSpacing.x5),
            _HeatmapCard(stats: stats),
            const SizedBox(height: AppSpacing.x4),
          ],
        ),
      ),
    );
  }
}

/// Async data for the two list cards. Both are kept tiny (3 entries
/// each) and recomputed on demand.
final _dueWordsProvider = FutureProvider.family<List<PulseWordEntry>, int>(
  (ref, limit) =>
      ref.watch(reviewStateProvider.notifier).dueWords(limit: limit),
);

final _recommendedNewProvider = FutureProvider.family<List<PulseWordEntry>, int>(
  (ref, limit) =>
      ref.watch(reviewStateProvider.notifier).recommendedNewWords(limit: limit),
);

class _PulseHeader extends StatelessWidget {
  const _PulseHeader();
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    const weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];
    final weekday = weekdayNames[now.weekday - 1]; // Mon=1..Sun=7, maps to 0..6
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Pulse',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${now.month} 月 ${now.day} 日 · 周$weekday',
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.inkMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// 1. Today's headline card — streak / new / due / learned.
class _FocusCard extends StatelessWidget {
  final ReviewStats stats;
  const _FocusCard({required this.stats});

  String _greeting() {
    if (stats.streakDays == 0 && stats.reviewsToday == 0) {
      return '今天还没有开始';
    }
    if (stats.streakDays > 0) {
      return '连续 ${stats.streakDays} 天 · 今天别断';
    }
    return '回来啦';
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _greeting(),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              height: 1.3,
            ),
          ),
          const SizedBox(height: AppSpacing.x4),
          Row(
            children: [
              Expanded(
                child: _FocusCell(
                  label: '待复习',
                  value: '${stats.totalDue}',
                  hint: stats.totalDue == 0 ? '都过了' : '优先级最高',
                  color: AppColors.info,
                  icon: Icons.refresh_rounded,
                ),
              ),
              const SizedBox(width: AppSpacing.x3),
              Expanded(
                child: _FocusCell(
                  label: '今日新词',
                  value: '${stats.newToday}',
                  hint: stats.newToday == 0 ? '今天还没学' : '今天已学',
                  color: AppColors.primary,
                  icon: Icons.auto_awesome_rounded,
                ),
              ),
              const SizedBox(width: AppSpacing.x3),
              Expanded(
                child: _FocusCell(
                  label: '已掌握',
                  value: '${stats.totalLearned}',
                  hint: '累计',
                  color: AppColors.success,
                  icon: Icons.check_circle_outline_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FocusCell extends StatelessWidget {
  final String label;
  final String value;
  final String hint;
  final Color color;
  final IconData icon;

  const _FocusCell({
    required this.label,
    required this.value,
    required this.hint,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.inkMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          hint,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// 2. Top-3 due-for-review words.
class _DueListCard extends ConsumerWidget {
  const _DueListCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_dueWordsProvider(3));
    final entries = async.maybeWhen(data: (v) => v, orElse: () => <PulseWordEntry>[]);
    return _PulseListCard(
      title: '该复习了',
      icon: Icons.refresh_rounded,
      accent: AppColors.info,
      emptyHint: '现在没有待复习的词',
      entries: entries,
    );
  }
}

/// 3. Top-3 recommended new words from the user's lowest-coverage vocab.
class _RecommendedNewCard extends ConsumerWidget {
  const _RecommendedNewCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_recommendedNewProvider(3));
    final entries = async.maybeWhen(data: (v) => v, orElse: () => <PulseWordEntry>[]);
    return _PulseListCard(
      title: '推荐新词',
      icon: Icons.auto_awesome_rounded,
      accent: AppColors.primary,
      emptyHint: '已学完所有词',
      entries: entries,
    );
  }
}

class _PulseListCard extends ConsumerWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final String emptyHint;
  final List<PulseWordEntry> entries;

  const _PulseListCard({
    required this.title,
    required this.icon,
    required this.accent,
    required this.emptyHint,
    required this.entries,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasEntries = entries.isNotEmpty;
    final primaryVocabId = hasEntries ? entries.first.vocabId : 'ai_core';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const Spacer(),
              if (hasEntries)
                Text(
                  '${entries.length} 个',
                  style: TextStyle(
                    fontSize: 12,
                    color: accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.x4),
          if (!hasEntries)
            EmptyHint(
              icon: icon,
              message: emptyHint,
            )
          else
            for (var i = 0; i < entries.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.x3),
              _PulseWordRow(entry: entries[i]),
            ],
          if (hasEntries) ...[
            const SizedBox(height: AppSpacing.x4),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          LearningSessionScreen(vocabId: primaryVocabId),
                    ),
                  );
                },
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.x3),
                  backgroundColor: accent,
                ),
                child: const Text(
                  '开始',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PulseWordRow extends StatelessWidget {
  final PulseWordEntry entry;
  const _PulseWordRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.word,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                  fontFamily: 'serif',
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${entry.phonetic}  ${entry.translation}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.inkMuted,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.x3),
        if (entry.overdueDays != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Text(
              (entry.overdueDays ?? 0) <= 0
                  ? '今天'
                  : '逾期 ${entry.overdueDays} 天',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.info,
              ),
            ),
          )
        else
          PillTag.level(entry.level),
      ],
    );
  }
}

/// 4. Last-30-days heatmap so the user can see their trend.
class _HeatmapCard extends StatelessWidget {
  final ReviewStats stats;
  const _HeatmapCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final last30 = stats.last30Days;
    final total30 = last30.fold<int>(0, (a, b) => a + b);
    final activeDays = last30.where((n) => n > 0).length;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_fire_department,
                  size: 18, color: AppColors.warning),
              const SizedBox(width: 6),
              const Text(
                '最近 30 天',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const Spacer(),
              Text(
                total30 == 0
                    ? '还没开始'
                    : '$total30 次答题 · $activeDays 天活跃',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.inkMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x4),
          _PulseHeatmapGrid(last30: last30),
        ],
      ),
    );
  }
}

/// 5-col x 6-row grid of cells. Each cell = 5 days; we render 30 cells
/// (5 weeks of weekday columns). The right-most column is the most
/// recent day. Greener = more reviews.
class _PulseHeatmapGrid extends StatelessWidget {
  final List<int> last30;
  const _PulseHeatmapGrid({required this.last30});

  int _heatLevel(int n) {
    if (n <= 0) return 0;
    if (n <= 5) return 1;
    if (n <= 15) return 2;
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    // 5 columns (weeks), 6 rows. last30 is [d-29 .. today].
    // We want col 4 (rightmost) = today, going back column by column.
    // Easier: fill columns top-to-bottom, left-to-right.
    final cells = List<int?>.filled(30, null);
    for (var i = 0; i < last30.length && i < 30; i++) {
      cells[i] = last30[i];
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        const cols = 5;
        const rows = 6;
        final gap = 4.0;
        final cellSize =
            (constraints.maxWidth - (cols - 1) * gap) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: List.generate(cols * rows, (i) {
            final v = cells[i];
            if (v == null) {
              return SizedBox(width: cellSize, height: cellSize);
            }
            final level = _heatLevel(v);
            final color = switch (level) {
              0 => AppColors.surfaceMuted,
              1 => AppColors.primary.withValues(alpha: 0.3),
              2 => AppColors.primary.withValues(alpha: 0.6),
              _ => AppColors.primary,
            };
            return Container(
              width: cellSize,
              height: cellSize,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(AppRadii.sm),
              ),
            );
          }),
        );
      },
    );
  }
}
