package com.arcpdf.build

import groovy.json.JsonSlurper
import java.io.File
import java.net.URI

/**
 * Finds the PDFium binary that the installed pdfium_dart package downloads, without guessing.
 *
 * The expected revision comes from the package itself (found through
 * .dart_tool/package_config.json), and only that revision's directory in the Flutter
 * native-hook cache is accepted. A different revision is never used as a fallback.
 */
object PdfiumResolver {
    private val revisionPattern = Regex("""const\s+pdfiumRelease\s*=\s*'([^']+)'""")

    /** Files of pdfium_dart that declare the pinned release, in lookup order. */
    private val revisionSources = listOf("lib/src/pdfium_archive_integrity.dart", "hook/build.dart")

    fun packageRoot(repoRoot: File): File {
        val config = File(repoRoot, ".dart_tool/package_config.json")
        check(config.isFile) {
            "${config.path} not found. Run `flutter pub get` so pdfium_dart can be located."
        }
        @Suppress("UNCHECKED_CAST")
        val json = JsonSlurper().parse(config) as Map<String, Any?>
        val packages = json["packages"] as? List<*> ?: error("${config.path} has no packages list")
        val entry = packages.filterIsInstance<Map<*, *>>().firstOrNull { it["name"] == "pdfium_dart" }
            ?: error("pdfium_dart is not listed in ${config.path}")
        var rootUri = entry["rootUri"] as? String ?: error("pdfium_dart has no rootUri in ${config.path}")
        if (!rootUri.endsWith("/")) rootUri += "/"
        val resolved = config.toURI().resolve(URI(rootUri))
        check(resolved.scheme == "file") { "pdfium_dart rootUri $rootUri is not a local path" }
        return File(resolved)
    }

    /** The pinned PDFium release, for example `chromium%2F8125`. */
    fun revision(repoRoot: File): String {
        val root = packageRoot(repoRoot)
        for (relative in revisionSources) {
            val source = File(root, relative)
            if (!source.isFile) continue
            revisionPattern.find(source.readText())?.let { return it.groupValues[1] }
        }
        error(
            "Could not read the PDFium release from pdfium_dart at ${root.path} " +
                "(looked in ${revisionSources.joinToString()}).",
        )
    }

    /** Directory name the build hook uses for [revision]. */
    fun cacheDirectoryName(revision: String): String = revision.replace("%2F", "_")

    /**
     * Expected cache path without requiring the file to exist yet.
     *
     * Gradle evaluates task input providers while it builds the execution graph. The
     * Flutter compile task creates this file by running pdfium_dart's native-assets
     * hook, so checking existence here would fail before that dependency can run.
     */
    fun libraryPath(repoRoot: File, pdfiumArch: String): File {
        val revision = revision(repoRoot)
        val cache = File(repoRoot, ".dart_tool/hooks_runner/shared/pdfium_dart/build")
        return File(cache, "${cacheDirectoryName(revision)}/android-$pdfiumArch/libpdfium.so")
    }

    fun library(repoRoot: File, pdfiumArch: String): File {
        val revision = revision(repoRoot)
        val library = libraryPath(repoRoot, pdfiumArch)
        check(library.isFile) {
            "PDFium $revision for android-$pdfiumArch was not found at ${library.path}. " +
                "The pdfium_dart build hook downloads it during the Flutter native-assets step " +
                "(flutter pub get, then flutter build). Other revisions in the cache are not used."
        }
        return library
    }
}
