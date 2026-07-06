# Thumbnail Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `thumbnail` Flutter plugin: a cached, scheduled, cancellable video-thumbnail engine (assets, files, network URLs) with thin correct Kotlin/Swift extractors, per docs/superpowers/specs/2026-07-06-thumbnail-engine-design.md.

**Architecture:** Pure-Dart engine (scheduler + disk cache + negative cache + metrics + ImageProvider) over an injectable `ThumbnailExtractor` interface; v1 extractor is Pigeon-generated typed channels into stateless Kotlin (`MediaMetadataRetriever`) and Swift (`AVAssetImageGenerator`) executors. Natives encode straight into engine-chosen `.part` files; Dart commits with atomic renames.

**Tech Stack:** Flutter 3.44.x / Dart 3.12, Pigeon ^27.1.0 (dev), crypto ^3, path ^1.9, path_provider ^2.1, Kotlin coroutines, Swift 5.9+ with `#available(iOS 16)` async path.

## Global Constraints

- Package name `thumbnail`, org `tech.tomars`, version `0.1.0`, MIT (c) 2026 Omar Hanafy, homepage `https://github.com/omar-hanafy/thumbnail`.
- Dart SDK `^3.12.0`, Flutter `>=3.44.0`. Android minSdk 24. iOS deployment target: keep the flutter create template value (do not lower).
- Never use the em-dash character anywhere (docs, comments, strings). Use '-' instead.
- No `Co-Authored-By` or self-mention in any commit message.
- No WebP anywhere. Formats: jpeg (default), png.
- Defaults: quality 80, exact false, position 0, maxConcurrentExtractions 2, timeout 15s, negativeCacheTtl 60s, maxCacheBytes 256 MiB, maxCacheEntries 4000, evict-to 90% watermark, mtime touch throttle 1h.
- Errors are always `ThumbnailException` with a `ThumbnailErrorCode`; never null/false swallowing.
- Every Dart change: `dart analyze` clean before commit; `dart format .` before the final polish commit.
- Commit after each task (small, descriptive, imperative messages).

## File Structure (final)

```
pigeons/messages.dart                       Pigeon schema (single source of truth for the channel)
lib/thumbnail.dart                          Barrel export (public API only)
lib/src/video_source.dart                   sealed VideoSource + validation
lib/src/thumbnail_spec.dart                 ThumbnailSpec, ThumbnailFormat
lib/src/thumbnail_result.dart               Thumbnail, ThumbnailPriority
lib/src/thumbnail_exception.dart            ThumbnailErrorCode, ThumbnailException
lib/src/cache/cache_key.dart                canonical string, sha1, filename, source prefix
lib/src/cache/disk_cache.dart               index, atomic commit, LRU eviction, orphan cleanup, evict/clear
lib/src/cache/negative_cache.dart           TTL failure memo (injectable clock)
lib/src/scheduler/request_scheduler.dart    bands, LIFO, slots, cancel, bump, timeout
lib/src/extractor/thumbnail_extractor.dart  abstract extractor + ExtractionResult
lib/src/extractor/pigeon_extractor.dart     VideoSource->Pigeon mapping + error mapping
lib/src/pigeon/messages.g.dart              generated
lib/src/metrics.dart                        ThumbnailMetrics + events + ring buffer percentiles
lib/src/engine.dart                         ThumbnailEngine + ThumbnailEngineConfig + ThumbnailRequest
lib/src/image_provider.dart                 VideoThumbnailImage
android/src/main/kotlin/tech/tomars/thumbnail/ThumbnailPlugin.kt   plugin + pigeon setup
android/src/main/kotlin/tech/tomars/thumbnail/Extractor.kt         MMR extraction + encode
android/src/main/kotlin/tech/tomars/thumbnail/Messages.g.kt        generated
ios/Classes/ThumbnailPlugin.swift           plugin + pigeon setup + cancel registry
ios/Classes/Extractor.swift                 AVAssetImageGenerator extraction + encode
ios/Classes/messages.g.swift                generated
test/cache_key_test.dart, negative_cache_test.dart, disk_cache_test.dart,
test/request_scheduler_test.dart, engine_test.dart, image_provider_test.dart,
test/pigeon_mapping_test.dart, test/support/fake_extractor.dart
example/lib/main.dart                       demo screens + bench page
example/integration_test/thumbnail_test.dart
example/assets/fixtures/landscape.mp4, portrait_rot90.mp4
tool/generate_fixtures.sh                   ffmpeg commands used to produce fixtures (committed)
```

