package com.arcpdf.build

import org.gradle.api.DefaultTask
import org.gradle.api.file.ConfigurableFileCollection
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.file.FileSystemOperations
import org.gradle.api.file.RegularFileProperty
import org.gradle.api.provider.MapProperty
import org.gradle.api.provider.ListProperty
import org.gradle.api.provider.Property
import org.gradle.api.tasks.IgnoreEmptyDirectories
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.InputFile
import org.gradle.api.tasks.InputFiles
import org.gradle.api.tasks.Internal
import org.gradle.api.tasks.Optional
import org.gradle.api.tasks.OutputDirectory
import org.gradle.api.tasks.PathSensitive
import org.gradle.api.tasks.PathSensitivity
import org.gradle.api.tasks.TaskAction
import org.gradle.process.ExecOperations
import java.io.File
import javax.inject.Inject

/**
 * Builds libarcpdf_indexer.so for one ABI and stages it together with libpdfium.so
 * in its own output directory: <outputDirectory>/<abi>/.
 *
 * Deliberately not cacheable: the output depends on the host Rust toolchain and the
 * NDK, which are not declared as inputs. Incremental up-to-date checks still apply.
 */
abstract class BuildRustAbiTask @Inject constructor(
    private val execOperations: ExecOperations,
    private val fileSystemOperations: FileSystemOperations,
) : DefaultTask() {

    @get:Input abstract val abi: Property<String>
    @get:Input abstract val rustTarget: Property<String>
    @get:Input abstract val clangPrefix: Property<String>
    @get:Input abstract val minSdk: Property<Int>
    @get:Input abstract val ndkVersion: Property<String>
    @get:Input abstract val cargoExecutable: Property<String>

    /** Features passed to cargo, sorted for a stable input value. */
    @get:Input abstract val cargoFeatures: ListProperty<String>

    /** Compiler flag environment (RUSTFLAGS and friends) that changes the produced binary. */
    @get:Input abstract val compilerFlags: MapProperty<String, String>

    /** Pinned PDFium release; a revision bump invalidates the task even before the file hash. */
    @get:Input abstract val pdfiumRevision: Property<String>

    @get:Input @get:Optional abstract val androidHome: Property<String>

    /** Cargo.toml, Cargo.lock, build.rs, Cargo config files and the crate sources. */
    @get:InputFiles
    @get:PathSensitive(PathSensitivity.RELATIVE)
    @get:IgnoreEmptyDirectories
    abstract val crateInputs: ConfigurableFileCollection

    @get:InputFile
    @get:PathSensitive(PathSensitivity.NAME_ONLY)
    abstract val pdfiumLibrary: RegularFileProperty

    @get:Internal abstract val crateDirectory: DirectoryProperty
    @get:Internal abstract val cargoTargetDirectory: DirectoryProperty

    /** CARGO_BUILD_JOBS budget; does not change the produced binary, so it is not an input. */
    @get:Internal abstract val cargoJobs: Property<Int>

    @get:OutputDirectory abstract val outputDirectory: DirectoryProperty

    @TaskAction
    fun build() {
        val target = rustTarget.get()
        val home = androidHome.orNull
            ?: error("ANDROID_HOME or ANDROID_SDK_ROOT is required to build the Rust indexer")
        val ndkBin = File("$home/ndk/${ndkVersion.get()}/toolchains/llvm/prebuilt/linux-x86_64/bin")
        val llvmAr = ndkBin.resolve("llvm-ar")
        val clang = ndkBin.resolve("${clangPrefix.get()}${minSdk.get()}-clang")
        require(clang.exists()) { "NDK clang not found at ${clang.absolutePath}" }

        val envTriple = target.replace('-', '_')
        val cargoTarget = cargoTargetDirectory.get().asFile
        val crate = crateDirectory.get().asFile
        val features = cargoFeatures.get().sorted()

        val command = mutableListOf(cargoExecutable.get(), "build", "--release", "--locked", "--target", target)
        if (features.isNotEmpty()) command += listOf("--features", features.joinToString(","))

        execOperations.exec {
            workingDir = crate
            commandLine(command)
            environment("CARGO_TARGET_${envTriple.uppercase()}_LINKER", clang.absolutePath)
            environment("CC_$envTriple", clang.absolutePath)
            environment("AR_$envTriple", llvmAr.absolutePath)
            environment("CARGO_TARGET_DIR", cargoTarget.absolutePath)
            environment("CARGO_BUILD_JOBS", cargoJobs.get().toString())
        }

        val indexer = cargoTarget.resolve("$target/release/libarcpdf_indexer.so")
        val pdfium = pdfiumLibrary.get().asFile
        val rustAbi = RustAbi.all.first { it.abi == abi.get() }
        ElfValidator.validate(indexer, rustAbi)
        // PDFium is a third-party prebuilt: a missing 16 KB alignment is a warning, not a build failure.
        ElfValidator.validate(pdfium, rustAbi, enforce16k = false).forEach { logger.warn("warning: $it") }

        // pdfium_dart's native-assets manifest references libpdfium.so, but Flutter does
        // not place that asset in an Android APK. Package it as a normal JNI library so
        // both pdfrx and the Rust PDF backend resolve the same bundled PDFium binary.
        val destination = outputDirectory.get().dir(abi.get())
        fileSystemOperations.sync {
            from(indexer)
            from(pdfium)
            into(destination)
        }
    }
}
