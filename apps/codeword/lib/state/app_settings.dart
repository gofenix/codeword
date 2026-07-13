import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppSettings {
  static const int minDailyNewWords = 3;
  static const int maxDailyNewWords = 30;
  static const int defaultDailyNewWords = 12;

  final int dailyNewWords;

  const AppSettings({this.dailyNewWords = defaultDailyNewWords});

  AppSettings copyWith({int? dailyNewWords}) {
    return AppSettings(
      dailyNewWords: _clampDailyNewWords(dailyNewWords ?? this.dailyNewWords),
    );
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      dailyNewWords: _clampDailyNewWords(
        (json['dailyNewWords'] as num?)?.toInt() ?? defaultDailyNewWords,
      ),
    );
  }

  Map<String, dynamic> toJson() => {'dailyNewWords': dailyNewWords};

  static int _clampDailyNewWords(int value) {
    return value.clamp(minDailyNewWords, maxDailyNewWords).toInt();
  }
}

class AppSettingsStore {
  static const _fileName = 'codeword_app_settings.json';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _fileName));
  }

  Future<AppSettings> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const AppSettings();
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return const AppSettings();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return AppSettings.fromJson(json);
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> write(AppSettings settings) async {
    final file = await _file();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(settings.toJson()), flush: true);
    await tmp.rename(file.path);
  }
}

class AppSettingsNotifier extends StateNotifier<AppSettings> {
  final AppSettingsStore _store;
  late final Future<void> ready;
  Future<void> _writeQueue = Future<void>.value();
  AppSettings _persisted = const AppSettings();

  AppSettingsNotifier(this._store) : super(const AppSettings()) {
    ready = _load();
  }

  Future<void> _load() async {
    final loaded = await _store.read();
    _persisted = loaded;
    state = loaded;
  }

  Future<void> setDailyNewWords(int value) async {
    await ready;
    await _persistDailyNewWords(value);
  }

  Future<void> adjustDailyNewWords(int delta) async {
    await ready;
    await _persistDailyNewWords(state.dailyNewWords + delta);
  }

  Future<void> _persistDailyNewWords(int value) async {
    final next = state.copyWith(dailyNewWords: value);
    if (next.dailyNewWords == state.dailyNewWords) return;

    state = next;
    final operation = _writeQueue.then((_) async {
      await _store.write(next);
      _persisted = next;
    });
    _writeQueue = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    try {
      await operation;
    } catch (_) {
      // Do not roll back a newer tap that is already queued.
      if (state.dailyNewWords == next.dailyNewWords) state = _persisted;
      rethrow;
    }
  }
}

final appSettingsProvider =
    StateNotifierProvider<AppSettingsNotifier, AppSettings>(
      (ref) => AppSettingsNotifier(AppSettingsStore()),
    );
