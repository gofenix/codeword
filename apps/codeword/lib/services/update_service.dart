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
  final String? releaseNotes;
  final String? htmlUrl;

  const AppUpdateInfo({
    required this.version,
    this.apkUrl,
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
      for (final a in assets) {
        final name = (a['name'] as String?) ?? '';
        if (name.endsWith('.apk')) {
          apkUrl = a['browser_download_url'] as String?;
          break;
        }
      }
      return AppUpdateInfo(
        version: version,
        apkUrl: apkUrl,
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
  /// install intent. Returns true on success.
  static Future<bool> downloadAndInstall(
    AppUpdateInfo info, {
    void Function(int received, int total)? onProgress,
  }) async {
    final url = info.apkUrl;
    if (url == null) return false;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/codeword-update.apk');
      if (file.existsSync()) file.deleteSync();
      // Append timestamp to bypass any CDN / network cache that may serve
      // a stale APK (e.g. an older version with the same filename).
      final sep = url.contains('?') ? '&' : '?';
      final cacheBustUrl = '$url${sep}t=${DateTime.now().millisecondsSinceEpoch}';
      final req = http.Request('GET', Uri.parse(cacheBustUrl));
      req.headers['Cache-Control'] = 'no-cache';
      final resp = await req.send();
      if (resp.statusCode != 200) return false;
      final total = resp.contentLength ?? 0;
      var received = 0;
      final sink = file.openWrite();
      await resp.stream.listen((chunk) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }).asFuture();
      await sink.close();
      // Guard against truncated / cached responses: a real APK is ~60MB.
      if (file.lengthSync() < 10 * 1024 * 1024) return false;
      final result = await OpenFilex.open(file.path);
      return result.type == ResultType.done;
    } catch (_) {
      return false;
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
