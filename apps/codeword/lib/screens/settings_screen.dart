import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lib_ui/lib_ui.dart';

import '../services/storage_path.dart';
import '../state/llm_config.dart';
import 'ai_settings_screen.dart';

/// 设置 — profile, preferences, AI config and local-data info.
///
/// The library/catalog moved to the 发现 tab; this screen is intentionally
/// smaller and focused on configuration.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            Text('设置', style: AppTheme.screenHeader(context: context)),
            const SizedBox(height: AppSpacing.x5),
            const _ProfileCard(),
            const SizedBox(height: AppSpacing.x5),
            const _SectionLabel('学习'),
            const SizedBox(height: AppSpacing.x3),
            const _DailyGoalRow(),
            const SizedBox(height: AppSpacing.x2),
            const _AccentRow(),
            const SizedBox(height: AppSpacing.x5),
            const _SectionLabel('AI 与数据'),
            const SizedBox(height: AppSpacing.x3),
            const _AiSettingsRow(),
            const SizedBox(height: AppSpacing.x2),
            const _StorageRow(),
            const SizedBox(height: AppSpacing.x5),
            const _SectionLabel('关于'),
            const SizedBox(height: AppSpacing.x3),
            const _AboutRow(),
            const SizedBox(height: AppSpacing.x4),
          ],
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.x5),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Text(
              'C',
              style: AppTheme.wordDisplay(
                size: 26,
                color: AppColors.onPrimary,
                weight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '极客',
                  style: AppTheme.cardTitle(
                    context: context,
                  ).copyWith(fontSize: 17),
                ),
                const SizedBox(height: 2),
                Text(
                  '本地用户 · 无需登录',
                  style: AppTheme.mutedCaption(context: context),
                ),
              ],
            ),
          ),
          PillTag(label: '已激活', color: AppColors.success, icon: Icons.verified),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: AppTheme.sectionLabel(context: context));
  }
}

class _DailyGoalRow extends StatelessWidget {
  const _DailyGoalRow();

  @override
  Widget build(BuildContext context) {
    return const _SettingRow(
      icon: Icons.tune,
      title: '每日新词数',
      subtitle: '12 词',
      color: AppColors.warning,
    );
  }
}

class _AccentRow extends StatelessWidget {
  const _AccentRow();

  @override
  Widget build(BuildContext context) {
    return const _SettingRow(
      icon: Icons.volume_up_outlined,
      title: '发音',
      subtitle: '美音 · 来自有道',
      color: AppColors.primary,
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
        : 'OpenAI 兼容 · Base URL / Key / Model';
    return AppCard(
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const AiSettingsScreen())),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x4,
        vertical: AppSpacing.x3,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cfg.isConfigured
                  ? AppColors.primary.withValues(alpha: 0.12)
                  : AppColors.of(context).inkSubtle.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Icon(
              cfg.isConfigured ? Icons.bolt : Icons.bolt_outlined,
              color: cfg.isConfigured
                  ? AppColors.primary
                  : AppColors.of(context).inkMuted,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('AI 接入', style: AppTheme.rowTitle(context: context)),
                    if (cfg.isConfigured) ...[
                      const SizedBox(width: AppSpacing.x1_5),
                      const PillTag(
                        label: '已配置',
                        color: AppColors.success,
                        icon: Icons.check,
                      ),
                    ],
                  ],
                ),
                Text(
                  subtitle,
                  style: AppTheme.code(size: 11, context: context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            color: AppColors.of(context).inkSubtle,
            size: 20,
          ),
        ],
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow();

  @override
  Widget build(BuildContext context) {
    return const _SettingRow(
      icon: Icons.info_outline,
      title: '关于',
      subtitle: 'CodeWord · 本地优先背单词',
      color: AppColors.inkMuted,
    );
  }
}

class _StorageRow extends StatefulWidget {
  const _StorageRow();

  @override
  State<_StorageRow> createState() => _StorageRowState();
}

class _StorageRowState extends State<_StorageRow> {
  String? _path;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await resolveStoragePath();
    if (!mounted) return;
    setState(() => _path = result ?? '—');
  }

  @override
  Widget build(BuildContext context) {
    return _SettingRow(
      icon: Icons.folder_outlined,
      title: '本地数据',
      subtitle: _path ?? '加载中…',
      color: AppColors.info,
    );
  }
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const _SettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x4,
        vertical: AppSpacing.x3,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: AppSpacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTheme.rowTitle(context: context)),
                Text(
                  subtitle,
                  style: AppTheme.mutedCaption(size: 11, context: context),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
