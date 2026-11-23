package com.arcpdf.app

import android.app.ActivityManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.math.min
import kotlin.math.roundToInt

object ReflowOcrChannel {
    private const val channelName = "com.arcpdf.app/reflow_ocr"
    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "arcpdf-reflow-ocr").apply { isDaemon = true }
    }

    fun register(activity: FlutterFragmentActivity, messenger: BinaryMessenger) {
        MethodChannel(messenger, channelName).setMethodCallHandler { call, result ->
            if (call.method != "recognizePages") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val path = call.argument<String>("path")
            val pages = call.argument<List<Int>>("pages").orEmpty().distinct().sorted()
            val maxDimension = call.argument<Int>("maxDimension")?.coerceIn(1200, 3200) ?: 2400
            if (path.isNullOrBlank() || pages.isEmpty()) {
                result.error("invalid_ocr_request", "A PDF and at least one page are required.", null)
                return@setMethodCallHandler
            }
            executor.execute {
                try {
                    val memory = activity.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                    val deviceLimit = when {
                        memory.isLowRamDevice -> 1600
                        memory.memoryClass < 192 -> 1900
                        else -> maxDimension
                    }
                    val recognized = recognize(path, pages, min(maxDimension, deviceLimit))
                    activity.runOnUiThread { result.success(recognized) }
                } catch (_: SecurityException) {
                    activity.runOnUiThread {
                        result.error("ocr_permission_denied", "ArcPDF cannot read this PDF for OCR.", null)
                    }
                } catch (_: Exception) {
                    activity.runOnUiThread {
                        result.error("ocr_failed", "Scanned text could not be recognized.", null)
                    }
                }
            }
        }
    }

    private fun recognize(
        path: String,
        pages: List<Int>,
        maxDimension: Int,
    ): List<Map<String, Any>> {
        val source = File(path)
        require(source.isFile) { "PDF is unavailable" }
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        try {
            ParcelFileDescriptor.open(source, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
                PdfRenderer(descriptor).use { renderer ->
                    return pages.mapNotNull { pageNumber ->
                        val index = pageNumber - 1
                        if (index !in 0 until renderer.pageCount) return@mapNotNull null
                        renderer.openPage(index).use { page ->
                            val longest = maxOf(page.width, page.height).toFloat()
                            val scale = if (longest >= maxDimension) {
                                maxDimension / longest
                            } else {
                                min(2.5f, maxDimension / longest)
                            }
                            val bitmapWidth = (page.width * scale).roundToInt().coerceAtLeast(1)
                            val bitmapHeight = (page.height * scale).roundToInt().coerceAtLeast(1)
                            val bitmap = Bitmap.createBitmap(
                                bitmapWidth,
                                bitmapHeight,
                                Bitmap.Config.ARGB_8888,
                            )
                            try {
                                bitmap.eraseColor(Color.WHITE)
                                page.render(
                                    bitmap,
                                    null,
                                    Matrix().apply { setScale(scale, scale) },
                                    PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY,
                                )
                                val text = Tasks.await(
                                    recognizer.process(InputImage.fromBitmap(bitmap, 0)),
                                    45,
                                    TimeUnit.SECONDS,
                                )
                                val lines = text.textBlocks.flatMap { block -> block.lines }.mapNotNull { line ->
                                    val bounds = line.boundingBox ?: return@mapNotNull null
                                    mapOf(
                                        "text" to line.text,
                                        "bounds" to listOf(
                                            bounds.left / scale.toDouble(),
                                            bounds.top / scale.toDouble(),
                                            bounds.right / scale.toDouble(),
                                            bounds.bottom / scale.toDouble(),
                                        ),
                                        "confidence" to (line.confidence ?: 0.72f).toDouble(),
                                        "elements" to line.elements.mapNotNull { element ->
                                            val elementBounds = element.boundingBox
                                                ?: return@mapNotNull null
                                            mapOf(
                                                "text" to element.text,
                                                "bounds" to listOf(
                                                    elementBounds.left / scale.toDouble(),
                                                    elementBounds.top / scale.toDouble(),
                                                    elementBounds.right / scale.toDouble(),
                                                    elementBounds.bottom / scale.toDouble(),
                                                ),
                                                "confidence" to
                                                    (element.confidence ?: line.confidence ?: 0.72f)
                                                        .toDouble(),
                                            )
                                        },
                                    )
                                }
                                mapOf("page" to pageNumber, "lines" to lines)
                            } finally {
                                bitmap.recycle()
                            }
                        }
                    }
                }
            }
        } finally {
            recognizer.close()
        }
    }
}
