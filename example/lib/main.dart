import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:thumbnail/thumbnail.dart';

import 'bench_page.dart';

void main() {
  runApp(const ExampleApp());
}

/// Demo + benchmark shell for the thumbnail engine.
class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'thumbnail example',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('thumbnail'),
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Demo'),
                Tab(text: 'Bench'),
              ],
            ),
          ),
          body: const TabBarView(children: [DemoPage(), BenchPage()]),
        ),
      ),
    );
  }
}

/// One tile per source kind, all rendered through [VideoThumbnailImage].
class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  static const _spec = ThumbnailSpec(maxWidth: 480, maxHeight: 480);

  final _urlController = TextEditingController(
    text:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
  );
  String? _localFilePath;
  VideoSource? _networkSource;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _prepareLocalFile() async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/demo_local.mp4');
    if (!file.existsSync()) {
      final data = await rootBundle.load('assets/fixtures/landscape.mp4');
      await file.writeAsBytes(data.buffer.asUint8List());
    }
    setState(() => _localFilePath = file.path);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _tile(
          'Bundle asset (landscape)',
          VideoSource.asset('assets/fixtures/landscape.mp4'),
        ),
        _tile(
          'Bundle asset (rotated portrait)',
          VideoSource.asset('assets/fixtures/portrait_rot90.mp4'),
        ),
        if (_localFilePath == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: OutlinedButton(
              onPressed: _prepareLocalFile,
              child: const Text('Copy asset to a local file and thumbnail it'),
            ),
          )
        else
          _tile('Local file', VideoSource.file(_localFilePath!)),
        const SizedBox(height: 8),
        TextField(
          controller: _urlController,
          decoration: InputDecoration(
            labelText: 'Video URL',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: const Icon(Icons.play_arrow),
              onPressed: () => setState(() {
                _networkSource = VideoSource.network(
                  Uri.parse(_urlController.text.trim()),
                );
              }),
            ),
          ),
        ),
        if (_networkSource != null) _tile('Network', _networkSource!),
      ],
    );
  }

  Widget _tile(String label, VideoSource source) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 180,
              width: double.infinity,
              child: Image(
                image: VideoThumbnailImage(source, spec: _spec),
                fit: BoxFit.cover,
                frameBuilder: (context, child, frame, _) => frame == null
                    ? const ColoredBox(
                        color: Colors.black12,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : child,
                errorBuilder: (context, error, _) => ColoredBox(
                  color: Colors.red.shade50,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        '$error',
                        style: const TextStyle(fontSize: 11),
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
