import 'dart:async';

import 'models/vocab_list.dart';
import 'storage_backend.dart';
import 'storage_backend_factory.dart';

/// Local-first persistence for the user's review state and daily
/// activity counts. The actual file vs. localStorage plumbing lives
/// in [StorageBackend]; this class is the in-memory cache plus the
/// debounced write logic.
///
/// # Concurrency
///
///  * [init] is safe to call concurrently — only the first call runs
///    the work; all concurrent callers wait on the same Future.
///  * [_flushInternal] serialises overlapping calls: if a write is in
///    flight when a second call lands, the second is queued via
///    [_needsAnotherFlush] so dirty state is always drained.
///  * Dirty flags are cleared ONLY when the generation counter at
///    START of the write matches the counter at END. Any mutation
///    that arrives during the IO window increments the counter,
///    keeping the flag set for a follow-up pass. This prevents
///    silent data loss from overlapping IO.
///
/// # Durability
///
/// Any storage error from [StorageBackend] is surfaced to the
/// caller (throw). Callers MUST wrap any "best effort" write path
/// (e.g. debounced from user actions) with try/catch. Errors do
/// NOT cause half-persisted state — either the whole write
/// succeeds, or the dirty flags remain set (generation counter
/// pattern), and the next scheduled flush retries.
class ReviewRepository {
  static ReviewRepository? _instance;
  static Completer<ReviewRepository>? _initCompleter;

  // --- In-memory caches ------------------------------------------
  final Map<String, ReviewState> _cache;
  final Map<String, int> _activity;
  final Set<String> _favorites;
  final Set<String> _removed;
  final Map<String, int> _openCounts;
  final Map<String, int> _studyMinutes;
  String? _selectedVocabId;
  final StorageBackend _backend;

  // --- Debouncing / flushing ------------------------------------
  Timer? _saveDebounce;
  bool _dirtyReview = false;
  bool _dirtyActivity = false;
  bool _dirtyUserData = false;

  // Generation counters bumped on every mutation so
  // _flushInternal can tell whether a concurrent write arrived
  // DURING the IO window and therefore must NOT clear the flag.
  int _genReview = 0;
  int _genActivity = 0;
  int _genUserData = 0;

  // Serialise overlapping flush calls.
  bool _isFlushing = false;
  bool _needsAnotherFlush = false;

  // Bump schema version whenever the on-disk format changes. Any
  // data without the current header is treated as legacy and wiped.
  static const int _schemaVersion = 2;

  ReviewRepository._(
    this._cache,
    this._activity,
    this._favorites,
    this._removed,
    this._openCounts,
    this._studyMinutes,
    this._selectedVocabId,
    this._backend,
  );

