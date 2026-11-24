package com.arcpdf.app

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OcrOwnerGuardTest {
    @Test
    fun currentOwnerCanRelease() {
        val guard = OcrOwnerGuard()
        val a = Any()
        guard.claim(a)
        assertTrue(guard.release(a))
        assertFalse(guard.release(a))
    }

    @Test
    fun lateReleaseFromOldOwnerIsIgnored() {
        val guard = OcrOwnerGuard()
        val old = Any()
        val new = Any()
        guard.claim(old)
        guard.claim(new)
        assertFalse(guard.release(old))
        assertTrue(guard.release(new))
    }
}
