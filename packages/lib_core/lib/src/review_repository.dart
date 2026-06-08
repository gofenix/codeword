import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models/vocab_list.dart';

class ReviewRepository {
  static ReviewRepository? _instance;

  final Map<String, ReviewState> _cache;
  late final String _filePath;
  bool _loaded = false;

  ReviewRepository._(this._cache);

  static Future<ReviewRepository> init() async {
    if (_instance != null) return _instance!;
    final dir = await getApplicationDocumentsDirectory();
    final filePath = p.join(dir.path, 'codeword_review_state.json');
    final cache = await _loadFromFile(filePath);
    _instance = ReviewRepository._(cache);
    _instance!._filePath = filePath;
    _instance!._loaded = true;
    return _instance!;
  }

  static ReviewRepository get instance {
    if (_instance == null) throw StateError('ReviewRepository not initialized. Call init() first.');
    return _instance!;
  }

  static Future<Map<String, ReviewState>> _loadFromFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return {};
      final raw = await file.readAsString();
      if (raw.isEmpty) return {};
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, ReviewState.fromJson(v as Map<String, dynamic>)));
    } catch (_) {
      return {};
    }
  }

  Future<void> _save() async {
    final json = _cache.map((k, v) => MapEntry(k, v.toJson()));
    final file = File(_filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(json));
  }

  ReviewState? get(String wordId) => _cache[wordId];

  Future<void> put(String wordId, ReviewState state) async {
    _cache[wordId] = state;
    await _save();
  }

  Map<String, ReviewState> get all => Map.unmodifiable(_cache);

  int get totalLearned => _cache.values.where((s) => s.repetitions >= 1).length;

  int totalDue(DateTime now) =>
      _cache.values.where((s) => s.dueAt != null && !s.dueAt!.isAfter(now)).length;
}
