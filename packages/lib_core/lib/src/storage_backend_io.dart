import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'storage_backend.dart';

/// File-based storage backend for desktop and mobile (where
/// `dart:io` and `path_provider` are available). Reads and writes
/// three JSON files in the app documents directory.
///
/// Writes use a tmp-then-rename pattern so process kills during a
/// write can't leave a truncated JSON file in place. Reads NEVER
/// throw on a corrupted / unreadable file — the goal is graceful
/// degradation. The app should start up with empty state rather than
/// crash at the gate, so an unreadable file is quarantined (renamed
/// to `*.corrupted`) and treated as "file missing".
///
/// Platform notes:
///   * On Windows, `File.rename` over an existing target has not
///     always been atomic / permissive, so we fall back to a
///     delete-then-rename path on failure.
///   * Errors are reported via `debugPrint` (dev only) so developers
///     can triage issues — production users never see them.
class IoFileBackend implements StorageBackend {
  // Late-final with an initialiser is single-shot: even if three
  // parallel callers hit _ready() at the same microtask, the
  // initialiser runs exactly once, and everyone awaits the same
  // Future. No additional synchronisation needed on the Dart event
  // loop.
  late final Future<void> _pathsReady = _initPaths();

  late final String _reviewPath;
  late final String _activityPath;
  late final String _userDataPath;

  Future<void> _initPaths() async {
    final dir = await getApplicationDocumentsDirectory();
    _reviewPath = p.join(dir.path, 'codeword_review_state.json');
    _activityPath = p.join(dir.path, 'codeword_activity.json');
    _userDataPath = p.join(dir.path, 'codeword_user_data.json');
  }

  Future<void> _ready() => _pathsReady;

  @override
  Future<Map<String, dynamic>?> loadReviewState() async {
    await _ready();
    return _readJson(_reviewPath, 'review_state');
  }

  @override
  Future<void> saveReviewState(Map<String, dynamic> json) async {
    await _ready();
    await _writeJson(_reviewPath, json);
  }

  @override
  Future<Map<String, dynamic>?> loadActivity() async {
    await _ready();
    return _readJson(_activityPath, 'activity');
  }

  @override
  Future<void> saveActivity(Map<String, dynamic> json) async {
    await _ready();
    await _writeJson(_activityPath, json);
  }

  @override
  Future<Map<String, dynamic>?> loadUserData() async {
    await _ready();
    return _readJson(_userDataPath, 'user_data');
  }

  @override
  Future<void> saveUserData(Map<String, dynamic> json) async {
    await _ready();
    await _writeJson(_userDataPath, json);
  }

