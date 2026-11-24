package com.arcpdf.app

/*
 * OCR module state machine. Pure Kotlin (no Android types) so it runs in JVM unit
 * tests. The Google Play services calls live behind ModuleInstallGateway
 * (see PlayModuleInstallGateway in OcrModuleChannel.kt).
 *
 * Readiness is never persisted. READY only comes from a live areModulesAvailable
 * answer or a COMPLETED install update, and is re-queried on resume and restart.
 * Progress is only reported when Play services supplies totalBytesToDownload > 0,
 * otherwise it is null.
 *
 * Retry policy: after a failed install or availability check the manager retries
 * automatically after 2s, 4s, 8s and 16s (at most 4 retries, 5 attempts in total).
 * retry() resets the budget.
 */

enum class OcrModuleState(val wire: String) {
    CHECKING("checking"),
    NOT_INSTALLED("notInstalled"),
    WAITING("waiting"),
    DOWNLOADING("downloading"),
    READY("ready"),
    FAILED("failed"),
    UNSUPPORTED("unsupported"),
}

data class OcrModuleSnapshot(
    val state: OcrModuleState,
    /** 0.0..1.0, or null when Play services reports no byte totals. */
    val progress: Double? = null,
    val bytesDownloaded: Long? = null,
    val totalBytes: Long? = null,
    val errorCode: String? = null,
    /** WAITING because of a deferred (Play-scheduled) request, not a user install. */
    val deferred: Boolean = false,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "state" to state.wire,
        "progress" to progress,
        "errorCode" to errorCode,
        "bytesDownloaded" to bytesDownloaded,
        "totalBytes" to totalBytes,
        "deferred" to deferred,
    )
}

enum class InstallPhase { UNKNOWN, PENDING, DOWNLOADING, PAUSED, INSTALLING, COMPLETED, FAILED, CANCELED }

data class InstallUpdate(
    val phase: InstallPhase,
    val bytesDownloaded: Long = 0,
    val totalBytes: Long = 0,
    val errorCode: Int = 0,
)

interface InstallHandle {
    fun unregister()
}

interface ModuleInstallGateway {
    /** Device and Google Play services can host the unbundled module. */
    fun isSupported(): Boolean
    fun areModulesAvailable(callback: (Result<Boolean>) -> Unit)
    fun deferredInstall(callback: (Result<Unit>) -> Unit)

    /**
     * Starts an explicit install. [onResult] reports whether the module was
     * already installed. [onUpdate] reports status until a terminal phase.
     */
    fun installModules(
        onUpdate: (InstallUpdate) -> Unit,
        onResult: (Result<Boolean>) -> Unit,
    ): InstallHandle
}

interface Cancellable {
    fun cancel()
}

interface OcrScheduler {
    fun schedule(delayMs: Long, task: () -> Unit): Cancellable
}

