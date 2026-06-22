import 'dart:async';
import 'dart:convert';

import 'models/vocab_list.dart';
import 'storage_backend.dart';
import 'storage_backend_factory.dart';

/// Local-first persistence for the user's review state and daily
/// activity counts. The actual file vs. localStorage plumbing lives
/// in [StorageBackend]; this class is just the in-memory cache plus
/// the debounced write logic.
class ReviewRepository {
  static ReviewRepository? _instance;
  static Completer<ReviewRepository>? _initCompleter;

  final Map<String, ReviewState> _cache;
  final Map<String, int> _activity;
  final Set<String> _favorites;
  final Set<String> _removed;
  final Map<String, int> _openCounts;
  final Map<String, int> _studyMinutes;
  final StorageBackend _backend;

  Timer? _saveDebounce;
  bool _dirtyReview = false;
  bool _dirtyActivity = false;
  bool _dirtyUserData = false;

  ReviewRepository._(
    this._cache,
    this._activity,
    this._favorites,
    this._removed,
    this._openCounts,
    this._studyMinutes,
    this._backend,
  );

  static Future<ReviewRepository> init() async {
    if (_instance != null) return _instance!;
    if (_initCompleter != null) return _initCompleter!.future;
    _initCompleter = Completer<ReviewRepository>();
    try {
      final backend = createStorageBackend();
      final reviewRaw = await backend.loadReviewState();
      final activityRaw = await backend.loadActivity();
      final userDataRaw = await backend.loadUserData();

      final cache = reviewRaw == null
          ? <String, ReviewState>{}
          : reviewRaw.map(
              (k, v) => MapEntry(
                k,
                ReviewState.fromJson(v as Map<String, dynamic>),
              ),
            );
      final activity = activityRaw == null
          ? <String, int>{}
          : activityRaw.map(
              (k, v) => MapEntry(k, (v as num).toInt()),
            );
      final userData = userDataRaw ?? const <String, dynamic>{};

      _instance = ReviewRepository._(
        cache,
        activity,
        (userData['favorites'] as List?)?.cast<String>().toSet() ?? <String>{},
        (userData['removed'] as List?)?.cast<String>().toSet() ?? <String>{},
        ((userData['openCounts'] as Map?) ?? {}).map(
          (k, v) => MapEntry(k.toString(), (v as num).toInt()),
        ),
        ((userData['studyMinutes'] as Map?) ?? {}).map(
          (k, v) => MapEntry(k.toString(), (v as num).toInt()),
        ),
        backend,
      );
      await _instance!._enforceSchemaVersion();
      _initCompleter!.complete(_instance);
      _initCompleter = null;
      return _instance!;
    } catch (e) {
      _initCompleter!.completeError(e);
      _initCompleter = null;
      rethrow;
    }
  }

  /// Bump whenever the on-disk format changes. Any data without the
  /// current header is treated as legacy and wiped.
  static const int _schemaVersion = 2;

  Future<void> _enforceSchemaVersion() async {
    final raw = await _backend.loadUserData();
    final present = (raw?['schemaVersion'] as int?) ?? 0;
    if (present >= _schemaVersion) return;

    // Legacy data — wipe the three stores and reset in-memory state.
    await _backend.wipeAll();
    _cache.clear();
    _activity.clear();
    _favorites.clear();
    _removed.clear();
    _openCounts.clear();
    _studyMinutes.clear();
    _dirtyReview = false;
    _dirtyActivity = false;
    _dirtyUserData = false;
    // Write a fresh user-data store carrying the new schemaVersion header.
    await _saveUserData();
  }

  static ReviewRepository get instance {
    if (_instance == null) {
      throw StateError('ReviewRepository not initialized. Call init() first.');
    }
    return _instance!;
  }

  // --- Per-word review state (SM-2) -------------------------------

  ReviewState? get(String wordId) => _cache[wordId];

  Future<void> put(String wordId, ReviewState state) async {
    _cache[wordId] = state;
    _dirtyReview = true;
    _scheduleSave();
  }

  Map<String, ReviewState> get all => Map.unmodifiable(_cache);

  int get totalLearned =>
      _cache.values.where((s) => s.repetitions >= 1).length;

  int totalDue(DateTime now) =>
      _cache.values.where((s) => s.dueAt != null && !s.dueAt!.isAfter(now)).length;

