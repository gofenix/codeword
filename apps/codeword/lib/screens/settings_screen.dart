import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lib_core/lib_core.dart';
import 'package:lib_ui/lib_ui.dart';

import '../services/article_repository.dart';
import '../state/app_settings.dart';
import '../state/learning_session.dart';
import '../state/llm_config.dart';
import 'ai_settings_screen.dart';

/// 设置 — only configuration that changes the learning experience.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppColors.of(context);
    return Scaffold(
      backgroundColor: palette.background,
      body: CustomScrollView(
        slivers: [
          SliverSafeArea(
            sliver: SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.x6,
                AppSpacing.x3,
                AppSpacing.x6,
                AppSpacing.x8,
              ),
              sliver: SliverList.list(
                children: [
                  const _SettingsHeader(),
                  const SizedBox(height: AppSpacing.x5),
                  const _SectionLabel('学习节奏'),
                  const SizedBox(height: AppSpacing.x2),
                  const _SettingsGroup(children: [_DailyNewWordsRow()]),
                  const SizedBox(height: AppSpacing.x5),
                  const _SectionLabel('AI'),
                  const SizedBox(height: AppSpacing.x2),
                  const _SettingsGroup(children: [_AiSettingsRow()]),
                  const SizedBox(height: AppSpacing.x5),
                  const _SectionLabel('数据'),
                  const SizedBox(height: AppSpacing.x2),
                  const _SettingsGroup(
                    children: [_LocalDataRow(), _ClearLearningDataRow()],
                  ),
                  const SizedBox(height: AppSpacing.x8),
                  Center(
                    child: Text(
                      'CodeWord · 本地优先背单词',
                      style: AppTheme.mutedCaption(size: 12, context: context),
                    ),
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

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          tooltip: '返回',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 21),
          color: AppColors.of(context).ink,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        ),
        const SizedBox(height: AppSpacing.x3),
        Text('设置', style: AppTheme.screenHeader(context: context)),
        const SizedBox(height: AppSpacing.x2),
        Text(
          '只保留会影响学习体验的配置',
          style: AppTheme.mutedCaption(size: 14, context: context),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(label, style: AppTheme.sectionLabel(context: context));
  }
}

class _SettingsGroup extends StatelessWidget {
  final List<Widget> children;

  const _SettingsGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              Divider(
                height: 0.5,
                thickness: 0.5,
                indent: AppSpacing.x4,
                color: AppColors.of(context).divider.withValues(alpha: 0.7),
              ),
          ],
        ],
      ),
    );
  }
}

class _DailyNewWordsRow extends ConsumerWidget {
  const _DailyNewWordsRow();

  Future<void> _adjust(BuildContext context, WidgetRef ref, int delta) async {
    HapticFeedback.selectionClick();
    try {
      await ref.read(appSettingsProvider.notifier).adjustDailyNewWords(delta);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('保存失败，请稍后再试')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final value = settings.dailyNewWords;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x4,
        vertical: AppSpacing.x3,
      ),
      child: Row(
        children: [
          const _SettingIcon(icon: Icons.calendar_today_rounded),
          const SizedBox(width: AppSpacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('每日新词', style: AppTheme.rowTitle(context: context)),
                const SizedBox(height: 2),
                Text(
                  '新词上限，复习仍然优先',
                  style: AppTheme.mutedCaption(size: 12, context: context),
                ),
              ],
            ),
          ),
          _StepperButton(
            icon: Icons.remove_rounded,
            enabled: value > AppSettings.minDailyNewWords,
            onPressed: () => _adjust(context, ref, -1),
          ),
          SizedBox(
            width: 48,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: AppTheme.wordDisplay(
                size: 20,
                color: AppColors.of(context).ink,
                weight: FontWeight.w700,
              ),
            ),
          ),
          _StepperButton(
            icon: Icons.add_rounded,
            enabled: value < AppSettings.maxDailyNewWords,
            onPressed: () => _adjust(context, ref, 1),
          ),
        ],
      ),
    );
  }
}

