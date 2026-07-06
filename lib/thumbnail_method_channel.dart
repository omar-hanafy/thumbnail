import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'thumbnail_platform_interface.dart';

/// An implementation of [ThumbnailPlatform] that uses method channels.
class MethodChannelThumbnail extends ThumbnailPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('thumbnail');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
