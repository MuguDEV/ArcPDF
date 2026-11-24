package com.arcpdf.app

import java.util.concurrent.TimeoutException
import kotlin.math.min
import kotlin.math.roundToInt

/*
 * Pure (JVM testable) building blocks for ReflowOcrChannel: request registry,
 * cooperative page loop, structured errors, resource gates and the adaptive
 * rendering dimensions.
 */

/** Structured OCR failure. [code] is sent to Dart as the channel error code. */
class OcrException(
    val code: String,
    message: String,
    val details: Map<String, Any?> = emptyMap(),
    cause: Throwable? = null,
) : Exception(message, cause)

object OcrErrors {
    const val MODULE_MISSING = "ocr_module_missing"
    const val UNSUPPORTED_DEVICE = "ocr_unsupported_device"
    const val CANCELLED = "ocr_cancelled"
    const val TIMEOUT = "ocr_timeout"
    const val RECOGNITION_FAILED = "ocr_recognition_failed"
    const val PERMISSION_DENIED = "ocr_permission_denied"
    const val INVALID_REQUEST = "ocr_invalid_request"

    /** Maps any throwable to a structured error. Messages never contain paths. */
    fun from(error: Throwable): OcrException = when (error) {
        is OcrException -> error
        is SecurityException -> OcrException(
            PERMISSION_DENIED,
            "ArcPDF cannot read this PDF for OCR.",
            cause = error,
        )
        is TimeoutException -> OcrException(
            TIMEOUT,
            "Scanned text recognition timed out.",
            cause = error,
        )
        else -> OcrException(
            RECOGNITION_FAILED,
            "Scanned text could not be recognized.",
            mapOf("cause" to (error.cause ?: error).javaClass.simpleName),
            error,
        )
    }
}

/** One in-flight Dart request. Completion is exactly-once and cancellation is cooperative. */
class OcrRequestToken(val id: String) {
    @Volatile
    var cancelled = false
        private set
    private var completed = false

    val isActive: Boolean get() = synchronized(this) { !cancelled && !completed }

    fun cancel() {
        cancelled = true
    }

    fun throwIfCancelled() {
        if (cancelled) throw OcrException(OcrErrors.CANCELLED, "OCR was cancelled.")
    }

    /** True for the single caller that may deliver the Dart reply. */
    fun tryComplete(): Boolean = synchronized(this) {
        if (completed) false else { completed = true; true }
    }

    /** Runs [block] only while the request is still active (progress events). */
    fun publishIfActive(block: () -> Unit): Boolean = synchronized(this) {
        if (cancelled || completed) false else { block(); true }
    }
}

open class OcrRequestRegistry {
    private val tokens = LinkedHashMap<String, OcrRequestToken>()

    /** Returns null when an active request already uses [id]. */
    @Synchronized
    fun register(id: String): OcrRequestToken? {
        if (tokens.containsKey(id)) return null
        return OcrRequestToken(id).also { tokens[id] = it }
    }

    @Synchronized
    fun cancel(id: String): OcrRequestToken? = tokens[id]?.also { it.cancel() }

    @Synchronized
    fun cancelAll(): List<OcrRequestToken> = tokens.values.toList().onEach { it.cancel() }

    @Synchronized
    open fun release(token: OcrRequestToken) {
        if (tokens[token.id] === token) tokens.remove(token.id)
    }

    @Synchronized
    fun activeCount(): Int = tokens.size
}

object OcrPageLoop {
    /**
     * Runs [recognizePage] for each page, checking cancellation before every page.
     * A null result means the page does not exist and is skipped.
     * Progress is reported after every page, including skipped ones.
     */
    fun <T : Any> run(
        token: OcrRequestToken,
        pages: List<Int>,
        onProgress: (page: Int, done: Int, total: Int) -> Unit,
        recognizePage: (Int) -> T?,
    ): List<T> {
        val output = ArrayList<T>(pages.size)
        pages.forEachIndexed { index, page ->
            token.throwIfCancelled()
            recognizePage(page)?.let(output::add)
            token.throwIfCancelled()
            onProgress(page, index + 1, pages.size)
        }
        return output
    }
}

/**
 * Releases a resource (bitmap, recognizer) only after every task that uses it has
 * ended. [close] may be called while work is in flight (for example after a
 * timeout); the release then happens when the last task calls [end].
 */
class ResourceGate(private val release: () -> Unit) {
    private var inFlight = 0
    private var closeRequested = false
    private var released = false

    /** False when the resource is already closing and must not be used. */
    @Synchronized
    fun begin(): Boolean {
        if (closeRequested) return false
        inFlight++
        return true
    }

    fun end() {
        if (shouldRelease { inFlight-- }) release()
    }

    fun close() {
        if (shouldRelease { closeRequested = true }) release()
    }

    @Synchronized
    private fun shouldRelease(change: () -> Unit): Boolean {
        change()
        if (released || !closeRequested || inFlight > 0) return false
        released = true
        return true
    }

    @Synchronized
    fun isReleased(): Boolean = released
}

object OcrDimensions {
    const val MIN = 1200
    const val MAX = 3200
    const val DEFAULT = 2400

    fun maxDimension(requested: Int?, isLowRamDevice: Boolean, memoryClass: Int): Int {
        val wanted = (requested ?: DEFAULT).coerceIn(MIN, MAX)
        val deviceLimit = when {
            isLowRamDevice -> 1600
            memoryClass < 192 -> 1900
            else -> wanted
        }
        return min(wanted, deviceLimit)
    }

