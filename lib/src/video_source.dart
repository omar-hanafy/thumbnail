import 'package:path/path.dart' as p;

/// Where a video comes from.
///
/// Identity semantics (used by `==`, the disk cache, and [VideoThumbnailImage]
/// equality): assets are identified by key + package, files by absolute path
/// (plus mtime and size at cache-key time, so edited files self-invalidate),
/// and network sources by URL only. HTTP headers are intentionally NOT part
/// of a network source's identity: auth tokens rotate while the content does
/// not. Call `ThumbnailEngine.evict` if a URL's content genuinely changed.
sealed class VideoSource {
  const VideoSource();

  /// A video bundled in the Flutter asset bundle.
  ///
  /// [assetKey] is the pubspec-declared key, e.g. `assets/videos/intro.mp4`.
  /// Pass [package] for assets that live in another package.
  factory VideoSource.asset(String assetKey, {String? package}) =
      AssetVideoSource;

  /// A video at an absolute local file [path].
  factory VideoSource.file(String path) = FileVideoSource;

  /// A video at an http(s) [url], optionally fetched with [headers].
  factory VideoSource.network(Uri url, {Map<String, String>? headers}) =
      NetworkVideoSource;

  /// Short human-readable form for error messages and logs.
  String describe();
}

/// A video bundled in the Flutter asset bundle.
final class AssetVideoSource extends VideoSource {
  /// Creates an asset source; [assetKey] must be non-empty.
  AssetVideoSource(this.assetKey, {this.package}) {
    if (assetKey.isEmpty) {
      throw ArgumentError.value(assetKey, 'assetKey', 'must not be empty');
    }
  }

  /// The pubspec-declared asset key.
  final String assetKey;

  /// Owning package for package-relative assets, if any.
  final String? package;

  @override
  String describe() => package == null ? 'asset:$assetKey' : 'asset:$package/$assetKey';

  @override
  bool operator ==(Object other) =>
      other is AssetVideoSource &&
      other.assetKey == assetKey &&
      other.package == package;

  @override
  int get hashCode => Object.hash(AssetVideoSource, assetKey, package);
}

/// A video at an absolute local file path.
final class FileVideoSource extends VideoSource {
  /// Creates a file source; [path] must be non-empty and absolute.
  FileVideoSource(this.path) {
    if (path.isEmpty || !p.isAbsolute(path)) {
      throw ArgumentError.value(path, 'path', 'must be an absolute file path');
    }
  }

  /// Absolute path of the video file.
  final String path;

  @override
  String describe() => 'file:$path';

  @override
  bool operator ==(Object other) => other is FileVideoSource && other.path == path;

  @override
  int get hashCode => Object.hash(FileVideoSource, path);
}

/// A video at an http(s) URL.
final class NetworkVideoSource extends VideoSource {
  /// Creates a network source; [url] must use the http or https scheme.
  NetworkVideoSource(this.url, {Map<String, String>? headers})
      : headers = headers == null ? null : Map.unmodifiable(headers) {
    if (url.scheme != 'http' && url.scheme != 'https') {
      throw ArgumentError.value(url, 'url', 'must use the http or https scheme');
    }
  }

  /// The video URL.
  final Uri url;

  /// Optional request headers. Not part of the source's identity.
  final Map<String, String>? headers;

  @override
  String describe() => 'url:$url';

  @override
  bool operator ==(Object other) => other is NetworkVideoSource && other.url == url;

  @override
  int get hashCode => Object.hash(NetworkVideoSource, url);
}