Delete from scaffold: `lib/thumbnail_platform_interface.dart`, `lib/thumbnail_method_channel.dart`, template tests, template method-channel code in both natives, template example body.

---

### Task 1: Scaffold cleanup, pubspec, Pigeon schema + codegen, plugin wiring compiles

**Files:** Modify `pubspec.yaml`, `lib/thumbnail.dart`, `android/.../ThumbnailPlugin.kt`, `ios/Classes/ThumbnailPlugin.swift`, `example/lib/main.dart` (placeholder body); Create `pigeons/messages.dart`; Delete template interface/method-channel/test files.

**Interfaces produced:** Pigeon types `PigeonSourceType {asset,file,network}`, `ExtractRequest{requestId,sourceType,source,assetPackage?,headers?,positionMs,exact,maxWidth,maxHeight,format,quality,destPath}`, `ExtractResult{width,height}`, `@HostApi ThumbnailHostApi{ @async ExtractResult extract(ExtractRequest r); void cancel(String requestId); }`.

Pigeon schema (complete):

```dart
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/src/pigeon/messages.g.dart',
  kotlinOut: 'android/src/main/kotlin/tech/tomars/thumbnail/Messages.g.kt',
  kotlinOptions: KotlinOptions(package: 'tech.tomars.thumbnail'),
  swiftOut: 'ios/Classes/messages.g.swift',
  dartPackageName: 'thumbnail',
))
enum PigeonSourceType { asset, file, network }

class ExtractRequest {
  ExtractRequest({ required this.requestId, required this.sourceType, required this.source,
    this.assetPackage, this.headers, required this.positionMs, required this.exact,
    required this.maxWidth, required this.maxHeight, required this.format,
    required this.quality, required this.destPath });
  String requestId;
  PigeonSourceType sourceType;
  String source;
  String? assetPackage;
  Map<String, String>? headers;
  int positionMs; bool exact; int maxWidth; int maxHeight;
  String format; int quality; String destPath;
}

class ExtractResult { ExtractResult({required this.width, required this.height}); int width; int height; }

@HostApi()
abstract class ThumbnailHostApi {
  @async ExtractResult extract(ExtractRequest request);
  void cancel(String requestId);
}
```

Steps: pubspec (description "High-performance video thumbnail engine: cached, scheduled, cancellable thumbnail generation from assets, files and network videos."; deps crypto/path/path_provider; dev pigeon ^27.1.0; homepage; remove plugin_platform_interface); delete template files; run `dart run pigeon --input pigeons/messages.dart`; stub natives to register pigeon API with a temporary `TODO`-free failing implementation (`FlutterError("unimplemented", ...)`) so everything compiles; `flutter pub get` + `dart analyze` clean in root and example; commit.

### Task 2: Value types + exception (TDD)

**Files:** Create `lib/src/{video_source,thumbnail_spec,thumbnail_result,thumbnail_exception}.dart`, `test/value_types_test.dart`.

**Produces:** `VideoSource.asset(key,{package})/.file(path)/.network(uri,{headers})` with `String describe()` for messages and validation (`asset key non-empty`, `file path non-empty and absolute`, `network scheme http/https`); `ThumbnailSpec` (defaults per Global Constraints, `ArgumentError` on negative sizes / quality outside 1..100, `copyWith`, `==`, `hashCode`); `ThumbnailFormat.jpeg/.png` with `extension` getter ('jpg'/'png') and `mimeType`; `Thumbnail{filePath,width,height,wasCached}`; `ThumbnailPriority{prefetch,normal,visible}`; `ThumbnailErrorCode` enum per spec section 9; `ThumbnailException{code,message,cause}` with readable `toString`.

Tests: construction, validation throws, equality/hashing, spec copyWith, network rejects `ftp://`, file rejects relative path.

### Task 3: Cache key (TDD, goldens)

**Files:** Create `lib/src/cache/cache_key.dart`, `test/cache_key_test.dart`.

**Produces:**

