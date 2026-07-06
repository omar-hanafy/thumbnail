## 0.1.0

Initial release: a disk-cached, scheduled, cancellable video thumbnail
engine for Android and iOS, designed for infinite feeds on low-end devices.

- Thumbnails from Flutter bundle assets, local files, and http(s) URLs
  (with optional request headers), requested with `getThumbnail` (a plain
  `Future`) or `thumbnail` (a cancellable request handle).
- `ThumbnailSpec` controls the output: fit-within sizing that preserves
  aspect ratio and never upscales, frame position (clamped into the video's
  duration), nearest-keyframe or exact-frame seeking, JPEG or PNG encoding,
  and JPEG quality.
- Persistent disk cache with deterministic keys, atomic writes, and LRU
  eviction capped by total bytes and entry count; hits are served from an
  in-memory index with no decoding and no platform-channel round trip. A
  file's cache identity includes its size and modification time, so editing
  a local video invalidates its thumbnails automatically.
- Request scheduling built for scroll performance: `visible`, `normal`, and
  `prefetch` priority bands, newest-first dispatch within a band, a bounded
  number of concurrent native extractions, coalescing of identical
  requests, per-request cancellation, priority bumping, and per-request
  timeouts.
- Negative caching: recent failures are remembered for a configurable TTL
  and fail fast instead of re-hammering a broken source during scroll.
- `VideoThumbnailImage`, an `ImageProvider` for any `Image` widget: its
  identity covers source and spec so Flutter's `ImageCache` deduplicates
  identical tiles, generation is cancelled when the last listener detaches,
  and externally purged or corrupted cache files are evicted and
  regenerated on the next resolve.
- Cache management: `prefetch` for warming, `evict` for a single source,
  and `clearCache` for everything.
- Every failure is a `ThumbnailException` carrying a classified
  `ThumbnailErrorCode` (asset/file not found, network, unsupported media,
  timeout, cancelled, ...); failures are never silently swallowed into
  nulls or booleans.
- Observability: a `metrics` snapshot (requests, cache hits, coalesced
  joins, extractions, failures, queue depth, and extraction and queue-wait
  percentiles) plus an `onEvent` hook for structured engine events.
- Engine tuning through `ThumbnailEngineConfig`: extraction concurrency,
  default timeout, negative-cache TTL, cache size caps, and the default
  spec.
- Hermetic test support: `ThumbnailEngine.forTesting` with an injectable
  `ThumbnailExtractor` and cache directory, so app tests run without native
  code.
