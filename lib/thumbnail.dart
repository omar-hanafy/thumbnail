
import 'thumbnail_platform_interface.dart';

class Thumbnail {
  Future<String?> getPlatformVersion() {
    return ThumbnailPlatform.instance.getPlatformVersion();
  }
}
