import 'package:flutter/foundation.dart';

import 'thumbnail_exception.dart';

/// What happened, for the optional [ThumbnailEventListener] log hook.
enum ThumbnailEventKind {
  /// A request entered the engine.
  requested,

  /// Served from the disk cache with no extraction.
  cacheHit,

  /// Joined an identical in-flight request.
  coalesced,

  /// A native extraction completed and was committed.
  extracted,

  /// The request failed; see [ThumbnailEvent.errorCode].
  failed,

  /// The request was cancelled by its caller(s).
  cancelled,

  /// The request hit its timeout.
  timedOut,
}

/// One structured engine event.
@immutable
class ThumbnailEvent {
  /// Creates an event; produced by the engine only.
  const ThumbnailEvent(this.kind, this.key, {this.elapsed, this.errorCode});

  /// What happened.
  final ThumbnailEventKind kind;

  /// The cache file name identifying the (source, spec) pair.
  final String key;

  /// End-to-end elapsed time for terminal events, when known.
  final Duration? elapsed;

  /// Failure classification for [ThumbnailEventKind.failed].
  final ThumbnailErrorCode? errorCode;

  @override
  String toString() =>
      'ThumbnailEvent(${kind.name}, $key'
      '${elapsed == null ? '' : ', ${elapsed!.inMilliseconds}ms'}'
      '${errorCode == null ? '' : ', ${errorCode!.name}'})';
}

/// Receives structured engine events; wire it to your logger to trace the
/// pipeline in profile builds.
typedef ThumbnailEventListener = void Function(ThumbnailEvent event);

/// Immutable point-in-time engine statistics.
///
/// Percentiles are nearest-rank over the newest 256 samples and are null
/// until at least one extraction completed.
@immutable
class ThumbnailMetrics {
  /// Creates a snapshot; produced by the engine only.
  const ThumbnailMetrics({
    required this.requests,
    required this.cacheHits,
    required this.coalescedJoins,
    required this.extractions,
    required this.cancellations,
    required this.timeouts,
    required this.failures,
    required this.queueDepth,
    required this.activeJobs,
    required this.extractP50,
    required this.extractP95,
    required this.queueWaitP50,
    required this.queueWaitP95,
  });

  /// Total requests seen (including cache hits and joins).
  final int requests;

  /// Requests served straight from the disk cache.
  final int cacheHits;

  /// Requests that joined an identical in-flight extraction.
  final int coalescedJoins;

  /// Completed native extractions.
  final int extractions;

  /// Requests cancelled before completion.
  final int cancellations;

  /// Requests that hit their timeout.
  final int timeouts;

  /// Failure counts by classification.
  final Map<ThumbnailErrorCode, int> failures;

  /// Requests currently waiting for a native slot.
  final int queueDepth;

  /// Native extractions currently running.
  final int activeJobs;

  /// Median native extraction time.
  final Duration? extractP50;

  /// 95th percentile native extraction time.
  final Duration? extractP95;

  /// Median time spent queued before dispatch.
  final Duration? queueWaitP50;

  /// 95th percentile time spent queued before dispatch.
  final Duration? queueWaitP95;

  @override
  String toString() =>
      'ThumbnailMetrics(requests: $requests, cacheHits: $cacheHits, '
      'coalesced: $coalescedJoins, extractions: $extractions, '
      'cancelled: $cancellations, timeouts: $timeouts, '
      'failures: ${failures.length}, queue: $queueDepth, active: $activeJobs, '
      'extractP50: ${extractP50?.inMilliseconds}ms, '
      'extractP95: ${extractP95?.inMilliseconds}ms)';
}

/// Mutable counter store used internally by the engine.
class MetricsRecorder {
  static const int _window = 256;

  int _requests = 0;
  int _cacheHits = 0;
  int _coalesced = 0;
  int _extractions = 0;
  int _cancellations = 0;
  int _timeouts = 0;
  final Map<ThumbnailErrorCode, int> _failures = {};
  final _RingBuffer _extract = _RingBuffer(_window);
  final _RingBuffer _queueWait = _RingBuffer(_window);

  /// Counts a new request.
  void incRequest() => _requests++;

  /// Counts a disk-cache hit.
  void incCacheHit() => _cacheHits++;

  /// Counts a join onto an in-flight extraction.
  void incCoalesced() => _coalesced++;

  /// Counts a caller cancellation.
  void incCancelled() => _cancellations++;

  /// Counts a timeout.
  void incTimeout() => _timeouts++;

  /// Counts a classified failure.
  void incFailure(ThumbnailErrorCode code) =>
      _failures[code] = (_failures[code] ?? 0) + 1;

  /// Records a completed extraction's timings.
  void recordExtraction({required Duration queueWait, required Duration extract}) {
    _extractions++;
    _extract.add(extract.inMicroseconds);
    _queueWait.add(queueWait.inMicroseconds);
  }

  /// Builds an immutable snapshot.
  ThumbnailMetrics snapshot({required int queueDepth, required int activeJobs}) {
    return ThumbnailMetrics(
      requests: _requests,
      cacheHits: _cacheHits,
      coalescedJoins: _coalesced,
      extractions: _extractions,
      cancellations: _cancellations,
      timeouts: _timeouts,
      failures: Map.unmodifiable(_failures),
      queueDepth: queueDepth,
      activeJobs: activeJobs,
      extractP50: _extract.percentile(50),
      extractP95: _extract.percentile(95),
      queueWaitP50: _queueWait.percentile(50),
      queueWaitP95: _queueWait.percentile(95),
    );
  }
}

class _RingBuffer {
  _RingBuffer(this.capacity) : _values = List.filled(capacity, 0);

  final int capacity;
  final List<int> _values;
  int _next = 0;
  int _length = 0;

  void add(int value) {
    _values[_next] = value;
    _next = (_next + 1) % capacity;
    if (_length < capacity) _length++;
  }

  /// Nearest-rank percentile of the samples in the window, or null if empty.
  Duration? percentile(int p) {
    if (_length == 0) return null;
    final sorted = _values.sublist(0, _length)..sort();
    final rank = ((p / 100) * _length).ceil().clamp(1, _length);
    return Duration(microseconds: sorted[rank - 1]);
  }
}
