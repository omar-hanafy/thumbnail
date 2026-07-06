# cached_video_thumbnail

A high-performance video thumbnail engine for Flutter. Generates thumbnails
from **bundle assets**, **local files**, and **network URLs** through a
cached, scheduled, cancellable pipeline built for one goal: in an infinite,
fast-flinging feed on a low-end device, thumbnail generation is never the
reason the UI janks.

## Why another thumbnail package?

Existing packages give you a one-shot `video -> image` call. That is the easy
20%. The hard 80% is what happens when a feed asks for 40 thumbnails during a
fling: unbounded native decoders, no caching, no deduplication, no
cancellation, bytes shipped over the platform channel, and slow exact-frame
seeks. This package is an engine, not a converter:

| Capability | cached_video_thumbnail |
|---|---|
| Disk cache (deterministic keys, LRU, atomic writes) | yes |
| Cache hits without decoding (dims stored in the entry) | yes |
| Bounded native concurrency (default 2) | yes |
| Newest-first priority scheduling (visible > normal > prefetch) | yes |
| Identical requests coalesce into one extraction | yes |
| Cancellation (free pre-dispatch, native abort on iOS) | yes |
| Negative caching of recent failures | yes |
| Keyframe-fast seeks by default, exact frames opt-in | yes |
| Direct-to-file native encoding (no byte arrays over the channel) | yes |
| Typed errors, metrics, event hook | yes |

Native side: Kotlin `MediaMetadataRetriever` with `OPTION_CLOSEST_SYNC` and
`getScaledFrameAtTime` (decode-time downscaling); Swift
`AVAssetImageGenerator` with infinite tolerances by default, a precomputed
fit box, and per-request cancellation. No FFmpeg, no extra native
dependencies.

## Quickstart

```dart
import 'package:cached_video_thumbnail/cached_video_thumbnail.dart';

// The simplest path: drop the provider into any Image widget.
Image(
  image: VideoThumbnailImage(
    VideoSource.network(Uri.parse('https://cdn.example.com/v.mp4')),
    spec: const ThumbnailSpec(maxWidth: 480, maxHeight: 480),
  ),
  fit: BoxFit.cover,
)
```

Or drive the engine directly:

```dart
final engine = ThumbnailEngine.instance;

final thumb = await engine.getThumbnail(
  VideoSource.asset('assets/videos/intro.mp4'),
  spec: const ThumbnailSpec(maxWidth: 320, maxHeight: 320),
);
// thumb.filePath, thumb.width, thumb.height, thumb.wasCached
```

## Sources

```dart
VideoSource.asset('assets/videos/intro.mp4', package: 'my_pkg'); // bundle asset
VideoSource.file('/path/to/video.mp4');                          // absolute path
VideoSource.network(url, headers: {'Authorization': 'Bearer t'}); // http(s)
```

- File sources embed mtime + size in the cache identity, so edited files
  self-invalidate.
- Network headers are passed to the platform media stack but are not part of
  the cache identity (tokens rotate; content does not). Call `evict` if a
  URL's content genuinely changed.

## Specs

```dart
const ThumbnailSpec(
  maxWidth: 480,   // fit-within box, physical px; 0 = unconstrained
  maxHeight: 480,  // aspect preserved; frames are never upscaled
  position: Duration.zero,
  exact: false,    // false = nearest keyframe (fast); true = exact frame
  format: ThumbnailFormat.jpeg, // or png
  quality: 80,
);
```

Keep `exact: false` for feeds. Exact seeking can force the decoder to chew
through every frame since the previous keyframe.

## Requests, priorities, cancellation

```dart
final request = engine.thumbnail(
  source,
  spec: spec,
  priority: ThumbnailPriority.visible, // visible > normal > prefetch
  timeout: const Duration(seconds: 15), // counted from native dispatch
);
final thumb = await request.result;

request.cancel();                    // detach; queued work is dequeued free
request.bumpPriority(ThumbnailPriority.visible);

engine.prefetch(source, spec: spec); // fire-and-forget warmup
```

Within a band the newest request dispatches first: during a fling, the cells
the user is looking at now beat the ones from two flings ago. Identical
in-flight requests share one extraction; cancelling one joiner never affects
the others.

