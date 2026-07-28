import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../services/update_service.dart';

/// iOS 风格的更新弹窗：毛玻璃白底、居中、圆角 14、扁平按钮，
/// 符合 Apple Human Interface Guidelines。
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
    return showCupertinoDialog(
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
    final notes = widget.info.releaseNotes?.trim();
    final isDark =
        MediaQuery.of(context).platformBrightness == Brightness.dark;

    final bgColor =
        isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);
    const iosBlue = Color(0xFF007AFF);
    const dividerColor = Color(0x338E8E93);

    return Center(
      child: Container(
        width: 270,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 18, 16, 6),
              child: Text(
                '发现新版本',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // 版本号
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(
                'v${widget.currentVersion}  →  v${widget.info.version}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.white60 : Colors.black54,
                  fontSize: 13,
                ),
              ),
            ),
            // release notes
            if (notes != null && notes.isNotEmpty)
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: _MarkdownNotes(data: notes, isDark: isDark),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  '本次更新包含若干改进与修复。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark ? Colors.white60 : Colors.black54,
                    fontSize: 13,
                  ),
                ),
              ),
            // 错误
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFFF3B30),
                    fontSize: 13,
                  ),
                ),
              ),
            // 下载进度
            if (_downloading)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: _progress,
                        minHeight: 3,
                        backgroundColor:
                            isDark ? Colors.white12 : Colors.black12,
                        valueColor:
                            const AlwaysStoppedAnimation(iosBlue),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '下载中… ${(_progress * 100).toStringAsFixed(0)}%',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            // 按钮区
            if (!_downloading)
              _buildActions(dividerColor, iosBlue),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(Color dividerColor, Color iosBlue) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(height: 0.5, color: dividerColor),
        Row(
          children: [
            Expanded(
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 12),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  '稍后',
                  style: TextStyle(
                    color: iosBlue,
                    fontSize: 17,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
            Container(width: 0.5, height: 44, color: dividerColor),
            Expanded(
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 12),
                onPressed: _download,
                child: Text(
                  '更新',
                  style: TextStyle(
                    color: iosBlue,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 渲染 GitHub release notes（Markdown），配色适配 iOS 弹窗。
class _MarkdownNotes extends StatelessWidget {
  final String data;
  final bool isDark;

  const _MarkdownNotes({required this.data, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : Colors.black;
    final body = TextStyle(color: textColor, fontSize: 13, height: 1.5);
    return MarkdownBody(
      data: data,
      shrinkWrap: true,
      styleSheet: MarkdownStyleSheet(
        p: body,
        h1: body.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
        h2: body.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
        h3: body.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
        listBullet: body,
        strong: body.copyWith(fontWeight: FontWeight.w600),
        em: body.copyWith(fontStyle: FontStyle.italic),
        a: body.copyWith(
          color: const Color(0xFF007AFF),
          decoration: TextDecoration.underline,
        ),
        code: body.copyWith(
          fontFamily: 'monospace',
          fontSize: 12,
          backgroundColor: isDark ? Colors.white12 : Colors.black12,
        ),
        codeblockDecoration: BoxDecoration(
          color: isDark ? Colors.white12 : Colors.black12,
          borderRadius: BorderRadius.circular(4),
        ),
        blockquoteDecoration: BoxDecoration(
          color: isDark ? Colors.white12 : Colors.black12,
          borderRadius: BorderRadius.circular(4),
        ),
        h1Padding: const EdgeInsets.only(top: 8, bottom: 4),
        h2Padding: const EdgeInsets.only(top: 8, bottom: 4),
        blockSpacing: 6,
      ),
    );
  }
}
