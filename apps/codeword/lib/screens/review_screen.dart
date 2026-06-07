import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lib_ui/lib_ui.dart';

import '../state/learning_session.dart';

class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final review = ref.watch(reviewStateProvider);
    final due = review.values
        .where((s) => s.dueAt != null && !s.dueAt!.isAfter(DateTime.now()))
        .length;
    final totalLearned = review.values
        .where((s) => s.repetitions >= 1)
        .length;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x5,
          AppSpacing.x4,
          AppSpacing.x5,
          AppSpacing.x4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '复习',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              '基于 SM-2 算法的间隔重复',
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
                      label: '待复习',
                      value: '$due',
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
                      label: '已学过',
                      value: '$totalLearned',
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.x5),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(AppRadii.xl),
                      ),
                      child: const Icon(
                        Icons.refresh_rounded,
                        size: 36,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.x4),
                    Text(
                      totalLearned == 0
                          ? '先从今日开始学'
                          : (due == 0 ? '今天没有要复习的' : '点击下方开始复习'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.x2),
                    Text(
                      totalLearned == 0
                          ? '学完 10 个词,复习队列就会有内容了'
                          : (due == 0
                              ? '明天再来,或者去词库加新词'
                              : '按 SM-2 间隔混合新旧词'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.inkMuted,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
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
