import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thumbnail/thumbnail.dart';

import 'support/fake_extractor.dart';

void main() {
  late Directory root;
  late FakeExtractor extractor;
  var fakeNow = DateTime(2026, 1, 1);

  ThumbnailEngine newEngine({ThumbnailEngineConfig? config}) {
    return ThumbnailEngine.forTesting(
      extractor: extractor,
      directory: Directory('${root.path}/cache'),
      config: config ?? const ThumbnailEngineConfig(),
      now: () => fakeNow,
    );
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('engine_test');
    extractor = FakeExtractor();
    fakeNow = DateTime(2026, 1, 1);
  });

  tearDown(() => root.delete(recursive: true));

  final asset = VideoSource.asset('assets/v.mp4');

  test('miss extracts once, then identical requests hit the cache', () async {
    final engine = newEngine();
    final first = await engine.getThumbnail(asset);
    expect(first.wasCached, isFalse);
    expect(first.width, 1);
    expect(File(first.filePath).existsSync(), isTrue);
    expect(extractor.callCount, 1);

    final second = await engine.getThumbnail(asset);
    expect(second.wasCached, isTrue);
    expect(second.filePath, first.filePath);
    expect(extractor.callCount, 1, reason: 'hit must not touch the extractor');

    final m = engine.metrics;
    expect(m.requests, 2);
    expect(m.cacheHits, 1);
    expect(m.extractions, 1);
  });

  test('identical concurrent requests coalesce into one extraction', () async {
    final engine = newEngine();
    extractor.gated = true;
    final futures = [
      for (var i = 0; i < 5; i++) engine.thumbnail(asset).result,
    ];
    await pumpEventQueue();
    extractor.release();
    final results = await Future.wait(futures);
    expect(extractor.callCount, 1);
    expect(results.map((r) => r.filePath).toSet().length, 1);
    expect(engine.metrics.coalescedJoins, 4);
  });

  test('different specs of one source extract separately', () async {
    final engine = newEngine();
    await engine.getThumbnail(asset);
    await engine.getThumbnail(
      asset,
      spec: const ThumbnailSpec(maxWidth: 100, maxHeight: 100),
    );
    expect(extractor.callCount, 2);
  });

  test(
    'cancelling the only pre-dispatch request never calls the extractor',
    () async {
      final engine = newEngine(
        config: const ThumbnailEngineConfig(maxConcurrentExtractions: 1),
      );
      extractor.gated = true;
      // Occupy the single slot.
      final blocker = engine.thumbnail(VideoSource.asset('other.mp4'));
      await pumpEventQueue();

      final request = engine.thumbnail(asset);
      request.result.ignore();
      await pumpEventQueue();
      request.cancel();

      extractor.release();
      await blocker.result;
      await pumpEventQueue();
      expect(extractor.calls.where((c) => c.source == asset), isEmpty);
      await expectLater(
        request.result,
        throwsA(
          isA<ThumbnailException>().having(
            (e) => e.code,
            'code',
            ThumbnailErrorCode.cancelled,
          ),
        ),
      );
    },
  );

  test('cancelling one joiner leaves the other unaffected', () async {
    final engine = newEngine();
    extractor.gated = true;
    final a = engine.thumbnail(asset);
    await pumpEventQueue();
    final b = engine.thumbnail(asset);
    await pumpEventQueue();

    b.cancel();
    await expectLater(
      b.result,
      throwsA(
        isA<ThumbnailException>().having(
          (e) => e.code,
          'code',
          ThumbnailErrorCode.cancelled,
        ),
      ),
    );

    extractor.release();
    final result = await a.result;
    expect(result.width, 1);
    expect(engine.metrics.cancellations, 1);
  });

  test(
    'cancelling all joiners of an in-flight request calls extractor.cancel',
    () async {
      final engine = newEngine();
      extractor.gated = true;
      final a = engine.thumbnail(asset);
      final b = engine.thumbnail(asset);
      a.result.ignore();
      b.result.ignore();
      await pumpEventQueue();
      expect(extractor.callCount, 1);

      a.cancel();
      b.cancel();
      await pumpEventQueue();
      expect(extractor.cancelled, [extractor.calls.single.requestId]);

      // The sunk-cost result still lands in the cache for the next request.
      // The orphaned worker commits through real file IO, which event-queue
      // pumping does not bound; wait for the post-commit metrics signal.
      extractor.release();
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (engine.metrics.extractions < 1) {
        expect(
          DateTime.now().isBefore(deadline),
          isTrue,
          reason: 'orphaned extraction never committed',
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final next = await engine.getThumbnail(asset);
      expect(next.wasCached, isTrue);
      expect(extractor.callCount, 1);
    },
  );

  test('visible requests dispatch before earlier prefetch requests', () async {
    final engine = newEngine(
      config: const ThumbnailEngineConfig(maxConcurrentExtractions: 1),
    );
    extractor.gated = true;
    engine.thumbnail(VideoSource.asset('blocker.mp4')).result.ignore();
    await pumpEventQueue();

    engine.prefetch(VideoSource.asset('p.mp4'));
    await pumpEventQueue();
    final visible = engine.thumbnail(
      VideoSource.asset('v.mp4'),
      priority: ThumbnailPriority.visible,
    );
    await pumpEventQueue();

    extractor.gated = false;
    extractor.release();
    await visible.result;
    // blocker ran first (it held the slot), then the visible one.
    final order = extractor.calls
        .map((c) => (c.source as AssetVideoSource).assetKey)
        .toList();
    expect(order[0], 'blocker.mp4');
    expect(order[1], 'v.mp4');
  });

  test('failures are negative-cached within the ttl, then retried', () async {
    final engine = newEngine();
    extractor.failWith = const ThumbnailException(
      ThumbnailErrorCode.network,
      '404',
    );

    await expectLater(
      engine.getThumbnail(asset),
      throwsA(
        isA<ThumbnailException>().having(
          (e) => e.code,
          'code',
          ThumbnailErrorCode.network,
        ),
      ),
    );
    expect(extractor.callCount, 1);

    // Within the TTL: fast-fail without calling the extractor.
    await expectLater(
      engine.getThumbnail(asset),
      throwsA(
        isA<ThumbnailException>().having(
          (e) => e.code,
          'code',
          ThumbnailErrorCode.network,
        ),
      ),
    );
    expect(extractor.callCount, 1);

    // After the TTL: retried.
    fakeNow = fakeNow.add(const Duration(seconds: 61));
    extractor.failWith = null;
    final result = await engine.getThumbnail(asset);
    expect(result.wasCached, isFalse);
    expect(extractor.callCount, 2);
    expect(engine.metrics.failures[ThumbnailErrorCode.network], 1);
  });

  test('evict removes disk and negative entries for one source only', () async {
    final engine = newEngine();
    final other = VideoSource.asset('other.mp4');
    await engine.getThumbnail(asset);
    await engine.getThumbnail(other);
    expect(extractor.callCount, 2);

    await engine.evict(asset);
    await engine.getThumbnail(asset);
    expect(extractor.callCount, 3, reason: 'evicted source re-extracts');
    await engine.getThumbnail(other);
    expect(extractor.callCount, 3, reason: 'other source still cached');
  });

  test('clearCache drops everything', () async {
    final engine = newEngine();
    await engine.getThumbnail(asset);
    await engine.clearCache();
    await engine.getThumbnail(asset);
    expect(extractor.callCount, 2);
  });

  test('spec validation fails synchronously', () {
    final engine = newEngine();
    expect(
      () => engine.thumbnail(asset, spec: const ThumbnailSpec(quality: 0)),
      throwsArgumentError,
    );
  });

  test('missing file source fails with fileNotFound', () async {
    final engine = newEngine();
    await expectLater(
      engine.getThumbnail(VideoSource.file('/definitely/not/here.mp4')),
      throwsA(
        isA<ThumbnailException>().having(
          (e) => e.code,
          'code',
          ThumbnailErrorCode.fileNotFound,
        ),
      ),
    );
    expect(extractor.callCount, 0);
  });

  test('events stream the request lifecycle', () async {
    final engine = newEngine();
    final events = <ThumbnailEvent>[];
    engine.onEvent = events.add;

    await engine.getThumbnail(asset);
    await engine.getThumbnail(asset);
    expect(events.map((e) => e.kind), [
      ThumbnailEventKind.requested,
      ThumbnailEventKind.extracted,
      ThumbnailEventKind.requested,
      ThumbnailEventKind.cacheHit,
    ]);
  });

  test(
    'configure adjusts concurrency live but refuses cache resizing after init',
    () async {
      final engine = newEngine();
      await engine.getThumbnail(asset);
      await engine.configure(
        const ThumbnailEngineConfig(maxConcurrentExtractions: 4),
      );
      expect(
        () => engine.configure(const ThumbnailEngineConfig(maxCacheBytes: 1)),
        throwsStateError,
      );
    },
  );

  test('config validation rejects out-of-range concurrency', () {
    expect(
      () => const ThumbnailEngineConfig(maxConcurrentExtractions: 0).validate(),
      throwsArgumentError,
    );
    expect(
      () => const ThumbnailEngineConfig(maxConcurrentExtractions: 9).validate(),
      throwsArgumentError,
    );
  });

  test('prefetch never surfaces errors', () async {
    final engine = newEngine();
    extractor.failWith = const ThumbnailException(ThumbnailErrorCode.io, 'x');
    engine.prefetch(asset);
    await pumpEventQueue();
    // No unhandled error: reaching this line is the assertion.
    expect(engine.metrics.failures[ThumbnailErrorCode.io], 1);
  });
}
