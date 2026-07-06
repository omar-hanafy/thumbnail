import 'package:thumbnail/thumbnail.dart';

/// One thumbnail to render in the gallery: a source plus the spec to use.
class DemoEntry {
  const DemoEntry({
    required this.label,
    required this.source,
    this.spec = const ThumbnailSpec(maxWidth: 480, maxHeight: 480),
    this.note,
    this.expectFailure = false,
  });

  final String label;
  final VideoSource source;
  final ThumbnailSpec spec;

  /// Short explanation shown under the label.
  final String? note;

  /// Marks tiles whose whole point is to show clean error handling.
  final bool expectFailure;
}

/// A titled group of gallery entries.
class DemoSection {
  const DemoSection({required this.title, required this.entries, this.blurb});

  final String title;
  final String? blurb;
  final List<DemoEntry> entries;
}

/// Big Buck Bunny direct downloads (Blender Foundation, CC-BY).
const bbbMp4Url =
    'https://download.blender.org/peach/bigbuckbunny_movies/BigBuckBunny_320x180.mp4';
const bbbM4vUrl =
    'https://download.blender.org/peach/bigbuckbunny_movies/BigBuckBunny_640x360.m4v';
const bbbMovUrl =
    'https://download.blender.org/peach/bigbuckbunny_movies/big_buck_bunny_720p_h264.mov';

/// Big Buck Bunny as an HLS stream (Mux public test stream).
const bbbHlsUrl = 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8';

/// Deliberately broken sources for the error-handling section.
const missing404Url =
    'https://download.blender.org/peach/bigbuckbunny_movies/does_not_exist.mp4';
const notAVideoUrl = 'https://download.blender.org/peach/';

const landscapeAsset = 'assets/fixtures/landscape.mp4';
const portraitAsset = 'assets/fixtures/portrait_rot90.mp4';

VideoSource _net(String url) => VideoSource.network(Uri.parse(url));

/// The static part of the gallery. Local-file entries are created at runtime
/// by the gallery page because their paths depend on the device.
List<DemoSection> buildDemoSections() {
  return [
    DemoSection(
      title: 'Bundle assets',
      blurb: 'Read straight from the app bundle, no copying.',
      entries: [
        DemoEntry(
          label: 'Landscape asset (640x360)',
          source: VideoSource.asset(landscapeAsset),
        ),
        DemoEntry(
          label: 'Portrait asset (rotation metadata)',
          source: VideoSource.asset(portraitAsset),
          note: 'Must render upright: 360x640, not sideways.',
        ),
      ],
    ),
    DemoSection(
      title: 'Network: direct video links',
      blurb: 'Big Buck Bunny from download.blender.org, three containers.',
      entries: [
        DemoEntry(
          label: 'MP4 320x180 at 10s',
          source: _net(bbbMp4Url),
          spec: const ThumbnailSpec(
            maxWidth: 480,
            maxHeight: 480,
            position: Duration(seconds: 10),
          ),
        ),
        DemoEntry(
          label: 'M4V 640x360 at 30s, exact frame',
          source: _net(bbbM4vUrl),
          spec: const ThumbnailSpec(
            maxWidth: 480,
            maxHeight: 480,
            position: Duration(seconds: 30),
            exact: true,
          ),
          note: 'exact: true decodes to the precise frame.',
        ),
        DemoEntry(
          label: 'MOV 720p, first keyframe',
          source: _net(bbbMovUrl),
          note: 'Large remote file; only the needed bytes are fetched.',
        ),
      ],
    ),
    DemoSection(
      title: 'Network: HLS stream',
      blurb:
          'Stream thumbnailing depends on OS support. Android and iOS '
          'may extract a frame, fail cleanly, or time out; the engine '
          'classifies whatever happens.',
      entries: [
        DemoEntry(
          label: 'Big Buck Bunny HLS (.m3u8)',
          source: _net(bbbHlsUrl),
          note: 'Platform-dependent; a clean error here is acceptable.',
        ),
      ],
    ),
    DemoSection(
      title: 'Spec variations (same asset)',
      blurb: 'Every knob on ThumbnailSpec, applied to the landscape asset.',
      entries: [
        DemoEntry(
          label: 'Keyframe seek (default)',
          source: VideoSource.asset(landscapeAsset),
          spec: const ThumbnailSpec(
            maxWidth: 480,
            maxHeight: 480,
            position: Duration(milliseconds: 500),
          ),
        ),
        DemoEntry(
          label: 'Exact frame at 500ms',
          source: VideoSource.asset(landscapeAsset),
          spec: const ThumbnailSpec(
            maxWidth: 480,
            maxHeight: 480,
            position: Duration(milliseconds: 500),
            exact: true,
          ),
        ),
        DemoEntry(
          label: 'PNG output',
          source: VideoSource.asset(landscapeAsset),
          spec: const ThumbnailSpec(
            maxWidth: 480,
            maxHeight: 480,
            format: ThumbnailFormat.png,
          ),
        ),
        DemoEntry(
          label: 'JPEG quality 10',
          source: VideoSource.asset(landscapeAsset),
          spec: const ThumbnailSpec(maxWidth: 480, maxHeight: 480, quality: 10),
          note: 'Visible compression artifacts are the point.',
        ),
        DemoEntry(
          label: 'JPEG quality 95',
          source: VideoSource.asset(landscapeAsset),
          spec: const ThumbnailSpec(maxWidth: 480, maxHeight: 480, quality: 95),
        ),
        DemoEntry(
          label: 'Tiny 96px fit box',
          source: VideoSource.asset(landscapeAsset),
          spec: const ThumbnailSpec(maxWidth: 96, maxHeight: 96),
          note: 'Decoded at 96x54; shown scaled up, so it looks soft.',
        ),
        DemoEntry(
          label: 'Unconstrained (native size)',
          source: VideoSource.asset(landscapeAsset),
          spec: const ThumbnailSpec(),
        ),
        DemoEntry(
          label: 'Position past the end (clamped)',
          source: VideoSource.asset(landscapeAsset),
          spec: const ThumbnailSpec(
            maxWidth: 480,
            maxHeight: 480,
            position: Duration(minutes: 5),
          ),
          note: 'The clip is 1s long; the engine clamps to the last frame.',
        ),
      ],
    ),
    DemoSection(
      title: 'Error handling',
      blurb:
          'These are supposed to fail. What matters is that they fail '
          'with a classified error, in bounded time, without crashing. '
          'On some Android devices HTTP failures classify as timeout '
          'because the OS retriever retries internally.',
      entries: [
        DemoEntry(
          label: 'HTTP 404',
          source: _net(missing404Url),
          expectFailure: true,
        ),
        DemoEntry(
          label: 'Not a video (HTML page)',
          source: _net(notAVideoUrl),
          expectFailure: true,
        ),
        DemoEntry(
          label: 'Missing asset',
          source: VideoSource.asset('assets/fixtures/nope.mp4'),
          expectFailure: true,
        ),
      ],
    ),
  ];
}
