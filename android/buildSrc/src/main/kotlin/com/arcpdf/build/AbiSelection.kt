package com.arcpdf.build

import org.gradle.api.Project

/** Resolves which ABIs to build from ARCPDF_ABIS and Flutter's target-platform property. */
object AbiSelection {
    const val FLUTTER_PROPERTY = "target-platform"
    const val ABIS_VARIABLE = "ARCPDF_ABIS"

    val flutterPlatforms: Map<String, RustAbi> = mapOf(
        "android-arm64" to RustAbi.ARM64,
        "android-arm" to RustAbi.ARM_V7,
        "android-x64" to RustAbi.X64,
    )

    data class Selection(
        val abis: List<RustAbi>,
        /** Set when ARCPDF_ABIS was given but Flutter has no target-platform: the value to apply. */
        val flutterPlatformsToApply: String?,
    )

    private fun tokens(value: String?): List<String> =
        value?.split(",")?.map { it.trim() }?.filter { it.isNotEmpty() }.orEmpty()

    fun parseAbis(value: String?): List<RustAbi> {
        val requested = tokens(value)
        val unknown = requested.filter { name -> RustAbi.all.none { it.abi == name } }
        require(unknown.isEmpty()) {
            "Unsupported ABI in $ABIS_VARIABLE: ${unknown.joinToString(", ")}. " +
                "Supported ABIs: ${RustAbi.all.joinToString(", ") { it.abi }}"
        }
        return RustAbi.all.filter { it.abi in requested }
    }

    fun parseFlutterPlatforms(value: String?): List<RustAbi> {
        val requested = tokens(value)
        val unknown = requested.filter { it !in flutterPlatforms }
        require(unknown.isEmpty()) {
            "Unsupported Flutter $FLUTTER_PROPERTY value: ${unknown.joinToString(", ")}. " +
                "Supported platforms: ${flutterPlatforms.keys.joinToString(", ")}"
        }
        return RustAbi.all.filter { abi -> requested.any { flutterPlatforms[it] == abi } }
    }

    fun flutterPlatformsFor(abis: List<RustAbi>): String =
        abis.joinToString(",") { abi -> flutterPlatforms.entries.first { it.value == abi }.key }

    /**
     * @param abisValue raw ARCPDF_ABIS value, or null/blank when unset
     * @param flutterValue raw Flutter target-platform value, or null/blank when unset
     */
    fun resolve(abisValue: String?, flutterValue: String?): Selection {
        val fromAbis = parseAbis(abisValue)
        val fromFlutter = parseFlutterPlatforms(flutterValue)
        return when {
            fromAbis.isEmpty() && fromFlutter.isEmpty() -> Selection(RustAbi.all, null)
            fromFlutter.isEmpty() -> Selection(fromAbis, flutterPlatformsFor(fromAbis))
            fromAbis.isEmpty() -> Selection(fromFlutter, null)
            else -> {
                val missing = fromFlutter.filter { it !in fromAbis }
                require(missing.isEmpty()) {
                    "Flutter $FLUTTER_PROPERTY packages ${missing.joinToString(", ") { it.abi }}, but " +
                        "$ABIS_VARIABLE=${fromAbis.joinToString(",") { it.abi }} does not build it. " +
                        "Make $ABIS_VARIABLE cover the target platforms or unset it."
                }
                // ARCPDF_ABIS may list more than Flutter packages; build only what is packaged.
                Selection(fromFlutter, null)
            }
        }
    }

    private fun value(project: Project, name: String): String? =
        (project.findProperty(name) as String?)?.takeIf { it.isNotBlank() } ?: System.getenv(name)?.takeIf { it.isNotBlank() }

    /** Selection for the given project from its Gradle properties and the environment. */
    fun resolve(project: Project): Selection =
        resolve(value(project, ABIS_VARIABLE), (project.findProperty(FLUTTER_PROPERTY) as String?))

    /**
     * Makes Flutter's target-platform follow ARCPDF_ABIS when only the latter is set, so the
     * engine and Dart AOT libraries are packaged for exactly the ABIs that get native libraries.
     * Call from the root build script, before the Flutter plugin is applied in :app. It only
     * sets a project extra property; Flutter SDK internals are untouched.
     */
    fun syncFlutterTargetPlatform(root: Project) {
        val selection = resolve(root)
        val platforms = selection.flutterPlatformsToApply ?: return
        root.allprojects { extensions.extraProperties.set(FLUTTER_PROPERTY, platforms) }
        root.logger.lifecycle("ARCPDF_ABIS restricts Flutter $FLUTTER_PROPERTY to $platforms")
    }
}
