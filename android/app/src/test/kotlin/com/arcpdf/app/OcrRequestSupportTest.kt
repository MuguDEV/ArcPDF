package com.arcpdf.app

import java.util.concurrent.TimeoutException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class OcrRequestSupportTest {
    private val registry = OcrRequestRegistry()

    private fun page(n: Int, lines: List<String> = listOf("x")) =
        mapOf("page" to n, "lines" to lines)

    @Test
    fun cancellationBeforeProcessingRunsNoPage() {
        val token = registry.register("a")!!
        registry.cancel("a")
        val seen = mutableListOf<Int>()
        try {
            OcrPageLoop.run(token, listOf(1, 2), { _, _, _ -> }) { seen.add(it); page(it) }
            fail()
        } catch (e: OcrException) {
            assertEquals(OcrErrors.CANCELLED, e.code)
        }
        assertTrue(seen.isEmpty())
    }

    @Test
    fun cancellationBetweenPagesStopsTheLoop() {
        val token = registry.register("a")!!
        val seen = mutableListOf<Int>()
        val progress = mutableListOf<Triple<Int, Int, Int>>()
        try {
            OcrPageLoop.run(token, listOf(1, 2, 3), { p, d, t -> progress.add(Triple(p, d, t)) }) {
                seen.add(it)
                if (it == 2) registry.cancel("a")
                page(it)
            }
            fail()
        } catch (e: OcrException) {
            assertEquals(OcrErrors.CANCELLED, e.code)
        }
        assertEquals(listOf(1, 2), seen)
        assertEquals(listOf(Triple(1, 1, 3)), progress)
    }

    @Test
    fun progressIsReportedPerPageIncludingSkippedPages() {
        val token = registry.register("a")!!
        val progress = mutableListOf<Triple<Int, Int, Int>>()
        val out = OcrPageLoop.run(token, listOf(1, 9, 3), { p, d, t -> progress.add(Triple(p, d, t)) }) {
            if (it == 9) null else page(it)
        }
        assertEquals(2, out.size)
        assertEquals(listOf(Triple(1, 1, 3), Triple(9, 2, 3), Triple(3, 3, 3)), progress)
    }

    @Test
    fun cancelAllCancelsEveryRequestAndLateResultIsNotPublished() {
        val a = registry.register("a")!!
        val b = registry.register("b")!!
        assertEquals(2, registry.cancelAll().size)
        assertTrue(a.cancelled && b.cancelled)
        // Document closed: cancel replied once, a late worker result must not.
        assertTrue(a.tryComplete())
        assertFalse(a.tryComplete())
        var published = false
        assertFalse(a.publishIfActive { published = true })
        assertFalse(published)
    }

    @Test
    fun lateCompletionAfterCancelReplyIsDropped() {
        val token = registry.register("a")!!
        registry.cancel("a")
        assertTrue(token.tryComplete())      // cancel reply
        assertFalse(token.tryComplete())     // late recognition result
    }

    @Test
    fun duplicateActiveIdIsRejectedAndReusableAfterRelease() {
        val token = registry.register("a")!!
        assertNull(registry.register("a"))
        registry.release(token)
        assertNotNull(registry.register("a"))
    }

    @Test
    fun timeoutDefersResourceReleaseUntilTaskEnds() {
        val events = mutableListOf<String>()
        val bitmap = ResourceGate { events.add("bitmap") }
        val recognizer = ResourceGate { events.add("recognizer") }
        // owners
        bitmap.begin(); recognizer.begin()
        // recognition task in flight
        assertTrue(bitmap.begin()); assertTrue(recognizer.begin())
        // timeout: owners finish and request close while the task still runs
        bitmap.end(); bitmap.close()
        recognizer.end(); recognizer.close()
        assertTrue(events.isEmpty())
        assertFalse(bitmap.isReleased())
        // task completes late
        bitmap.end(); recognizer.end()
        assertEquals(listOf("bitmap", "recognizer"), events)
    }

    @Test
    fun gateReleasesOnceAndRefusesNewWorkAfterClose() {
        var count = 0
        val gate = ResourceGate { count++ }
        gate.begin()
        gate.end()
        gate.close()
        gate.close()
        assertEquals(1, count)
        assertFalse(gate.begin())
    }

    @Test
    fun emptyTextIsASuccessfulPageNotAnError() {
        val token = registry.register("a")!!
        val out = OcrPageLoop.run(token, listOf(1), { _, _, _ -> }) { page(it, emptyList()) }
        assertEquals(listOf(page(1, emptyList())), out)
    }

    @Test
    fun recognitionFailureIsAStructuredErrorNotEmptyText() {
        val token = registry.register("a")!!
        val failure = try {
            OcrPageLoop.run<Map<String, Any>>(token, listOf(1), { _, _, _ -> }) {
                throw IllegalStateException("engine")
            }
            null
        } catch (e: Exception) {
            OcrErrors.from(e)
        }
        assertEquals(OcrErrors.RECOGNITION_FAILED, failure!!.code)
        assertEquals("IllegalStateException", failure.details["cause"])
    }

    @Test
    fun errorMappingDistinguishesCauses() {
        assertEquals(OcrErrors.TIMEOUT, OcrErrors.from(TimeoutException()).code)
        assertEquals(OcrErrors.PERMISSION_DENIED, OcrErrors.from(SecurityException()).code)
        assertEquals(
            OcrErrors.MODULE_MISSING,
            OcrErrors.from(OcrException(OcrErrors.MODULE_MISSING, "m")).code,
        )
    }

    @Test
    fun dimensionClampAndDeviceLimits() {
        assertEquals(2400, OcrDimensions.maxDimension(null, false, 256))
        assertEquals(1200, OcrDimensions.maxDimension(10, false, 256))
        assertEquals(3200, OcrDimensions.maxDimension(9999, false, 256))
        assertEquals(1900, OcrDimensions.maxDimension(3200, false, 128))
        assertEquals(1600, OcrDimensions.maxDimension(3200, true, 512))
        assertEquals(1200, OcrDimensions.maxDimension(1200, true, 512))
    }

    @Test
    fun scaleRule() {
        // Longest side below the limit: upscale capped at 2.5.
        assertEquals(2.5f, OcrDimensions.scale(612, 792, 2400), 1e-6f)
        // Longest side at/above the limit: fit to the limit.
        assertEquals(0.5f, OcrDimensions.scale(2000, 4800, 2400), 1e-6f)
        assertEquals(1f, OcrDimensions.scale(2400, 1000, 2400), 1e-6f)
        assertEquals(2000 to 3000, OcrDimensions.bitmapSize(1000, 1500, 2f))
    }
}
