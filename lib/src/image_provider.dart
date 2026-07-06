import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'engine.dart';
import 'thumbnail_exception.dart';
import 'thumbnail_result.dart';
import 'thumbnail_spec.dart';
import 'video_source.dart';

/// A 1x1 transparent PNG used to quietly settle an image stream whose
/// request was cancelled after its last listener detached: nothing is
/// listening, so failing the stream would only spam FlutterError.
final Uint8List _kTransparentPixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// An [ImageProvider] that resolves a video's thumbnail through
/// [ThumbnailEngine].
///
/// Drop it into any `Image` widget:
///
/// ```dart
/// Image(image: VideoThumbnailImage(
///   VideoSource.network(Uri.parse('https://cdn.io/v.mp4')),
///   spec: const ThumbnailSpec(maxWidth: 480, maxHeight: 480),
/// ))
/// ```
///
/// Behavior tuned for feeds:
/// - Identity (`==`) covers source + spec + engine, so Flutter's
///   [ImageCache] deduplicates identical cells for free (priority is
///   deliberately excluded from identity).
/// - When the last listener detaches before the thumbnail is ready, the
///   engine request is cancelled; combined with Flutter's own
///   scroll-aware resolution this keeps fling storms off the decoders.
/// - If a cached file was purged or corrupted externally, the entry is
///   evicted so the next resolve regenerates it.
class VideoThumbnailImage extends ImageProvider<VideoThumbnailImage> {
  /// Creates a provider for [source] rendered per [spec].
  VideoThumbnailImage(
    this.source, {
    this.spec = const ThumbnailSpec(),
    this.priority = ThumbnailPriority.visible,
    this._engine,
  });

  /// The video to thumbnail.
  final VideoSource source;

  /// Size/position/encoding of the generated thumbnail.
  final ThumbnailSpec spec;

  /// Scheduling band used when this provider triggers generation.
  /// Not part of the provider's identity.
  final ThumbnailPriority priority;

  final ThumbnailEngine? _engine;

  /// The engine this provider resolves through.
  ThumbnailEngine get engine => _engine ?? ThumbnailEngine.instance;

  @override
  Future<VideoThumbnailImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<VideoThumbnailImage>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    VideoThumbnailImage key,
    ImageDecoderCallback decode,
  ) {
    final request = engine.thumbnail(source, spec: spec, priority: priority);
    final completer = MultiFrameImageStreamCompleter(
      codec: _decodeThumbnail(request, decode),
      scale: 1.0,
      debugLabel: 'VideoThumbnailImage(${source.describe()})',
      informationCollector: () => [
        DiagnosticsProperty<VideoSource>('source', source),
        DiagnosticsProperty<ThumbnailSpec>('spec', spec),
      ],
    );
    completer.addOnLastListenerRemovedCallback(request.cancel);
    return completer;
  }

  Future<ui.Codec> _decodeThumbnail(
    ThumbnailRequest request,
    ImageDecoderCallback decode,
  ) async {
    final Thumbnail thumbnail;
    try {
      thumbnail = await request.result;
    } on ThumbnailException catch (e) {
      if (e.code == ThumbnailErrorCode.cancelled) {
        // Cancelled because the last listener detached; settle the dead
        // stream with an inert pixel instead of reporting a phantom error.
        return decode(
          await ui.ImmutableBuffer.fromUint8List(_kTransparentPixel),
        );
      }
      rethrow;
    }
    try {
      final buffer = await ui.ImmutableBuffer.fromFilePath(thumbnail.filePath);
      return await decode(buffer);
    } catch (_) {
      // The cached file is unreadable (purged by the OS or corrupted):
      // evict it so the next resolve regenerates, then surface the error.
      await engine.removeCorrupted(source, spec);
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is VideoThumbnailImage &&
      other.source == source &&
      other.spec == spec &&
      identical(other.engine, engine);

  @override
  int get hashCode => Object.hash(source, spec, engine);

  @override
  String toString() => 'VideoThumbnailImage(${source.describe()}, $spec)';
}
