import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lib_core/lib_core.dart';
import 'package:lib_content/lib_content.dart';
import 'package:lib_ui/lib_ui.dart';

import '../screens/learning_session_screen.dart';
import '../state/learning_session.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meta = ref.watch(vocabMetaProvider);
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
              '词库',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              '9 套程序员向词库 · 持续更新中',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.inkMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: AppSpacing.x5),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: AppSpacing.x3,
                  mainAxisSpacing: AppSpacing.x3,
                  childAspectRatio: 0.95,
                ),
                itemCount: kBuiltinLists.length,
                itemBuilder: (_, i) {
                  final list = kBuiltinLists[i];
                  return _VocabCard(
                    list: list,
                    available: kBuiltinVocabIds.contains(list.id),
                    meta: meta[list.id],
                    onTap: list.wordCount == 0 || !kBuiltinVocabIds.contains(list.id)
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => LearningSessionScreen(
                                  vocabId: list.id,
                                ),
                              ),
                            ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VocabCard extends ConsumerWidget {
  final VocabList list;
  final bool available;
  final VocabList? meta;
  final VoidCallback? onTap;

  const _VocabCard({
    required this.list,
    required this.available,
    required this.meta,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _hex(list.domainColor);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: Text(
                  list.emoji,
                  style: const TextStyle(fontSize: 20),
                ),
              ),
              if (!available)
                PillTag(
                  label: '敬请期待',
                  color: AppColors.inkSubtle,
                  variant: PillVariant.soft,
                )
              else
                PillTag(
                  label: 'Lv ${list.level}',
                  color: color,
                  variant: PillVariant.soft,
                ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                list.name,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                list.description,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.inkMuted,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                available
                    ? '${list.wordCount} 词'
                    : 'W2 上线',
                style: TextStyle(
                  fontSize: 11,
                  color: available
                      ? AppColors.inkSubtle
                      : AppColors.inkSubtle,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (available)
                Icon(
                  Icons.play_arrow_rounded,
                  color: color,
                  size: 18,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Color _hex(String hex) {
    final cleaned = hex.replaceFirst('#', '');
    return Color(int.parse('FF$cleaned', radix: 16));
  }
}
