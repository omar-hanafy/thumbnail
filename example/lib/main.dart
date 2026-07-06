import 'package:flutter/material.dart';

void main() {
  runApp(const ExampleApp());
}

/// Placeholder example shell; the demo and benchmark pages land with the
/// engine implementation.
class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'thumbnail example',
      home: Scaffold(
        body: Center(child: Text('thumbnail example')),
      ),
    );
  }
}
