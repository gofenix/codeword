import 'dart:async';
import 'dart:io';

import 'package:codeword/services/tts_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late TtsCache cache;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('codeword_tts_cache_test_');
    cache = TtsCache(tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'getOrFetchEntry caches fetched bytes and reports cache source',
    () async {
      var fetchCount = 0;

      final first = await cache.getOrFetchEntry('algorithm', 'us', () async {
        fetchCount++;
        return [1, 2, 3];
      });
      final second = await cache.getOrFetchEntry('algorithm', 'us', () async {
        fetchCount++;
        return [4, 5, 6];
      });

      expect(fetchCount, 1);
      expect(first?.source, TtsCacheSource.fetched);
      expect(second?.source, TtsCacheSource.cached);
      expect(await first!.file.readAsBytes(), [1, 2, 3]);
      expect(second!.file.path, first.file.path);
    },
  );

  test('getOrFetchEntry shares one in-flight fetch for the same key', () async {
    var fetchCount = 0;
    final completer = Completer<List<int>>();

    final firstFuture = cache.getOrFetchEntry('concurrency', 'us', () {
      fetchCount++;
      return completer.future;
    });
    final secondFuture = cache.getOrFetchEntry('concurrency', 'us', () {
      fetchCount++;
      return Future.value([9, 9, 9]);
    });

    completer.complete([7, 8, 9]);
    final results = await Future.wait([firstFuture, secondFuture]);

    expect(fetchCount, 1);
    expect(results[0]?.source, TtsCacheSource.fetched);
    expect(results[1]?.source, TtsCacheSource.shared);
    expect(results[0]!.file.path, results[1]!.file.path);
    expect(await results[0]!.file.readAsBytes(), [7, 8, 9]);
  });

  test(
    'getOrFetchEntry returns null and does not cache empty fetches',
    () async {
      var fetchCount = 0;

      final first = await cache.getOrFetchEntry('empty', 'us', () async {
        fetchCount++;
        return const [];
      });
      final second = await cache.getOrFetchEntry('empty', 'us', () async {
        fetchCount++;
        return [1];
      });

      expect(first, isNull);
      expect(second?.source, TtsCacheSource.fetched);
      expect(fetchCount, 2);
      expect(await second!.file.readAsBytes(), [1]);
    },
  );
}
