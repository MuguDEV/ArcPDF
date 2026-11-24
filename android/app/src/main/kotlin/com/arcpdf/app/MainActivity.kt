package com.arcpdf.app

import android.Manifest
import android.content.pm.PackageManager
import android.content.Intent
import android.os.Build
import android.os.Environment
import android.os.CancellationSignal
import java.util.Timer
import java.util.TimerTask
import android.net.Uri
import android.provider.MediaStore
import android.provider.Settings
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import java.util.Locale
import java.util.UUID
import java.io.File
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val storageAccessRequestCode = 9042
    private var pendingStorageAccessResult: MethodChannel.Result? = null
    private var readerSpeech: TextToSpeech? = null
    private var readerSpeechChannel: MethodChannel? = null
    private var ocrModuleChannel: OcrModuleChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        ReflowOcrChannel.register(this, messenger)
        ocrModuleChannel?.dispose()
        ocrModuleChannel = OcrModuleChannel(this, messenger)
        MethodChannel(messenger, "com.arcpdf.app/file_access")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            Environment.isExternalStorageManager()
                        } else {
                            null
                        }
                    )
                    "request" -> requestAllFilesAccess(result)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(messenger, "com.arcpdf.app/job_service")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        ArcPdfJobService.start(
                            this,
                            call.argument<String>("jobId").orEmpty(),
                            call.argument<String>("title") ?: "ArcPDF operation",
                            call.argument<String>("stage") ?: "Preparing…",
                            call.argument<String>("outputPath"),
                        )
                        result.success(null)
                    }
                    "update" -> {
                        ArcPdfJobService.update(
                            this,
                            call.argument<String>("stage") ?: "Working…",
                            call.argument<Int>("progress"),
                        )
                        result.success(null)
                    }
                    "finish" -> {
                        ArcPdfJobService.finish(this)
                        result.success(null)
                    }
                    "recover" -> result.success(ArcPdfJobService.recover(this))
                    "clearRecovery" -> {
                        ArcPdfJobService.clearRecovery(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        readerSpeechChannel = MethodChannel(messenger, "com.arcpdf.app/reader_speech")
        readerSpeechChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "speak" -> {
                    val text = call.argument<String>("text")?.trim().orEmpty()
                    if (text.isEmpty()) {
                        result.error("empty_text", "No readable text was supplied", null)
                        return@setMethodCallHandler
                    }
                    if (readerSpeech == null) {
                        readerSpeech = TextToSpeech(this) { status ->
                            if (status == TextToSpeech.SUCCESS) {
                                readerSpeech?.language = Locale.getDefault()
                                readerSpeech?.setOnUtteranceProgressListener(readerSpeechListener())
                                readerSpeech?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "arcpdf-reader")
                            }
                        }
                    } else {
                        readerSpeech?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "arcpdf-reader")
                    }
                    result.success(null)
                }
                "stop" -> {
                    readerSpeech?.stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            messenger,
            "com.arcpdf.app/share_import",
            io.flutter.plugin.common.StandardMethodCodec.INSTANCE,
            messenger.makeBackgroundTaskQueue(),
        ).setMethodCallHandler { call, result ->
            if (call.method != "copyContentUri") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val rawUri = call.argument<String>("uri")
            if (rawUri.isNullOrBlank() || !rawUri.startsWith("content://")) {
                result.error("invalid_uri", "Only content URIs are supported", null)
                return@setMethodCallHandler
            }
            try {
                val directory = File(filesDir, "shared_imports").apply { mkdirs() }
                val target = File(directory, "shared_${UUID.randomUUID()}.pdf")
                contentResolver.openInputStream(Uri.parse(rawUri)).use { input ->
                    if (input == null) {
                        result.error("unreadable_uri", "The shared document could not be read", null)
                        return@setMethodCallHandler
                    }
                    target.outputStream().use { output -> input.copyTo(output) }
                }
                result.success(target.absolutePath)
            } catch (_: Exception) {
                result.error("import_failed", "The shared document could not be imported", null)
            }
        }
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

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        ReflowOcrChannel.unregister(flutterEngine.dartExecutor.binaryMessenger)
        ocrModuleChannel?.dispose()
        ocrModuleChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onResume() {
        super.onResume()
        // Module availability is re-queried, never trusted from a stored flag.
        ocrModuleChannel?.onResume()
    }

    private fun requestAllFilesAccess(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            result.success(null)
            return
        }
        if (Environment.isExternalStorageManager()) {
            result.success(true)
            return
        }
        if (pendingStorageAccessResult != null) {
            result.error("request_active", "A file-access request is already open", null)
            return
        }
        pendingStorageAccessResult = result
        val appSettings = Intent(
            Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
            Uri.parse("package:$packageName"),
        )
        try {
            startActivityForResult(appSettings, storageAccessRequestCode)
        } catch (_: Exception) {
            try {
                startActivityForResult(
                    Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION),
                    storageAccessRequestCode,
                )
            } catch (_: Exception) {
                pendingStorageAccessResult = null
                result.error("settings_unavailable", "File-access settings are unavailable", null)
            }
        }
    }

    @Deprecated("Android settings still return through the activity result API")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != storageAccessRequestCode) return
        pendingStorageAccessResult?.success(
            Build.VERSION.SDK_INT < Build.VERSION_CODES.R ||
                Environment.isExternalStorageManager()
        )
        pendingStorageAccessResult = null
    }

    private fun readerSpeechListener() = object : UtteranceProgressListener() {
        override fun onStart(utteranceId: String?) = Unit
        override fun onError(utteranceId: String?) {
            runOnUiThread { readerSpeechChannel?.invokeMethod("completed", null) }
        }
        override fun onDone(utteranceId: String?) {
            runOnUiThread { readerSpeechChannel?.invokeMethod("completed", null) }
        }
    }

    override fun onDestroy() {
        pendingStorageAccessResult?.error(
            "activity_destroyed",
            "The file-access request was interrupted",
            null,
        )
        pendingStorageAccessResult = null
        readerSpeech?.stop()
        readerSpeech?.shutdown()
        readerSpeech = null
        flutterEngine?.let { ReflowOcrChannel.unregister(it.dartExecutor.binaryMessenger) }
        ocrModuleChannel?.dispose()
        ocrModuleChannel = null
        super.onDestroy()
    }

    @Suppress("DEPRECATION") // The library/viewer require readable filesystem paths.
    private fun indexedPdfPaths(): List<String> {
        val manager = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
            Environment.isExternalStorageManager()
        val legacy = Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            (Build.VERSION.SDK_INT <= Build.VERSION_CODES.S_V2 &&
                checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED)
        if (!manager && !legacy) {
            throw SecurityException()
        }

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
