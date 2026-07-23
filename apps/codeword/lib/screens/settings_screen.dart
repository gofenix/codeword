import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lib_core/lib_core.dart';
import 'package:lib_ui/lib_ui.dart';

import '../services/article_repository.dart';
import '../state/learning_session.dart';
import '../state/learning_preferences.dart';
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
      body: DecoratedBox(
        decoration: AppMaterials.canvasDecoration(context),
        child: CustomScrollView(
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
                    const _SectionLabel('高级题型'),
                    const SizedBox(height: AppSpacing.x2),
                    const _SettingsGroup(
                      children: [
                        _AdvancedQuestionTypeRow(
                          type: _AdvancedQuestionType.spelling,
                        ),
                        _AdvancedQuestionTypeRow(
                          type: _AdvancedQuestionType.listening,
                        ),
                      ],
                    ),
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
                    const SizedBox(height: AppSpacing.x12),
                    Center(
                      child: Column(
                        children: [
                          Text(
                            'CodeWord · 本地优先背单词',
                            style: AppTheme.mutedCaption(
                              size: 12,
                              context: context,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.x1),
                          Text(
                            '1.1.1',
                            style: AppTheme.mutedCaption(
                              size: 11,
                              context: context,
                            ),
                          ),
                        ],
                      ),
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

enum _AdvancedQuestionType { spelling, listening }

class _AdvancedQuestionTypeRow extends ConsumerWidget {
  final _AdvancedQuestionType type;

  const _AdvancedQuestionTypeRow({required this.type});

  Future<void> _setEnabled(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    try {
      final notifier = ref.read(learningPreferencesProvider.notifier);
      switch (type) {
        case _AdvancedQuestionType.spelling:
          await notifier.setSpellingEnabled(enabled);
        case _AdvancedQuestionType.listening:
          await notifier.setListeningEnabled(enabled);
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('设置保存失败，请稍后重试')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(learningPreferencesProvider);
    final spelling = type == _AdvancedQuestionType.spelling;
    final enabled = spelling
        ? preferences.spellingEnabled
        : preferences.listeningEnabled;
    return _SettingsTile(
      icon: spelling ? Icons.keyboard_rounded : Icons.hearing_rounded,
      title: spelling ? '手动拼写' : '听音选择',
      subtitle: spelling ? '输入完整英文单词' : '听发音后选择正确释义',
      trailing: Switch.adaptive(
        key: ValueKey(
          spelling ? 'spelling-question-toggle' : 'listening-question-toggle',
        ),
        value: enabled,
        onChanged: (value) => _setEnabled(context, ref, value),
      ),
      onTap: () => _setEnabled(context, ref, !enabled),
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
        SizedBox(
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: AppGlassIconButton(
                  tooltip: '返回',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Icons.arrow_back_ios_new_rounded,
                  size: 21,
                  color: AppColors.primary,
                ),
              ),
              Text(
                '设置',
                style: AppTheme.cardTitle(
                  context: context,
                ).copyWith(fontSize: 22),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.x8),
        Text('PREFERENCES', style: AppTheme.sectionLabel(context: context)),
        const SizedBox(height: AppSpacing.x3),
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
    return Text(
      label,
      style: AppTheme.mutedCaption(
        size: 13,
        color: AppColors.primary,
        context: context,
      ).copyWith(fontWeight: FontWeight.w600),
    );
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
          Text(
            cfg.isConfigured ? '已连接' : '未配置',
            style: AppTheme.mutedCaption(
              size: 12,
              color: cfg.isConfigured
                  ? AppColors.success
                  : AppColors.of(context).inkSubtle,
              context: context,
            ).copyWith(fontWeight: FontWeight.w600),
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
          content: const Text('将清空背词记录、统计、收藏、已移除词和阅读历史。AI 配置、当前词书和学习偏好会保留。'),
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
        await ref
            .read(learningSessionProvider.notifier)
            .start(vocabId: ref.read(selectedVocabProvider));
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
      subtitle: '保留 AI 配置、当前词书和学习偏好',
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
        vertical: AppSpacing.x4,
      ),
      child: Row(
        children: [
          _SettingIcon(icon: icon, color: color),
          const SizedBox(width: AppSpacing.x4),
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
                  maxLines: 2,
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
    return SizedBox(
      width: 40,
      height: 40,
      child: Icon(icon, color: color, size: 27),
    );
  }
}
