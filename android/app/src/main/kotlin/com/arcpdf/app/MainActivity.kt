package com.arcpdf.app

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.CancellationSignal
import java.util.Timer
import java.util.TimerTask
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        // ContentResolver queries/cursor traversal must not block Android's UI
        // thread. Flutter's serial background queue also bounds native concurrency.
        MethodChannel(
            messenger,
            "com.arcpdf.app/pdf_index",
            io.flutter.plugin.common.StandardMethodCodec.INSTANCE,
            messenger.makeBackgroundTaskQueue(),
        ).setMethodCallHandler { call, result ->
            if (call.method != "listPdfPaths") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            try {
                result.success(indexedPdfPaths())
            } catch (_: SecurityException) {
                result.error("index_unavailable", "Storage access is unavailable", null)
            } catch (_: Exception) {
                // Some OEM providers do not support the Files collection/columns.
                // Dart falls back to the filesystem; do not leak paths in errors.
                result.error("index_unavailable", "PDF index is unavailable", null)
            }
        }
    }

    @Suppress("DEPRECATION") // The library/viewer require readable filesystem paths.
    private fun indexedPdfPaths(): List<String> {
        val manager = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
            Environment.isExternalStorageManager()
        val legacy = Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            (Build.VERSION.SDK_INT <= Build.VERSION_CODES.S_V2 &&
                checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED)
        if (!manager && !legacy) throw SecurityException()

        val data = MediaStore.MediaColumns.DATA
        val name = MediaStore.MediaColumns.DISPLAY_NAME
        val mime = MediaStore.MediaColumns.MIME_TYPE
        var selection = "($mime = ? OR $name LIKE ?)"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            selection += " AND ${MediaStore.MediaColumns.IS_PENDING} = 0"
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            selection += " AND ${MediaStore.MediaColumns.IS_TRASHED} = 0"
        }
        val paths = linkedSetOf<String>()
        // On Android 10+, 'external' is the merged view of mounted shared
        // volumes, not just primary storage. This is NOT all PDFs on the device.
        val cancellation = CancellationSignal()
        val timeout = Timer("pdf-index-timeout", true)
        // Best-effort cancellation for slow/broken OEM providers. Dart also
        // bounds the channel wait, so indexing cannot indefinitely delay a walk.
        timeout.schedule(object : TimerTask() {
            override fun run() {
                try {
                    cancellation.cancel()
                } finally {
                    timeout.cancel()
                }
            }
        }, 2500)
        try {
            contentResolver.query(
                MediaStore.Files.getContentUri("external"),
                arrayOf(data),
                selection,
                arrayOf("application/pdf", "%.pdf"),
                null,
                cancellation,
            )?.use { cursor ->
                val column = cursor.getColumnIndexOrThrow(data)
                while (cursor.moveToNext()) {
                    cancellation.throwIfCanceled()
                    val path = cursor.getString(column)
                    if (!path.isNullOrBlank()) paths.add(path)
                }
            } ?: throw IllegalStateException("No index cursor")
        } finally {
            timeout.cancel()
        }
        // Existence, readability, private-directory exclusions and PDF contents
        // are independently validated in Dart's worker isolate before publishing.
        return paths.toList()
    }
}
