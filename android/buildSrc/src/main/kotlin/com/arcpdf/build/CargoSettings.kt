package com.arcpdf.build

import java.io.File

/** Cargo target directory and parallelism decisions, kept free of Gradle types for testing. */
object CargoSettings {
    const val TARGET_DIR_VARIABLE = "ARCPDF_RUST_TARGET_DIR"
    const val JOBS_VARIABLE = "ARCPDF_CARGO_JOBS"

    /**
     * Persistent per-triple Cargo target directory. Each ABI gets its own directory so
     * independent tasks never contend for Cargo's build lock and keep their incremental state.
     * ARCPDF_RUST_TARGET_DIR replaces the default <repo>/.arc-build/cargo-target base.
     */
    fun targetDirectory(repoRoot: File, override: String?, rustTarget: String): File {
        val base = override?.takeIf { it.isNotBlank() }?.let { File(it) }
            ?: File(repoRoot, ".arc-build/cargo-target")
        return File(base, rustTarget)
    }

    /**
     * CARGO_BUILD_JOBS for one build. An explicit ARCPDF_CARGO_JOBS or CARGO_BUILD_JOBS wins;
     * otherwise the CPUs are shared evenly between the selected ABIs, at least one each.
     */
    fun jobs(cpus: Int, selectedAbis: Int, explicit: String?): Int {
        val requested = explicit?.trim()?.toIntOrNull()
        if (requested != null && requested > 0) return requested
        return maxOf(1, cpus / maxOf(1, selectedAbis))
    }
}
