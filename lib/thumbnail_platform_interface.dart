import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'thumbnail_method_channel.dart';

abstract class ThumbnailPlatform extends PlatformInterface {
  /// Constructs a ThumbnailPlatform.
  ThumbnailPlatform() : super(token: _token);

  static final Object _token = Object();

  static ThumbnailPlatform _instance = MethodChannelThumbnail();

  /// The default instance of [ThumbnailPlatform] to use.
  ///
  /// Defaults to [MethodChannelThumbnail].
  static ThumbnailPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [ThumbnailPlatform] when
  /// they register themselves.
  static set instance(ThumbnailPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
