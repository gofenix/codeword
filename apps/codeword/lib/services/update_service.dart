import 'dart:convert';
import 'dart:io';
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

  /// Returns the latest release info, or null if the check failed.
  static Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      final resp = await http
          .get(
            Uri.parse('$_apiBase/releases/latest'),
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
      // Download via browser_download_url. Each version's APK has a unique
      // filename (codeword-v<version>.apk), so the CDN URL is unique per
      // release and never serves a stale cached build.
      final req = http.Request('GET', Uri.parse(url));
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
      // Verify the downloaded file matches the expected size from GitHub.
      // This catches stale CDN caches that serve an older APK with the same name.
      final actualSize = file.lengthSync();
      if (info.apkSize != null) {
        final diff = (actualSize - info.apkSize!).abs();
        if (diff > info.apkSize! * 0.02) {
          return const DownloadResult(
            success: false,
            error: '下载的文件不完整，可能是网络缓存问题，请重试',
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
