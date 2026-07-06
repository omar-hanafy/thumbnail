import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:cached_video_thumbnail/cached_video_thumbnail.dart';

import 'demo_catalog.dart';
import 'metrics_dialog.dart';

/// Renders every way the engine can produce a thumbnail, one tile each,
/// all through [VideoThumbnailImage]. Meant for eyeball verification.
class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key});

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  final List<DemoSection> _sections = buildDemoSections();

  /// Absolute paths of fixtures copied out of the bundle, once ready.
  List<String> _localFiles = const [];

  /// Bumped to give every tile a fresh widget identity after a cache clear,
  /// so the images are re-requested instead of served from memory.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _prepareLocalFiles();
  }

  /// Copies both bundled fixtures to real files so the gallery can exercise
  /// [VideoSource.file] with genuine on-disk videos.
  Future<void> _prepareLocalFiles() async {
    final dir = await getTemporaryDirectory();
    final paths = <String>[];
    for (final asset in [landscapeAsset, portraitAsset]) {
      final file = File('${dir.path}/gallery_${asset.split('/').last}');
      if (!file.existsSync()) {
        final data = await rootBundle.load(asset);
        await file.writeAsBytes(data.buffer.asUint8List());
      }
      paths.add(file.path);
    }
    if (mounted) setState(() => _localFiles = paths);
  }

  Future<void> _prefetchNetwork() async {
    final engine = ThumbnailEngine.instance;
    for (final section in _sections) {
      for (final entry in section.entries) {
        if (entry.source is NetworkVideoSource && !entry.expectFailure) {
          engine.prefetch(entry.source, spec: entry.spec);
        }
      }
    }
    _toast('Prefetch queued for all network sources.');
  }

  Future<void> _clearAndReload() async {
    await ThumbnailEngine.instance.clearCache();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    if (mounted) setState(() => _generation++);
    _toast('Disk + memory caches cleared; every tile re-extracts.');
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              avatar: const Icon(Icons.download_for_offline, size: 18),
              label: const Text('Prefetch network'),
              onPressed: _prefetchNetwork,
            ),
            ActionChip(
              avatar: const Icon(Icons.delete_sweep, size: 18),
              label: const Text('Clear caches + reload'),
              onPressed: _clearAndReload,
            ),
            ActionChip(
              avatar: const Icon(Icons.query_stats, size: 18),
              label: const Text('Metrics'),
              onPressed: () => showMetricsDialog(context),
            ),
          ],
        ),
        for (final section in _sections) ..._buildSection(section),
        ..._buildLocalFileSection(),
        const SizedBox(height: 24),
      ],
    );
  }

  List<Widget> _buildSection(DemoSection section) {
    return [
      _sectionHeader(section.title, section.blurb),
      for (final entry in section.entries)
        _DemoTile(entry, key: _tileKey(entry)),
    ];
  }

  List<Widget> _buildLocalFileSection() {
    if (_localFiles.isEmpty) {
      return [
        _sectionHeader('Local files', 'Copying bundled fixtures to disk...'),
        const Center(child: CircularProgressIndicator()),
      ];
    }
    return [
      _sectionHeader(
        'Local files',
        'The bundled fixtures copied to real files, thumbnailed via '
            'VideoSource.file. Edited files re-key automatically '
            '(mtime + size are part of the cache key).',
      ),
      for (final path in _localFiles)
        _DemoTile(
          DemoEntry(
            label: 'File: ${path.split('/').last}',
            source: VideoSource.file(path),
          ),
          key: ValueKey('$_generation|file|$path'),
        ),
    ];
  }

  Key _tileKey(DemoEntry entry) =>
      ValueKey('$_generation|${entry.source.describe()}|${entry.spec}');

  Widget _sectionHeader(String title, String? blurb) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          if (blurb != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                blurb,
                style: theme.textTheme.bodySmall!.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One gallery tile: label, optional note, and the thumbnail itself with
/// loading and error states.
class _DemoTile extends StatelessWidget {
  const _DemoTile(this.entry, {super.key});

  final DemoEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(entry.label, style: theme.textTheme.titleSmall),
          if (entry.note != null)
            Text(
              entry.note!,
              style: theme.textTheme.bodySmall!.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 180,
              width: double.infinity,
              child: Image(
                image: VideoThumbnailImage(entry.source, spec: entry.spec),
                fit: BoxFit.cover,
                frameBuilder: (context, child, frame, _) => frame == null
                    ? const ColoredBox(
                        color: Colors.black12,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : child,
                errorBuilder: (context, error, _) => ColoredBox(
                  color: entry.expectFailure
                      ? Colors.amber.shade50
                      : Colors.red.shade50,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        entry.expectFailure
                            ? 'Failed as expected:\n$error'
                            : '$error',
                        style: const TextStyle(fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