```dart
class CacheKey {
  final String canonical;     // v1|<sourceId>|<w>x<h>|p<ms>|e<0|1>|<fmt>|q<q>
  final String sourceId;      // a|<pkg or ''>|<key>   f|<abs>|<mtimeMs>|<size>   n|<url>
  final String fileName;      // <sha1(sourceId)[0..16)>-<sha1(canonical)[0..24)>.<ext>
  final String sourcePrefix;  // sha1(sourceId)[0..16)
  static Future<CacheKey> compute(VideoSource source, ThumbnailSpec spec); // stats file sources
  static CacheKey computeSync(VideoSource source, ThumbnailSpec spec, {int? fileMtimeMs, int? fileSize});
}
```

`compute` for `FileVideoSource` uses `File.stat()`; missing file -> `ThumbnailException(fileNotFound)`. Tests: golden canonical strings and filenames for one asset/file/network case (hardcoded expected sha1 prefixes computed in-test via crypto to stay stable), file identity changes when mtime/size change, headers do NOT affect the key, spec fields all affect the key, filename charset `[a-f0-9-]` + extension.

### Task 4: Negative cache (TDD)

**Files:** Create `lib/src/cache/negative_cache.dart`, `test/negative_cache_test.dart`.

**Produces:** `NegativeCache({required Duration ttl, DateTime Function()? now})` with `record(String key, ThumbnailException e)`, `ThumbnailException? lookup(String key)` (expired entries removed on lookup), `remove(key)`, `removeByPrefix(String sourcePrefix)` (for evict-by-source), `clear()`, `int get length`. Injectable clock; tests cover TTL expiry via fake clock, prefix removal, overwrite.

### Task 5: Disk cache (TDD, real temp dirs)

**Files:** Create `lib/src/cache/disk_cache.dart`, `test/disk_cache_test.dart`.

**Produces:**

```dart
class DiskCache {
  DiskCache({required Directory directory, required int maxBytes, required int maxEntries,
             DateTime Function()? now});
  Future<void> init();                       // mkdir -p, list dir, delete *.part orphans, build index
  String? lookupPath(CacheKey key);          // memoized index; touches lastAccess (throttled mtime write >=1h)
  String tempPathFor(CacheKey key);          // <dir>/<fileName>.<8 rand hex>.part
  Future<String> commit(CacheKey key, String tempPath); // atomic rename, index add, async evictIfNeeded()
  Future<void> evictSource(String sourcePrefix);        // delete matching files + index entries
  Future<void> clear();
  int get totalBytes; int get entryCount;
}
```

Eviction (complete algorithm): after commit, if `totalBytes > maxBytes || entryCount > maxEntries`, sort index by lastAccess ascending and delete until `totalBytes <= 0.9*maxBytes && entryCount <= 0.9*maxEntries`; deletions are awaited in tests via returned `Future` from exposed `@visibleForTesting Future<void> evictIfNeeded()`.

Tests: init on empty/missing dir; orphan `.part` removed while committed entries survive; commit renames (temp gone, final exists, `lookupPath` hits); double commit same key overwrite-safe; LRU eviction order (fake clock drives lastAccess; oldest deleted, watermark respected); evictSource removes only matching prefix; clear empties dir; index rebuild on new instance sees prior entries (restart survival); lookup of missing returns null.

### Task 6: Metrics

**Files:** Create `lib/src/metrics.dart`, `test/metrics_test.dart`.

**Produces:** `ThumbnailMetrics` immutable snapshot `{int requests, cacheHits, coalescedJoins, extractions, cancellations, timeouts, Map<ThumbnailErrorCode,int> failures, int queueDepth, activeJobs, Duration? extractP50, extractP95, queueWaitP50, queueWaitP95}`; internal `MetricsRecorder` with 256-sample ring buffers and `snapshot()`; `ThumbnailEvent` (enum kind + key + duration + error code) with `void Function(ThumbnailEvent)? onEvent` fan-out. Tests: counters, percentile math on known samples (p50/p95 nearest-rank), ring wraparound.

### Task 7: Request scheduler (TDD, the heart)

**Files:** Create `lib/src/scheduler/request_scheduler.dart`, `test/request_scheduler_test.dart`.

**Produces:**

