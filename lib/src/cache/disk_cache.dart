import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../thumbnail_exception.dart';
import 'cache_key.dart';

/// LRU disk cache of encoded thumbnail files.
///
/// Design rules that keep the request hot path cheap:
/// - The index is fully in memory after [init]; [lookupPath] performs no
///   disk stat. (If the OS purges a file mid-session, the decode layer
///   detects it and evicts the entry.)
/// - Writers never write final names directly: natives fill an engine-chosen
///   `<name>.<rand>.part` temp file that [commit] renames atomically.
///   Crash leftovers are deleted during [init].
/// - Eviction runs asynchronously after commits, never blocking a request.
///
/// LRU order approximately survives restarts: hits refresh the in-memory
/// recency immediately and push it to the file mtime at most once per
/// [touchThrottle].
class DiskCache {
  /// Creates a cache rooted at [directory]. [now] is injectable for tests.
  DiskCache({
    required this.directory,
    required this.maxBytes,
    required this.maxEntries,
    this.touchThrottle = const Duration(hours: 1),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Root directory; created by [init].
  final Directory directory;

  /// Soft cap on total cached bytes; eviction targets 90% of it.
  final int maxBytes;

  /// Soft cap on the number of entries; eviction targets 90% of it.
  final int maxEntries;

  /// Minimum interval between mtime writes for the same entry.
  final Duration touchThrottle;

  final DateTime Function() _now;
  final Random _random = Random();
  final Map<String, _Entry> _index = {};
  int _totalBytes = 0;
  Future<void>? _evictionRun;

  /// Total bytes accounted in the index.
  int get totalBytes => _totalBytes;

  /// Number of committed entries.
  int get entryCount => _index.length;

  /// Creates the directory, deletes orphaned `.part` files, and builds the
  /// in-memory index from the files on disk.
  Future<void> init() async {
    await directory.create(recursive: true);
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.endsWith('.part')) {
        try {
          await entity.delete();
        } on FileSystemException {
          // Orphan cleanup is best-effort.
        }
        continue;
      }
      final stat = await entity.stat();
      final accessMs = stat.modified.millisecondsSinceEpoch;
      _index[name] = _Entry(stat.size, accessMs, accessMs);
      _totalBytes += stat.size;
    }
  }

  /// Returns the absolute path for [key] if cached, refreshing its recency.
  /// Performs no disk I/O beyond an occasional throttled mtime touch.
  String? lookupPath(CacheKey key) {
    final entry = _index[key.fileName];
    if (entry == null) return null;
    final now = _now();
    entry.lastAccessMs = now.millisecondsSinceEpoch;
    final path = _pathOf(key.fileName);
    if (now.millisecondsSinceEpoch - entry.lastTouchMs >=
        touchThrottle.inMilliseconds) {
      entry.lastTouchMs = now.millisecondsSinceEpoch;
      try {
        File(path).setLastModifiedSync(now);
      } on FileSystemException {
        // Best-effort; recency survives in memory for this session anyway.
      }
    }
    return path;
  }

  /// Reserves a unique temp path for [key] inside the cache directory.
  String tempPathFor(CacheKey key) {
    final rand = _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    return _pathOf('${key.fileName}.$rand.part');
  }

  /// Atomically publishes [tempPath] as the entry for [key] and returns the
  /// final path. Triggers asynchronous eviction when over the caps.
  Future<String> commit(CacheKey key, String tempPath) async {
    final finalPath = _pathOf(key.fileName);
    final int size;
    try {
      size = await File(tempPath).length();
      await File(tempPath).rename(finalPath);
    } on FileSystemException catch (e) {
      throw ThumbnailException(
        ThumbnailErrorCode.io,
        'failed to publish cache entry ${key.fileName}',
        cause: e,
      );
    }
    final previous = _index[key.fileName];
    if (previous != null) _totalBytes -= previous.size;
    final nowMs = _now().millisecondsSinceEpoch;
    _index[key.fileName] = _Entry(size, nowMs, nowMs);
    _totalBytes += size;
    if (_totalBytes > maxBytes || _index.length > maxEntries) {
      unawaited(evictIfNeeded());
    }
    return finalPath;
  }

  /// Deletes every entry whose file name starts with [sourcePrefix].
  Future<void> evictSource(String sourcePrefix) async {
    final names =
        _index.keys.where((n) => n.startsWith(sourcePrefix)).toList();
    for (final name in names) {
      await _deleteEntry(name);
    }
  }

  /// Deletes all entries and files.
  Future<void> clear() async {
    final names = _index.keys.toList();
    for (final name in names) {
      await _deleteEntry(name);
    }
    // Also remove any stray files (e.g. in-flight temp files).
    if (directory.existsSync()) {
      await for (final entity in directory.list()) {
        if (entity is File) {
          try {
            await entity.delete();
          } on FileSystemException {
            // Best-effort.
          }
        }
      }
    }
  }

  /// Evicts least-recently-used entries until both caps sit at or below
  /// their 90% watermarks. Serialized: concurrent calls share one run.
  @visibleForTesting
  Future<void> evictIfNeeded() {
    return _evictionRun ??= _evict().whenComplete(() => _evictionRun = null);
  }

  Future<void> _evict() async {
    final byteTarget = (maxBytes * 0.9).floor();
    final entryTarget = (maxEntries * 0.9).floor();
    if (_totalBytes <= maxBytes && _index.length <= maxEntries) return;
    final names = _index.keys.toList()
      ..sort((a, b) => _index[a]!.lastAccessMs.compareTo(_index[b]!.lastAccessMs));
    for (final name in names) {
      if (_totalBytes <= byteTarget && _index.length <= entryTarget) break;
      await _deleteEntry(name);
    }
  }

  Future<void> _deleteEntry(String name) async {
    final entry = _index.remove(name);
    if (entry != null) _totalBytes -= entry.size;
    try {
      await File(_pathOf(name)).delete();
    } on FileSystemException {
      // Already gone (OS purge, concurrent delete): index is corrected above.
    }
  }

  String _pathOf(String name) => p.join(directory.path, name);
}

class _Entry {
  _Entry(this.size, this.lastAccessMs, this.lastTouchMs);
  final int size;
  int lastAccessMs;
  int lastTouchMs;
}
