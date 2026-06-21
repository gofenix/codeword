import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// On-disk cache for Youdao audio, keyed by sha1(text|lang).
///
/// Files live at `<appDocs>/tts_cache/<hash>.mp3` and are kept under
/// 100 MB total (LRU eviction by mtime). Per-key in-flight dedup
/// ensures simultaneous speak() calls for the same word don't trigger
/// duplicate downloads.
class TtsCache {
  TtsCache._();

  static const int maxBytes = 100 * 1024 * 1024;
  static final Map<String, Future<File?>> _inflight = {};

  static String _key(String text, String lang) =>
      sha1.convert(utf8.encode('$text|$lang')).toString();

  /// Returns the cached file, or null if not cached.
  /// Two simultaneous calls for the same (text, lang) share one future.
  static Future<File?> get(String text, String lang) {
    final key = _key(text, lang);
    final existing = _inflight[key];
    if (existing != null) return existing;
    final fut = _doGet(key);
    _inflight[key] = fut;
    fut.whenComplete(() => _inflight.remove(key));
    return fut;
  }

  static Future<File?> _doGet(String key) async {
    final dir = await _cacheDir();
    final f = File(p.join(dir.path, '$key.mp3'));
    return f.existsSync() ? f : null;
  }

  /// Persist [bytes] for the given key. Returns the file.
  static Future<File> put(
    String text,
    String lang,
    List<int> bytes,
  ) async {
    final key = _key(text, lang);
    final dir = await _cacheDir();
    final f = File(p.join(dir.path, '$key.mp3'));
    await f.writeAsBytes(bytes, flush: true);
    unawaited(_evictIfNeeded(dir));
    return f;
  }

  /// Total bytes currently on disk.
  static Future<int> totalSize() async {
    final dir = await _cacheDir();
    return dir
        .listSync()
        .whereType<File>()
        .fold<int>(0, (a, f) => a + f.lengthSync());
  }

  /// Wipe the entire cache.
  static Future<void> clear() async {
    final dir = await _cacheDir();
    for (final f in dir.listSync().whereType<File>()) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
  }

  static Future<Directory> _cacheDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'tts_cache'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Evict oldest files (by mtime) until total ≤ [maxBytes].
  static Future<void> _evictIfNeeded(Directory dir) async {
    final files = dir.listSync().whereType<File>().toList();
    var total = files.fold<int>(0, (a, f) => a + f.lengthSync());
    if (total <= maxBytes) return;
    files.sort(
      (a, b) => a.statSync().modified.compareTo(b.statSync().modified),
    );
    for (final f in files) {
      if (total <= maxBytes) break;
      total -= f.lengthSync();
      try {
        f.deleteSync();
      } catch (_) {}
    }
  }
}
