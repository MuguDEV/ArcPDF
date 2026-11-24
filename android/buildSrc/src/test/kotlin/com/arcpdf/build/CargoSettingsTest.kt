package com.arcpdf.build

import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File

class CargoSettingsTest {
    private val root = File("/repo")

    @Test fun defaultsToPersistentPerTripleDirectory() {
        assertEquals(
            File("/repo/.arc-build/cargo-target/aarch64-linux-android"),
            CargoSettings.targetDirectory(root, null, "aarch64-linux-android"),
        )
        assertEquals(
            File("/repo/.arc-build/cargo-target/x86_64-linux-android"),
            CargoSettings.targetDirectory(root, " ", "x86_64-linux-android"),
        )
    }

    @Test fun overrideReplacesBaseAndKeepsTripleIsolation() {
        assertEquals(
            File("/cache/rust/armv7-linux-androideabi"),
            CargoSettings.targetDirectory(root, "/cache/rust", "armv7-linux-androideabi"),
        )
    }

    @Test fun jobsAreSharedBetweenAbisWithMinimumOne() {
        assertEquals(4, CargoSettings.jobs(12, 3, null))
        assertEquals(12, CargoSettings.jobs(12, 1, null))
        assertEquals(1, CargoSettings.jobs(2, 3, null))
        assertEquals(1, CargoSettings.jobs(0, 0, null))
    }

    @Test fun explicitJobsWinWhenValid() {
        assertEquals(6, CargoSettings.jobs(12, 3, "6"))
        assertEquals(4, CargoSettings.jobs(12, 3, "0"))
        assertEquals(4, CargoSettings.jobs(12, 3, "many"))
    }
}
