/// Classified failure reasons surfaced by the engine.
enum ThumbnailErrorCode {
  /// The source was structurally invalid (bad URL, empty path, ...).
  invalidSource,

  /// A bundle asset could not be resolved.
  assetNotFound,

  /// A file source does not exist.
  fileNotFound,

  /// A network fetch failed (DNS, HTTP status, connectivity, ...).
  network,

  /// The media has no decodable video track or an unsupported codec/container.
  unsupportedMedia,

  /// Frame decoding failed for another reason.
  extractionFailed,

  /// The decoded frame could not be encoded to jpeg/png.
  encodingFailed,

  /// A local I/O failure (write, rename, disk full, ...).
  io,

  /// The request exceeded its timeout.
  timeout,

  /// The request was cancelled before completion.
  cancelled,
}

/// The only exception type the engine ever throws for request failures.
///
/// Failures are never swallowed into nulls or booleans; every error path
/// carries a [code] callers can branch on and a human-readable [message].
class ThumbnailException implements Exception {
  /// Creates an exception with a classified [code] and diagnostic [message].
  const ThumbnailException(this.code, this.message, {this.cause});

  /// Classified failure reason.
  final ThumbnailErrorCode code;

  /// Human-readable diagnostic detail.
  final String message;

  /// Underlying platform or Dart error, when available.
  final Object? cause;

  @override
  String toString() {
    final suffix = cause == null ? '' : ' (cause: $cause)';
    return 'ThumbnailException(${code.name}): $message$suffix';
  }
}