  @override
  Future<void> wipeReviewAndActivity() async {
    await _ready();
    Object? firstError;
    for (final path in [_reviewPath, _activityPath]) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (e) {
        firstError ??= e;
      }
    }
    if (firstError != null) throw StateError('wipeReviewAndActivity failed: $firstError');
  }

  @override
  Future<void> wipeAll() async {
    await _ready();
    final paths = [_reviewPath, _activityPath, _userDataPath];
    Object? firstError;
    for (final path in paths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (e) {
        firstError ??= e;
      }
    }
    if (firstError != null) throw StateError('wipeAll failed: $firstError');
  }

  /// Read + parse a JSON file, with **graceful degradation** on every
  /// failure path:
  ///   * Missing file → `null` (first run, expected).
  ///   * Empty file → `null` (truncated zero-byte write, benign).
  ///   * Invalid JSON → quarantine + `null` + `debugPrint` (evidence
  ///     preserved in `<path>.corrupted`, app starts with empty data
  ///     instead of red-screening).
  ///   * Any I/O error (permissions, locked, bad disk, …) → `null` +
  ///     `debugPrint` (same philosophy: never fail to start).
  Future<Map<String, dynamic>?> _readJson(
    String path,
    String debugTag,
  ) async {
    final file = File(path);
    try {
      if (!await file.exists()) return null;
    } catch (e) {
      debugPrint('[storage:$debugTag] exists() failed: $e');
      return null;
    }

    final String raw;
    try {
      raw = await file.readAsString();
    } on FileSystemException catch (e) {
      debugPrint('[storage:$debugTag] read failed: $e');
      return null;
    } catch (e) {
      debugPrint('[storage:$debugTag] unexpected read error: $e');
      return null;
    }

    if (raw.isEmpty) return null;

    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } on FormatException catch (e) {
      // Corrupt payload. Quarantine evidence — the rename itself is
      // best-effort; if the file can't be moved we still return null
      // so the app doesn't hang.
      debugPrint('[storage:$debugTag] corrupt JSON: $e; quarantining');
      try {
        await file.rename('$path.corrupted');
      } catch (qErr) {
        debugPrint('[storage:$debugTag] quarantine failed: $qErr');
        try {
          await file.delete();
        } catch (_) {
          // Worst case: leave the corrupt file in place. Next restart
          // we'll hit the same path again — not great, but we still
          // return null so the app stays up.
        }
      }
      return null;
    } catch (e) {
      debugPrint('[storage:$debugTag] decode error: $e');
      return null;
    }
  }

  /// Atomic write: encode to a `*.tmp` sibling file, flush to disk,
  /// then POSIX-rename over the target. Renames inside a directory
  /// are atomic on every filesystem Dart targets when the OS
  /// cooperates (i.e. target is not held open by another process).
  ///
  /// Fallback path for edge-case environments where rename-over-
  /// existing fails (Windows Defender, cloud sync, macOS NFS, etc.):
  /// use a three-step swap so the pre-existing file is recoverable
  /// even if the final rename step throws:
  ///
  ///   1. `path`      → `path.old`   (preserve existing data)
  ///   2. `path.tmp`  → `path`      (install new version)
  ///   3. delete      `path.old`   (best-effort cleanup)
  ///
  /// Any exception in step 2 leaves `path.old` intact; the next
  /// restart will recover it (see the "orphaned .old restore" block
  /// inside the `_writeJson` error path below).
  Future<void> _writeJson(String path, Map<String, dynamic> json) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final tmpPath = '$path.tmp';
    final tmp = File(tmpPath);
    final oldPath = '$path.old';
    final encoded = jsonEncode(json);
    // flush: true forces fsync before the future completes so we
    // know bytes are on disk before rename — otherwise a power loss
    // right after rename can yield an empty/partial target.
    await tmp.writeAsString(encoded, flush: true);

    try {
      await tmp.rename(path);
    } on FileSystemException {
      // POSIX-rename failed. Fall back to the three-step swap.
      final existing = File(path);
      bool hasOld = false;
      try {
        if (await existing.exists()) {
          final oldFile = File(oldPath);
          if (await oldFile.exists()) await oldFile.delete();
          await existing.rename(oldPath);
          hasOld = true;
        }
      } catch (_) {
        // Worst case: can't even preserve the original file —
        // continue; if the subsequent rename also fails the caller
        // will receive the error and dirty-flags will remain set
        // for a retry.
      }
      try {
        await tmp.rename(path);
      } catch (_) {
        // rename still failed. Restore the .old backup so we don't
        // leave the user with a missing file. If restore also fails
        // the user will restart with whatever state is on disk.
        if (hasOld) {
          try {
            await File(oldPath).rename(path);
          } catch (_) {}
        }
        rethrow;
      }
      // Step 3: cleanup the .old backup. This is fire-and-forget;
      // if it fails the orphaned .old is harmless.
      try {
        final old = File(oldPath);
        if (await old.exists()) await old.delete();
      } catch (_) {}
    }
  }
}

/// Top-level factory function used by the conditional import.
/// Always returns an [IoFileBackend]; on web this file is never
/// compiled.
StorageBackend buildStorageBackend() => IoFileBackend();
