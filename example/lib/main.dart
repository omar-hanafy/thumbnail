import 'package:flutter/material.dart';
import 'package:thumbnail/thumbnail.dart';

import 'bench_page.dart';
import 'gallery_page.dart';
import 'playground_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Network extractions of large remote movies can outlive the 15s default:
  // BigBuckBunny_320x180.mp4 keeps its moov atom at the end of a ~64 MiB
  // file, so the first frame needs ~50s on a mid-range device. Give the
  // demo app generous headroom.
  await ThumbnailEngine.instance.configure(
    const ThumbnailEngineConfig(defaultTimeout: Duration(seconds: 90)),
  );
  runApp(const ExampleApp());
}

/// Gallery (every generation path), Playground (direct engine API with all
/// the knobs), and Bench (cold/warm performance runs).
class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'thumbnail example',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('thumbnail'),
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Gallery'),
                Tab(text: 'Playground'),
                Tab(text: 'Bench'),
              ],
            ),
          ),
          body: const TabBarView(
            children: [GalleryPage(), PlaygroundPage(), BenchPage()],
          ),
        ),
      ),
    );
  }
}
