import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models/vocab_list.dart';

/// Local-first persistence for the user's review state and daily
/// activity counts. Two files in the app documents directory:
///   - codeword_review_state.json  (per-word SM-2 state)
///   - codeword_activity.json      (per-day review count for heatmap/streak)
///
/// Everything stays on disk; nothing is synced anywhere.
class ReviewRepository {
  static ReviewRepository? _instance;

  final Map<String, ReviewState> _cache;
  final Map<String, int> _activity;
  late final String _filePath;
  late final String _activityFilePath;
  bool _loaded = false;

  ReviewRepository._(this._cache, this._activity);

  static Future<ReviewRepository> init() async {
    if (_instance != null) return _instance!;
    final dir = await getApplicationDocumentsDirectory();
    final filePath = p.join(dir.path, 'codeword_review_state.json');
    final activityPath = p.join(dir.path, 'codeword_activity.json');
    final cache = await _loadFromFile(filePath);
    final activity = await _loadActivityFromFile(activityPath);
    _instance = ReviewRepository._(cache, activity);
    _instance!._filePath = filePath;
    _instance!._activityFilePath = activityPath;
    _instance!._loaded = true;
    return _instance!;
  }

  static ReviewRepository get instance {
    if (_instance == null) {
      throw StateError('ReviewRepository not initialized. Call init() first.');
    }
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

  static Future<Map<String, int>> _loadActivityFromFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return {};
      final raw = await file.readAsString();
      if (raw.isEmpty) return {};
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, (v as num).toInt()));
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

  Future<void> _saveActivity() async {
    final file = File(_activityFilePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(_activity));
  }

  ReviewState? get(String wordId) => _cache[wordId];

  Future<void> put(String wordId, ReviewState state) async {
    _cache[wordId] = state;
    await _save();
  }

  Map<String, ReviewState> get all => Map.unmodifiable(_cache);

  int get totalLearned =>
      _cache.values.where((s) => s.repetitions >= 1).length;

  int totalDue(DateTime now) =>
      _cache.values.where((s) => s.dueAt != null && !s.dueAt!.isAfter(now)).length;

  // --- Daily activity (for streak / heatmap) -----------------------

  Map<String, int> get activity => Map.unmodifiable(_activity);

  Future<void> recordActivity(DateTime when) async {
    final key = _dateKey(when);
    _activity[key] = (_activity[key] ?? 0) + 1;
    await _saveActivity();
  }

  int activityOn(DateTime when) => _activity[_dateKey(when)] ?? 0;

  /// Last 7 days (oldest → today) of review counts.
  /// Index 6 is today, index 0 is 6 days ago.
  List<int> last7Days({DateTime? now}) {
    final today = _dateOnly(now ?? DateTime.now());
    return List<int>.generate(7, (i) {
      final day = today.subtract(Duration(days: 6 - i));
      return _activity[_dateKey(day)] ?? 0;
    });
  }

  /// Consecutive days, counting back from today (or yesterday if today has
  /// no activity yet — gives the user the full day to start). Returns 0
  /// if no activity on either day.
  int streakDays({DateTime? now}) {
    final today = _dateOnly(now ?? DateTime.now());
    var day = today;
    if (activityOn(day) == 0) {
      day = day.subtract(const Duration(days: 1));
      if (activityOn(day) == 0) return 0;
    }
    var n = 0;
    while (activityOn(day) > 0) {
      n++;
      day = day.subtract(const Duration(days: 1));
    }
    return n;
  }

  static String _dateKey(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';

  static DateTime _dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);
}
