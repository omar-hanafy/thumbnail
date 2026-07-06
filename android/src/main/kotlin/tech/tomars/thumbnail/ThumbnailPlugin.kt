package tech.tomars.thumbnail

import io.flutter.embedding.engine.plugins.FlutterPlugin

/** Registers the Pigeon host API for the thumbnail engine. */
class ThumbnailPlugin : FlutterPlugin, ThumbnailHostApi {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        ThumbnailHostApi.setUp(binding.binaryMessenger, this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        ThumbnailHostApi.setUp(binding.binaryMessenger, null)
    }

    override fun extract(request: ExtractRequest, callback: (Result<ExtractResult>) -> Unit) {
        callback(
            Result.failure(
                FlutterError("extractionFailed", "Android extractor not implemented yet", null)
            )
        )
    }

    override fun cancel(requestId: String) {
        // Not supported on Android in v1; MediaMetadataRetriever cannot be aborted safely.
    }
}