  // --- Daily activity (review count for streak / heatmap) --------

  Map<String, int> get activity => Map.unmodifiable(_activity);

  Future<void> recordActivity(DateTime when) async {
    final key = _dateKey(when);
    _activity[key] = (_activity[key] ?? 0) + 1;
    _dirtyActivity = true;
    _scheduleSave();
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

  /// Last 30 days (oldest → today) of review counts.
  List<int> last30Days({DateTime? now}) {
    final today = _dateOnly(now ?? DateTime.now());
    return List<int>.generate(30, (i) {
      final day = today.subtract(Duration(days: 29 - i));
      return _activity[_dateKey(day)] ?? 0;
    });
  }

  /// Last 30 days of study minutes (used by the chart).
  List<int> last30DaysMinutes({DateTime? now}) {
    final today = _dateOnly(now ?? DateTime.now());
    return List<int>.generate(30, (i) {
      final day = today.subtract(Duration(days: 29 - i));
      return _studyMinutes[_dateKey(day)] ?? 0;
    });
  }

  /// Last 90 days of activity, used by streak schedule (boolean per day).
  List<bool> last90DaysActivity({DateTime? now}) {
    final today = _dateOnly(now ?? DateTime.now());
    return List<bool>.generate(90, (i) {
      final day = today.subtract(Duration(days: 89 - i));
      return (_activity[_dateKey(day)] ?? 0) > 0;
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

  // --- User data: favorites / removed / open count / minutes -----

  Set<String> get favorites => Set.unmodifiable(_favorites);
  Set<String> get removed => Set.unmodifiable(_removed);

  int openCountOn(DateTime when) => _openCounts[_dateKey(when)] ?? 0;
  int studyMinutesOn(DateTime when) => _studyMinutes[_dateKey(when)] ?? 0;

  /// Total study minutes across all days (for cumulative stats).
  int get totalStudyMinutes =>
      _studyMinutes.values.fold(0, (a, b) => a + b);

  Future<void> recordOpen(DateTime when) async {
    final key = _dateKey(when);
    _openCounts[key] = (_openCounts[key] ?? 0) + 1;
    _dirtyUserData = true;
    _scheduleSave();
  }

  Future<void> addStudyMinutes(DateTime when, int minutes) async {
    if (minutes <= 0) return;
    final key = _dateKey(when);
    _studyMinutes[key] = (_studyMinutes[key] ?? 0) + minutes;
    _dirtyUserData = true;
    _scheduleSave();
  }

  Future<bool> toggleFavorite(String wordId) async {
    if (_favorites.contains(wordId)) {
      _favorites.remove(wordId);
    } else {
      _favorites.add(wordId);
    }
    _dirtyUserData = true;
    _scheduleSave();
    return _favorites.contains(wordId);
  }

  Future<void> markRemoved(String wordId) async {
    _removed.add(wordId);
    _dirtyUserData = true;
    _scheduleSave();
  }

  // --- Debounced save -----------------------------------------------

  /// Schedule a batched save. Multiple mutations within 300ms coalesce
  /// into a single write. Call [flush] to force immediate write.
  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 300), _flushInternal);
  }

  /// Force-write any pending dirty state immediately.
  Future<void> flush() async {
    _saveDebounce?.cancel();
    _saveDebounce = null;
    await _flushInternal();
  }

  Future<void> _flushInternal() async {
    final doReview = _dirtyReview;
    _dirtyReview = false;
    final doActivity = _dirtyActivity;
    _dirtyActivity = false;
    final doUserData = _dirtyUserData;
    _dirtyUserData = false;

    if (doReview) {
      final json = _cache.map((k, v) => MapEntry(k, v.toJson()));
      await _backend.saveReviewState(Map<String, dynamic>.from(json));
    }
    if (doActivity) {
      await _backend.saveActivity(Map<String, dynamic>.from(_activity));
    }
    if (doUserData) {
      await _saveUserData();
    }
  }

  Future<void> _saveUserData() async {
    final json = <String, dynamic>{
      'schemaVersion': _schemaVersion,
      'favorites': _favorites.toList(),
      'removed': _removed.toList(),
      'openCounts': _openCounts,
      'studyMinutes': _studyMinutes,
    };
    await _backend.saveUserData(json);
  }

  // --- date helpers ----------------------------------------------

  static String _dateKey(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';

  static DateTime _dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);
}
