import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../services/update_service.dart';

/// iOS 风格的更新弹窗：毛玻璃底、居中、圆角 18、扁平按钮。
/// 标题/版本号/下载链接由弹窗本身提供，release notes 只渲染更新内容。
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
    final result = await UpdateService.downloadAndInstall(
      widget.info,
      onProgress: (received, total) {
        if (total > 0 && mounted) {
          setState(() => _progress = received / total);
        }
      },
    );
    if (!mounted) return;
    if (!result.success) {
      setState(() {
        _downloading = false;
        _error = result.error ?? '下载失败，请重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final notes = widget.info.releaseNotes?.trim();
    final isDark = MediaQuery.of(context).platformBrightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);
    const iosBlue = Color(0xFF007AFF);
    const dividerColor = Color(0x338E8E93);

    return Center(
      child: Material(
        // Provide a Material ancestor so bare Text widgets don't render
        // with the yellow "missing Material" double-underline.
        type: MaterialType.transparency,
        child: Container(
          width: 300,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(18),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部：图标 + 标题 + 版本号
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 4),
                child: Column(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF007AFF), Color(0xFF5856D6)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        CupertinoIcons.arrow_down_circle_fill,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '发现新版本',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'v${widget.currentVersion}  →  v${widget.info.version}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark ? Colors.white54 : Colors.black45,
                        fontSize: 13,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // release notes（只渲染更新内容，不含标题/版本/链接）
              if (notes != null && notes.isNotEmpty)
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                    child: _MarkdownNotes(data: notes, isDark: isDark),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Text(
                    '本次更新包含若干改进与修复。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.black45,
                      fontSize: 13,
                    ),
                  ),
                ),
              // 错误提示
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFF3B30),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              // 下载进度 / 按钮区
              if (_downloading)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: _progress,
                          minHeight: 4,
                          backgroundColor: isDark
                              ? Colors.white12
                              : Colors.black12,
                          valueColor: const AlwaysStoppedAnimation(iosBlue),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '正在下载… ${(_progress * 100).toStringAsFixed(0)}%',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.black45,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                )
              else
                _buildActions(dividerColor, iosBlue),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActions(Color dividerColor, Color iosBlue) {
    final hasError = _error != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(height: 0.5, color: dividerColor),
        Row(
          children: [
            Expanded(
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 13),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  hasError ? '关闭' : '稍后',
                  style: TextStyle(
                    color: iosBlue,
                    fontSize: 17,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
            Container(width: 0.5, height: 46, color: dividerColor),
            Expanded(
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 13),
                onPressed: hasError ? _copyDownloadLink : _download,
                child: Text(
                  hasError ? '复制链接' : '立即更新',
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

  Future<void> _copyDownloadLink() async {
    final url = widget.info.apkUrl;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    setState(() {
      _error = '下载链接已复制，请在浏览器中打开下载安装。';
    });
  }
}

/// 渲染 GitHub release notes（Markdown），配色适配弹窗。
/// 只渲染更新内容本身，不渲染标题/版本号/下载链接。
class _MarkdownNotes extends StatelessWidget {
  final String data;
  final bool isDark;

  const _MarkdownNotes({required this.data, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : Colors.black;
    final body = TextStyle(color: textColor, fontSize: 13, height: 1.55);
    return MarkdownBody(
      data: data,
      shrinkWrap: true,
      styleSheet: MarkdownStyleSheet(
        p: body,
        h1: body.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
        h2: body.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
        h3: body.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
        listBullet: body,
        strong: body.copyWith(fontWeight: FontWeight.w600),
        em: body.copyWith(fontStyle: FontStyle.italic),
        a: body.copyWith(
          color: const Color(0xFF007AFF),
          decoration: TextDecoration.none,
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
        h1Padding: const EdgeInsets.only(top: 6, bottom: 3),
        h2Padding: const EdgeInsets.only(top: 6, bottom: 3),
        blockSpacing: 5,
      ),
    );
  }
}
