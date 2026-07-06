import 'package:flutter/material.dart';
import 'package:cached_video_thumbnail/cached_video_thumbnail.dart';

/// Benchmark harness: proves where thumbnail time goes on a real device.
///
/// Cold runs clear the disk cache first (every request pays a native
/// extraction); warm runs replay the same requests against the cache. The
/// difference is the engine's whole value proposition.
class BenchPage extends StatefulWidget {
  const BenchPage({super.key});

  @override
  State<BenchPage> createState() => _BenchPageState();
}

class _BenchPageState extends State<BenchPage> {
  int _count = 24;
  int _size = 320;
  int _concurrency = 2;
  bool _running = false;
  String _report = 'No runs yet.';

  Future<void> _run({required bool cold}) async {
    setState(() {
      _running = true;
      _report = 'Running ${cold ? 'cold' : 'warm'} with $_count requests...';
    });
    final engine = ThumbnailEngine.instance;
    await engine.configure(
      ThumbnailEngineConfig(maxConcurrentExtractions: _concurrency),
    );
    if (cold) await engine.clearCache();

    final before = engine.metrics;
    final stopwatch = Stopwatch()..start();
    final futures = <Future<Thumbnail>>[];
    for (var i = 0; i < _count; i++) {
      futures.add(
        engine.getThumbnail(
          VideoSource.asset(
            i.isEven
                ? 'assets/fixtures/landscape.mp4'
                : 'assets/fixtures/portrait_rot90.mp4',
          ),
          // Distinct sizes force distinct cache keys so `count` is honest.
          spec: ThumbnailSpec(maxWidth: _size + i, maxHeight: _size + i),
        ),
      );
    }
    var failures = 0;
    for (final f in futures) {
      try {
        await f;
      } on ThumbnailException {
        failures++;
      }
    }
    stopwatch.stop();
    final after = engine.metrics;

    final hits = after.cacheHits - before.cacheHits;
    final extractions = after.extractions - before.extractions;
    setState(() {
      _running = false;
      _report = [
        '${cold ? 'COLD' : 'WARM'} run: $_count requests, '
            'size $_size, concurrency $_concurrency',
        'total: ${stopwatch.elapsedMilliseconds} ms '
            '(${(stopwatch.elapsedMilliseconds / _count).toStringAsFixed(1)} ms/thumb)',
        'cache hits: $hits, extractions: $extractions, failures: $failures',
        'extract p50: ${after.extractP50?.inMilliseconds} ms, '
            'p95: ${after.extractP95?.inMilliseconds} ms',
        'queue wait p50: ${after.queueWaitP50?.inMilliseconds} ms, '
            'p95: ${after.queueWaitP95?.inMilliseconds} ms',
      ].join('\n');
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _IntSelector(
          label: 'Requests',
          options: const [12, 24, 48, 96],
          value: _count,
          onChanged: (v) => setState(() => _count = v),
        ),
        _IntSelector(
          label: 'Box size (px)',
          options: const [160, 320, 480],
          value: _size,
          onChanged: (v) => setState(() => _size = v),
        ),
        _IntSelector(
          label: 'Concurrency',
          options: const [1, 2, 4],
          value: _concurrency,
          onChanged: (v) => setState(() => _concurrency = v),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: _running ? null : () => _run(cold: true),
                child: const Text('Run cold'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.tonal(
                onPressed: _running ? null : () => _run(cold: false),
                child: const Text('Run warm'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              _report,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Scroll test (200 cells, engine-backed):',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 140,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: 200,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image(
                  width: 100,
                  height: 140,
                  fit: BoxFit.cover,
                  image: VideoThumbnailImage(
                    VideoSource.asset(
                      index.isEven
                          ? 'assets/fixtures/landscape.mp4'
                          : 'assets/fixtures/portrait_rot90.mp4',
                    ),
                    spec: ThumbnailSpec(
                      maxWidth: 200 + (index % 40),
                      maxHeight: 280,
                    ),
                  ),
                  errorBuilder: (_, _, _) =>
                      const ColoredBox(color: Colors.black12),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _IntSelector extends StatelessWidget {
  const _IntSelector({
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final List<int> options;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(label)),
          Expanded(
            child: SegmentedButton<int>(
              segments: [
                for (final option in options)
                  ButtonSegment(value: option, label: Text('$option')),
              ],
              selected: {value},
              onSelectionChanged: (selection) => onChanged(selection.first),
            ),
          ),
        ],
      ),
    );
  }
}
