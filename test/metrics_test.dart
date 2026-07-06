import 'package:flutter_test/flutter_test.dart';
import 'package:thumbnail/src/metrics.dart';
import 'package:thumbnail/thumbnail.dart';

void main() {
  test('counters accumulate into the snapshot', () {
    final recorder = MetricsRecorder();
    recorder.incRequest();
    recorder.incRequest();
    recorder.incCacheHit();
    recorder.incCoalesced();
    recorder.incCancelled();
    recorder.incTimeout();
    recorder.incFailure(ThumbnailErrorCode.network);
    recorder.incFailure(ThumbnailErrorCode.network);
    recorder.incFailure(ThumbnailErrorCode.io);

    final m = recorder.snapshot(queueDepth: 3, activeJobs: 2);
    expect(m.requests, 2);
    expect(m.cacheHits, 1);
    expect(m.coalescedJoins, 1);
    expect(m.cancellations, 1);
    expect(m.timeouts, 1);
    expect(m.failures[ThumbnailErrorCode.network], 2);
    expect(m.failures[ThumbnailErrorCode.io], 1);
    expect(m.queueDepth, 3);
    expect(m.activeJobs, 2);
  });

  test('extraction timings produce nearest-rank percentiles', () {
    final recorder = MetricsRecorder();
    for (var i = 1; i <= 100; i++) {
      recorder.recordExtraction(
        queueWait: Duration(milliseconds: i * 2),
        extract: Duration(milliseconds: i),
      );
    }
    final m = recorder.snapshot(queueDepth: 0, activeJobs: 0);
    expect(m.extractions, 100);
    expect(m.extractP50, const Duration(milliseconds: 50));
    expect(m.extractP95, const Duration(milliseconds: 95));
    expect(m.queueWaitP50, const Duration(milliseconds: 100));
    expect(m.queueWaitP95, const Duration(milliseconds: 190));
  });

  test('percentiles are null with no samples', () {
    final m = MetricsRecorder().snapshot(queueDepth: 0, activeJobs: 0);
    expect(m.extractP50, isNull);
    expect(m.extractP95, isNull);
  });

  test('ring buffer keeps only the newest 256 samples', () {
    final recorder = MetricsRecorder();
    // 300 samples; the first 44 (1..44ms) fall out of the window.
    for (var i = 1; i <= 300; i++) {
      recorder.recordExtraction(
        queueWait: Duration.zero,
        extract: Duration(milliseconds: i),
      );
    }
    final m = recorder.snapshot(queueDepth: 0, activeJobs: 0);
    // Window holds 45..300; nearest-rank p50 of 256 samples is the 128th.
    expect(m.extractP50, const Duration(milliseconds: 45 + 128 - 1));
    expect(m.extractions, 300);
  });

  test('snapshot failure map is a copy', () {
    final recorder = MetricsRecorder();
    recorder.incFailure(ThumbnailErrorCode.io);
    final m = recorder.snapshot(queueDepth: 0, activeJobs: 0);
    recorder.incFailure(ThumbnailErrorCode.io);
    expect(m.failures[ThumbnailErrorCode.io], 1);
  });

  test('toString gives a compact summary', () {
    final recorder = MetricsRecorder()
      ..incRequest()
      ..incCacheHit();
    final m = recorder.snapshot(queueDepth: 0, activeJobs: 0);
    expect(m.toString(), contains('requests: 1'));
    expect(m.toString(), contains('cacheHits: 1'));
  });
}