class OcrModuleManager(
    private val gateway: ModuleInstallGateway,
    private val scheduler: OcrScheduler,
    private val onChanged: (OcrModuleSnapshot) -> Unit,
    private val retryDelaysMs: List<Long> = DEFAULT_RETRY_DELAYS_MS,
) {
    private enum class Action { CHECK, DEFERRED, USER }

    private val lock = Any()
    private var snapshot = OcrModuleSnapshot(OcrModuleState.CHECKING)
    private var disposed = false
    private var checkEpoch = 0
    private var installEpoch = 0
    private var inFlight: Action? = null
    private var lastAction = Action.CHECK
    private var handle: InstallHandle? = null
    private var retryTask: Cancellable? = null
    private var retryCount = 0
    private var deferredRequested = false

    val current: OcrModuleSnapshot get() = synchronized(lock) { snapshot }

    fun checkAvailability() {
        synchronized(lock) {
        if (disposed) return
        if (!gateway.isSupported()) {
            markUnsupported()
            return
        }
        // An explicit install normally reports the truth through its listener.
        // The listener can go silent (for example when Play services restarts),
        // so a check quietly reconciles: it only acts on a positive answer and
        // never changes the snapshot or the retry state otherwise.
        val quiet = inFlight == Action.USER
        if (!quiet) lastAction = Action.CHECK
        val epoch = ++checkEpoch
        val visible = snapshot.state == OcrModuleState.READY ||
            snapshot.state == OcrModuleState.WAITING ||
            snapshot.state == OcrModuleState.DOWNLOADING
        if (!quiet && !visible) set(OcrModuleSnapshot(OcrModuleState.CHECKING))
        gateway.areModulesAvailable { result ->
            synchronized(lock) {
                if (disposed || epoch != checkEpoch) return@synchronized
                result.fold(
                    onSuccess = { available ->
                        if (available) {
                            markReady()
                        } else if (inFlight == null) {
                            set(
                                if (deferredRequested) {
                                    OcrModuleSnapshot(OcrModuleState.WAITING, deferred = true)
                                } else {
                                    OcrModuleSnapshot(OcrModuleState.NOT_INSTALLED)
                                },
                            )
                        }
                    },
                    onFailure = { if (!quiet) fail("availability_check_failed", Action.CHECK) },
                )
            }
        }
    } }

    fun requestDeferredInstall() {
        synchronized(lock) {
        if (disposed || inFlight != null) return
        if (!gateway.isSupported()) return markUnsupported()
        if (snapshot.state == OcrModuleState.READY) return
        startInstall(Action.DEFERRED)
    } }

    fun requestUserInstall() {
        synchronized(lock) {
        if (disposed || inFlight == Action.USER) return
        if (!gateway.isSupported()) return markUnsupported()
        if (snapshot.state == OcrModuleState.READY) return
        startInstall(Action.USER)
    } }

    /** Manual retry: resets the backoff budget and repeats the last action. */
    fun retry() {
        synchronized(lock) {
        if (disposed || inFlight != null) return
        cancelRetry()
        retryCount = 0
        run(lastAction)
    } }

    fun onResume() = checkAvailability()

    fun dispose() {
        synchronized(lock) {
        disposed = true
        checkEpoch++
        installEpoch++
        cancelRetry()
        releaseHandle()
        inFlight = null
    } }

    private fun run(action: Action) = when (action) {
        Action.CHECK -> checkAvailability()
        Action.DEFERRED, Action.USER -> startInstall(action)
    }

    private fun startInstall(action: Action) {
        cancelRetry()
        releaseHandle()
        lastAction = action
        inFlight = action
        val epoch = ++installEpoch
        if (action == Action.USER) set(OcrModuleSnapshot(OcrModuleState.WAITING))
        if (action == Action.DEFERRED) {
            gateway.deferredInstall { result ->
                synchronized(lock) {
                    if (disposed || epoch != installEpoch) return@synchronized
                    inFlight = null
                    result.fold(
                        onSuccess = {
                            deferredRequested = true
                            retryCount = 0
                            set(OcrModuleSnapshot(OcrModuleState.WAITING, deferred = true))
                        },
                        onFailure = { fail("deferred_install_failed", Action.DEFERRED) },
                    )
                }
            }
            return
        }
        val registered = gateway.installModules(
            onUpdate = { update ->
                synchronized(lock) {
                    if (disposed || epoch != installEpoch || inFlight != Action.USER) return@synchronized
                    handleUpdate(update)
                }
            },
            onResult = { result ->
                synchronized(lock) {
                    if (disposed || epoch != installEpoch || inFlight != Action.USER) return@synchronized
                    result.fold(
                        onSuccess = { alreadyInstalled -> if (alreadyInstalled) markReady() },
                        onFailure = { fail("install_request_failed", Action.USER) },
                    )
                }
            },
        )
        // A synchronous terminal callback may already have finished this install.
        if (epoch == installEpoch && inFlight == Action.USER) handle = registered
        else registered.unregister()
    }

    private fun handleUpdate(update: InstallUpdate) {
        when (update.phase) {
            InstallPhase.PENDING, InstallPhase.PAUSED ->
                set(OcrModuleSnapshot(OcrModuleState.WAITING))
            InstallPhase.DOWNLOADING, InstallPhase.INSTALLING -> {
                val known = update.totalBytes > 0
                set(
                    OcrModuleSnapshot(
                        OcrModuleState.DOWNLOADING,
                        progress = if (known) {
                            (update.bytesDownloaded.toDouble() / update.totalBytes).coerceIn(0.0, 1.0)
                        } else {
                            null
                        },
                        bytesDownloaded = if (known) update.bytesDownloaded else null,
                        totalBytes = if (known) update.totalBytes else null,
                    ),
                )
            }
            InstallPhase.COMPLETED -> markReady()
            InstallPhase.FAILED -> fail("install_failed:${update.errorCode}", Action.USER)
            InstallPhase.CANCELED -> fail("install_canceled", Action.USER)
            InstallPhase.UNKNOWN -> Unit
        }
    }

    private fun markReady() {
        cancelRetry()
        releaseHandle()
        inFlight = null
        retryCount = 0
        deferredRequested = false
        set(OcrModuleSnapshot(OcrModuleState.READY))
    }

    private fun markUnsupported() {
        cancelRetry()
        releaseHandle()
        inFlight = null
        set(OcrModuleSnapshot(OcrModuleState.UNSUPPORTED, errorCode = "ocr_unsupported_device"))
    }

    private fun fail(code: String, action: Action) {
        releaseHandle()
        inFlight = null
        lastAction = action
        cancelRetry()
        set(OcrModuleSnapshot(OcrModuleState.FAILED, errorCode = code))
        if (retryCount >= retryDelaysMs.size) return
        val delay = retryDelaysMs[retryCount++]
        retryTask = scheduler.schedule(delay) {
            synchronized(lock) {
                retryTask = null
                if (!disposed && inFlight == null) run(action)
            }
        }
    }

    private fun cancelRetry() {
        retryTask?.cancel()
        retryTask = null
    }

    private fun releaseHandle() {
        handle?.unregister()
        handle = null
    }

    private fun set(next: OcrModuleSnapshot) {
        if (next == snapshot) return
        snapshot = next
        onChanged(next)
    }

    companion object {
        val DEFAULT_RETRY_DELAYS_MS = listOf(2_000L, 4_000L, 8_000L, 16_000L)
    }
}
