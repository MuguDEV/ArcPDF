package com.arcpdf.app

import android.app.ActivityManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.pdf.PdfRenderer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.common.moduleinstall.ModuleInstall
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.common.MlKitException
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ExecutionException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/*
 * Channel contract: com.arcpdf.app/reflow_ocr
 *
 * Dart -> native
 *   recognizePages  args: {requestId: String (required, unique among active
 *                   requests), path: String, pages: List<int> (1-based),
 *                   maxDimension: int? (clamped 1200..3200, default 2400)}
 *                   Success: List<Map> with {page: int, lines: List<{text,
 *                   bounds: [l,t,r,b] in PDF points, confidence: double,
 *                   elements: List<{text, bounds, confidence}>}>}. The format is
 *                   unchanged. A page with no recognized text is returned with
 *                   lines = [] and is not an error. Pages outside the document
 *                   are omitted.
 *   cancelOcr       args: {requestId: String}. The pending recognizePages reply
 *                   completes immediately with ocr_cancelled; queued work never
 *                   starts and running work stops between pages. Reply: null.
 *   cancelAll       no args. Call when the document closes. Cancels every request
 *                   as cancelOcr does. Reply: null.
 *
 * Native -> Dart (invokeMethod on this channel, main thread, only while the
 * request is still active)
 *   progress  args: {requestId: String, page: int (page just processed),
 *             done: int (pages processed so far), total: int}
 *
 * Errors (PlatformException code, message without paths, details map):
 *   ocr_invalid_request     missing requestId/path/pages, duplicate requestId,
 *                           unreadable file
 *   ocr_unsupported_device  no usable Google Play services or Android < 6.0
 *   ocr_module_missing      the OCR module is not installed (use ocr_module
 *                           channel to install it, then retry)
 *   ocr_cancelled           cancelOcr, cancelAll or engine detach
 *   ocr_timeout             a page exceeded 45s; no result is published
 *   ocr_permission_denied   the PDF could not be read
 *   ocr_recognition_failed  any other failure; details.cause = exception class
 *
 * Resource trade-off: if ML Kit never completes a task after a timeout, the
 * page bitmap and the recognizer stay allocated until the process ends,
 * because releasing them while the task may still read them is unsafe. The
 * request itself still fails with ocr_timeout and the worker moves on.
 */
object ReflowOcrChannel {
    private const val channelName = "com.arcpdf.app/reflow_ocr"
    private const val pageTimeoutSeconds = 45L
    private const val moduleCheckTimeoutSeconds = 15L

    private val mainHandler = Handler(Looper.getMainLooper())
    private var executor: ExecutorService? = null
    private var runner: OcrRequestRunner? = null
    private var channel: MethodChannel? = null
    private val owner = OcrOwnerGuard()

