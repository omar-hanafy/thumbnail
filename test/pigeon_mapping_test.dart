import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thumbnail/src/extractor/pigeon_extractor.dart';
import 'package:thumbnail/src/pigeon/messages.g.dart';
import 'package:thumbnail/thumbnail.dart';

void main() {
  const spec = ThumbnailSpec(maxWidth: 320, maxHeight: 180, quality: 70);

  group('buildExtractRequest', () {
    test('maps an asset source', () {
      final r = buildExtractRequest(
        requestId: 'r1',
        source: VideoSource.asset('assets/v.mp4', package: 'pkg'),
        spec: spec,
        destPath: '/tmp/x.part',
      );
      expect(r.requestId, 'r1');
      expect(r.sourceType, SourceKind.asset);
      expect(r.source, 'assets/v.mp4');
      expect(r.assetPackage, 'pkg');
      expect(r.headers, isNull);
      expect(r.maxWidth, 320);
      expect(r.maxHeight, 180);
      expect(r.positionMs, 0);
      expect(r.exact, isFalse);
      expect(r.format, 'jpeg');
      expect(r.quality, 70);
      expect(r.destPath, '/tmp/x.part');
    });

    test('maps a file source', () {
      final r = buildExtractRequest(
        requestId: 'r2',
        source: VideoSource.file('/videos/v.mp4'),
        spec: spec,
        destPath: '/tmp/y.part',
      );
      expect(r.sourceType, SourceKind.file);
      expect(r.source, '/videos/v.mp4');
      expect(r.assetPackage, isNull);
    });

    test('maps a network source with headers and position', () {
      final r = buildExtractRequest(
        requestId: 'r3',
        source: VideoSource.network(
          Uri.parse('https://cdn.io/v.mp4'),
          headers: {'Authorization': 'Bearer t'},
        ),
        spec: spec.copyWith(
          position: const Duration(milliseconds: 2500),
          exact: true,
          format: ThumbnailFormat.png,
        ),
        destPath: '/tmp/z.part',
      );
      expect(r.sourceType, SourceKind.network);
      expect(r.source, 'https://cdn.io/v.mp4');
      expect(r.headers, {'Authorization': 'Bearer t'});
      expect(r.positionMs, 2500);
      expect(r.exact, isTrue);
      expect(r.format, 'png');
    });
  });

  group('mapPlatformError', () {
    test('maps every native code to its enum value', () {
      const codes = {
        'invalidSource': ThumbnailErrorCode.invalidSource,
        'assetNotFound': ThumbnailErrorCode.assetNotFound,
        'fileNotFound': ThumbnailErrorCode.fileNotFound,
        'network': ThumbnailErrorCode.network,
        'unsupportedMedia': ThumbnailErrorCode.unsupportedMedia,
        'extractionFailed': ThumbnailErrorCode.extractionFailed,
        'encodingFailed': ThumbnailErrorCode.encodingFailed,
        'io': ThumbnailErrorCode.io,
        'cancelled': ThumbnailErrorCode.cancelled,
      };
      codes.forEach((code, expected) {
        final e = mapPlatformError(
          PlatformException(code: code, message: 'detail'),
        );
        expect(e.code, expected, reason: code);
        expect(e.message, contains('detail'));
      });
    });

    test('unknown platform codes fall back to extractionFailed', () {
      final e = mapPlatformError(
        PlatformException(code: 'channel-error', message: 'gone'),
      );
      expect(e.code, ThumbnailErrorCode.extractionFailed);
      expect(e.message, contains('channel-error'));
    });

    test('passes through ThumbnailException unchanged', () {
      const original = ThumbnailException(ThumbnailErrorCode.io, 'disk');
      expect(mapPlatformError(original), same(original));
    });

    test('wraps arbitrary errors as extractionFailed with cause', () {
      final e = mapPlatformError(StateError('weird'));
      expect(e.code, ThumbnailErrorCode.extractionFailed);
      expect(e.cause, isA<StateError>());
    });
  });
}
