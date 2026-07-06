import 'package:flutter/foundation.dart';

import '../thumbnail_spec.dart';
import '../video_source.dart';

/// Dimensions of the encoded image an extraction produced.
@immutable
class ExtractionResult {
  /// Creates a result value.
  const ExtractionResult({required this.width, required this.height});

  /// Encoded width in pixels.
  final int width;

  /// Encoded height in pixels.
  final int height;
}

/// Produces one encoded thumbnail file per request.
///
/// This is the engine's extension point: v1 ships a Pigeon-backed native
/// implementation; alternative backends (Media3, FFmpeg, desktop) can be
/// injected without touching the engine.
///
/// Contract:
/// - Encode straight into [extract]'s `destPath`; never return bytes.
/// - Throw [ThumbnailException] (or a platform error the engine can map)
///   on failure; never resolve with a bogus result.
/// - [cancel] is best-effort and may be a no-op.
abstract class ThumbnailExtractor {
  /// Extracts one frame of [source] per [spec] and encodes it into
  /// [destPath]. Returns the encoded dimensions.
  Future<ExtractionResult> extract({
    required String requestId,
    required VideoSource source,
    required ThumbnailSpec spec,
    required String destPath,
  });

  /// Best-effort cancellation of the in-flight extraction [requestId].
  Future<void> cancel(String requestId) async {}
}
