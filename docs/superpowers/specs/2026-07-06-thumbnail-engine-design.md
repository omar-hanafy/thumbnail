# thumbnail: a video thumbnail engine for Flutter

Date: 2026-07-06
Status: approved (part 1 explicitly by Omar; part 2 details decided autonomously per Omar's directive, logged in Decision Log)
Package name: `thumbnail` (verified 404 on pub.dev on 2026-07-06)
Publisher: tomars.tech / Omar Hanafy
Platforms v1: Android, iOS

## 1. Problem

Feed apps need video thumbnails inside infinite, fast-scrolling lists on low-end devices. The goal of this package is that thumbnail generation is never the performance suspect: when the feed janks, it is provably something else. The deliverable is the engine only; the feed UI itself is out of scope.

Existing packages were audited from local clones on 2026-07-06:

- `video_thumbnail` 0.5.6 (justsoft): native-first (correct category) but defect-heavy. Verified in source: `OPTION_CLOSEST` everywhere, `timeMs * 1000` int overflow after ~35.8 min, unclosed `FileInputStream` per local call, unbounded `newCachedThreadPool`, file output built through `byte[]` in memory, PNG + quality 10 defaults, iOS `FlutterResult` invoked from a background queue, WebP branch leaks (`CGImage`, encoder output buffer) and over-releases Get-rule objects (`CGColorSpaceRelease`, `CGDataProviderRelease`), AGP 4.1 + jcenter + minSdk 16 + iOS 8 target, no cache, no asset support (README says copy asset to temp file yourself). Upstream inactive ~13 months.
- `flutter_video_thumbnail_plus` 1.0.5: copy-fork of the above. Inherits every defect above verbatim (same Java, same ObjC, same WebP leaks, same `OPTION_CLOSEST`). Adds federation and a `dart:html` web hack. Dart SDK capped `<3.0.0`. Dead ~18 months.
- `fc_native_video_thumbnail` 3.0.1: modern and maintained (Kotlin coroutines, `OPTION_CLOSEST_SYNC`, `getScaledFrameAtTime`, AGP 9, June 2026 activity). But: JPEG only (Android ignores the format arg), no remote URL or headers support, no asset support, iOS/macOS uses exact zero tolerances (the slow seek path) with synchronous `copyCGImage`, errors swallowed into false/null, no cache, no scheduler.

None of the three has: caching, request scheduling, deduplication, cancellation, priorities, asset-bundle sources, timeouts, or metrics. That gap is the engine.

## 2. Goals

1. Sources: Flutter bundle assets, plain local file paths, http(s) URLs with optional headers.
2. Cache-hit path costs no channel traffic, no extraction, no disk stat (memoized index).
3. Fling-storm safety: bounded native concurrency, newest-first scheduling, free cancellation of not-yet-started work, coalescing of identical requests, negative caching of recent failures.
4. Extraction itself takes the cheapest correct native path (sync-frame seek, decode-time scaling, direct-to-file encode).
5. Typed errors; failures are never silently swallowed.
6. Observability: enough metrics to prove where time goes.
7. Publishable quality: docs, example + benchmark app, tests, semantic versioning.

Non-goals (v1): web/desktop backends, WebP output, FFmpeg fallback, server-side thumbnailing, `content://` URIs (cheap later add, documented), building the feed UI.

## 3. Architecture

One plugin package, not federated. Federation pays off when third parties ship platform implementations; our extension point is the Dart-level `ThumbnailExtractor` interface inside the package. A platform interface package can be split out later without breaking the public API.

    +---------------------------------------------------+
    | App (feed)  Image(image: VideoThumbnailImage(..)) |
    +---------------------------------------------------+
    | ENGINE (pure Dart, unit-testable)                 |
    |   ThumbnailEngine facade                          |
    |    - RequestScheduler: priority bands, LIFO       |
    |      within band, dedup, cancel, N native slots   |
    |    - DiskCache: deterministic keys, atomic        |
    |      writes, LRU eviction, orphan cleanup         |
    |    - Negative cache (in-memory, TTL)              |
    |    - Metrics                                      |
    +---------------------------------------------------+
    | ThumbnailExtractor (abstract, injectable)         |
    |   v1: PigeonExtractor                             |
    +---------------------------------------------------+
    | Kotlin: MediaMetadataRetriever                    |
    | Swift: AVAssetImageGenerator                      |
    +---------------------------------------------------+

## 4. Public API

```dart
sealed class VideoSource {
  const factory VideoSource.asset(String assetKey, {String? package}) = AssetVideoSource;
  const factory VideoSource.file(String path) = FileVideoSource;
  const factory VideoSource.network(Uri url, {Map<String, String>? headers}) = NetworkVideoSource;
}

enum ThumbnailFormat { jpeg, png }

@immutable
class ThumbnailSpec {
  const ThumbnailSpec({
    this.maxWidth = 0,          // physical px, 0 = unconstrained
    this.maxHeight = 0,         // fit-within box, aspect preserved, never upscaled
    this.position = Duration.zero,
    this.exact = false,         // false = nearest keyframe (fast path)
    this.format = ThumbnailFormat.jpeg,
    this.quality = 80,          // 1..100
  });
}

enum ThumbnailPriority { prefetch, normal, visible }

class Thumbnail {
  final String filePath;
  final int width;
  final int height;
  final bool wasCached;
}

class ThumbnailRequest {
  Future<Thumbnail> get result;
  void cancel();
  void bumpPriority(ThumbnailPriority priority);
}

class ThumbnailEngine {
  static ThumbnailEngine get instance;
  Future<void> configure(ThumbnailEngineConfig config); // optional, idempotent-safe
  ThumbnailRequest thumbnail(VideoSource source, {ThumbnailSpec spec, ThumbnailPriority priority, Duration? timeout});
  Future<Thumbnail> getThumbnail(VideoSource source, {ThumbnailSpec spec, ...}); // convenience await
  void prefetch(VideoSource source, {ThumbnailSpec spec});
  Future<void> evict(VideoSource source);   // all specs for that source
  Future<void> clearCache();
  ThumbnailMetrics get metrics;             // snapshot
  set onEvent(ThumbnailEventListener? l);   // optional structured log hook
}

class VideoThumbnailImage extends ImageProvider<VideoThumbnailImage> { ... }
```

`ThumbnailEngineConfig`: `maxConcurrentExtractions` (default 2, allowed 1..8; use 1 for very low-end fleets), `defaultTimeout` (default 15s), `negativeCacheTtl` (default 60s), `maxCacheBytes` (default 256 MiB), `maxCacheEntries` (default 4000), `cacheDirectoryOverride`, `defaultSpec`.

## 5. Request lifecycle

1. Canonicalize (source, spec) to a cache key (section 6).
2. If the in-memory disk index knows the file: return completed result (`wasCached: true`).
3. If an identical key is in flight: join it (one extraction, N futures).
4. If the key is negative-cached and unexpired: fail fast with the memoized error.
5. Enqueue into the band deque (visible > normal > prefetch), push-front so newest wins. Scheduler dispatches whenever one of N slots frees; before dispatch it re-checks cancellation and cache.
6. Native extracts and encodes directly into an engine-chosen `.part` temp path inside the cache dir, returns actual dimensions. Dart renames atomically to the final name, updates index + LRU accounting, completes all joined futures.
7. Timeout (Dart-side watchdog): completes the future with `ThumbnailErrorCode.timeout`; on iOS also cancels natively; on Android the orphaned result may still land in cache (sunk cost, next request hits).
8. `cancel()`: pre-dispatch and sole-joiner: dequeued for free. Joined: detaches only that future. In-flight: iOS cancels natively when it was the sole joiner; Android lets it finish into cache.

Failure completes all joiners with `ThumbnailException` and writes the negative-cache entry.

## 6. Disk cache

- Location: `<getApplicationCacheDirectory()>/thumbnail/v1/`. OS-purgeable by design; engine re-extracts on miss. `v1` = schema version for wholesale invalidation.
- Canonical key string: `v1|<sourceId>|<maxW>x<maxH>|p<positionMs>|e<0|1>|<fmt>|q<quality>`.
  - asset: `a|<package or ''>|<assetKey>`
  - file: `f|<absolute path>|<mtimeMs>|<sizeBytes>` (self-invalidates on file change)
  - network: `n|<url>` (headers intentionally excluded from identity; documented)
- Filename: `<sha1(sourceId) first 16 hex>-<sha1(canonical) first 24 hex>.<jpg|png>`. The source prefix enables `evict(source)` by directory prefix scan.
- Writes: `<name>.<rand>.part` then atomic rename. Orphaned `.part` files deleted during index build.
- Index: built lazily and asynchronously on first use (single dir list); in-memory map name -> (size, lastAccess). Hits update lastAccess in memory; file mtime touched at most once per hour per entry so LRU order approximately survives restarts.
- Eviction: when over `maxCacheBytes` or `maxCacheEntries`, delete LRU entries until at 90% watermark; runs async off the request path.
- Negative cache: in-memory `key -> (error, expiry)`; TTL default 60s; cleared by `evict`/`clearCache`.

## 7. Android extractor (Kotlin)

- Toolchain: Kotlin as generated by Flutter 3.44 template; minSdk 24; compileSdk latest stable.
- Pigeon `@async` HostApi; each request runs in a coroutine on `Dispatchers.Default` (`SupervisorJob`); replies hop to the main thread. Concurrency is governed by the Dart scheduler only.
- Data source selection:
  - asset: `flutterAssets.getAssetFilePathByName(key[, package])` then `context.assets.openFd(lookupKey)` and `setDataSource(fd, startOffset, declaredLength)`. If the asset is compressed in the APK (`openFd` throws), one-time stream copy to `<cache>/thumbnail/assets/<hash>` and use the file path (mp4/m4v/webm are in aapt's default noCompress list, so the copy path is rare).
  - file: `setDataSource(path)` directly. No FileInputStream, no FD leak class.
  - network: `setDataSource(url, headers ?: emptyMap())`.
- Metadata first: width, height, rotation, duration via `extractMetadata`; clamp position into `[0, duration]`; compute the rotation-aware fit box; never upscale.
- Frame: API >= 27 and a constraining box: `getScaledFrameAtTime(timeUs, option, w, h)`; else `getFrameAtTime(timeUs, option)` plus `createScaledBitmap` only if needed (API 24..26 only). `option = if (exact) OPTION_CLOSEST else OPTION_CLOSEST_SYNC`. `timeUs = positionMs.toLong() * 1000L` (overflow impossible by construction).
- Encode: `bitmap.compress(JPEG|PNG, quality, BufferedOutputStream(FileOutputStream(destPath)))`; `bitmap.recycle()`; `retriever.release()` in `finally`.
- Returns actual width/height. Errors mapped to structured codes (section 9). No native cancel in v1: MMR is not safely abortable; canceling releases from another thread risks native crashes. Dart-side detach covers the semantics.

## 8. iOS extractor (Swift)

- Min iOS per current Flutter template (>= 13); `#available(iOS 16)` branch uses `try await generator.image(at:)`, otherwise `generateCGImagesAsynchronously(forTimes:)` wrapped in a checked continuation. Both paths support cancellation.
- One `AVAssetImageGenerator` per request, retained in a `[requestId: generator]` map so `cancel(requestId)` can call `cancelAllCGImageGeneration()` for that request only.
- `AVURLAsset` with `AVURLAssetHTTPHeaderFieldsKey` option when headers are provided (de facto standard key; documented as such). Asset sources resolve via `FlutterDartProject.lookupKey(forAsset:fromPackage:)` + `Bundle.main.path(...)`; file sources via `URL(fileURLWithPath:)`.
- Generator config: `appliesPreferredTrackTransform = true`; `maximumSize = fit box` (AVFoundation preserves aspect within it); tolerances `.zero`/`.zero` when `exact`, else `.positiveInfinity` both ways (nearest keyframe, cheapest decode).
- Guard: no video track -> `unsupportedMedia`.
- Encode: `CGImageDestinationCreateWithURL(tempURL, UTType.jpeg/png, 1, nil)` + `kCGImageDestinationLossyCompressionQuality` for JPEG; `CGImageDestinationFinalize`. No `UIImage`, no intermediate `NSData`, no WebP (whole libwebp bug class excluded by design).
- Extraction work off the main thread; Pigeon completion invoked on the main thread (platform-channel threading contract).

## 9. Error model

```dart
enum ThumbnailErrorCode {
  invalidSource, assetNotFound, fileNotFound, network,
  unsupportedMedia, extractionFailed, encodingFailed,
  io, timeout, cancelled,
}
class ThumbnailException implements Exception {
  final ThumbnailErrorCode code; final String message; final Object? cause;
}
```

Natives throw Pigeon errors carrying `code:detail`; the Dart layer maps them. A request never resolves to null; `bool`-swallowing (fc) and stringly errors (justsoft) are both rejected patterns.

## 10. ImageProvider integration

`VideoThumbnailImage` (`obtainKey` = source + spec + engine identity, proper `==`/`hashCode` so Flutter's `ImageCache` dedups). `loadImage` runs `engine.thumbnail(..., priority: visible)`, decodes the resulting file with the provided decoder (file is already at target size, so decode cost is exact), and registers a last-listener-removed callback that calls `request.cancel()`. Result: any plain `Image` widget in a recycled list cell gets fling cancellation with zero app code.

## 11. Metrics

Snapshot counters: requests, cacheHits, coalescedJoins, extractions, failuresByCode, cancellations, timeouts, queueDepth, activeJobs; timing ring buffer (256 samples) with p50/p95 for queueWait/extract/total. Optional `onEvent` callback streams structured events for logging. The example app's bench page renders these.

## 12. Testing

- Pure Dart unit tests (bulk of the suite; `FakeExtractor`, temp dirs, fake clock): key canonicalization goldens; cache atomic writes, orphan cleanup, LRU eviction, touch throttling; scheduler band ordering, LIFO within band, dedup joining, cancel semantics, concurrency cap, timeout, negative-cache TTL; engine facade; provider behavior.
- Integration tests (example/integration_test, run on emulator/simulator): committed tiny fixture videos (landscape, portrait-by-rotation-metadata, ~1s) served also via an in-process `HttpServer` that asserts received headers; assertions on fit-box dimensions + aspect + rotation, JPEG/PNG magic bytes, keyframe vs exact positioning, 404 -> network, garbage bytes -> unsupportedMedia/extractionFailed, 24-request burst completes under the concurrency cap, cancel storm leaves no wedged queue.
- Benchmark page in the example app: cold vs warm burst of N thumbnails, p50/p95/total, hit rate, concurrency toggle. This is the "prove it is not the thumbnails" tool.

## 13. Milestones

1. Repo scaffold, Pigeon schema + codegen, CI-friendly analyze/format.
2. Dart core TDD: sources/spec/keys, disk cache, scheduler, engine facade, errors, metrics.
3. Android extractor + integration tests.
4. iOS extractor + integration tests.
5. ImageProvider, bench page, README/dartdoc/CHANGELOG polish.
6. Full verification: `dart analyze`, `dart format`, unit suite, example builds for Android + iOS.

## 14. Decision log (autonomous decisions, per Omar's directive)

- Package name `thumbnail` per Omar (404-verified). Org `tech.tomars` matching verified publisher tomars.tech. Homepage `https://github.com/omar-hanafy/thumbnail`. MIT, (c) 2026 Omar Hanafy.
- Single package, not federated (reasoning in section 3).
- No WebP in v1 on either platform: removes a whole native-bug class; JPEG covers the use case; Android-only WebP would break parity.
- JPEG quality default 80 (75-85 is the sweet band; 80 balances low-end encode cost vs size).
- Headers excluded from cache identity (auth tokens rotate; content does not). Documented; `evict` covers edge cases.
- Android native cancel omitted in v1 (MMR unsafe to abort); iOS native cancel included (free with per-request generator).
- Dart-side concurrency control only; natives are stateless executors.
- `crypto`, `path_provider`, `path` as runtime deps; `pigeon` dev-only.
- Timeout watchdog lives in Dart so both platforms behave identically; iOS additionally aborts native work.