class _AiSettingsRow extends ConsumerWidget {
  const _AiSettingsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(llmConfigProvider);
    final subtitle = cfg.isConfigured
        ? '${cfg.model} · ${cfg.maskedKey}'
        : '需要自备模型 API Key，费用由服务商收取';
    return _SettingsTile(
      icon: Icons.bolt_rounded,
      title: 'AI 阅读配置',
      subtitle: subtitle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PillTag(
            label: cfg.isConfigured ? '已配置' : '未配置',
            color: cfg.isConfigured ? AppColors.success : AppColors.inkSubtle,
            icon: cfg.isConfigured ? Icons.check : Icons.more_horiz,
            variant: PillVariant.soft,
          ),
          const SizedBox(width: AppSpacing.x2),
          Icon(
            Icons.chevron_right_rounded,
            color: AppColors.of(context).inkSubtle,
            size: 20,
          ),
        ],
      ),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const AiSettingsScreen())),
    );
  }
}

class _LocalDataRow extends StatelessWidget {
  const _LocalDataRow();

  @override
  Widget build(BuildContext context) {
    return const _SettingsTile(
      icon: Icons.folder_outlined,
      title: '本地数据',
      subtitle: '学习记录仅保存在此设备',
    );
  }
}

class _ClearLearningDataRow extends ConsumerWidget {
  const _ClearLearningDataRow();

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    HapticFeedback.selectionClick();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('清理学习数据'),
          content: const Text('将清空背词记录、统计、收藏、已移除词和阅读历史。AI 配置和当前词书会保留。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('清理'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return;
    ref.read(learningDataClearInProgressProvider.notifier).state = true;
    var completed = false;
    var message = '学习数据已清理';
    try {
      await ref.read(reviewStateProvider.notifier).clearLearningData();
      final articleRepository = ArticleRepository.instance;
      await articleRepository.clear();
      ref.read(articleRepositoryRevisionProvider.notifier).state =
          articleRepository.revision;
      await ReviewRepository.instance.completeLearningDataClear();
      completed = true;
    } catch (_) {
      final pending =
          ReviewRepository.isReady &&
          ReviewRepository.instance.pendingLearningDataClear;
      if (!pending) {
        ref.read(learningDataClearInProgressProvider.notifier).state = false;
      }
      message = pending ? '清理尚未完成，请重试' : '清理失败，请稍后再试';
    }

    if (completed) {
      ref.read(learningDataClearInProgressProvider.notifier).state = false;
      try {
        await ref.read(appSettingsProvider.notifier).ready;
        final settings = ref.read(appSettingsProvider);
        await ref
            .read(learningSessionProvider.notifier)
            .start(
              vocabId: ref.read(selectedVocabProvider),
              dailyNewWordLimit: settings.dailyNewWords,
              maxSessionSize: settings.dailyNewWords + 20,
            );
      } catch (_) {
        // The Words tab already shows its loading state and can retry.
      }
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _SettingsTile(
      icon: Icons.delete_outline_rounded,
      title: '清理学习数据',
      subtitle: '保留 AI 配置和当前词书',
      color: AppColors.danger,
      destructive: true,
      onTap: () => _confirm(context, ref),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool destructive;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.color = AppColors.primary,
    this.destructive = false,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final titleColor = destructive
        ? AppColors.danger
        : AppColors.of(context).ink;
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x4,
        vertical: AppSpacing.x3,
      ),
      child: Row(
        children: [
          _SettingIcon(icon: icon, color: color),
          const SizedBox(width: AppSpacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.rowTitle(color: titleColor, context: context),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTheme.mutedCaption(size: 12, context: context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.x3),
            trailing!,
          ],
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(onTap: onTap, child: content);
  }
}

class _SettingIcon extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _SettingIcon({required this.icon, this.color = AppColors.primary});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Icon(icon, color: color, size: 19),
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  const _StepperButton({
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: icon == Icons.add_rounded ? '增加' : '减少',
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon, size: 18),
      style: IconButton.styleFrom(
        backgroundColor: AppColors.of(context).surfaceMuted,
        foregroundColor: AppColors.of(context).ink,
        disabledForegroundColor: AppColors.of(context).inkSubtle,
        minimumSize: const Size(36, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
