import 'package:path_provider/path_provider.dart';

/// Desktop / mobile implementation: returns the app documents
/// directory path as a string.
Future<String?> computeStoragePath() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  } catch (_) {
    return null;
  }
}
