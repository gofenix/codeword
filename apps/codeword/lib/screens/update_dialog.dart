import 'package:flutter/material.dart';
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
    final theme = AppColors.of(context);
    return AlertDialog(
      backgroundColor: theme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
      title: Row(
        children: [
          Icon(Icons.system_update, color: AppColors.primary),
          const SizedBox(width: AppSpacing.x2),
          const Text('发现新版本'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'v${widget.currentVersion} → v${widget.info.version}',
              style: AppTheme.mutedCaption(size: 13, context: context),
            ),
            const SizedBox(height: AppSpacing.x3),
            if (widget.info.releaseNotes != null &&
                widget.info.releaseNotes!.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.x3),
                decoration: BoxDecoration(
                  color: theme.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: Text(
                  widget.info.releaseNotes!,
                  style: AppTheme.mutedCaption(size: 13, context: context),
                ),
              ),
            const SizedBox(height: AppSpacing.x3),
            if (_downloading)
              Column(
                children: [
                  LinearProgressIndicator(value: _progress),
                  const SizedBox(height: AppSpacing.x2),
                  Text(
                    '下载中… ${(_progress * 100).toStringAsFixed(0)}%',
                    style: AppTheme.mutedCaption(size: 12, context: context),
                  ),
                ],
              )
            else if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: AppColors.danger, fontSize: 13),
              ),
          ],
        ),
      ),
      actions: [
        if (!_downloading)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('稍后', style: TextStyle(color: theme.inkMuted)),
          ),
        if (!_downloading)
          FilledButton(
            onPressed: _download,
            child: const Text('立即更新'),
          ),
      ],
    );
  }
}