```dart
typedef SchedulerWorker<T> = Future<T> Function();
class ScheduledJob<T> {
  Future<T> get future;                 // completes with worker result / ThumbnailException
  void cancel();                        // pre-dispatch: dequeue + complete(cancelled); running: detach only
  void bump(ThumbnailPriority p);       // raises band, re-inserts at front of new band
  bool get isRunning; bool get isDone;
}
class RequestScheduler {
  RequestScheduler({required int maxConcurrent});
  ScheduledJob<T> submit<T>(String key, ThumbnailPriority priority, Duration timeout, SchedulerWorker<T> worker);
  ScheduledJob<T>? existing<T>(String key); // dedup lookup for engine-level joining
  int get queueDepth; int get activeCount;
  Future<void> drain();                  // test helper: completes when queue+active empty
}
```

Dispatch loop (complete semantics): three deques (visible, normal, prefetch); `submit` push-front; free slot pops front of highest non-empty band; before running worker re-check `cancelled`; worker runs with `Future.any([worker(), timeoutFuture])`; timeout completes future with `ThumbnailException(timeout)` and marks job detached (worker result, when it eventually lands, is delivered to an `onOrphanResult(key, result)` callback the engine uses to still commit to cache); running-job `cancel()` only detaches (future completes with `cancelled`), engine decides native cancel. Dedup is engine-level: `existing(key)` returns a live job to join (scheduler stores jobs by key until done).

Tests (with `FakeAsync` where timing matters): FIFO slot limit respected (never > maxConcurrent concurrent workers); LIFO within band (submit A,B -> B runs first when 1 slot); band priority (visible beats normal beats prefetch even if enqueued later); cancel before dispatch never runs worker and frees queue; cancel while running detaches but worker completes and fires orphan callback; bump moves job to front of higher band; timeout fires `timeout` error, later worker success fires orphan callback; `existing` returns live job then null after completion; drain works; a worker throwing `ThumbnailException` propagates as-is, other errors wrapped as `extractionFailed`.

### Task 8: Extractor interface + Pigeon mapping (TDD for pure parts)

**Files:** Create `lib/src/extractor/thumbnail_extractor.dart`, `lib/src/extractor/pigeon_extractor.dart`, `test/pigeon_mapping_test.dart`, `test/support/fake_extractor.dart`.

**Produces:**

```dart
class ExtractionResult { final int width; final int height; }
abstract class ThumbnailExtractor {
  Future<ExtractionResult> extract({required String requestId, required VideoSource source,
    required ThumbnailSpec spec, required String destPath});
  Future<void> cancel(String requestId);   // no-op default ok
}
class PigeonExtractor implements ThumbnailExtractor { PigeonExtractor({ThumbnailHostApi? api}); ... }
ExtractRequest buildExtractRequest(...) // pure, unit-tested
ThumbnailException mapPlatformError(Object error) // pure: PlatformException(code 'code:detail') -> ThumbnailException
```

Error contract with natives: `PlatformException.code` is exactly one of `invalidSource|assetNotFound|fileNotFound|network|unsupportedMedia|extractionFailed|encodingFailed|io|cancelled`; anything else maps to `extractionFailed` with the raw code embedded in the message. `FakeExtractor` (test support): configurable delay/results/errors, writes a tiny valid 1x1 PNG (const byte list) or given bytes to `destPath`, records calls, supports hanging until released (for cancel/timeout tests).

Tests: request building for all three source types (asset package passthrough, headers passthrough, format string 'jpeg'/'png'), error mapping table, unknown code fallback.

### Task 9: Engine facade (TDD)

**Files:** Create `lib/src/engine.dart`, `test/engine_test.dart`; Modify `lib/thumbnail.dart` (exports).

**Produces (public):** `ThumbnailEngineConfig` (fields per Global Constraints + `Directory? cacheDirectoryOverride`, `ThumbnailSpec defaultSpec`, `copyWith`), `ThumbnailEngine.instance`, `ThumbnailEngine.forTesting({extractor, directory, config, now})`, `configure(config)` (live-updates limits; changing cache dir after first use -> `StateError`), `thumbnail(source,{spec,priority,timeout}) -> ThumbnailRequest`, `getThumbnail(...) -> Future<Thumbnail>`, `prefetch`, `evict(source)`, `clearCache()`, `metrics`, `onEvent`.