    @Synchronized
    fun register(context: Context, messenger: BinaryMessenger) {
        teardown()
        owner.claim(messenger)
        val appContext = context.applicationContext
        val worker = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "arcpdf-reflow-ocr").apply { isDaemon = true }
        }
        executor = worker
        val requests = OcrRequestRunner(worker, { mainHandler.post(it) })
        runner = requests
        val methodChannel = MethodChannel(messenger, channelName)
        channel = methodChannel
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "recognizePages" -> start(appContext, methodChannel, requests, call.arguments, result)
                "cancelOcr" -> {
                    val id = call.argument<String>("requestId")
                    if (!id.isNullOrBlank()) requests.cancel(id)
                    result.success(null)
                }
                "cancelAll" -> {
                    requests.cancelAll()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Cancels everything and releases the executor when the engine detaches.
     * A task already running keeps its worker until the current page finishes
     * or times out (45 s at most).
     */
    @Synchronized
    fun unregister(messenger: BinaryMessenger) {
        if (!owner.release(messenger)) return
        teardown()
    }

    private fun teardown() {
        runner?.cancelAll()
        runner = null
        channel?.setMethodCallHandler(null)
        channel = null
        executor?.shutdownNow()
        executor = null
    }

    private fun start(
        context: Context,
        methodChannel: MethodChannel,
        requests: OcrRequestRunner,
        arguments: Any?,
        result: MethodChannel.Result,
    ) {
        val args = arguments as? Map<*, *>
        val requestId = args?.get("requestId") as? String
        val path = args?.get("path") as? String
        val pages = (args?.get("pages") as? List<*>).orEmpty()
            .mapNotNull { (it as? Number)?.toInt() }.distinct().sorted()
        val requested = (args?.get("maxDimension") as? Number)?.toInt()
        if (requestId.isNullOrBlank() || path.isNullOrBlank() || pages.isEmpty()) {
            result.error(
                OcrErrors.INVALID_REQUEST,
                "A request id, a PDF and at least one page are required.",
                emptyMap<String, Any?>(),
            )
            return
        }
        val reply = object : OcrReply {
            override fun success(value: Any?) = result.success(value)
            override fun error(code: String, message: String?, details: Map<String, Any?>) =
                result.error(code, message, details)
        }
        val started = requests.start(requestId, reply) { token ->
            val memory = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val maxDimension = OcrDimensions.maxDimension(
                requested,
                memory.isLowRamDevice,
                memory.memoryClass,
            )
            recognize(context, methodChannel, token, path, pages, maxDimension)
        }
        if (!started) {
            result.error(OcrErrors.INVALID_REQUEST, "Request id is already active.", emptyMap<String, Any?>())
        }
    }

    private fun recognize(
        context: Context,
        methodChannel: MethodChannel,
        token: OcrRequestToken,
        path: String,
        pages: List<Int>,
        maxDimension: Int,
    ): List<Map<String, Any>> {
        val source = File(path)
        if (!source.isFile) throw OcrException(OcrErrors.INVALID_REQUEST, "PDF is unavailable")
        if (Build.VERSION.SDK_INT < 23 ||
            GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context) !=
            ConnectionResult.SUCCESS
        ) {
            throw OcrException(OcrErrors.UNSUPPORTED_DEVICE, "Google Play services is unavailable.")
        }
        token.throwIfCancelled()
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        // The recognizer closes once the request and every recognition task that
        // uses it have finished, including a task that outlives a timeout.
        val recognizerGate = ResourceGate { recognizer.close() }
        recognizerGate.begin()
        try {
            requireModule(context, recognizer)
            token.throwIfCancelled()
            ParcelFileDescriptor.open(source, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
                PdfRenderer(descriptor).use { renderer ->
                    return OcrPageLoop.run(
                        token,
                        pages,
                        onProgress = { page, done, total ->
                            token.publishIfActive {
                                mainHandler.post {
                                    if (token.isActive) {
                                        methodChannel.invokeMethod(
                                            "progress",
                                            mapOf(
                                                "requestId" to token.id,
                                                "page" to page,
                                                "done" to done,
                                                "total" to total,
                                            ),
                                        )
                                    }
                                }
                            }
                        },
                    ) { pageNumber ->
                        val index = pageNumber - 1
                        if (index !in 0 until renderer.pageCount) return@run null
                        renderPage(renderer, index, pageNumber, maxDimension, token, recognizer, recognizerGate)
                    }
                }
            }
        } finally {
            recognizerGate.end()
            recognizerGate.close()
        }
    }

    private fun requireModule(context: Context, recognizer: TextRecognizer) {
        val available = try {
            Tasks.await(
                ModuleInstall.getClient(context).areModulesAvailable(recognizer),
                moduleCheckTimeoutSeconds,
                TimeUnit.SECONDS,
            ).areModulesAvailable()
        } catch (error: Exception) {
            throw OcrErrors.from(unwrap(error))
        }
        if (!available) throw OcrException(OcrErrors.MODULE_MISSING, "The OCR module is not installed.")
    }

    private fun renderPage(
        renderer: PdfRenderer,
        index: Int,
        pageNumber: Int,
        maxDimension: Int,
        token: OcrRequestToken,
        recognizer: TextRecognizer,
        recognizerGate: ResourceGate,
    ): Map<String, Any> = renderer.openPage(index).use { page ->
        val scale = OcrDimensions.scale(page.width, page.height, maxDimension)
        val (bitmapWidth, bitmapHeight) = OcrDimensions.bitmapSize(page.width, page.height, scale)
        val bitmap = Bitmap.createBitmap(bitmapWidth, bitmapHeight, Bitmap.Config.ARGB_8888)
        // The bitmap is recycled only after the recognition task using it ended.
        val bitmapGate = ResourceGate { bitmap.recycle() }
        val text = OcrPageStep.run(
            token,
            bitmapGate,
            recognizerGate,
            render = {
                bitmap.eraseColor(Color.WHITE)
                page.render(
                    bitmap,
                    null,
                    Matrix().apply { setScale(scale, scale) },
                    PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY,
                )
            },
            start = { MlKitOcrTask(recognizer.process(InputImage.fromBitmap(bitmap, 0))) },
        )
        mapOf("page" to pageNumber, "lines" to toLines(text, scale))
    }

    /** Adapts an ML Kit task; maps its failures to structured OCR errors. */
    private class MlKitOcrTask(private val task: com.google.android.gms.tasks.Task<Text>) : OcrTask<Text> {
        override fun onFinished(callback: () -> Unit) {
            task.addOnCompleteListener({ it.run() }) { callback() }
        }

        override fun await(): Text = try {
            Tasks.await(task, pageTimeoutSeconds, TimeUnit.SECONDS)
        } catch (error: ExecutionException) {
            val cause = error.cause
            if (cause is MlKitException && cause.errorCode == MlKitException.UNAVAILABLE) {
                throw OcrException(OcrErrors.MODULE_MISSING, "The OCR module is not installed.", cause = cause)
            }
            throw OcrErrors.from(error.cause ?: error)
        }
    }

    private fun unwrap(error: Exception): Throwable =
        if (error is ExecutionException) error.cause ?: error else error

    private fun toLines(text: Text, scale: Float): List<Map<String, Any>> =
        text.textBlocks.flatMap { block -> block.lines }.mapNotNull { line ->
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
                    val elementBounds = element.boundingBox ?: return@mapNotNull null
                    mapOf(
                        "text" to element.text,
                        "bounds" to listOf(
                            elementBounds.left / scale.toDouble(),
                            elementBounds.top / scale.toDouble(),
                            elementBounds.right / scale.toDouble(),
                            elementBounds.bottom / scale.toDouble(),
                        ),
                        "confidence" to
                            (element.confidence ?: line.confidence ?: 0.72f).toDouble(),
                    )
                },
            )
        }
}
