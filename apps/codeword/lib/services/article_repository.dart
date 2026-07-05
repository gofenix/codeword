import 'dart:io';

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

  Future<String> get _path async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, _fileName);
  }

  Future<List<SavedArticle>> load() async {
    if (_loaded) return _cache;
    try {
      final path = await _path;
      final file = File(path);
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          _cache = SavedArticle.listFromJson(content);
        }
      }
    } catch (_) {
      _cache = const [];
    }
    _loaded = true;
    return _cache;
  }

  Future<void> save(SavedArticle article) async {
    final current = await load();
    _cache = [article, ...current]
        .take(maxArticles)
        .toList();
    await _flush();
  }

  Future<void> delete(String id) async {
    final current = await load();
    _cache = current.where((a) => a.id != id).toList();
    await _flush();
  }

  Future<void> _flush() async {
    try {
      final path = await _path;
      final tmpPath = '$path.tmp';
      final file = File(tmpPath);
      await file.writeAsString(
        SavedArticle.listToJson(_cache),
        flush: true,
      );
      await file.rename(path);
    } catch (_) {}
  }
}
