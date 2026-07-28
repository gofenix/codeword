import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:lib_ui/lib_ui.dart';

import '../services/update_service.dart';

/// Shows the latest release notes and lets the user download + install
/// the APK in-place. Call [show] to present it.
class UpdateDialog extends StatefulWidget {
  final AppUpdateInfo info;
  final String currentVersion;

  const UpdateDialog({
    super.key,
    required this.info,
    required this.currentVersion,
  });

  static Future<void> show(
    BuildContext context, {
    required AppUpdateInfo info,
    required String currentVersion,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(info: info, currentVersion: currentVersion),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _downloading = false;
  double _progress = 0;
  String? _error;

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
    });
    final ok = await UpdateService.downloadAndInstall(
      widget.info,
      onProgress: (received, total) {
        if (total > 0 && mounted) {
          setState(() => _progress = received / total);
        }
      },
    );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _downloading = false;
        _error = '下载失败，请稍后重试或前往 GitHub 手动下载';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final notes = widget.info.releaseNotes?.trim();

    return Dialog(
      backgroundColor: palette.surface,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x6,
        vertical: AppSpacing.x8,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.xl),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, palette),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.x6,
                  AppSpacing.x4,
                  AppSpacing.x6,
                  AppSpacing.x2,
                ),
                child: (notes != null && notes.isNotEmpty)
                    ? _MarkdownNotes(data: notes)
                    : Text(
                        '本次更新包含若干改进与修复。',
                        style: AppTheme.mutedCaption(size: 14, context: context),
                      ),
              ),
            ),
            _footer(context, palette),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, AppPalette palette) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.x6,
        AppSpacing.x6,
        AppSpacing.x6,
        AppSpacing.x4,
      ),
      decoration: BoxDecoration(
        gradient: AppMaterials.bronze,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(AppRadii.xl),
          topRight: Radius.circular(AppRadii.xl),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.rocket_launch_rounded,
              color: AppColors.onPrimary, size: 26),
          const SizedBox(width: AppSpacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '发现新版本',
                  style: TextStyle(
                    color: AppColors.onPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: AppSpacing.x1),
                Text(
                  'v${widget.currentVersion}  →  v${widget.info.version}',
                  style: TextStyle(
                    color: AppColors.onPrimary.withValues(alpha: 0.85),
                    fontSize: 13,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context, AppPalette palette) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.x6,
        AppSpacing.x3,
        AppSpacing.x6,
        AppSpacing.x6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_downloading) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.pill),
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 6,
                backgroundColor: palette.surfaceMuted,
                valueColor:
                    const AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
            const SizedBox(height: AppSpacing.x2),
            Text(
              '下载中… ${(_progress * 100).toStringAsFixed(0)}%',
              textAlign: TextAlign.center,
              style: AppTheme.mutedCaption(size: 12, context: context),
            ),
          ] else ...[
            if (_error != null) ...[
              Text(
                _error!,
                style: const TextStyle(color: AppColors.danger, fontSize: 13),
              ),
              const SizedBox(height: AppSpacing.x3),
            ],
            EditorialPrimaryButton(
              onPressed: _download,
              icon: const Icon(Icons.system_update_rounded),
              label: const Text('立即更新'),
            ),
            const SizedBox(height: AppSpacing.x2),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                '稍后再说',
                style: TextStyle(color: palette.inkMuted),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Renders GitHub release notes (Markdown) with the app's editorial
/// typography so headings, lists and inline code read cleanly instead
/// of showing raw `#`/`-`/`*` markers.
class _MarkdownNotes extends StatelessWidget {
  final String data;

  const _MarkdownNotes({required this.data});

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final body = AppTheme.mutedCaption(size: 14, context: context)
        .copyWith(height: 1.5, color: palette.ink);
    return MarkdownBody(
      data: data,
      shrinkWrap: true,
      styleSheet: MarkdownStyleSheet(
        p: body,
        h1: AppTheme.cardTitle(context: context).copyWith(fontSize: 18),
        h2: AppTheme.cardTitle(context: context).copyWith(fontSize: 16),
        h3: AppTheme.cardTitle(context: context).copyWith(fontSize: 15),
        listBullet: body,
        strong: body.copyWith(fontWeight: FontWeight.w700),
        em: body.copyWith(fontStyle: FontStyle.italic),
        a: body.copyWith(
          color: AppColors.primary,
          decoration: TextDecoration.underline,
        ),
        code: AppTheme.code(size: 13, context: context).copyWith(
          backgroundColor: palette.surfaceMuted,
        ),
        codeblockDecoration: BoxDecoration(
          color: palette.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        blockquoteDecoration: BoxDecoration(
          color: palette.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        h1Padding: const EdgeInsets.only(top: AppSpacing.x3, bottom: AppSpacing.x1),
        h2Padding: const EdgeInsets.only(top: AppSpacing.x3, bottom: AppSpacing.x1),
        blockSpacing: AppSpacing.x2,
      ),
    );
  }
}
