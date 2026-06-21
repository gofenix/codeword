import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:lib_core/lib_core.dart';

/// Load the qwerty-learner derived catalogue (manifest-only).
Future<List<VocabList>> loadQwertyCatalog() async {
  final raw = await rootBundle.loadString('assets/vocab/_qwerty_index.json');
  final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  return list.map(VocabList.fromJson).toList(growable: false);
}

/// Loads vocabulary word lists bundled as JSON assets.
class ContentLoader {
  /// Load all words for a built-in list. Asset path: `assets/vocab/<listId>.json`.
  static Future<List<VocabWord>> loadList(String listId) async {
    final raw = await rootBundle.loadString('assets/vocab/$listId.json');
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(VocabWord.fromJson).toList(growable: false);
  }
}