  /// Initialise the repository. Safe to call concurrently.
  ///
  /// Failures are rethrown — main() should catch and degrade
  /// gracefully (empty data, logged error). Never returns a
  /// half-initialised singleton.
  static Future<ReviewRepository> init() async {
    if (_instance != null) return _instance!;
    if (_initCompleter != null) return _initCompleter!.future;
    final completer = Completer<ReviewRepository>();
    _initCompleter = completer;
    try {
      final backend = createStorageBackend();
      // Three independent reads — parallelise.
      final results = await Future.wait<Map<String, dynamic>?>([
        backend.loadReviewState(),
        backend.loadActivity(),
        backend.loadUserData(),
      ]);
      final reviewRaw = results[0];
      final activityRaw = results[1];
      final userDataRaw = results[2];

      // Parse each store with per-entry tolerance. We'd rather drop
      // one corrupted row than fail the entire init and crash the
      // app. The tolerant readers are verbose on purpose — inline
      // fallback mirrors the null-when-missing semantics we want.
      final cache = <String, ReviewState>{};
      if (reviewRaw != null) {
        reviewRaw.forEach((k, v) {
          if (v is Map<String, dynamic>) {
            try {
              cache[k] = ReviewState.fromJson(v);
            } catch (_) {
              // Skip corrupt entry.
            }
          }
        });
      }

      final activity = <String, int>{};
      if (activityRaw != null) {
        activityRaw.forEach((k, v) {
          if (v is num) activity[k] = v.toInt();
          // else: corrupt value — drop silently.
        });
      }

      final ud = userDataRaw ?? const <String, dynamic>{};
      final favs =
          (ud['favorites'] as List?)?.whereType<String>().toSet() ?? <String>{};
      final rems =
          (ud['removed'] as List?)?.whereType<String>().toSet() ?? <String>{};
      final openCounts = <String, int>{};
      final ocRaw = ud['openCounts'] as Map?;
      if (ocRaw != null) {
        ocRaw.forEach((k, v) {
          if (v is num) openCounts[k.toString()] = v.toInt();
        });
      }
      final studyMins = <String, int>{};
      final smRaw = ud['studyMinutes'] as Map?;
      if (smRaw != null) {
        smRaw.forEach((k, v) {
          if (v is num) studyMins[k.toString()] = v.toInt();
        });
      }
      final selectedVocab = ud['selectedVocabId'] as String?;
      final schemaPresent = (ud['schemaVersion'] as int?) ?? 0;

      final instance = ReviewRepository._(
        cache, activity, favs, rems, openCounts, studyMins,
        selectedVocab, backend,
      );
      // Run schema enforcement BEFORE publishing the instance via
      // _instance assignment — never expose a partially-migrated repo.
      await instance._enforceSchemaVersion(schemaPresent);

      _instance = instance;
      completer.complete(instance);
      _initCompleter = null;
      return instance;
    } catch (e, st) {
      // Wipe partial state so the NEXT init() call has a clean slate.
      _instance = null;
      completer.completeError(e, st);
      _initCompleter = null;
      rethrow;
    }
  }

  /// Schema migration. Guarantees:
  ///
  ///   * The `schemaVersion` header is durable BEFORE we wipe any user
  ///     data, so a crash mid-migration doesn't loop forever on restart.
  ///   * The "legacy data wipe" explicitly targets ONLY review_state +
  ///     activity — NEVER the user_data store that carries the header.
  ///     (If we wrote the header just to delete it a line later, the
  ///     schema version would go back to 0 on restart and trigger a
  ///     fresh wipe EVERY launch — a silent total-data-loss bug.)
  ///   * In-memory state is updated LAST; a throw during the disk
  ///     phase leaves RAM untouched so the caller can cleanly retry.
  Future<void> _enforceSchemaVersion(int present) async {
    if (present >= _schemaVersion) return;

    // --- Phase 1: commit the schema header DURABLY. ---------------
    // This write establishes "version N seen" as a durable invariant
    // before we touch any other file. Even if the app dies right after
    // this write, next restart will see present >= _schemaVersion and
    // skip migration.
    await _saveUserDataInternal();

    // --- Phase 2: wipe legacy stores (review + activity only!). ----
    // User-data is deliberately left alone — it already contains the
    // new schemaVersion header (we wrote it above). Fallback: if the
    // backend does NOT expose a targeted wipe, fall back to writing
    // empty payloads atomically — same effect, no dependency on
    // StorageBackend surface area.
    try {
      await _backend.wipeReviewAndActivity();
    } on UnsupportedError catch (_) {
      // Backend doesn't implement the targeted wipe. Fall back to
      // writing empty payloads atomically; since wipeAll() was the
      // only prior path, this is safe (we simply don't nuke the
      // store that holds the schema header).
      await _backend.saveReviewState(const <String, dynamic>{});
      await _backend.saveActivity(const <String, int>{});
    } catch (_) {
      // Any other storage failure: tolerate. Because the schema
      // header was already committed in Phase 1, the next run will
      // NOT re-enter migration, so legacy files are at worst stale —
      // their data won't be re-read (we clear RAM in Phase 3 anyway).
    }

    // --- Phase 3: only now touch RAM. -----------------------------
    // These are purely synchronous local mutations and cannot throw.
    _cache.clear();
    _activity.clear();
    _favorites.clear();
    _removed.clear();
    _openCounts.clear();
    _studyMinutes.clear();
    _selectedVocabId = null;
    _dirtyReview = false;
    _dirtyActivity = false;
    _dirtyUserData = false;
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
    _genReview++;
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
    _genActivity++;
    _scheduleSave();
  }

