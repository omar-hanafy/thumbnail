package tech.tomars.thumbnail

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Registers the Pigeon host API and runs extractions off the main thread.
 *
 * Concurrency is governed by the Dart-side scheduler (at most 8 in-flight
 * calls, default 2), so the pool here only needs to match that ceiling; its
 * threads are created lazily as slots are actually used.
 */
class ThumbnailPlugin : FlutterPlugin, ThumbnailHostApi {
    private var extractor: Extractor? = null
    private var executor: ExecutorService? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        extractor = Extractor(binding.applicationContext, binding.flutterAssets)
        executor = Executors.newFixedThreadPool(8)
        ThumbnailHostApi.setUp(binding.binaryMessenger, this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        ThumbnailHostApi.setUp(binding.binaryMessenger, null)
        executor?.shutdown()
        executor = null
        extractor = null
    }

    override fun extract(request: ExtractRequest, callback: (Result<ExtractResult>) -> Unit) {
        val extractor = this.extractor
        val executor = this.executor
        if (extractor == null || executor == null) {
            callback(
                Result.failure(
                    FlutterError("extractionFailed", "plugin detached from engine", null)
                )
            )
            return
        }
        executor.execute {
            val result = try {
                Result.success(extractor.extract(request))
            } catch (e: FlutterError) {
                Result.failure(e)
            } catch (e: Throwable) {
                Result.failure(
                    FlutterError("extractionFailed", e.message ?: e.toString(), null)
                )
            }
            mainHandler.post { callback(result) }
        }
    }

    override fun cancel(requestId: String) {
        // Not supported on Android in v1: MediaMetadataRetriever cannot be
        // aborted safely from another thread. The Dart engine detaches the
        // request; the finished frame still lands in the disk cache.
    }
}
