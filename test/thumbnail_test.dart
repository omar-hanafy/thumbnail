import 'package:flutter_test/flutter_test.dart';
import 'package:thumbnail/thumbnail.dart';
import 'package:thumbnail/thumbnail_platform_interface.dart';
import 'package:thumbnail/thumbnail_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockThumbnailPlatform
    with MockPlatformInterfaceMixin
    implements ThumbnailPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final ThumbnailPlatform initialPlatform = ThumbnailPlatform.instance;

  test('$MethodChannelThumbnail is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelThumbnail>());
  });

  test('getPlatformVersion', () async {
    Thumbnail thumbnailPlugin = Thumbnail();
    MockThumbnailPlatform fakePlatform = MockThumbnailPlatform();
    ThumbnailPlatform.instance = fakePlatform;

    expect(await thumbnailPlugin.getPlatformVersion(), '42');
  });
}
