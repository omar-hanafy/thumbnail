// Deterministic in-memory ThumbnailExtractor for hermetic tests of code
// that uses cached_video_thumbnail. Copy into your app's test/support/ and
// pair it with:
//
//   final engine = ThumbnailEngine.forTesting(
//     extractor: FakeThumbnailExtractor(),
//     directory: Directory('${tempDir.path}/cache'),
//   );
//
// Extractor contract honored here (required of any fake): write real
// decodable image bytes into destPath, return the true dimensions, throw
// ThumbnailException on simulated failure - never "succeed" without
// producing the file.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cached_video_thumbnail/cached_video_thumbnail.dart';

/// A valid 2x2 PNG. Deliberately not 1x1: a cancelled provider stream
/// settles with an internal 1x1 transparent pixel, so asserting 2x2
/// guarantees the decoded image came from this fake.
final Uint8List kFake2x2Png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGP4zwAE/xkgF'
  'AAb8gP91pbyKwAAAABJRU5ErkJggg==',
);

/// One recorded [FakeThumbnailExtractor.extract] call.
class FakeExtraction {
  FakeExtraction(this.requestId, this.source, this.spec, this.destPath);

  final String requestId;
  final VideoSource source;
  final ThumbnailSpec spec;
  final String destPath;
}

/// Test double for the native extractor.
///
/// Defaults to instantly writing [kFake2x2Png] and reporting 2x2. Knobs:
///
/// - [failWith]: every call throws this instead of producing a file.
/// - [gated] + [release]: calls block until released - deterministic
///   loading states and cancellation races without sleeps.
/// - [delay]: artificial latency before completing.
/// - [calls] / [cancelled]: assert what reached the extractor.
class FakeThumbnailExtractor implements ThumbnailExtractor {
  /// Extract calls received, in order.
  final List<FakeExtraction> calls = [];

  /// Request ids passed to [cancel].
  final List<String> cancelled = [];

  /// Artificial latency before completing each call.
  Duration delay = Duration.zero;

  /// When set, every call throws this instead of producing a file.
  ThumbnailException? failWith;

  /// When true, calls block until [release] is invoked.
  bool gated = false;

  /// Bytes written to destPath; must stay a real decodable image.
  Uint8List bytes = kFake2x2Png;

  /// Dimensions reported to the engine; keep in sync with [bytes].
  int width = 2;

  /// See [width].
  int height = 2;

  Completer<void> _gate = Completer<void>();

  /// Number of extract calls seen so far.
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
