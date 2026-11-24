package com.arcpdf.build

import java.io.Serializable

/** One Android ABI that the Rust indexer and PDFium are built for. */
data class RustAbi(
    val abi: String,
    val rustTarget: String,
    val clangPrefix: String,
    val pdfiumArch: String,
    val taskName: String,
    val elfMachine: Int,
    val is64Bit: Boolean,
) : Serializable {
    companion object {
        val ARM64 = RustAbi(
            "arm64-v8a", "aarch64-linux-android", "aarch64-linux-android", "arm64",
            "buildRustIndexerArm64", elfMachine = 183, is64Bit = true,
        )
        val ARM_V7 = RustAbi(
            "armeabi-v7a", "armv7-linux-androideabi", "armv7a-linux-androideabi", "arm",
            "buildRustIndexerArmV7", elfMachine = 40, is64Bit = false,
        )
        val X64 = RustAbi(
            "x86_64", "x86_64-linux-android", "x86_64-linux-android", "x64",
            "buildRustIndexerX64", elfMachine = 62, is64Bit = true,
        )

        val all: List<RustAbi> = listOf(ARM64, ARM_V7, X64)
    }
}
