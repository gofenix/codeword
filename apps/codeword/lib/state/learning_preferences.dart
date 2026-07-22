import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class LearningPreferences {
  final bool spellingEnabled;
  final bool listeningEnabled;

  const LearningPreferences({
    this.spellingEnabled = false,
    this.listeningEnabled = false,
  });

  LearningPreferences copyWith({
    bool? spellingEnabled,
    bool? listeningEnabled,
  }) {
    return LearningPreferences(
      spellingEnabled: spellingEnabled ?? this.spellingEnabled,
      listeningEnabled: listeningEnabled ?? this.listeningEnabled,
    );
  }

  factory LearningPreferences.fromJson(Map<String, dynamic> json) {
    return LearningPreferences(
      spellingEnabled: json['spellingEnabled'] == true,
      listeningEnabled: json['listeningEnabled'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'spellingEnabled': spellingEnabled,
    'listeningEnabled': listeningEnabled,
  };

  @override
  bool operator ==(Object other) {
    return other is LearningPreferences &&
        other.spellingEnabled == spellingEnabled &&
        other.listeningEnabled == listeningEnabled;
  }

  @override
  int get hashCode => Object.hash(spellingEnabled, listeningEnabled);
}

abstract class LearningPreferencesBackend {
  Future<String?> read();
  Future<void> write(String value);
}

class _FileLearningPreferencesBackend implements LearningPreferencesBackend {
  static const _fileName = 'codeword_learning_preferences.json';

  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    return File(p.join(directory.path, _fileName));
  }

  @override
  Future<String?> read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<void> write(String value) async {
    final file = await _file();
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(value, flush: true);
    await temporary.rename(file.path);
  }
}

class LearningPreferencesStore {
  final LearningPreferencesBackend _backend;

  LearningPreferencesStore([LearningPreferencesBackend? backend])
    : _backend = backend ?? _FileLearningPreferencesBackend();

  Future<LearningPreferences> read() async {
    try {
      final raw = await _backend.read();
      if (raw == null || raw.trim().isEmpty) {
        return const LearningPreferences();
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return const LearningPreferences();
      }
      return LearningPreferences.fromJson(decoded);
    } catch (_) {
      return const LearningPreferences();
    }
  }

  Future<void> write(LearningPreferences preferences) {
    return _backend.write(jsonEncode(preferences.toJson()));
  }
}

class LearningPreferencesNotifier extends StateNotifier<LearningPreferences> {
  final LearningPreferencesStore _store;
  late final Future<void> ready;
  Future<void> _writeQueue = Future<void>.value();
  LearningPreferences _persisted = const LearningPreferences();

  LearningPreferencesNotifier(this._store)
    : super(const LearningPreferences()) {
    ready = _load();
  }

  Future<void> _load() async {
    final loaded = await _store.read();
    _persisted = loaded;
    state = loaded;
  }

  Future<void> setSpellingEnabled(bool enabled) async {
    await ready;
    await _persist(state.copyWith(spellingEnabled: enabled));
  }

  Future<void> setListeningEnabled(bool enabled) async {
    await ready;
    await _persist(state.copyWith(listeningEnabled: enabled));
  }

  Future<void> _persist(LearningPreferences next) async {
    if (next == state) return;
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
      if (state == next) state = _persisted;
      rethrow;
    }
  }
}

final learningPreferencesProvider =
    StateNotifierProvider<LearningPreferencesNotifier, LearningPreferences>(
      (ref) => LearningPreferencesNotifier(LearningPreferencesStore()),
    );
