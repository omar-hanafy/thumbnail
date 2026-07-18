---
name: mock-thumbnail-engine
description: Use when writing or fixing unit/widget tests for Flutter code that uses cached_video_thumbnail - tests that must run hermetically under flutter test without native plugins, platform channels, or network, or that hit MissingPluginException / path_provider errors from ThumbnailEngine or VideoThumbnailImage.
---

# Test code that uses cached_video_thumbnail hermetically

The package has one designed test seam, and it makes everything else
unnecessary: `ThumbnailEngine.forTesting(extractor:, directory:)` builds a
fully real engine (scheduler, disk cache, metrics) on top of an injected
`ThumbnailExtractor` fake and a temp directory. The only thing faked is
the native decode. Never mock the Pigeon channel, `path_provider`, or the
engine class itself.

## Step 1 - make the code under test injectable

`ThumbnailEngine.instance` has no setter, and a widget that hardcodes
`VideoThumbnailImage(source)` resolves through the real singleton
(-> MissingPluginException under `flutter test`). Do NOT work around that
with ImageCache seeding tricks; fix the seam - it is a one-parameter
change:

```dart
class MyVideoTile extends StatelessWidget {
  const MyVideoTile({super.key, required this.videoUrl, this.engine});
  final String videoUrl;
  final ThumbnailEngine? engine;   // test seam; null = production singleton

  @override
  Widget build(BuildContext context) => Image(
    image: VideoThumbnailImage(
      VideoSource.network(Uri.parse(videoUrl)),
      spec: const ThumbnailSpec(maxWidth: 320, maxHeight: 320),
      engine: engine,   // public named parameter, exists for exactly this
    ),
    fit: BoxFit.cover,
  );
}
```

Note: `VideoThumbnailImage`'s `engine:` parameter is declared as a Dart
private named parameter (`this._engine`) - it does not appear in some API
listings, but callers pass it as `engine:`. Non-widget code should take a
`ThumbnailEngine engine` constructor/function parameter the same way.

## Step 2 - copy the fake extractor

Take [fake_thumbnail_extractor.dart](references/fake_thumbnail_extractor.dart)
into the app's `test/support/`. Contract it honors (required of any fake):
write real decodable image bytes into `destPath` (the engine commits that
file into its cache and the provider really decodes it), return the true
dimensions, throw `ThumbnailException` for failure cases - never return
without producing the file.

## Step 3 - build the engine per test

```dart
late Directory root;
late FakeThumbnailExtractor extractor;
late ThumbnailEngine engine;

setUp(() async {
  root = await Directory.systemTemp.createTemp('thumb_test');
  extractor = FakeThumbnailExtractor();
  engine = ThumbnailEngine.forTesting(
    extractor: extractor,
    directory: Directory('${root.path}/cache'),
  );
  PaintingBinding.instance.imageCache..clear()..clearLiveImages();
});
tearDown(() => root.delete(recursive: true));
```

`forTesting` is `@visibleForTesting`: the analyzer allows it in `test/`
and `integration_test/` directories; if it warns elsewhere, the call is in
the wrong place. Each test gets a fresh engine + directory - engines are
cheap and isolated; never share cache dirs between tests.

## Step 4 - write the tests

Engine-level (plain `test`, no pumping needed):

```dart
final thumb = await engine.getThumbnail(
  VideoSource.asset('assets/v.mp4'),
  spec: const ThumbnailSpec(maxWidth: 64, maxHeight: 64),
);
expect(thumb.wasCached, isFalse);
expect(extractor.callCount, 1);
// Second call: cache hit, no new extraction.
```

Widget-level (`testWidgets`): wrap the pipeline in `tester.runAsync` -
real file IO and image decoding never complete inside the fake-async test
zone:

```dart
await tester.runAsync(() async {
  await tester.pumpWidget(MaterialApp(
    home: MyVideoTile(videoUrl: url, engine: engine),
  ));
  // Let extraction + decode land; then settle frames.
  await Future<void>.delayed(const Duration(milliseconds: 50));
});
await tester.pump();
final raw = tester.widget<RawImage>(find.byType(RawImage));
expect(raw.image?.width, 2);   // the fake's 2x2 PNG
```

Behavior cases the fake supports: `failWith = ThumbnailException(...)` to
drive `errorBuilder` paths; `gated = true` + `release()` to test loading
states and cancellation; `delay` for latency; `cancelled` list to assert
cancellation reached the extractor.

## Sharp edges

- **Assert against a 2x2 image, not 1x1**: when a provider's request is
  cancelled after listener detach, the stream settles with an internal 1x1
  transparent pixel - a 1x1 assertion can pass for the wrong reason. The
  bundled fake writes a 2x2 PNG deliberately.
- **`fakeAsync`/`FakeAsync` does not play well with the engine's real
  file IO** - disk cache writes are genuine async IO that fake clocks do
  not advance. Use real async (`runAsync`, `pumpEventQueue`); reserve
  fake clocks for pure scheduler-timing units, as the package's own tests
  do.
- The provider cancels on last-listener detach: a widget disposed before
  decode completes will record a cancellation, not a failure. Use the
  gated fake to make such races deterministic instead of sleeping.
- Widget-test assertions on `metrics` counters: prefer counters over
  timing percentiles; percentiles are null until samples exist.
- Do not construct `ThumbnailEngine.instance` in host tests at all; even
  though construction is currently inert, only the injected engine is
  guaranteed hermetic.

## Failure handling

If `forTesting` or the `engine:` parameter is missing in the installed
version, this skill predates or postdates that API - read the installed
package source in `.pub-cache` (`lib/src/engine.dart`,
`lib/src/image_provider.dart`) and adapt; say which version you found.

## Example scenario

"CI fails with MissingPluginException in golden tests of our video feed."
-> add the `engine` seam to the feed widget, inject
`ThumbnailEngine.forTesting` with the bundled fake (instant 2x2 PNGs),
`runAsync` around pumps, goldens now deterministic and offline.
