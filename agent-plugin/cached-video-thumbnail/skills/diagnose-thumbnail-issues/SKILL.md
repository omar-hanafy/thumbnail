---
name: diagnose-thumbnail-issues
description: Use when cached_video_thumbnail misbehaves - ThumbnailException errors (timeout, network, unsupportedMedia, extractionFailed), thumbnails failing instantly on retry, wrong or stale images, cache misses or repeated extraction, scroll jank blamed on thumbnails, black or rotated frames, HLS streams, or Android/iOS behavior differences.
---

# Diagnose cached_video_thumbnail issues

Most "bugs" reported against this engine are documented, deliberate
behavior (negative caching, keyframe snapping, platform quirks). Diagnose
from evidence - the error code and the metrics snapshot - before proposing
fixes. Full tables: [error-codes-and-platform-behavior.md](references/error-codes-and-platform-behavior.md).

## Triage workflow

1. **Get the `ThumbnailErrorCode`** (from the exception, `engine.onEvent`
   log, or `metrics.failures`). Never diagnose from the message string
   alone; the code is the classification.
2. **Read `ThumbnailEngine.instance.metrics`** and compute:
   - hit ratio = `cacheHits / requests` (warm scrolling should approach 1);
   - `coalescedJoins` high = duplicate simultaneous requests (usually fine);
   - `extractP95` high = decode cost (spec too large? exact seeks? remote
     non-faststart files?);
   - `queueWaitP95` high with low `extractP95` = concurrency starvation or
     a request storm;
   - `failures` map = what is actually failing, by code.
3. **Match against the known-behavior table** below before reading engine
   source. If the report matches a row, it is working as designed - explain
   the mechanism and apply the documented remedy.
4. Only then suspect a real defect; reproduce minimally (one source, one
   spec, `getThumbnail`) and check the package issue tracker.

## Known behavior that gets reported as bugs

| Report | Mechanism | Remedy |
|---|---|---|
| "Failed once, now fails instantly for ~a minute" | Negative cache memoizes non-cancellation failures for `negativeCacheTtl` (default 60s) and replays the original exception | For explicit retry buttons / connectivity-restored: `await engine.evict(source)` then re-request. Globally: shorter `negativeCacheTtl` in `configure` (re-running `configure` also clears all failure memos) |
| "404 URL reports `timeout` not `network` on Android" | Some Android media stacks retry internally and never surface HTTP status; the Dart deadline ends the attempt | Documented platform quirk. Bucket `timeout`+`network` together for remote-source analytics; optionally probe the URL app-side to reclassify |
| "Cache stopped working / thumbnails regenerate after days" | Cache lives in the OS-purgeable app cache dir; the OS reclaimed it | By design; engine re-extracts on demand. Do not move the cache; reduce churn with correct shared specs |
| "Changed request headers but same thumbnail" | Headers are deliberately excluded from cache identity | `evict(source)` when content truly changed |
| "Thumbnail is not the exact frame I asked for" | `exact: false` snaps to nearest keyframe (the fast path) | `exact: true` only where precision matters; never in feeds |
| "First frame is black" | Many videos open on black; position 0 + keyframe snap lands there | `position: Duration(seconds: 1)` (still keyframe-fast) |
| "HLS (.m3u8) works on one platform, fails on other" | Stream thumbnailing depends on OS media stack support; both outcomes are classified, bounded failures | Treat HLS tiles as best-effort with an error placeholder, or use direct MP4 URLs |
| "Cancelled request still produced a cache file (Android)" | Android cannot abort `MediaMetadataRetriever`; the engine detaches the caller and banks the finished frame | By design (sunk cost -> future hit). iOS aborts natively |
| "Portrait video renders sideways/wrong box" | Rotation metadata is applied natively; fit box is display-oriented | Expected correct; if actually sideways, that IS a defect - report upstream with the file |
| "StateError: cache sizing can only be configured before the first request" | `maxCacheBytes`/`maxCacheEntries` are locked once the engine initializes | Move the single `configure()` call to main() before any request |
| "evict/clearCache didn't cancel a running extraction" | Eviction only removes stored entries; in-flight work completes | Cancel via the request handle; or ignore - next request re-checks cache |

## Error-code fast table

`invalidSource` structurally bad input | `assetNotFound` wrong key or
missing pubspec asset entry | `fileNotFound` path missing at key time |
`network` connectivity/HTTP surfaced | `unsupportedMedia` no decodable
video track / codec | `extractionFailed` decoder failed otherwise (also the
fallback for unmapped platform errors) | `encodingFailed` jpeg/png encode
failed | `io` local write/rename | `timeout` deadline exceeded (counted
from native dispatch, not enqueue) | `cancelled` caller cancelled (never
negative-cached).

Causes and per-code fixes: see the reference file.

## Perf investigations

- Jank while scrolling: confirm with metrics that thumbnails are even
  involved (bounded `activeJobs` <= `maxConcurrentExtractions`; if the UI
  janks with 0-2 active jobs and high hit ratio, look elsewhere).
- Oversized specs are the top decode-cost cause: spec must be cell physical
  size, not unconstrained. See the `integrate-feed-thumbnails` skill.
- The package example app has a bench page (cold/warm percentiles, 200-cell
  scroll test) for before/after numbers on real devices.

## Safety rails

- Do not "fix" by calling `clearCache()` in production paths, disabling the
  negative cache to zero for feeds, or raising concurrency past 2-3 without
  bench evidence.
- Do not parse or depend on cache file names/paths; they are an
  implementation detail (schema-versioned, wholesale-invalidated).
- If behavior contradicts this skill, the installed package source is the
  truth - read it in `.pub-cache` and note the version.

## Example scenario

"Analytics shows spikes of `timeout` errors from Android users on one CDN
URL that returns 404." -> Known quirk row 2 + negative cache row 1: the
device retriever swallowed the 404, deadline classified `timeout`, and each
fast-fail replay during the 60s TTL logged another one. Fix analytics
bucketing; nothing is stuck.
