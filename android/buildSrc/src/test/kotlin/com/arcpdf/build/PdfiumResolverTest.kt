package com.arcpdf.build

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class PdfiumResolverTest {
    @get:Rule val tmp = TemporaryFolder()

    private fun repo(revision: String? = "chromium%2F8125", rootUri: (File) -> String = { "../pkgs/pdfium_dart" }): File {
        val root = tmp.newFolder("repo")
        val pkg = File(root, "pkgs/pdfium_dart")
        File(pkg, "lib/src").mkdirs()
        if (revision != null) {
            File(pkg, "lib/src/pdfium_archive_integrity.dart").writeText("const pdfiumRelease = '$revision';\n")
        }
        File(root, ".dart_tool").mkdirs()
        File(root, ".dart_tool/package_config.json").writeText(
            """{"configVersion":2,"packages":[
            {"name":"other","rootUri":"../x","packageUri":"lib/"},
            {"name":"pdfium_dart","rootUri":"${rootUri(pkg)}","packageUri":"lib/"}]}""",
        )
        return root
    }

    private fun cached(root: File, dir: String, arch: String): File =
        File(root, ".dart_tool/hooks_runner/shared/pdfium_dart/build/$dir/android-$arch/libpdfium.so").also {
            it.parentFile.mkdirs()
            it.writeBytes(byteArrayOf(1))
        }

    private fun failure(block: () -> Unit): String {
        try {
            block()
        } catch (e: IllegalStateException) {
            return e.message.orEmpty()
        }
        fail("expected failure")
        return ""
    }

    @Test fun readsRevisionThroughRelativePackageConfig() {
        assertEquals("chromium%2F8125", PdfiumResolver.revision(repo()))
    }

    @Test fun readsRevisionThroughAbsoluteFileUri() {
        val root = repo(rootUri = { it.toURI().toString().trimEnd('/') })
        assertEquals("chromium%2F8125", PdfiumResolver.revision(root))
    }

    @Test fun picksExactRevisionAndArchEvenWhenOtherRevisionsSortHigher() {
        val root = repo()
        val expected = cached(root, "chromium_8125", "arm64")
        cached(root, "chromium_9999", "arm64")
        cached(root, "chromium_7811", "arm64")
        assertEquals(expected, PdfiumResolver.library(root, "arm64"))
    }

    @Test fun doesNotFallBackToAnotherRevision() {
        val root = repo()
        cached(root, "chromium_9999", "arm64")
        val msg = failure { PdfiumResolver.library(root, "arm64") }
        assertTrue(msg, msg.contains("chromium%2F8125") && msg.contains("chromium_8125/android-arm64"))
    }

    @Test fun doesNotUseAnotherArchitecture() {
        val root = repo()
        cached(root, "chromium_8125", "arm64")
        assertTrue(failure { PdfiumResolver.library(root, "x64") }.contains("android-x64"))
    }

    @Test fun failsClearlyWithoutPackageConfig() {
        val root = tmp.newFolder("empty")
        assertTrue(failure { PdfiumResolver.revision(root) }.contains("flutter pub get"))
    }

    @Test fun failsWhenRevisionCannotBeRead() {
        assertTrue(failure { PdfiumResolver.revision(repo(revision = null)) }.contains("Could not read the PDFium release"))
    }
}
