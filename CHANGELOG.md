## 0.1.0-dev.2

- No functional changes. First version released through the automated
  tag-driven publishing pipeline (CI, pana gate, OIDC publish).

## 0.1.0-dev.1

Initial release (prerelease).

- Thumbnail generation from Flutter bundle assets, local files, and http(s)
  URLs (with request headers) on Android and iOS.
- Disk cache with deterministic keys, atomic writes, LRU eviction, and
  dimension-aware cache hits that require no decoding.
- Request scheduler: priority bands (visible/normal/prefetch), newest-first
  dispatch, bounded native concurrency, request coalescing, cancellation,
  and per-request timeouts.
- Negative caching of recent failures to protect scroll performance.
- `VideoThumbnailImage` ImageProvider with automatic cancellation when the
  last listener detaches and recovery from externally purged cache files.
- Typed `ThumbnailException` error model and engine metrics
  (hits/misses/percentiles) with a structured event hook.
