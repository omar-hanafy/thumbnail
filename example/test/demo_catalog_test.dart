import 'package:flutter_test/flutter_test.dart';
import 'package:thumbnail/thumbnail.dart';
import 'package:thumbnail_example/demo_catalog.dart';

void main() {
  final sections = buildDemoSections();
  final entries = [for (final s in sections) ...s.entries];

  test('every entry has a valid spec', () {
    for (final entry in entries) {
      expect(
        () => entry.spec.validate(),
        returnsNormally,
        reason: '"${entry.label}" must carry a valid spec',
      );
    }
  });

  test('labels are unique so tiles are identifiable', () {
    final labels = entries.map((e) => e.label).toList();
    expect(labels.toSet(), hasLength(labels.length));
  });

  test('section titles are unique and every section has entries', () {
    final titles = sections.map((s) => s.title).toList();
    expect(titles.toSet(), hasLength(titles.length));
    for (final section in sections) {
      expect(section.entries, isNotEmpty, reason: section.title);
    }
  });

  test('the gallery covers assets, direct links, HLS, and failures', () {
    expect(entries.whereType<Object>(), isNotEmpty);
    expect(
      entries.where((e) => e.source is AssetVideoSource && !e.expectFailure),
      isNotEmpty,
    );
    expect(
      entries.where((e) => e.source is NetworkVideoSource && !e.expectFailure),
      isNotEmpty,
    );
    expect(
      entries.where(
        (e) =>
            e.source is NetworkVideoSource &&
            (e.source as NetworkVideoSource).url.path.endsWith('.m3u8'),
      ),
      isNotEmpty,
      reason: 'an HLS stream entry must be present',
    );
    expect(
      entries.where((e) => e.expectFailure),
      hasLength(greaterThanOrEqualTo(3)),
      reason: '404, non-video, and missing asset error tiles',
    );
  });

  test('the gallery exercises every ThumbnailSpec knob', () {
    expect(entries.where((e) => e.spec.exact), isNotEmpty);
    expect(
      entries.where((e) => e.spec.format == ThumbnailFormat.png),
      isNotEmpty,
    );
    expect(
      entries.map((e) => e.spec.quality).toSet().length,
      greaterThan(1),
      reason: 'multiple JPEG quality levels',
    );
    expect(
      entries.where((e) => e.spec.maxWidth == 0 && e.spec.maxHeight == 0),
      isNotEmpty,
      reason: 'an unconstrained entry',
    );
    expect(
      entries.map((e) => e.spec.position).toSet().length,
      greaterThan(2),
      reason: 'several distinct positions',
    );
  });

  test('all network sources use https', () {
    for (final entry in entries) {
      final source = entry.source;
      if (source is NetworkVideoSource) {
        expect(source.url.scheme, 'https', reason: entry.label);
      }
    }
  });

  test('healthy sources point at the expected hosts', () {
    for (final entry in entries.where(
      (e) => e.source is NetworkVideoSource && !e.expectFailure,
    )) {
      final url = (entry.source as NetworkVideoSource).url;
      expect(
        url.host,
        isIn(['download.blender.org', 'test-streams.mux.dev']),
        reason: entry.label,
      );
    }
  });
}
