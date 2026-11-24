package com.arcpdf.app

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.common.api.OptionalModuleApi
import com.google.android.gms.common.moduleinstall.InstallStatusListener
import com.google.android.gms.common.moduleinstall.ModuleInstall
import com.google.android.gms.common.moduleinstall.ModuleInstallRequest
import com.google.android.gms.common.moduleinstall.ModuleInstallStatusUpdate
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/*
 * Channel contract: com.arcpdf.app/ocr_module
 *
 * Dart -> native (every method replies with the current snapshot map):
 *   status          current snapshot, no side effects
 *   check           re-query Play services for the real module availability
 *   installDeferred ask Play services to install in the background (may wait for
 *                   idle/Wi-Fi), the state becomes "waiting"
 *   installNow      explicit user-triggered install with status updates
 *   retry           reset the backoff budget and repeat the last action
 *
 * Native -> Dart (invokeMethod on the same channel, main thread):
 *   stateChanged  args: {
 *     state: "checking"|"notInstalled"|"waiting"|"downloading"|"ready"|"failed"|"unsupported",
 *     progress: double 0.0..1.0 or null (null when Play services gives no totals),
 *     errorCode: String? (e.g. "install_failed:<gms code>", "install_canceled",
 *                "availability_check_failed", "deferred_install_failed",
 *                "install_request_failed", "ocr_unsupported_device"),
 *     bytesDownloaded: int? , totalBytes: int?  (null unless totals are known)
 *   }
 * Snapshot maps returned from method calls use the same keys.
 * Readiness is never stored on disk; Dart must treat "ready" as live truth and
 * call "check" on app resume (native also rechecks in MainActivity.onResume).
 */
class PlayModuleInstallGateway(context: Context) : ModuleInstallGateway {
    private val appContext = context.applicationContext
    private var recognizer: TextRecognizer? = null

    private fun api(): OptionalModuleApi =
        recognizer ?: TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
            .also { recognizer = it }

    override fun isSupported(): Boolean = Build.VERSION.SDK_INT >= 23 &&
        GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(appContext) ==
        ConnectionResult.SUCCESS

    override fun areModulesAvailable(callback: (Result<Boolean>) -> Unit) {
        try {
            ModuleInstall.getClient(appContext).areModulesAvailable(api())
                .addOnSuccessListener { callback(Result.success(it.areModulesAvailable())) }
                .addOnFailureListener { callback(Result.failure(it)) }
        } catch (error: Exception) {
            callback(Result.failure(error))
        }
    }

    override fun deferredInstall(callback: (Result<Unit>) -> Unit) {
        try {
            ModuleInstall.getClient(appContext).deferredInstall(api())
                .addOnSuccessListener { callback(Result.success(Unit)) }
                .addOnFailureListener { callback(Result.failure(it)) }
        } catch (error: Exception) {
            callback(Result.failure(error))
        }
    }

    override fun installModules(
        onUpdate: (InstallUpdate) -> Unit,
        onResult: (Result<Boolean>) -> Unit,
    ): InstallHandle {
        val client = ModuleInstall.getClient(appContext)
        val listener = InstallStatusListener { update -> onUpdate(update.toInstallUpdate()) }
        val handle = object : InstallHandle {
            override fun unregister() {
                client.unregisterListener(listener)
            }
        }
        try {
            val request = ModuleInstallRequest.newBuilder()
                .addApi(api())
                .setListener(listener)
                .build()
            client.installModules(request)
                .addOnSuccessListener { onResult(Result.success(it.areModulesAlreadyInstalled())) }
                .addOnFailureListener { onResult(Result.failure(it)) }
        } catch (error: Exception) {
            onResult(Result.failure(error))
        }
        return handle
    }

    fun close() {
        recognizer?.close()
        recognizer = null
    }

    private fun ModuleInstallStatusUpdate.toInstallUpdate(): InstallUpdate {
        val phase = when (installState) {
            ModuleInstallStatusUpdate.InstallState.STATE_PENDING -> InstallPhase.PENDING
            ModuleInstallStatusUpdate.InstallState.STATE_DOWNLOADING -> InstallPhase.DOWNLOADING
            ModuleInstallStatusUpdate.InstallState.STATE_DOWNLOAD_PAUSED -> InstallPhase.PAUSED
            ModuleInstallStatusUpdate.InstallState.STATE_INSTALLING -> InstallPhase.INSTALLING
            ModuleInstallStatusUpdate.InstallState.STATE_COMPLETED -> InstallPhase.COMPLETED
            ModuleInstallStatusUpdate.InstallState.STATE_FAILED -> InstallPhase.FAILED
            ModuleInstallStatusUpdate.InstallState.STATE_CANCELED -> InstallPhase.CANCELED
            else -> InstallPhase.UNKNOWN
        }
        // progressInfo is null unless bytes are known; never invent totals.
        val info = progressInfo
        return InstallUpdate(
            phase,
            info?.bytesDownloaded ?: 0,
            info?.totalBytesToDownload ?: 0,
            errorCode,
        )
    }
}

class MainThreadScheduler : OcrScheduler {
    private val handler = Handler(Looper.getMainLooper())

    override fun schedule(delayMs: Long, task: () -> Unit): Cancellable {
        val runnable = Runnable { task() }
        handler.postDelayed(runnable, delayMs)
        return object : Cancellable {
            override fun cancel() = handler.removeCallbacks(runnable)
        }
    }
}

/** Owns the manager, the gateway and the Flutter channel for one activity/engine. */
class OcrModuleChannel(context: Context, messenger: BinaryMessenger) {
    private val gateway = PlayModuleInstallGateway(context)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, "com.arcpdf.app/ocr_module")
    private var disposed = false
    private val manager = OcrModuleManager(gateway, MainThreadScheduler(), { snapshot ->
        mainHandler.post {
            if (!disposed) channel.invokeMethod("stateChanged", snapshot.toMap())
        }
    })

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> Unit
                "check" -> manager.checkAvailability()
                "installDeferred" -> manager.requestDeferredInstall()
                "installNow" -> manager.requestUserInstall()
                "retry" -> manager.retry()
                else -> {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
            }
            result.success(manager.current.toMap())
        }
        manager.checkAvailability()
    }

    fun onResume() = manager.onResume()

    fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
        manager.dispose()
        gateway.close()
    }
}