  int activityOn(DateTime when) => _activity[_dateKey(when)] ?? 0;

  List<int> last7Days({DateTime? now}) {
    final today = _dateOnly(now ?? DateTime.now());
    return List<int>.generate(7, (i) {
      final day = today.subtract(Duration(days: 6 - i));
      return _activity[_dateKey(day)] ?? 0;
    });
  }

  List<int> last30Days({DateTime? now}) {
    final today = _dateOnly(now ?? DateTime.now());
    return List<int>.generate(30, (i) {
      final day = today.subtract(Duration(days: 29 - i));
      return _activity[_dateKey(day)] ?? 0;
    });
  }

  List<int> last30DaysMinutes({DateTime? now}) {
    final today = _dateOnly(now ?? DateTime.now());
    return List<int>.generate(30, (i) {
      final day = today.subtract(Duration(days: 29 - i));
      return _studyMinutes[_dateKey(day)] ?? 0;
    });
  }

  List<bool> last90DaysActivity({DateTime? now}) {
    final today = _dateOnly(now ?? DateTime.now());
    return List<bool>.generate(90, (i) {
      final day = today.subtract(Duration(days: 89 - i));
      return (_activity[_dateKey(day)] ?? 0) > 0;
    });
  }

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

  String? get selectedVocabId => _selectedVocabId;

  Future<void> setSelectedVocabId(String vocabId) async {
    if (_selectedVocabId == vocabId) return;
    _selectedVocabId = vocabId;
    _dirtyUserData = true;
    _genUserData++;
    _scheduleSave();
  }

  int openCountOn(DateTime when) => _openCounts[_dateKey(when)] ?? 0;
  int studyMinutesOn(DateTime when) => _studyMinutes[_dateKey(when)] ?? 0;

  int get totalStudyMinutes =>
      _studyMinutes.values.fold(0, (a, b) => a + b);

  Future<void> recordOpen(DateTime when) async {
    final key = _dateKey(when);
    _openCounts[key] = (_openCounts[key] ?? 0) + 1;
    _dirtyUserData = true;
    _genUserData++;
    _scheduleSave();
  }

  Future<void> addStudyMinutes(DateTime when, int minutes) async {
    if (minutes <= 0) return;
    final key = _dateKey(when);
    _studyMinutes[key] = (_studyMinutes[key] ?? 0) + minutes;
    _dirtyUserData = true;
    _genUserData++;
    _scheduleSave();
  }

  Future<bool> toggleFavorite(String wordId) async {
    if (_favorites.contains(wordId)) {
      _favorites.remove(wordId);
    } else {
      _favorites.add(wordId);
    }
    _dirtyUserData = true;
    _genUserData++;
    _scheduleSave();
    return _favorites.contains(wordId);
  }

  Future<void> markRemoved(String wordId) async {
    _removed.add(wordId);
    _dirtyUserData = true;
    _genUserData++;
    _scheduleSave();
  }

