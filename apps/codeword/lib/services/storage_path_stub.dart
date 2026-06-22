/// Fallback stub for platforms where neither dart:io nor web is
/// available. Should not be reached at runtime thanks to the
/// conditional import in storage_path.dart.
Future<String?> computeStoragePath() async => null;
