package com.arcpdf.build

import org.gradle.api.Project
import org.gradle.api.Task
import org.gradle.api.tasks.TaskProvider
import java.io.File

/** Values owned by the Flutter/Android extensions, passed in so tasks capture no extension. */
data class RustIndexerSettings(
    val minSdk: Int,
    val ndkVersion: String,
)

object RustIndexerTasks {
    private val compilerFlagVariables = listOf(
        "RUSTFLAGS", "CARGO_ENCODED_RUSTFLAGS", "CARGO_BUILD_RUSTFLAGS", "RUSTC_WRAPPER", "RUSTC",
    )

    /** Registers one task per ABI plus the aggregate buildRustIndexer task. */
    fun register(
        project: Project,
        abis: List<RustAbi>,
        settings: RustIndexerSettings,
    ): Map<RustAbi, TaskProvider<BuildRustAbiTask>> {
        val repoRoot = project.rootProject.file("..")
        val crateDir = File(repoRoot, "native/arcpdf_indexer")
        val pdfiumBuildDir = File(repoRoot, ".dart_tool/hooks_runner/shared/pdfium_dart/build")
        val targetDirOverride = System.getenv(CargoSettings.TARGET_DIR_VARIABLE)
        val jobs = CargoSettings.jobs(
            cpus = Runtime.getRuntime().availableProcessors(),
            selectedAbis = abis.size,
            explicit = System.getenv(CargoSettings.JOBS_VARIABLE) ?: System.getenv("CARGO_BUILD_JOBS"),
        )
        val androidHome = System.getenv("ANDROID_HOME") ?: System.getenv("ANDROID_SDK_ROOT")
        val flags = compilerFlagVariables.mapNotNull { name -> System.getenv(name)?.let { name to it } }.toMap()
        val features = System.getenv("ARCPDF_CARGO_FEATURES")
            ?.split(",")?.map { it.trim() }?.filter { it.isNotEmpty() }.orEmpty()

        val tasks = abis.associateWith { abi ->
            project.tasks.register(abi.taskName, BuildRustAbiTask::class.java) {
                description = "Builds libarcpdf_indexer.so and stages libpdfium.so for ${abi.abi}"
                this.abi.set(abi.abi)
                rustTarget.set(abi.rustTarget)
                clangPrefix.set(abi.clangPrefix)
                minSdk.set(settings.minSdk)
                ndkVersion.set(settings.ndkVersion)
                cargoExecutable.set(System.getenv("CARGO") ?: "cargo")
                cargoFeatures.set(features)
                compilerFlags.set(flags)
                if (androidHome != null) this.androidHome.set(androidHome)
                crateDirectory.set(crateDir)
                cargoTargetDirectory.set(CargoSettings.targetDirectory(repoRoot, targetDirOverride, abi.rustTarget))
                cargoJobs.set(jobs)
                crateInputs.from(
                    project.fileTree(File(crateDir, "src")),
                    File(crateDir, "Cargo.toml"),
                    File(crateDir, "Cargo.lock"),
                    File(crateDir, "build.rs"),
                    File(crateDir, ".cargo/config.toml"),
                    File(crateDir, ".cargo/config"),
                    File(repoRoot, ".cargo/config.toml"),
                    File(repoRoot, ".cargo/config"),
                )
                pdfiumLibrary.set(
                    pdfiumBuildDir.listFiles()
                        ?.filter { it.isDirectory }
                        ?.sortedByDescending { it.name }
                        ?.map { File(it, "android-${abi.pdfiumArch}/libpdfium.so") }
                        ?.firstOrNull { it.exists() }
                        ?: File(pdfiumBuildDir, "android-${abi.pdfiumArch}/libpdfium.so"),
                )
                outputDirectory.set(project.layout.buildDirectory.dir("generated/rustJni/${abi.abi}"))
            }
        }
        project.tasks.register("buildRustIndexer") {
            group = "build"
            description = "Builds the Rust indexer for every selected ABI"
            dependsOn(tasks.values)
        }
        return tasks
    }

    fun aggregate(project: Project): TaskProvider<Task> = project.tasks.named("buildRustIndexer")
}
