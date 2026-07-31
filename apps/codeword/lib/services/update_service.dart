import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show appFlavor;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

/// Information about the latest GitHub release.
class AppUpdateInfo {
  final String version;
  final String? apkUrl;
  final int? apkSize;
  final String? releaseNotes;
  final String? htmlUrl;

  const AppUpdateInfo({
    required this.version,
    this.apkUrl,
    this.apkSize,
    this.releaseNotes,
    this.htmlUrl,
  });
}

/// Checks for and installs app updates from GitHub Releases.
///
/// The repo is hard-coded to `gofenix/codeword`; the latest release's
/// tag is expected to look like `v1.2.3` and its assets must include an
/// `.apk` file.
class UpdateService {
  static const String _repo = 'gofenix/codeword';
  static const String _apiBase = 'https://api.github.com/repos/$_repo';

  /// GitHub APK updates are only available in the Android `github` channel.
  ///
  /// Unflavoured Android builds keep the historical GitHub behaviour so local
  /// debug/test builds remain backwards compatible. Google Play builds always
  /// use the explicit `play` flavour and are denied here as a second line of
  /// defence in addition to their stripped Android manifest.
  static bool get supportsInAppUpdate => isInAppUpdateSupported(
    isWeb: kIsWeb,
    platform: defaultTargetPlatform,
    flavor: appFlavor,
  );

  @visibleForTesting
  static bool isInAppUpdateSupported({
    required bool isWeb,
    required TargetPlatform platform,
    required String? flavor,
  }) {
    return !isWeb && platform == TargetPlatform.android && flavor != 'play';
  }

  /// Returns the latest release info, or null if the check failed.
  static Future<AppUpdateInfo?> checkForUpdate() async {
    if (!supportsInAppUpdate) return null;
    try {
      // Append a timestamp to bust any intermediate (CDN / carrier) cache
      // that might serve a stale "latest" release.
      final uri = Uri.parse('$_apiBase/releases/latest').replace(
        queryParameters: {'t': '${DateTime.now().millisecondsSinceEpoch}'},
      );
      final resp = await http
          .get(
            uri,
            headers: {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final tag = (json['tag_name'] as String?) ?? '';
      final version = tag.startsWith('v') ? tag.substring(1) : tag;
      final htmlUrl = json['html_url'] as String?;
      final body = json['body'] as String?;
      final assets = (json['assets'] as List?) ?? const [];
      String? apkUrl;
      int? apkSize;
      for (final a in assets) {
        final name = (a['name'] as String?) ?? '';
        if (name.endsWith('.apk')) {
          // Use browser_download_url (not the API asset URL) so downloads
          // are not subject to GitHub API rate limits (60/hr unauthenticated).
          // Each release's APK is named codeword-v<version>.apk, so the URL
          // differs per version and the CDN never serves a stale build.
          apkUrl = a['browser_download_url'] as String?;
          apkSize = (a['size'] as num?)?.toInt();
          break;
        }
      }
      return AppUpdateInfo(
        version: version,
        apkUrl: apkUrl,
        apkSize: apkSize,
        releaseNotes: body,
        htmlUrl: htmlUrl,
      );
    } catch (_) {
      return null;
    }
  }

  /// The currently installed version (e.g. `1.2.3`).
  static Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  /// True if [latest] is newer than the currently installed version.
  static Future<bool> hasUpdate(AppUpdateInfo latest) async {
    final current = await currentVersion();
    return _compareVersions(latest.version, current) > 0;
  }

  /// Downloads the APK to the app support directory and triggers the
  /// install intent. Returns a [DownloadResult] with a specific error
  /// message on failure so the UI can give actionable guidance.
  static Future<DownloadResult> downloadAndInstall(
    AppUpdateInfo info, {
    void Function(int received, int total)? onProgress,
  }) async {
    if (!supportsInAppUpdate) {
      return const DownloadResult(success: false, error: '当前平台不支持应用内安装更新');
    }
    final url = info.apkUrl;
    if (url == null) {
      return const DownloadResult(success: false, error: '未找到下载链接');
    }
    try {
      final dir = await getApplicationSupportDirectory();
      // Name the temp file per version so a stale codeword-update.apk from
      // a previous (possibly failed / cached) download is never reused.
      final file = File('${dir.path}/codeword-${info.version}.apk');
      if (file.existsSync()) file.deleteSync();
      // Append a timestamp to the download URL to bust any intermediate
      // (CDN / carrier) cache that might serve a stale APK.
      final downloadUri = Uri.parse(url).replace(
        queryParameters: {'t': '${DateTime.now().millisecondsSinceEpoch}'},
      );
      final req = http.Request('GET', downloadUri);
      req.headers['Cache-Control'] = 'no-cache';
      final resp = await req.send();
      if (resp.statusCode != 200) {
        return DownloadResult(
          success: false,
          error: '下载失败（HTTP ${resp.statusCode}），请检查网络后重试',
        );
      }
      final total = resp.contentLength ?? 0;
      var received = 0;
      final sink = file.openWrite();
      await resp.stream.listen((chunk) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }).asFuture();
      await sink.close();
      // Verify the downloaded file matches the expected size EXACTLY.
      // Previous 2% tolerance allowed a stale (older) APK of nearly-identical
      // size to pass, which is why users saw "已安装更新版本".
      final actualSize = file.lengthSync();
      if (info.apkSize != null) {
        if (actualSize != info.apkSize) {
          return DownloadResult(
            success: false,
            error: '下载的文件大小不符（期望 ${info.apkSize}，实际 $actualSize），可能是网络缓存，请重试',
          );
        }
      } else if (actualSize < 10 * 1024 * 1024) {
        return const DownloadResult(
          success: false,
          error: '下载的文件过小，可能是网络缓存问题，请重试',
        );
      }
      final result = await OpenFilex.open(file.path);
      if (result.type == ResultType.done) {
        return DownloadResult.ok;
      }
      // Install intent didn't launch — most often because the installed
      // app is signed with a different key and Android refuses to upgrade.
      return const DownloadResult(
        success: false,
        error: '无法自动安装。请先卸载旧版本，再点击"复制链接"在浏览器中下载安装',
      );
    } catch (e) {
      return DownloadResult(success: false, error: '下载出错：$e');
    }
  }

  /// Compares two version strings like `1.2.3`. Returns >0 if a > b.
  static int _compareVersions(String a, String b) {
    final pa = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final pb = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x - y;
    }
    return 0;
  }
}

/// Result of a download-and-install attempt.
class DownloadResult {
  final bool success;
  final String? error; // null when success
  const DownloadResult({required this.success, this.error});
  static const ok = DownloadResult(success: true);
}
