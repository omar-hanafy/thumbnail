import 'package:flutter/material.dart';
import 'package:thumbnail/thumbnail.dart';

String _ms(Duration? d) => d == null ? '-' : '${d.inMilliseconds}ms';

/// Shows the engine's current metrics snapshot in a dialog.
void showMetricsDialog(BuildContext context) {
  final m = ThumbnailEngine.instance.metrics;
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Engine metrics'),
      content: SingleChildScrollView(
        child: Text(
          'requests: ${m.requests}\n'
          'cacheHits: ${m.cacheHits}\n'
          'coalescedJoins: ${m.coalescedJoins}\n'
          'extractions: ${m.extractions}\n'
          'cancellations: ${m.cancellations}\n'
          'timeouts: ${m.timeouts}\n'
          'failures: ${m.failures}\n'
          'queueDepth: ${m.queueDepth}\n'
          'activeJobs: ${m.activeJobs}\n'
          'extract p50/p95: ${_ms(m.extractP50)} / ${_ms(m.extractP95)}\n'
          'queue wait p50/p95: '
          '${_ms(m.queueWaitP50)} / ${_ms(m.queueWaitP95)}',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
