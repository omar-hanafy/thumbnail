import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:thumbnail/thumbnail.dart';

/// A valid 1x1 PNG, so provider tests can decode real bytes.
final Uint8List kTinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// Records one extract call.
class FakeExtraction {
  FakeExtraction(this.requestId, this.source, this.spec, this.destPath);

  final String requestId;
  final VideoSource source;
  final ThumbnailSpec spec;
  final String destPath;
}

/// Deterministic in-memory extractor for engine and provider tests.
///
/// By default every call writes [kTinyPng] into `destPath` and reports 1x1.
/// Tests can add latency, force failures, or gate completion manually.
class FakeExtractor implements ThumbnailExtractor {
  /// Calls received, in order.
  final List<FakeExtraction> calls = [];

  /// Request ids passed to [cancel].
  final List<String> cancelled = [];

  /// Artificial latency before completing.
  Duration delay = Duration.zero;

  /// When set, every call throws this instead of producing a file.
  ThumbnailException? failWith;

  /// When true, calls block until [release] is invoked.
  bool gated = false;

  /// Bytes written to destPath.
  Uint8List bytes = kTinyPng;

  /// Reported dimensions.
  int width = 1;
  int height = 1;

  Completer<void> _gate = Completer<void>();

  /// Number of extract calls seen.
  int get callCount => calls.length;

  /// Releases every call currently blocked on the gate.
  void release() {
    _gate.complete();
    _gate = Completer<void>();
  }

  @override
  Future<ExtractionResult> extract({
    required String requestId,
    required VideoSource source,
    required ThumbnailSpec spec,
    required String destPath,
  }) async {
    calls.add(FakeExtraction(requestId, source, spec, destPath));
    if (delay != Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (gated) {
      await _gate.future;
    }
    final failure = failWith;
    if (failure != null) throw failure;
    await File(destPath).writeAsBytes(bytes);
    return ExtractionResult(width: width, height: height);
  }

  @override
  Future<void> cancel(String requestId) async {
    cancelled.add(requestId);
  }
}
