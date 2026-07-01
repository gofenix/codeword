import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

enum TtsCacheSource { cached, fetched, shared }

class TtsCacheEntry {
  final File file;
  final TtsCacheSource source;

  const TtsCacheEntry(this.file, this.source);
}

/// On-disk TTS cache with LRU eviction and in-flight request dedup.
///
/// Files live at `<cacheDir>/<sha1(text|lang)>.mp3`. LRU is tracked via
/// file last-modified time; total size is capped at [maxBytes] (100 MB).
class TtsCache {
  static const int maxBytes = 100 * 1024 * 1024;

  final Directory _dir;
  final Map<String, Future<TtsCacheEntry?>> _inFlight = {};
  Future<void>? _dirReady;

  TtsCache(this._dir);

  String key(String text, String lang) {
    return sha1.convert(utf8.encode('$text|$lang')).toString();
  }

  File _fileFor(String text, String lang) {
    return File(p.join(_dir.path, '${key(text, lang)}.mp3'));
  }

  Future<void> ensureReady() async {
    if (_dirReady != null) return _dirReady;
    final c = Completer<void>();
    _dirReady = c.future;
    try {
      if (!await _dir.exists()) {
        await _dir.create(recursive: true);
      }
      c.complete();
    } catch (e, st) {
      _dirReady = null;
      c.completeError(e, st);
    }
    return _dirReady;
  }

  Future<File?> get(String text, String lang) async {
    try {
      await ensureReady();
      final f = _fileFor(text, lang);
      if (!await f.exists()) return null;
      final len = await f.length();
      if (len == 0) {
        await f.delete();
        return null;
      }
      await f.setLastModified(DateTime.now());
      return f;
    } catch (_) {
      return null;
    }
  }

  Future<File> put(String text, String lang, List<int> bytes) async {
    await ensureReady();
    final f = _fileFor(text, lang);
    await f.writeAsBytes(bytes);
    await _evictIfNeeded();
    return f;
  }

  /// Return a cached file or await a single shared [fetch] for this key.
  Future<File?> getOrFetch(
    String text,
    String lang,
    Future<List<int>?> Function() fetch,
  ) async {
    final entry = await getOrFetchEntry(text, lang, fetch);
    return entry?.file;
  }

  /// Return a cached file or fetch it, preserving where the result came from.
  Future<TtsCacheEntry?> getOrFetchEntry(
    String text,
    String lang,
    Future<List<int>?> Function() fetch,
  ) async {
    final k = key(text, lang);
    final pending = _inFlight[k];
    if (pending != null) {
      final entry = await pending;
      if (entry == null) return null;
      return TtsCacheEntry(entry.file, TtsCacheSource.shared);
    }

    final future = () async {
      try {
        final cached = await get(text, lang);
        if (cached != null) {
          return TtsCacheEntry(cached, TtsCacheSource.cached);
        }

        final bytes = await fetch();
        if (bytes == null || bytes.isEmpty) return null;
        final file = await put(text, lang, bytes);
        return TtsCacheEntry(file, TtsCacheSource.fetched);
      } finally {
        _inFlight.remove(k);
      }
    }();
    _inFlight[k] = future;
    return future;
  }

  Future<void> _evictIfNeeded() async {
    try {
      final entries = <File>[];
      var total = 0;
      await for (final entity in _dir.list()) {
        if (entity is! File || !entity.path.endsWith('.mp3')) continue;
        final len = await entity.length();
        if (len == 0) {
          await entity.delete();
          continue;
        }
        total += len;
        entries.add(entity);
      }
      if (total <= maxBytes) return;

      entries.sort(
        (a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()),
      );
      for (final f in entries) {
        if (total <= maxBytes) break;
        total -= await f.length();
        await f.delete();
      }
    } catch (_) {
      // Best-effort eviction — a full cache is better than a crash.
    }
  }
}