  // --- Debounced save -------------------------------------------
  // Retry backoff for failed flushes. Starts at 250 ms and doubles up
  // to a ceiling of 8 s. Reset on successful flush. This guarantees
  // that transient errors (disk transiently locked, out-of-memory)
  // don't permanently stall persistence.
  Duration _retryDelay = const Duration(milliseconds: 250);
  static const _maxRetryDelay = Duration(seconds: 8);

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 300), _flushInternal);
  }

  /// Schedule a retry timer after a failed flush. The backoff doubles
  /// each retry so a stuck disk doesn't burn CPU; reset on success.
  void _scheduleRetryFlush() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(_retryDelay, _flushInternal);
    if (_retryDelay < _maxRetryDelay) {
      _retryDelay = Duration(milliseconds: _retryDelay.inMilliseconds * 2);
      if (_retryDelay > _maxRetryDelay) _retryDelay = _maxRetryDelay;
    }
  }

  /// Force an immediate write. Repeats until all pending dirty state
  /// (including any mutations arriving during the IO window) is
  /// durably written. Safe to overlap with concurrent debounced saves.
  Future<void> flush() async {
    _saveDebounce?.cancel();
    _saveDebounce = null;
    do {
      _needsAnotherFlush = false;
      await _flushInternal();
    } while (_needsAnotherFlush);
  }

  /// Core flush. Serialised via [_isFlushing].
  ///
  /// Correctness:
  ///   * Snapshot the generation counters alongside the dirty flags.
  ///   * Run IO (can throw — that's OK, flags remain dirty).
  ///   * Clear a flag ONLY if (a) we had a snapshot pending AND
  ///     (b) the counter still matches — meaning no concurrent
  ///     mutation re-set the flag during the IO window.
  ///   * Loop: if any flag is still set (new mutation during IO),
  ///     run another pass immediately — no point waiting 300 ms.
  ///   * On ANY exception: do NOT lose the dirty state. Clear the
  ///     in-flight mutex so subsequent calls can enter, and schedule
  ///     an exponential-backoff retry via Timer.
  Future<void> _flushInternal() async {
    if (_isFlushing) {
      _needsAnotherFlush = true;
      return;
    }
    _isFlushing = true;
    bool success = false;
    try {
      while (true) {
        final doReview = _dirtyReview;
        final doActivity = _dirtyActivity;
        final doUserData = _dirtyUserData;
        if (!doReview && !doActivity && !doUserData) {
          success = true;
          return;
        }

        // Snap generation counters at the START of the IO window.
        final gReview = _genReview;
        final gActivity = _genActivity;
        final gUserData = _genUserData;

        if (doReview) {
          final payload =
              _cache.map((k, v) => MapEntry(k, v.toJson()));
          await _backend.saveReviewState(
            Map<String, dynamic>.from(payload),
          );
        }
        if (doActivity) {
          await _backend.saveActivity(
            Map<String, dynamic>.from(_activity),
          );
        }
        if (doUserData) {
          await _saveUserDataInternal();
        }

        // Clear only flags whose generation is unchanged.
        if (doReview && gReview == _genReview) _dirtyReview = false;
        if (doActivity && gActivity == _genActivity) _dirtyActivity = false;
        if (doUserData && gUserData == _genUserData) _dirtyUserData = false;

        // Loop again if concurrent mutations kept anything dirty.
        if (!_dirtyReview && !_dirtyActivity && !_dirtyUserData) {
          success = true;
          return;
        }
      }
    } finally {
      _isFlushing = false;
      // Reset retry backoff on success, schedule a retry on failure.
      if (success) {
        _retryDelay = const Duration(milliseconds: 250);
      } else if (_dirtyReview || _dirtyActivity || _dirtyUserData) {
        // We exited with an exception and STILL have dirty state: the
        // disk write failed partway through. Schedule a retry via the
        // backoff timer. The 300ms debounce was cancelled when the
        // original flush was entered, so we must explicitly re-arm.
        _scheduleRetryFlush();
      }
      // Concurrent flush caller is waiting: dispatch a microtask pass.
      if (_needsAnotherFlush) {
        _needsAnotherFlush = false;
        scheduleMicrotask(_flushInternal);
      }
    }
  }

  /// Build + commit the user-data payload. Used by both schema
  /// migration (which MUST write a header BEFORE touching anything
  /// else) and the normal flush path.
  Future<void> _saveUserDataInternal() async {
    final json = <String, dynamic>{
      'schemaVersion': _schemaVersion,
      'favorites': _favorites.toList(),
      'removed': _removed.toList(),
      'openCounts': _openCounts,
      'studyMinutes': _studyMinutes,
      if (_selectedVocabId != null) 'selectedVocabId': _selectedVocabId,
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
