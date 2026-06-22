import 'dart:async';
import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'storage_backend.dart';

/// localStorage-based storage backend for Flutter web. Three keys
/// mirror the three JSON files used on desktop / mobile. Data
/// survives page reloads within the same origin.
class WebLocalStorageBackend implements StorageBackend {
  static const _kReview = 'codeword_review_state';
  static const _kActivity = 'codeword_activity';
  static const _kUserData = 'codeword_user_data';

  @override
  Future<Map<String, dynamic>?> loadReviewState() => _read(_kReview);

  @override
  Future<void> saveReviewState(Map<String, dynamic> json) =>
      _write(_kReview, json);

  @override
  Future<Map<String, dynamic>?> loadActivity() => _read(_kActivity);

  @override
  Future<void> saveActivity(Map<String, dynamic> json) =>
      _write(_kActivity, json);

  @override
  Future<Map<String, dynamic>?> loadUserData() => _read(_kUserData);

  @override
  Future<void> saveUserData(Map<String, dynamic> json) =>
      _write(_kUserData, json);

  @override
  Future<void> wipeAll() async {
    html.window.localStorage.remove(_kReview);
    html.window.localStorage.remove(_kActivity);
    html.window.localStorage.remove(_kUserData);
  }

  Future<Map<String, dynamic>?> _read(String key) async {
    final raw = html.window.localStorage[key];
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(String key, Map<String, dynamic> json) async {
    html.window.localStorage[key] = jsonEncode(json);
  }
}

/// Top-level factory function used by the conditional import.
/// Always returns a [WebLocalStorageBackend]; on io this file is
/// never compiled.
StorageBackend buildStorageBackend() => WebLocalStorageBackend();
