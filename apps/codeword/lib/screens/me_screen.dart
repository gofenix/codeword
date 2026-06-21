import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lib_core/lib_core.dart';
import 'package:lib_ui/lib_ui.dart';
import 'package:path_provider/path_provider.dart';

import '../state/learning_session.dart';
import '../state/llm_config.dart';
import 'ai_settings_screen.dart';
import 'learning_session_screen.dart';

class MeScreen extends ConsumerWidget {
  const MeScreen({super.key});

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
          children: const [
            Text(
              '我的',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
                height: 1.2,
              ),
            ),
            SizedBox(height: AppSpacing.x5),
            _ProfileCard(),
            SizedBox(height: AppSpacing.x5),
            // 词库: integrated here as a section, not a tab.
            _SectionLabel('词库'),
            SizedBox(height: AppSpacing.x3),
            _LibraryGrid(),
            SizedBox(height: AppSpacing.x5),
            // Settings + storage info.
            _SectionLabel('设置'),
            SizedBox(height: AppSpacing.x3),
            _AiSettingsRow(),
            SizedBox(height: AppSpacing.x2),
            _DailyGoalRow(),
            SizedBox(height: AppSpacing.x2),
            _AccentRow(),
            SizedBox(height: AppSpacing.x2),
            _AboutRow(),
            SizedBox(height: AppSpacing.x2),
            _StorageRow(),
            SizedBox(height: AppSpacing.x4),
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
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: const Text('🥷', style: TextStyle(fontSize: 24)),
          ),
          const SizedBox(width: AppSpacing.x4),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '极客',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  '本地用户 · 无需登录',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.inkMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          PillTag(
            label: '已激活',
            color: AppColors.success,
            icon: Icons.verified,
          ),
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
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        color: AppColors.inkMuted,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

/// All 371 qwerty-derived lists, grouped by category. Each category
/// renders a small section header and a 2-col grid of vocab cards.
class _LibraryGrid extends ConsumerWidget {
  const _LibraryGrid();

  /// Display order for categories. Anything not in here goes last,
  /// sorted alphabetically.
  static const _priority = [
    '考试英语',
    '编程',
    '青少年英语',
    '语言',
    '词典',
    '专业词汇',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meta = ref.watch(vocabMetaProvider);
    final lists = ref.watch(qwertyCatalogProvider);
    final byCategory = <String, List<VocabList>>{};
    for (final l in lists) {
      byCategory.putIfAbsent(l.category, () => []).add(l);
    }
    final categories = byCategory.keys.toList()
      ..sort((a, b) {
        final ai = _priority.indexOf(a);
        final bi = _priority.indexOf(b);
        if (ai == -1 && bi == -1) return a.compareTo(b);
        if (ai == -1) return 1;
        if (bi == -1) return -1;
        return ai.compareTo(bi);
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final cat in categories) ...[
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.x3, bottom: AppSpacing.x2),
            child: Text(
              '$cat · ${byCategory[cat]!.length}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.inkMuted,
                letterSpacing: 0.6,
              ),
            ),
          ),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AppSpacing.x3,
            crossAxisSpacing: AppSpacing.x3,
            childAspectRatio: 1.6,
            children: [
              for (final l in byCategory[cat]!)
                _LibraryTile(list: l, available: meta.containsKey(l.id)),
            ],
          ),
        ],
      ],
    );
  }
}

class _LibraryTile extends StatelessWidget {
  final VocabList list;
  final bool available;
  const _LibraryTile({required this.list, required this.available});

  Color _color() {
    final h = list.id.hashCode.abs();
    return AppColors.qwertyPalette[h % AppColors.qwertyPalette.length];
  }

  @override
  Widget build(BuildContext context) {
    final color = _color();
    return AppCard(
      onTap: available
          ? () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      LearningSessionScreen(vocabId: list.id),
                ),
              )
          : null,
      padding: const EdgeInsets.all(AppSpacing.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(list.emoji, style: const TextStyle(fontSize: 18)),
              if (available)
                PillTag(
                  label: 'Lv ${list.level}',
                  color: color,
                  variant: PillVariant.soft,
                )
              else
                const PillTag(
                  label: '即将推出',
                  color: AppColors.inkSubtle,
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
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                list.description,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.inkMuted,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );
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
    return _SettingRow(
      icon: Icons.volume_up_outlined,
      title: '发音',
      subtitle: '美音 · 来自有道',
      color: AppColors.qwertyPalette[0],
    );
  }
}

/// AI 接入 — opens AiSettingsScreen. Subtitle reflects whether
/// the user has configured a key.
class _AiSettingsRow extends ConsumerWidget {
  const _AiSettingsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(llmConfigProvider);
    final subtitle = cfg.isConfigured
        ? '${cfg.model} · ${cfg.maskedKey}'
        : 'OpenAI 兼容 · Base URL / Key / Model';
    return AppCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AiSettingsScreen()),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x4,
        vertical: AppSpacing.x3,
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cfg.isConfigured
                  ? AppColors.primary.withValues(alpha: 0.12)
                  : AppColors.inkSubtle.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Icon(
              cfg.isConfigured ? Icons.bolt : Icons.bolt_outlined,
              color: cfg.isConfigured
                  ? AppColors.primary
                  : AppColors.inkMuted,
              size: 18,
            ),
          ),
          const SizedBox(width: AppSpacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'AI 接入',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    if (cfg.isConfigured) ...[
                      const SizedBox(width: 6),
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
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.inkMuted,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            color: AppColors.inkSubtle,
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
      subtitle: 'CodeWord',
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
  bool _writable = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      // Verify it's actually writable (we just stat the dir).
      if (Platform.isMacOS || Platform.isLinux) {
        _writable = await Directory(dir.path).stat().then((_) => true)
            .catchError((_) => false);
      }
      if (mounted) setState(() => _path = dir.path);
    } catch (_) {
      if (mounted) setState(() => _path = '—');
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SettingRow(
      icon: Icons.folder_outlined,
      title: '本地数据',
      subtitle: _path == null
          ? '加载中…'
          : (_writable ? _path! : '$_path (只读)'),
      color: AppColors.primary,
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
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: AppSpacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.inkMuted,
                    fontWeight: FontWeight.w500,
                  ),
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
