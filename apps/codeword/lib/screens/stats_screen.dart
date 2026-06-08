import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lib_ui/lib_ui.dart';

import '../state/learning_session.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final review = ref.watch(reviewStateProvider);
    final totalLearned = review.values
        .where((s) => s.repetitions >= 1)
        .length;
    final totalSeen = review.length;
    final avgEasiness = review.isEmpty
        ? 0.0
        : review.values.map((s) => s.easiness / 100.0).reduce((a, b) => a + b) /
            review.length;

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
                      value: '$totalLearned',
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
                      value: '$totalSeen',
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
                      value: avgEasiness == 0
                          ? '—'
                          : avgEasiness.toStringAsFixed(2),
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
                        totalSeen == 0 ? '还没数据' : '$totalSeen 次答题',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.inkMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.x4),
                  _Heatmap(),
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
                    'v0.3 · V1',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.inkMuted,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  const Text(
                    '✅ A/B/C/D 看词选义\n✅ SM-2 间隔重复 + 持久化\n✅ 9 套词库 450 词\n✅ macOS + Android 双端\n🚧 6 位同步码 + E2E 加密\n🚧 4 种新题型(听音/拼写...)',
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
  @override
  Widget build(BuildContext context) {
    // Mock: deterministic per day to look real across renders.
    final rng = Random(42);
    final days = ['一', '二', '三', '四', '五', '六', '日'];
    return Row(
      children: List.generate(7, (i) {
        final level = rng.nextInt(4);
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
                  days[i],
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
