import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../models/saved_article.dart';

/// Simple persistent store for generated reading articles.
///
/// Saves up to [maxArticles] entries to `codeword_articles.json` in the
/// app documents directory. Uses atomic write (write to .tmp then rename).
class ArticleRepository {
  static const maxArticles = 20;
  static const _fileName = 'codeword_articles.json';

  static ArticleRepository? _instance;
  static ArticleRepository get instance => _instance ??= ArticleRepository._();
  ArticleRepository._();

  List<SavedArticle> _cache = const [];
  bool _loaded = false;
  Future<void> _operationQueue = Future<void>.value();
  int _revision = 0;

  int get revision => _revision;

  Future<String> get _path async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, _fileName);
  }

  Future<List<SavedArticle>> load() {
    return _enqueue(() async {
      final loaded = await _loadUnlocked();
      return List<SavedArticle>.unmodifiable(loaded);
    });
  }

  Future<List<SavedArticle>> _loadUnlocked() async {
    if (_loaded) return List.unmodifiable(_cache);
    final revisionAtStart = _revision;
    var loaded = const <SavedArticle>[];
    final path = await _path;
    final file = File(path);
    if (await file.exists()) {
      final content = await file.readAsString();
      if (content.trim().isNotEmpty) {
        loaded = SavedArticle.listFromJson(content);
      }
    }
    if (revisionAtStart != _revision) return List.unmodifiable(_cache);
    _cache = loaded;
    _loaded = true;
    return List.unmodifiable(_cache);
  }

  Future<bool> save(SavedArticle article, {int? expectedRevision}) {
    return _enqueue(() async {
      List<SavedArticle>? previous;
      try {
        if (expectedRevision != null && expectedRevision != _revision) {
          return false;
        }
        final current = await _loadUnlocked();
        if (expectedRevision != null && expectedRevision != _revision) {
          return false;
        }
        previous = _cache;
        _cache = [
          article,
          ...current.where((saved) => saved.id != article.id),
        ].take(maxArticles).toList();
        await _flush();
        return true;
      } catch (_) {
        if (previous != null) _cache = previous;
        return false;
      }
    });
  }

  Future<void> delete(String id) {
    return _enqueue(() async {
      List<SavedArticle>? previous;
      try {
        final current = await _loadUnlocked();
        previous = _cache;
        _cache = current.where((a) => a.id != id).toList();
        await _flush();
      } catch (_) {
        if (previous != null) _cache = previous;
        return;
      }
    });
  }

  Future<void> clear() {
    // Invalidate article generations that started before this request.
    _revision++;
    return _enqueue(() async {
      final previous = _cache;
      final wasLoaded = _loaded;
      _cache = const [];
      _loaded = true;
      try {
        await _flush();
      } catch (_) {
        _cache = previous;
        _loaded = wasLoaded;
        rethrow;
      }
    });
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _operationQueue.then((_) => operation());
    _operationQueue = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
  }

  Future<void> _flush() async {
    final path = await _path;
    final tmpPath = '$path.tmp';
    final file = File(tmpPath);
    final payload = SavedArticle.listToJson(_cache);
    await file.writeAsString(payload, flush: true);
    await file.rename(path);
  }
}

final articleRepositoryRevisionProvider = StateProvider<int>(
  (ref) => ArticleRepository.instance.revision,
);