Request flow (exact): compute key -> `diskCache.lookupPath` hit returns completed request (`wasCached:true`, metrics cacheHit) -> negative cache hit returns failed request -> `scheduler.existing(key)` join (metrics coalescedJoins; joiner cancel only detaches that joiner via per-joiner completer; flight cancelled only when all joiners cancelled and not running, then extractor.cancel(requestId)) -> else submit worker: re-check disk, `tempPathFor`, `extractor.extract`, `commit`, return `Thumbnail`; on error record negative cache + metrics; orphan results (post-timeout/cancel) still committed via scheduler orphan callback. Lazy init: first request awaits `init()` of disk cache (path_provider dir unless override).

Tests (FakeExtractor + temp dir): cache hit path performs zero extractor calls; miss extracts once then hit; concurrent identical requests coalesce to one extraction, all complete; cancel sole pre-dispatch request -> extractor never called; cancel one of two joiners -> other still completes; cancel all joiners pre-dispatch -> extractor never called + extractor.cancel invoked if in flight; priority order visible-before-prefetch under 1-slot config; timeout produces timeout error, orphan result still cached (next request hits); failure -> negative cache fast-fails within TTL then retries after expiry (fake clock); evict removes disk + negative entries for that source only; clearCache empties; metrics counters accurate for the above; `getThumbnail` convenience works; configure live-updates concurrency.

### Task 10: ImageProvider (TDD)

**Files:** Create `lib/src/image_provider.dart`, `test/image_provider_test.dart`; export.

**Produces:** `VideoThumbnailImage(source, {spec, priority=visible, engine})` extends `ImageProvider<VideoThumbnailImage>`; `==`/`hashCode` over (source, spec, engine identity); `loadImage` -> engine request; decode committed file bytes via `decode(await ImmutableBuffer.fromFilePath(path))`; on decode failure evict key and rethrow; `MultiFrameImageStreamCompleter` with `addOnLastListenerRemovedCallback(request.cancel)`. Tests (flutter_test): resolves to correct dimensions from FakeExtractor PNG; identical providers share ImageCache entry (one engine call); listener-removal before completion cancels engine request (FakeExtractor hang + release; assert cancelled); corrupt cached file evicted then error surfaces.

### Task 11: Android extractor (Kotlin)

**Files:** Rewrite `android/.../ThumbnailPlugin.kt`, Create `android/.../Extractor.kt`. Verify: `cd example && flutter build apk --debug`.

Complete implementation requirements (code in plan appendix A of this file): coroutine scope `SupervisorJob() + Dispatchers.Default`, per-request `launch`; reply via `Handler(Looper.getMainLooper())` hop wrapped in the pigeon callback; data sources per spec section 7 (flutterAssets lookup + `openFd` + fd/offset/length, compressed-asset copy fallback to `<cacheDir>/thumbnail_assets/<sha1>.bin` guarded by a per-path mutex; file path direct; url + headers); metadata (width/height/rotation/duration, clamp positionMs into [0,duration]); rotation-aware fit box, never upscale; `getScaledFrameAtTime` on API>=27 when box constrains else `getFrameAtTime` (+ `createScaledBitmap` for API<27 only); `timeUs = positionMs.toLong()*1000L` always (no `-1` representative-frame shortcut; `0L` with `OPTION_CLOSEST_SYNC` gives the deterministic first sync frame). Encode jpeg/png via `bitmap.compress` into `BufferedOutputStream(FileOutputStream(destPath))`, `flush/close`, `bitmap.recycle()`, `retriever.release()` in `finally`; map failures: `FileNotFoundException|ENOENT`->fileNotFound, asset lookup failure->assetNotFound, `setDataSource` IOException on http->network, null frame / no video track->unsupportedMedia, compress/write IOException->io or encodingFailed, else extractionFailed; `cancel` = no-op (documented). `FlutterError(code, message, null)` with codes exactly per Task 8 contract.

### Task 12: iOS extractor (Swift)

**Files:** Rewrite `ios/Classes/ThumbnailPlugin.swift`, Create `ios/Classes/Extractor.swift`; podspec description/homepage/license update. Verify: `cd example && flutter build ios --debug --simulator --no-codesign`.

