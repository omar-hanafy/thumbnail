package tech.tomars.cached_video_thumbnail

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileNotFoundException
import java.io.FileOutputStream
import java.io.IOException
import java.security.MessageDigest
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Stateless single-frame extractor built on [MediaMetadataRetriever].
 *
 * Performance rules (see the package design doc):
 * - OPTION_CLOSEST_SYNC by default; OPTION_CLOSEST only when `exact` is set.
 * - getScaledFrameAtTime (API 27+) so large sources are downscaled during
 *   decode instead of after it.
 * - Frames are compressed straight into the destination file; the encoded
 *   image never exists as an in-memory byte array.
 * - Time conversion happens in Long space; the classic `timeMs * 1000` int
 *   overflow is impossible by construction.
 */
internal class Extractor(
    private val context: Context,
    private val flutterAssets: FlutterPlugin.FlutterAssets,
) {
    fun extract(request: ExtractRequest): ExtractResult {
        val retriever = MediaMetadataRetriever()
        try {
            setDataSource(retriever, request)
            return decodeAndEncode(retriever, request)
        } finally {
            try {
                retriever.release()
            } catch (_: IOException) {
                // Releasing is best-effort.
            }
        }
    }

    private fun decodeAndEncode(
        retriever: MediaMetadataRetriever,
        request: ExtractRequest,
    ): ExtractResult {
        fun meta(key: Int): String? = retriever.extractMetadata(key)

        val srcWidth = meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
        val srcHeight = meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
        if (srcWidth <= 0 || srcHeight <= 0) {
            throw FlutterError("unsupportedMedia", "media has no decodable video track", null)
        }
        val rotation =
            meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
        val durationMs = meta(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L

        // MediaMetadataRetriever returns display-oriented frames, so the fit
        // box must be computed against display-oriented dimensions.
        val displayWidth = if (rotation == 90 || rotation == 270) srcHeight else srcWidth
        val displayHeight = if (rotation == 90 || rotation == 270) srcWidth else srcHeight

        val positionMs =
            if (durationMs > 0) min(max(request.positionMs, 0L), durationMs) else max(request.positionMs, 0L)
        val timeUs = positionMs * 1000L
        val option =
            if (request.exact) MediaMetadataRetriever.OPTION_CLOSEST
            else MediaMetadataRetriever.OPTION_CLOSEST_SYNC

        val target = fitBox(
            displayWidth,
            displayHeight,
            request.maxWidth.toInt(),
            request.maxHeight.toInt(),
        )
        var bitmap: Bitmap = if (Build.VERSION.SDK_INT >= 27 && target != null) {
            retriever.getScaledFrameAtTime(timeUs, option, target.first, target.second)
        } else {
            retriever.getFrameAtTime(timeUs, option)
        } ?: throw FlutterError("unsupportedMedia", "decoder produced no frame", null)

        if (target != null && (bitmap.width > target.first || bitmap.height > target.second)) {
            // Pre-API-27 fallback: decode happened at full size, scale after.
            val scaled = Bitmap.createScaledBitmap(bitmap, target.first, target.second, true)
            if (scaled !== bitmap) bitmap.recycle()
            bitmap = scaled
        }

        try {
            encodeToFile(bitmap, request)
            return ExtractResult(bitmap.width.toLong(), bitmap.height.toLong())
        } finally {
            bitmap.recycle()
        }
    }

    /**
     * Largest size that fits inside (maxWidth, maxHeight) preserving aspect,
     * or null when unconstrained or when the source is already small enough
     * (frames are never upscaled). A zero max means unconstrained on that axis.
     */
    private fun fitBox(width: Int, height: Int, maxWidth: Int, maxHeight: Int): Pair<Int, Int>? {
        if (maxWidth <= 0 && maxHeight <= 0) return null
        val scaleW = if (maxWidth > 0) maxWidth.toDouble() / width else Double.MAX_VALUE
        val scaleH = if (maxHeight > 0) maxHeight.toDouble() / height else Double.MAX_VALUE
        val scale = min(scaleW, scaleH)
        if (scale >= 1.0) return null
        return Pair(
            max(1, (width * scale).roundToInt()),
            max(1, (height * scale).roundToInt()),
        )
    }

    private fun encodeToFile(bitmap: Bitmap, request: ExtractRequest) {
        val format =
            if (request.format == "png") Bitmap.CompressFormat.PNG
            else Bitmap.CompressFormat.JPEG
        val quality = request.quality.toInt().coerceIn(1, 100)
        try {
            FileOutputStream(request.destPath).use { fileStream ->
                BufferedOutputStream(fileStream).use { stream ->
                    if (!bitmap.compress(format, quality, stream)) {
                        throw FlutterError("encodingFailed", "Bitmap.compress returned false", null)
                    }
                }
            }
        } catch (e: IOException) {
            throw FlutterError("io", "failed writing ${request.destPath}: ${e.message}", null)
        }
    }

    private fun setDataSource(retriever: MediaMetadataRetriever, request: ExtractRequest) {
        when (request.sourceType) {
            SourceKind.ASSET -> setAssetSource(retriever, request)
            SourceKind.FILE -> {
                val file = File(request.source)
                if (!file.exists()) {
                    throw FlutterError("fileNotFound", "file does not exist: ${request.source}", null)
                }
                try {
                    retriever.setDataSource(request.source)
                } catch (e: Exception) {
                    throw FlutterError("unsupportedMedia", "cannot open ${request.source}: ${e.message}", null)
                }
            }
            SourceKind.NETWORK -> {
                try {
                    retriever.setDataSource(request.source, request.headers ?: emptyMap())
                } catch (e: Exception) {
                    // MediaMetadataRetriever reports connection and HTTP-status
                    // failures as opaque runtime errors; classify them as network.
                    throw FlutterError("network", "cannot open ${request.source}: ${e.message}", null)
                }
            }
        }
    }

    private fun setAssetSource(retriever: MediaMetadataRetriever, request: ExtractRequest) {
        val assetPackage = request.assetPackage
        val lookupKey =
            if (assetPackage != null) flutterAssets.getAssetFilePathByName(request.source, assetPackage)
            else flutterAssets.getAssetFilePathByName(request.source)
        try {
            context.assets.openFd(lookupKey).use { afd ->
                retriever.setDataSource(afd.fileDescriptor, afd.startOffset, afd.declaredLength)
            }
            return
        } catch (_: IOException) {
            // Compressed asset (no direct fd) or missing; disambiguate below.
        }
        val copy = copyAssetToCache(lookupKey)
        try {
            retriever.setDataSource(copy.absolutePath)
        } catch (e: Exception) {
            throw FlutterError("unsupportedMedia", "cannot open asset $lookupKey: ${e.message}", null)
        }
    }

    /**
     * One-time fallback for assets stored compressed inside the APK (video
     * extensions are on aapt's default noCompress list, so this path is
     * rare). Copies are keyed by asset path and reused forever.
     */
    private fun copyAssetToCache(lookupKey: String): File {
        val dir = File(context.cacheDir, "thumbnail_assets")
        val digest = MessageDigest.getInstance("SHA-1")
            .digest(lookupKey.toByteArray())
            .joinToString("") { "%02x".format(it) }
        val target = File(dir, "$digest.bin")
        synchronized(assetCopyLock) {
            if (target.exists() && target.length() > 0) return target
            dir.mkdirs()
            val temp = File(dir, "$digest.tmp")
            try {
                context.assets.open(lookupKey).use { input ->
                    FileOutputStream(temp).use { output -> input.copyTo(output) }
                }
            } catch (e: FileNotFoundException) {
                temp.delete()
                throw FlutterError("assetNotFound", "asset not found: $lookupKey", null)
            } catch (e: IOException) {
                temp.delete()
                throw FlutterError("io", "failed copying asset $lookupKey: ${e.message}", null)
            }
            if (!temp.renameTo(target)) {
                temp.delete()
                throw FlutterError("io", "failed publishing asset copy for $lookupKey", null)
            }
            return target
        }
    }

    private companion object {
        val assetCopyLock = Any()
    }
}