    fun scale(pageWidth: Int, pageHeight: Int, maxDimension: Int): Float {
        val longest = maxOf(pageWidth, pageHeight).toFloat()
        return if (longest >= maxDimension) maxDimension / longest
        else min(2.5f, maxDimension / longest)
    }

    fun bitmapSize(pageWidth: Int, pageHeight: Int, scale: Float): Pair<Int, Int> =
        (pageWidth * scale).roundToInt().coerceAtLeast(1) to
            (pageHeight * scale).roundToInt().coerceAtLeast(1)
}

/** Reply sink for one Dart call. Wraps MethodChannel.Result so tests can fake it. */
interface OcrReply {
    fun success(value: Any?)
    fun error(code: String, message: String?, details: Map<String, Any?>)
}

/**
 * Owns the lifecycle of recognition requests: registration, queued execution on
 * [executor], exactly-once reply publication through [post] (the main thread in
 * production) and cleanup. [work] does the actual recognition.
 *
 * Ordering rules, covered by tests:
 * - the reply entry is removed before the token is released, so a new request
 *   that reuses the id after release can never lose its reply;
 * - a reply is published at most once and never for a cancelled request, except
 *   the single immediate ocr_cancelled reply.
 */
class OcrRequestRunner(
    private val executor: java.util.concurrent.Executor,
    private val post: (() -> Unit) -> Unit,
    private val registry: OcrRequestRegistry = OcrRequestRegistry(),
) {
    private val replies = HashMap<String, OcrReply>()

    /** Returns false when [requestId] is already active (nothing was started). */
    fun start(requestId: String, reply: OcrReply, work: (OcrRequestToken) -> Any?): Boolean {
        val token = registry.register(requestId) ?: return false
        synchronized(replies) { replies[requestId] = reply }
        try {
            executor.execute {
                try {
                    // Cancelled while queued: the reply was already sent.
                    if (!token.isActive) return@execute
                    val value = work(token)
                    deliver(token) { it.success(value) }
                } catch (error: Throwable) {
                    val failure = OcrErrors.from(error)
                    deliver(token) { it.error(failure.code, failure.message, failure.details) }
                } finally {
                    // Reply entry first, then the id becomes reusable.
                    synchronized(replies) { if (replies[requestId] === reply) replies.remove(requestId) }
                    registry.release(token)
                }
            }
        } catch (_: java.util.concurrent.RejectedExecutionException) {
            synchronized(replies) { if (replies[requestId] === reply) replies.remove(requestId) }
            registry.release(token)
            publishCancelled(token, reply)
        }
        return true
    }

    fun cancel(requestId: String) {
        registry.cancel(requestId)?.let { cancelled(it) }
    }

    fun cancelAll() {
        registry.cancelAll().forEach { cancelled(it) }
    }

    fun activeCount(): Int = registry.activeCount()

    private fun cancelled(token: OcrRequestToken) {
        if (!token.tryComplete()) return
        val reply = synchronized(replies) { replies.remove(token.id) } ?: return
        post { reply.error(OcrErrors.CANCELLED, "OCR was cancelled.", emptyMap()) }
    }

    private fun publishCancelled(token: OcrRequestToken, reply: OcrReply) {
        if (token.tryComplete()) {
            post { reply.error(OcrErrors.CANCELLED, "OCR was cancelled.", emptyMap()) }
        }
    }

    private fun deliver(token: OcrRequestToken, send: (OcrReply) -> Unit) {
        if (token.cancelled || !token.tryComplete()) return
        val reply = synchronized(replies) { replies.remove(token.id) } ?: return
        post { send(reply) }
    }
}

/** A running asynchronous recognition (an ML Kit task in production). */
interface OcrTask<T> {
    /** [callback] runs once the task has ended, whatever the outcome. */
    fun onFinished(callback: () -> Unit)

    /** Blocks for the result. May throw TimeoutException; the task keeps running. */
    fun await(): T
}

object OcrPageStep {
    /**
     * Renders into the bitmap guarded by [bitmapGate], then recognizes it. The
     * recognition task holds both gates until it ends, so a timeout releases
     * neither the bitmap nor the recognizer while ML Kit may still read them.
     * Cancellation after rendering skips recognition entirely.
     */
    fun <T> run(
        token: OcrRequestToken,
        bitmapGate: ResourceGate,
        recognizerGate: ResourceGate,
        render: () -> Unit,
        start: () -> OcrTask<T>,
    ): T {
        bitmapGate.begin()
        try {
            render()
            token.throwIfCancelled()
            if (!recognizerGate.begin()) throw OcrException(OcrErrors.CANCELLED, "OCR was cancelled.")
            if (!bitmapGate.begin()) {
                recognizerGate.end()
                throw OcrException(OcrErrors.CANCELLED, "OCR was cancelled.")
            }
            val task = try {
                start()
            } catch (error: Throwable) {
                bitmapGate.end()
                recognizerGate.end()
                throw error
            }
            task.onFinished {
                bitmapGate.end()
                recognizerGate.end()
            }
            return task.await()
        } finally {
            bitmapGate.end()
            bitmapGate.close()
        }
    }
}

/**
 * Tracks which engine (by messenger identity) owns the process-wide OCR
 * channel, so a late unregister from an old engine or activity cannot tear
 * down the channel a newer engine registered.
 */
class OcrOwnerGuard {
    private var current: Any? = null

    @Synchronized
    fun claim(owner: Any) {
        current = owner
    }

    /** Returns true and clears the owner only when [owner] is the current one. */
    @Synchronized
    fun release(owner: Any): Boolean {
        if (current !== owner) return false
        current = null
        return true
    }
}
