import 'package:flutter/foundation.dart';

/// Scheduling band for a request. Higher bands always dispatch first, and
/// within a band the newest request wins (what the user is looking at now
/// beats where they were two flings ago).
enum ThumbnailPriority {
  /// Speculative warming; runs only when nothing else is queued.
  prefetch,

  /// Default band.
  normal,

  /// On-screen content; always dispatched first.
  visible,
}

/// A generated (or cache-hit) thumbnail.
@immutable
class Thumbnail {
  /// Creates a result value.
  const Thumbnail({
    required this.filePath,
    required this.width,
    required this.height,
    required this.wasCached,
  });

  /// Absolute path of the encoded image inside the engine's cache directory.
  final String filePath;

  /// Encoded image width in pixels.
  final int width;

  /// Encoded image height in pixels.
  final int height;

  /// True when served from the disk cache without any extraction.
  final bool wasCached;

  @override
  String toString() =>
      'Thumbnail(${width}x$height, cached:$wasCached, $filePath)';
}
