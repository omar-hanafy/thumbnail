import 'package:flutter/foundation.dart';

/// Output encoding for generated thumbnails.
enum ThumbnailFormat {
  /// Lossy JPEG; the right default for video frames.
  jpeg('jpg', 'image/jpeg', 'jpeg'),

  /// Lossless PNG; larger and slower, only useful when artifacts are
  /// unacceptable. The `quality` field is ignored for PNG.
  png('png', 'image/png', 'png');

  const ThumbnailFormat(this.fileExtension, this.mimeType, this.wireName);

  /// File extension without the dot.
  final String fileExtension;

  /// MIME type of the encoded image.
  final String mimeType;

  /// Stable name used on the platform channel and in cache keys.
  final String wireName;
}

/// What to extract: frame position, target size, and encoding.
@immutable
class ThumbnailSpec {
  /// Creates a spec. See the field docs for defaults and semantics.
  const ThumbnailSpec({
    this.maxWidth = 0,
    this.maxHeight = 0,
    this.position = Duration.zero,
    this.exact = false,
    this.format = ThumbnailFormat.jpeg,
    this.quality = 80,
  });

  /// Fit-within box width in physical pixels; 0 means unconstrained.
  ///
  /// Aspect ratio is always preserved and frames are never upscaled.
  final int maxWidth;

  /// Fit-within box height in physical pixels; 0 means unconstrained.
  final int maxHeight;

  /// Frame position. Clamped into the video duration natively.
  final Duration position;

  /// When false (default) the nearest sync/key frame is used, which is the
  /// fast path. When true the exact frame at [position] is decoded, which
  /// can require decoding every frame since the previous key frame.
  final bool exact;

  /// Output encoding.
  final ThumbnailFormat format;

  /// JPEG quality, 1..100. Ignored for PNG.
  final int quality;

  /// Throws [ArgumentError] if any field is out of range.
  ///
  /// The engine calls this on every request so invalid specs fail fast in
  /// release builds too.
  void validate() {
    if (maxWidth < 0) {
      throw ArgumentError.value(maxWidth, 'maxWidth', 'must be >= 0');
    }
    if (maxHeight < 0) {
      throw ArgumentError.value(maxHeight, 'maxHeight', 'must be >= 0');
    }
    if (quality < 1 || quality > 100) {
      throw ArgumentError.value(quality, 'quality', 'must be in 1..100');
    }
    if (position.isNegative) {
      throw ArgumentError.value(position, 'position', 'must be >= zero');
    }
  }

  /// Returns a copy with the given fields replaced.
  ThumbnailSpec copyWith({
    int? maxWidth,
    int? maxHeight,
    Duration? position,
    bool? exact,
    ThumbnailFormat? format,
    int? quality,
  }) {
    return ThumbnailSpec(
      maxWidth: maxWidth ?? this.maxWidth,
      maxHeight: maxHeight ?? this.maxHeight,
      position: position ?? this.position,
      exact: exact ?? this.exact,
      format: format ?? this.format,
      quality: quality ?? this.quality,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ThumbnailSpec &&
      other.maxWidth == maxWidth &&
      other.maxHeight == maxHeight &&
      other.position == position &&
      other.exact == exact &&
      other.format == format &&
      other.quality == quality;

  @override
  int get hashCode =>
      Object.hash(maxWidth, maxHeight, position, exact, format, quality);

  @override
  String toString() =>
      'ThumbnailSpec(${maxWidth}x$maxHeight, p:${position.inMilliseconds}ms, '
      'exact:$exact, ${format.wireName}, q:$quality)';
}
