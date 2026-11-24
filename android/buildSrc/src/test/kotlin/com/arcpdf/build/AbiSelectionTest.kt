package com.arcpdf.build

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class AbiSelectionTest {
    private fun rejected(abis: String?, platforms: String?): String {
        try {
            AbiSelection.resolve(abis, platforms)
        } catch (e: IllegalArgumentException) {
            return e.message.orEmpty()
        }
        fail("expected rejection")
        return ""
    }

    @Test fun unrestrictedSelectsAllThree() {
        for (blank in listOf(null, "", " , ")) {
            val s = AbiSelection.resolve(blank, blank)
            assertEquals(listOf("arm64-v8a", "armeabi-v7a", "x86_64"), s.abis.map { it.abi })
            assertNull(s.flutterPlatformsToApply)
        }
    }

    @Test fun abisOnlyDrivesFlutterPlatform() {
        val s = AbiSelection.resolve("arm64-v8a", null)
        assertEquals(listOf(RustAbi.ARM64), s.abis)
        assertEquals("android-arm64", s.flutterPlatformsToApply)
        assertEquals("android-arm,android-x64", AbiSelection.resolve("x86_64, armeabi-v7a", null).flutterPlatformsToApply)
    }

    @Test fun flutterPlatformOnlyDrivesAbis() {
        val s = AbiSelection.resolve(null, "android-arm,android-x64")
        assertEquals(listOf(RustAbi.ARM_V7, RustAbi.X64), s.abis)
        assertNull(s.flutterPlatformsToApply)
    }

    @Test fun matchingSetsAreAccepted() {
        val s = AbiSelection.resolve("arm64-v8a,armeabi-v7a", "android-arm,android-arm64")
        assertEquals(listOf(RustAbi.ARM64, RustAbi.ARM_V7), s.abis)
    }

    @Test fun abiSetLargerThanFlutterBuildsOnlyPackagedAbis() {
        val s = AbiSelection.resolve("arm64-v8a,armeabi-v7a,x86_64", "android-arm64")
        assertEquals(listOf(RustAbi.ARM64), s.abis)
    }

    @Test fun rejectsUnknownAbi() {
        val msg = rejected("arm64-v8a,x86", null)
        assertTrue(msg, msg.contains("x86") && msg.contains("Supported ABIs"))
    }

    @Test fun rejectsUnknownFlutterPlatform() {
        assertTrue(rejected(null, "android-x86").contains("android-x86"))
    }

    @Test fun rejectsFlutterPlatformNotCoveredByAbis() {
        val msg = rejected("arm64-v8a", "android-arm,android-arm64")
        assertTrue(msg, msg.contains("armeabi-v7a"))
    }
}
