import 'package:flutter/services.dart';

import '../pigeon/messages.g.dart';
import '../thumbnail_exception.dart';
import '../thumbnail_spec.dart';
import '../video_source.dart';
import 'thumbnail_extractor.dart';

/// Builds the channel request for one extraction. Pure; unit-tested.
ExtractRequest buildExtractRequest({
  required String requestId,
  required VideoSource source,
  required ThumbnailSpec spec,
  required String destPath,
}) {
  final (kind, value, package, headers) = switch (source) {
    AssetVideoSource(:final assetKey, :final package) => (
      SourceKind.asset,
      assetKey,
      package,
      null,
    ),
    FileVideoSource(:final path) => (SourceKind.file, path, null, null),
    NetworkVideoSource(:final url, :final headers) => (
      SourceKind.network,
      url.toString(),
      null,
      headers,
    ),
  };
  return ExtractRequest(
    requestId: requestId,
    sourceType: kind,
    source: value,
    assetPackage: package,
    headers: headers,
    positionMs: spec.position.inMilliseconds,
    exact: spec.exact,
    maxWidth: spec.maxWidth,
    maxHeight: spec.maxHeight,
    format: spec.format.wireName,
    quality: spec.quality,
    destPath: destPath,
  );
}

/// Maps any platform-channel failure into a [ThumbnailException].
///
/// Natives throw `PlatformException`s whose `code` is one of the
/// [ThumbnailErrorCode] names; anything else (including channel plumbing
/// failures) becomes [ThumbnailErrorCode.extractionFailed] with the raw
/// code preserved in the message.
ThumbnailException mapPlatformError(Object error) {
  if (error is ThumbnailException) return error;
  if (error is PlatformException) {
    final code = ThumbnailErrorCode.values
        .where((c) => c.name == error.code)
        .firstOrNull;
    final detail = error.message ?? 'no detail';
    if (code != null) {
      return ThumbnailException(code, detail, cause: error);
    }
    return ThumbnailException(
      ThumbnailErrorCode.extractionFailed,
      'platform error ${error.code}: $detail',
      cause: error,
    );
  }
  return ThumbnailException(
    ThumbnailErrorCode.extractionFailed,
    'unexpected extractor error: $error',
    cause: error,
  );
}

/// The v1 extractor: typed Pigeon channel into the Kotlin/Swift executors.
class PigeonExtractor implements ThumbnailExtractor {
  /// Creates the extractor; [api] is injectable for tests.
  PigeonExtractor({ThumbnailHostApi? api}) : _api = api ?? ThumbnailHostApi();

  final ThumbnailHostApi _api;

  @override
  Future<ExtractionResult> extract({
    required String requestId,
    required VideoSource source,
    required ThumbnailSpec spec,
    required String destPath,
  }) async {
    final request = buildExtractRequest(
      requestId: requestId,
      source: source,
      spec: spec,
      destPath: destPath,
    );
    try {
      final result = await _api.extract(request);
      return ExtractionResult(width: result.width, height: result.height);
    } catch (e) {
      throw mapPlatformError(e);
    }
  }

  @override
  Future<void> cancel(String requestId) async {
    try {
      await _api.cancel(requestId);
    } catch (_) {
      // Cancellation is best-effort by contract.
    }
  }
}
