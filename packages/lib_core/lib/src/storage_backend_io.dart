import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'storage_backend.dart';

/// File-based storage backend for desktop and mobile (where
/// `dart:io` and `path_provider` are available). Reads and writes
/// three JSON files in the app documents directory.
class IoFileBackend implements StorageBackend {
  late final String _reviewPath;
  late final String _activityPath;
  late final String _userDataPath;

  Future<void>? _pathsReady;

  IoFileBackend() {
    _pathsReady = _initPaths();
  }

  Future<void> _initPaths() async {
    final dir = await getApplicationDocumentsDirectory();
    _reviewPath = p.join(dir.path, 'codeword_review_state.json');
    _activityPath = p.join(dir.path, 'codeword_activity.json');
    _userDataPath = p.join(dir.path, 'codeword_user_data.json');
  }

  Future<void> _ready() => _pathsReady ?? _initPaths();

  @override
  Future<Map<String, dynamic>?> loadReviewState() async {
    return _readJson(_reviewPath);
  }

  @override
  Future<void> saveReviewState(Map<String, dynamic> json) async {
    await _ready();
    await _writeJson(_reviewPath, json);
  }

  @override
  Future<Map<String, dynamic>?> loadActivity() async {
    return _readJson(_activityPath);
  }

  @override
  Future<void> saveActivity(Map<String, dynamic> json) async {
    await _ready();
    await _writeJson(_activityPath, json);
  }

  @override
  Future<Map<String, dynamic>?> loadUserData() async {
    return _readJson(_userDataPath);
  }

  @override
  Future<void> saveUserData(Map<String, dynamic> json) async {
    await _ready();
    await _writeJson(_userDataPath, json);
  }

  @override
  Future<void> wipeAll() async {
    await _ready();
    for (final path in [_reviewPath, _activityPath, _userDataPath]) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  Future<Map<String, dynamic>?> _readJson(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.isEmpty) return null;
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeJson(String path, Map<String, dynamic> json) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(json));
  }
}

/// Top-level factory function used by the conditional import.
/// Always returns an [IoFileBackend]; on web this file is never
/// compiled.
StorageBackend buildStorageBackend() => IoFileBackend();