`VideoThumbnailImage` wires cancellation automatically: when the last
listener detaches before completion, the request is cancelled.

## Configuration

```dart
await ThumbnailEngine.instance.configure(const ThumbnailEngineConfig(
  maxConcurrentExtractions: 2, // 1..8; use 1 for very low-end fleets
  defaultTimeout: Duration(seconds: 15),
  negativeCacheTtl: Duration(seconds: 60),
  maxCacheBytes: 256 << 20,
  maxCacheEntries: 4000,
  defaultSpec: ThumbnailSpec(maxWidth: 480, maxHeight: 480, quality: 80),
));
```

Cache sizing must be configured before the first request; everything else
applies live.

## Cache behavior

- Location: the app cache directory (`<cache>/thumbnail/v1/`). The OS may
  purge it; the engine re-extracts on demand.
- Hits are answered from an in-memory index: no platform channel, no disk
  stat, and no decoding (entry dimensions are stored in the file name).
- Writes are atomic (temp file + rename); crash leftovers are swept on init.
- LRU eviction targets 90% of the caps and runs off the request path.
- `evict(source)` removes every spec and content version of one source;
  `clearCache()` removes everything.

## Errors

Every failure is a `ThumbnailException` with a `ThumbnailErrorCode`:

| Code | Meaning |
|---|---|
| `invalidSource` | Structurally invalid input (bad URL, ...) |
| `assetNotFound` / `fileNotFound` | Source does not exist |
| `network` | Connectivity/HTTP failure |
| `unsupportedMedia` | No decodable video track / unsupported codec |
| `extractionFailed` | Decoder failed for another reason |
| `encodingFailed` | Frame could not be encoded |
| `io` | Local write/rename failure |
| `timeout` | Exceeded the request timeout |
| `cancelled` | Cancelled by the caller |

Recent failures are negative-cached for `negativeCacheTtl`, so a broken URL
fast-fails during scroll instead of re-hammering the network. Cancellations
are never negative-cached.

## Metrics

```dart
final m = ThumbnailEngine.instance.metrics;
// m.requests, m.cacheHits, m.coalescedJoins, m.extractions,
// m.extractP50/P95, m.queueWaitP50/P95, m.failures, m.queueDepth ...

ThumbnailEngine.instance.onEvent = (event) => log(event.toString());
```

The example app ships a benchmark page (cold vs warm runs, percentiles, a
200-cell scroll test) so you can measure on your own fleet.

## Feed checklist

1. Use `VideoThumbnailImage` inside cells; give every cell an explicit
   `ThumbnailSpec` box matching its physical pixel size.
2. Prefetch ahead of the viewport with `engine.prefetch` (prefetch band
   never blocks visible work).
3. Keep `maxConcurrentExtractions` at 2 (or 1 for very low-end devices).
4. Remote videos: on-device extraction downloads enough of the file to
   decode a frame (cheap for faststart MP4s, worse for badly muxed files).
   If you control the backend, server-generated thumbnails are still the
   fastest option for users; this engine is for when you do not.

## Platform notes

- Android: minSdk 24. Assets are read straight from the APK via file
  descriptors (a one-time copy fallback handles compressed assets).
  Cancellation of in-flight native work is not supported by
  `MediaMetadataRetriever`; the engine detaches the request and banks the
  finished frame in the cache instead. HTTP-error URLs (e.g. a 404) may
  classify as `timeout` rather than `network` on some devices: the platform
  retriever retries internally without surfacing the status code, so the
  engine's deadline is what ends the attempt (bounded and negative-cached
  either way).
- iOS: deployment target 13.0. Uses the async generator API on iOS 16+, with
  a continuation fallback below. Network headers use the de-facto
  `AVURLAssetHTTPHeaderFieldsKey` option.

## Not in v1 (by design)

- `content://` URIs (planned; cheap to add).
- WebP output (would drag a native dependency and its bug class along).
- Desktop/web backends and an FFmpeg fallback for exotic codecs: the
  extractor is a small Dart interface (`ThumbnailExtractor`), so backends
  can be added without touching the engine.

## License

MIT (c) 2026 Omar Hanafy
