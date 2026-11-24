package com.arcpdf.app

import java.util.concurrent.Executor
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.TimeoutException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

private class RecordingReply(val name: String = "r") : OcrReply {
    val events = mutableListOf<String>()
    override fun success(value: Any?) { events.add("success:$value") }
    override fun error(code: String, message: String?, details: Map<String, Any?>) {
        events.add("error:$code")
    }
}

private class ManualExecutor : Executor {
    val queue = ArrayDeque<Runnable>()
    override fun execute(command: Runnable) { queue.addLast(command) }
    fun runAll() { while (queue.isNotEmpty()) queue.removeFirst().run() }
}

private class FakeTask<T>(private val outcome: () -> T) : OcrTask<T> {
    private var callback: (() -> Unit)? = null
    var finished = false
    override fun onFinished(callback: () -> Unit) { this.callback = callback }
    override fun await(): T = outcome()
    fun finish() { finished = true; callback?.invoke() }
}

class OcrRequestRunnerTest {
    private val executor = ManualExecutor()
    private val main = ArrayDeque<() -> Unit>()
    private fun flushMain() { while (main.isNotEmpty()) main.removeFirst()() }
    private fun runner(registry: OcrRequestRegistry = OcrRequestRegistry()) =
        OcrRequestRunner(executor, { main.addLast(it) }, registry)

    @Test
    fun successIsPublishedOnceOnTheMainQueue() {
        val r = runner()
        val reply = RecordingReply()
        assertTrue(r.start("a", reply) { "ok" })
        executor.runAll()
        assertTrue("reply must wait for the main thread", reply.events.isEmpty())
        flushMain()
        assertEquals(listOf("success:ok"), reply.events)
        assertEquals(0, r.activeCount())
    }

    @Test
    fun duplicateActiveIdIsRejectedWithoutStartingWork() {
        val r = runner()
        assertTrue(r.start("a", RecordingReply()) { "x" })
        var ran = false
        assertFalse(r.start("a", RecordingReply()) { ran = true })
        executor.runAll()
        assertEquals(false, ran)
    }

    @Test
    fun cancelWhileQueuedRepliesOnceAndNeverRunsWork() {
        val r = runner()
        val reply = RecordingReply()
        var ran = false
        r.start("a", reply) { ran = true; "x" }
        r.cancel("a")
        executor.runAll()
        flushMain()
        assertEquals(listOf("error:${OcrErrors.CANCELLED}"), reply.events)
        assertFalse(ran)
        assertEquals(0, r.activeCount())
    }

    @Test
    fun cancelDuringWorkNeverPublishesTheResult() {
        val r = runner()
        val reply = RecordingReply()
        r.start("a", reply) {
            r.cancel("a")
            "late result"
        }
        executor.runAll()
        flushMain()
        assertEquals(listOf("error:${OcrErrors.CANCELLED}"), reply.events)
    }

    @Test
    fun cancelAllCancelsEveryRequest() {
        val r = runner()
        val a = RecordingReply()
        val b = RecordingReply()
        r.start("a", a) { "x" }
        r.start("b", b) { "y" }
        r.cancelAll()
        executor.runAll()
        flushMain()
        assertEquals(listOf("error:${OcrErrors.CANCELLED}"), a.events)
        assertEquals(listOf("error:${OcrErrors.CANCELLED}"), b.events)
    }

    @Test
    fun failureIsMappedToAStructuredError() {
        val r = runner()
        val reply = RecordingReply()
        r.start("a", reply) { throw TimeoutException("slow") }
        executor.runAll()
        flushMain()
        assertEquals(listOf("error:${OcrErrors.TIMEOUT}"), reply.events)
    }

    @Test
    fun rejectedExecutorRepliesCancelled() {
        val rejecting = Executor { throw RejectedExecutionException() }
        val r = OcrRequestRunner(rejecting, { main.addLast(it) })
        val reply = RecordingReply()
        r.start("a", reply) { "x" }
        flushMain()
        assertEquals(listOf("error:${OcrErrors.CANCELLED}"), reply.events)
        assertEquals(0, r.activeCount())
    }

    @Test
    fun idReusedWhileTheOldRequestIsBeingReleasedKeepsItsReply() {
        lateinit var runnerRef: OcrRequestRunner
        val second = RecordingReply("second")
        var reused = false
        // The id becomes reusable the moment release returns. A new request
        // that registers then must not lose its reply to the old cleanup.
        val registry = object : OcrRequestRegistry() {
            override fun release(token: OcrRequestToken) {
                super.release(token)
                if (!reused) {
                    reused = true
                    runnerRef.start("a", second) { "second result" }
                }
            }
        }
        runnerRef = runner(registry)
        runnerRef.start("a", RecordingReply("first")) { "first result" }
        executor.runAll()
        flushMain()
        assertEquals(listOf("success:second result"), second.events)
    }

    private fun gates(events: MutableList<String>): Triple<ResourceGate, ResourceGate, OcrRequestToken> {
        val bitmap = ResourceGate { events.add("bitmap") }
        val recognizer = ResourceGate { events.add("recognizer") }
        recognizer.begin() // the request owner
        return Triple(bitmap, recognizer, OcrRequestRegistry().register("a")!!)
    }

    @Test
    fun timeoutKeepsBitmapAndRecognizerUntilTheTaskEnds() {
        val events = mutableListOf<String>()
        val (bitmap, recognizer, token) = gates(events)
        val task = FakeTask<String> { throw TimeoutException("45s") }
        try {
            OcrPageStep.run(token, bitmap, recognizer, render = {}, start = { task })
            fail()
        } catch (e: TimeoutException) {
            assertEquals(OcrErrors.TIMEOUT, OcrErrors.from(e).code)
        }
        recognizer.end(); recognizer.close() // request finished after the timeout
        assertTrue("nothing may be freed while ML Kit may still read it", events.isEmpty())
        task.finish()
        assertEquals(listOf("bitmap", "recognizer"), events)
    }

    @Test
    fun cancelAfterRenderSkipsRecognitionAndReleasesTheBitmap() {
        val events = mutableListOf<String>()
        val (bitmap, recognizer, token) = gates(events)
        var started = false
        try {
            OcrPageStep.run(
                token, bitmap, recognizer,
                render = { token.cancel() },
                start = { started = true; FakeTask { "x" } },
            )
            fail()
        } catch (e: OcrException) {
            assertEquals(OcrErrors.CANCELLED, e.code)
        }
        assertFalse(started)
        assertEquals(listOf("bitmap"), events)
    }

    @Test
    fun completedTaskReleasesTheBitmapAfterTheResultIsRead() {
        val events = mutableListOf<String>()
        val (bitmap, recognizer, token) = gates(events)
        val task = FakeTask { events.add("read"); "text" }
        val out = OcrPageStep.run(token, bitmap, recognizer, render = {}, start = { task })
        assertEquals("text", out)
        assertEquals(listOf("read"), events)
        task.finish()
        assertEquals(listOf("read", "bitmap"), events)
    }

    @Test
    fun startFailureReleasesEverythingItHeld() {
        val events = mutableListOf<String>()
        val (bitmap, recognizer, token) = gates(events)
        try {
            OcrPageStep.run<String>(token, bitmap, recognizer, render = {}, start = { error("boom") })
            fail()
        } catch (_: IllegalStateException) {
        }
        assertEquals(listOf("bitmap"), events)
        recognizer.end(); recognizer.close()
        assertEquals(listOf("bitmap", "recognizer"), events)
    }
}