Complete implementation requirements (appendix B): per-request `AVAssetImageGenerator` stored in `ThreadSafeDictionary [requestId: AVAssetImageGenerator]`; sources: asset via `FlutterDartProject.lookupKey(forAsset:fromPackage:)` + `Bundle.main.path(forResource:ofType:nil)` -> file URL (missing -> assetNotFound), file via `URL(fileURLWithPath:)` + existence check (fileNotFound), network via `URL(string:)` (invalidSource on parse fail) + `AVURLAsset(url, options: headers.map{[ "AVURLAssetHTTPHeaderFieldsKey": $0 ]})`; video-track guard (`unsupportedMedia`); tolerances/maximumSize/transform per spec section 8; iOS16+: `try await generator.image(at: time)`; else continuation-wrapped `generateCGImagesAsynchronously(forTimes:)` mapping `.cancelled` result; clamp position to duration (`try await asset.load(.duration)` on 16+, `loadValuesAsynchronously(forKeys:)` continuation otherwise); encode via `CGImageDestinationCreateWithURL` (UTType.jpeg/png; lossy quality for jpeg) -> finalize failure = encodingFailed; work in `Task.detached(priority: .utility)`; completion invoked on main queue; `cancel(requestId)` -> generator.cancelAllCGImageGeneration() + registry removal; error mapping: URLError/AVError network codes -> network, cancelled -> cancelled, else extractionFailed; codes exactly per Task 8 contract.

### Task 13: Fixtures + integration tests

**Files:** Create `tool/generate_fixtures.sh`, `example/assets/fixtures/landscape.mp4`, `example/assets/fixtures/portrait_rot90.mp4` (ffmpeg: 1s, 30fps, x264 yuv420p, faststart; portrait via `-metadata:s:v rotate=90` display matrix), example pubspec asset entries, `example/integration_test/thumbnail_test.dart`.

Test list: asset landscape jpeg fits 320x320 box with correct aspect (640x360 -> 320x180) + JPEG magic (FF D8); portrait rotation honored (width<height); png format magic; exact vs keyframe at position 500ms both succeed; file source (copy fixture to temp) works and re-keys on modification; network via in-process `HttpServer` on 127.0.0.1 serving fixture with required header assertion (missing header -> 401 -> network error; correct header -> success); 404 -> network; garbage bytes served -> unsupportedMedia or extractionFailed; 24-request mixed-priority burst completes with maxConcurrent respected (engine metric activeJobs never observed above config; assert via final metrics + success count); cancel storm (submit 30 prefetch, cancel all, queue drains, engine still serves a fresh request). Run on available simulator/emulator; if none available, compile-check via `flutter build` and note in summary.

### Task 14: Example app + bench page

**Files:** Rewrite `example/lib/main.dart` (+ `example/lib/bench_page.dart`).

Demo tab: three tiles (asset, file-copied-from-asset, network sample URL text field) rendered with `Image(image: VideoThumbnailImage(...))`. Bench tab: parameters (count, concurrency, size), run cold (clearCache) vs warm, show p50/p95/total/hit-rate from `engine.metrics`, plus a 200-item `ListView.builder` of thumbnails to eyeball scroll behavior.

### Task 15: Docs + polish + full verification

**Files:** `README.md` (hero pitch, why-not-X table grounded in the audit, quickstart, API tour, performance guide for feeds, error table, cache behavior, limitations incl. remote-video cost + content:// future), `CHANGELOG.md` (0.1.0), `LICENSE` (MIT Omar Hanafy), dartdoc on every public symbol, `analysis_options.yaml` (flutter_lints + `public_member_api_docs: true` consideration), `dart format .`, full `dart analyze` (root + example), `flutter test`, both example builds, `flutter pub publish --dry-run` (validate only, DO NOT publish).

## Self-Review (performed)

- Spec coverage: sections 1-12 all map to tasks (spec s4->T2/T9/T10, s5->T7/T9, s6->T3/T5, s7->T11, s8->T12, s9->T2/T8, s10->T10, s11->T6, s12->T3..T10 unit + T13 integration, s13 milestones == task order). No gaps.
- Placeholders: none; every task states exact files, signatures, behaviors, and test lists; native appendices are the task bodies themselves (11/12).
- Type consistency: `CacheKey` consumed by DiskCache/Engine matches T3; `ScheduledJob`/`existing` used by engine matches T7; `ThumbnailExtractor.extract(requestId, source, spec, destPath)` consistent across T8/T9/T11/T12 via Pigeon `ExtractRequest`.
