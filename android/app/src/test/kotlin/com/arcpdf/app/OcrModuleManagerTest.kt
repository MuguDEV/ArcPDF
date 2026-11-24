package com.arcpdf.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

private class FakeScheduler : OcrScheduler {
    class Task(val delay: Long, val body: () -> Unit) : Cancellable {
        var cancelled = false
        override fun cancel() { cancelled = true }
    }

    val tasks = mutableListOf<Task>()
    val delays get() = tasks.map { it.delay }

    override fun schedule(delayMs: Long, task: () -> Unit): Cancellable =
        Task(delayMs, task).also { tasks.add(it) }

    /** Runs the oldest pending, non-cancelled task. */
    fun runNext(): Boolean {
        val next = tasks.firstOrNull { !it.cancelled } ?: return false
        tasks.remove(next)
        next.body()
        return true
    }

    fun pending() = tasks.count { !it.cancelled }
}

private class FakeGateway : ModuleInstallGateway {
    var supported = true
    var installed = false
    var availabilityError: Throwable? = null
    var deferredError: Throwable? = null
    var installRequestError: Throwable? = null
    var installCalls = 0
    var deferredCalls = 0
    var unregisterCalls = 0
    var onInstall: (InstallHandleFake) -> Unit = {}
    val handles = mutableListOf<InstallHandleFake>()

    inner class InstallHandleFake(
        val onUpdate: (InstallUpdate) -> Unit,
        val onResult: (Result<Boolean>) -> Unit,
    ) : InstallHandle {
        var active = true
        override fun unregister() {
            if (active) unregisterCalls++
            active = false
        }
    }

    override fun isSupported() = supported

    override fun areModulesAvailable(callback: (Result<Boolean>) -> Unit) {
        val error = availabilityError
        callback(if (error != null) Result.failure(error) else Result.success(installed))
    }

    override fun deferredInstall(callback: (Result<Unit>) -> Unit) {
        deferredCalls++
        val error = deferredError
        callback(if (error != null) Result.failure(error) else Result.success(Unit))
    }

    override fun installModules(
        onUpdate: (InstallUpdate) -> Unit,
        onResult: (Result<Boolean>) -> Unit,
    ): InstallHandle {
        installCalls++
        val handle = InstallHandleFake(onUpdate, onResult)
        handles.add(handle)
        val error = installRequestError
        if (error != null) onResult(Result.failure(error)) else onInstall(handle)
        return handle
    }
}

class OcrModuleManagerTest {
    private val gateway = FakeGateway()
    private val scheduler = FakeScheduler()
    private val states = mutableListOf<OcrModuleSnapshot>()

    private fun manager(g: FakeGateway = gateway, s: FakeScheduler = scheduler) =
        OcrModuleManager(g, s, { states.add(it) })

    private fun stateNames() = states.map { it.state }

    @Test
    fun alreadyInstalledReachesReady() {
        gateway.installed = true
        val m = manager()
        m.checkAvailability()
        assertEquals(listOf(OcrModuleState.READY), stateNames())
        assertEquals(OcrModuleState.READY, m.current.state)
    }

    @Test
    fun missingModuleIsNotInstalled() {
        val m = manager()
        m.checkAvailability()
        assertEquals(OcrModuleState.NOT_INSTALLED, m.current.state)
    }

    @Test
    fun missingPlayServicesIsUnsupportedAndNeverInstalls() {
        gateway.supported = false
        val m = manager()
        m.checkAvailability()
        m.requestUserInstall()
        m.requestDeferredInstall()
        assertEquals(OcrModuleState.UNSUPPORTED, m.current.state)
        assertEquals(0, gateway.installCalls)
        assertEquals(0, gateway.deferredCalls)
    }

    @Test
    fun deferredInstallWaitsThenResumeRecheckReachesReady() {
        val m = manager()
        m.checkAvailability()
        m.requestDeferredInstall()
        assertEquals(OcrModuleState.WAITING, m.current.state)
        m.checkAvailability()
        assertEquals(OcrModuleState.WAITING, m.current.state)
        gateway.installed = true
        m.onResume()
        assertEquals(OcrModuleState.READY, m.current.state)
    }

    @Test
    fun successfulInstallReportsProgressOnlyWhenKnown() {
        val m = manager()
        m.checkAvailability()
        m.requestUserInstall()
        val h = gateway.handles.single()
        h.onUpdate(InstallUpdate(InstallPhase.PENDING))
        assertEquals(OcrModuleState.WAITING, m.current.state)
        h.onUpdate(InstallUpdate(InstallPhase.DOWNLOADING))
        assertEquals(OcrModuleState.DOWNLOADING, m.current.state)
        assertNull(m.current.progress)
        h.onUpdate(InstallUpdate(InstallPhase.DOWNLOADING, 25, 100))
        assertEquals(0.25, m.current.progress!!, 1e-9)
        assertEquals(25L, m.current.bytesDownloaded)
        h.onUpdate(InstallUpdate(InstallPhase.COMPLETED))
        assertEquals(OcrModuleState.READY, m.current.state)
        assertFalse(h.active)
        assertEquals(1, gateway.unregisterCalls)
    }

    @Test
    fun alreadyInstalledResultFromInstallRequestIsReady() {
        gateway.onInstall = { it.onResult(Result.success(true)) }
        val m = manager()
        m.requestUserInstall()
        assertEquals(OcrModuleState.READY, m.current.state)
        assertEquals(1, gateway.unregisterCalls)
    }

    @Test
    fun installFailureRetriesWithBoundedBackoff() {
        val m = manager()
        m.requestUserInstall()
        var failures = 0
        // Every attempt fails: initial + 4 retries, then the manager stops.
        while (true) {
            gateway.handles.last().onUpdate(InstallUpdate(InstallPhase.FAILED, errorCode = 7))
            failures++
            assertEquals(OcrModuleState.FAILED, m.current.state)
            assertEquals("install_failed:7", m.current.errorCode)
            if (!scheduler.runNext()) break
        }
        assertEquals(5, failures)
        assertEquals(5, gateway.installCalls)
        assertEquals(0, scheduler.pending())
        // Manual retry resets the budget.
        m.retry()
        assertEquals(6, gateway.installCalls)
        assertEquals(OcrModuleState.WAITING, m.current.state)
    }

    @Test
    fun retryDelaysAreExponential() {
        val m = manager()
        m.requestUserInstall()
        val seen = mutableListOf<Long>()
        repeat(4) {
            gateway.handles.last().onUpdate(InstallUpdate(InstallPhase.FAILED))
            seen.add(scheduler.tasks.last { !it.cancelled }.delay)
            scheduler.runNext()
        }
        assertEquals(listOf(2000L, 4000L, 8000L, 16000L), seen)
    }

    @Test
    fun interruptedNetworkRecoversOnRetry() {
        val m = manager()
        m.requestUserInstall()
        gateway.handles.last().onUpdate(InstallUpdate(InstallPhase.DOWNLOADING, 10, 100))
        gateway.handles.last().onUpdate(InstallUpdate(InstallPhase.FAILED, errorCode = 17))
        assertEquals(OcrModuleState.FAILED, m.current.state)
        assertTrue(scheduler.runNext())
        gateway.handles.last().onUpdate(InstallUpdate(InstallPhase.DOWNLOADING, 60, 100))
        gateway.handles.last().onUpdate(InstallUpdate(InstallPhase.COMPLETED))
        assertEquals(OcrModuleState.READY, m.current.state)
        assertEquals(0, scheduler.pending())
    }

    @Test
    fun availabilityCheckFailureRetriesAndRecovers() {
        gateway.availabilityError = RuntimeException("offline")
        val m = manager()
        m.checkAvailability()
        assertEquals(OcrModuleState.FAILED, m.current.state)
        gateway.availabilityError = null
        gateway.installed = true
        scheduler.runNext()
        assertEquals(OcrModuleState.READY, m.current.state)
    }

    @Test
    fun deferredFailureIsFailedWithRetry() {
        gateway.deferredError = RuntimeException("no network")
        val m = manager()
        m.requestDeferredInstall()
        assertEquals(OcrModuleState.FAILED, m.current.state)
        assertEquals(1, scheduler.pending())
        gateway.deferredError = null
        scheduler.runNext()
        assertEquals(OcrModuleState.WAITING, m.current.state)
    }

    @Test
    fun duplicateUserInstallRequestsAreDeduplicated() {
        val m = manager()
        m.requestUserInstall()
        m.requestUserInstall()
        m.requestUserInstall()
        assertEquals(1, gateway.installCalls)
    }

    @Test
    fun checkDuringUserInstallDoesNotClobberDownloadState() {
        val m = manager()
        m.requestUserInstall()
        gateway.handles.last().onUpdate(InstallUpdate(InstallPhase.DOWNLOADING, 1, 2))
        m.onResume()
        assertEquals(OcrModuleState.DOWNLOADING, m.current.state)
    }

    @Test
    fun restartRequeriesGatewayTruthInsteadOfStoredState() {
        val first = manager()
        first.checkAvailability()
        first.requestDeferredInstall()
        first.dispose()
        // Module finished while the app was dead.
        gateway.installed = true
        states.clear()
        val second = manager()
        assertEquals(OcrModuleState.CHECKING, second.current.state)
        second.checkAvailability()
        assertEquals(OcrModuleState.READY, second.current.state)
    }

    @Test
    fun restartDuringDownloadReattachesThroughInstallRequest() {
        val second = manager()
        second.checkAvailability()
        assertEquals(OcrModuleState.NOT_INSTALLED, second.current.state)
        second.requestUserInstall()
        gateway.handles.last().onUpdate(InstallUpdate(InstallPhase.DOWNLOADING, 5, 10))
        assertEquals(OcrModuleState.DOWNLOADING, second.current.state)
    }

    @Test
    fun listenerUnregisteredOnTerminalStateAndDispose() {
        val m = manager()
        m.requestUserInstall()
        val h = gateway.handles.single()
        m.dispose()
        assertFalse(h.active)
        assertEquals(1, gateway.unregisterCalls)
        // Late callbacks after dispose are ignored.
        val before = states.size
        h.onUpdate(InstallUpdate(InstallPhase.COMPLETED))
        assertEquals(before, states.size)
    }

    @Test
    fun disposeCancelsPendingRetry() {
        val m = manager()
        m.requestUserInstall()
        gateway.handles.last().onUpdate(InstallUpdate(InstallPhase.FAILED))
        assertEquals(1, scheduler.pending())
        m.dispose()
        assertEquals(0, scheduler.pending())
    }

    @Test
    fun failureDuringSynchronousInstallDoesNotLeakListener() {
        gateway.installRequestError = RuntimeException("boom")
        val m = manager()
        m.requestUserInstall()
        assertEquals(OcrModuleState.FAILED, m.current.state)
        assertEquals(1, gateway.unregisterCalls)
    }

    @Test
    fun stalledUserInstallIsReconciledOnResume() {
        gateway.onInstall = { it.onUpdate(InstallUpdate(InstallPhase.DOWNLOADING, 10, 100)) }
        val m = manager()
        m.requestUserInstall()
        assertEquals(OcrModuleState.DOWNLOADING, m.current.state)
        // The terminal update is lost, but the module is installed.
        gateway.installed = true
        m.onResume()
        assertEquals(OcrModuleState.READY, m.current.state)
        assertEquals(1, gateway.unregisterCalls)
    }

    @Test
    fun resumeDuringUserInstallKeepsTheSnapshotWhenNotInstalled() {
        gateway.onInstall = { it.onUpdate(InstallUpdate(InstallPhase.DOWNLOADING, 10, 100)) }
        val m = manager()
        m.requestUserInstall()
        states.clear()
        m.onResume()
        assertTrue(states.isEmpty())
        assertEquals(OcrModuleState.DOWNLOADING, m.current.state)
        // A failing query during a user install is ignored and schedules nothing.
        gateway.availabilityError = RuntimeException("x")
        m.onResume()
        assertEquals(OcrModuleState.DOWNLOADING, m.current.state)
        assertEquals(0, scheduler.pending())
    }

    @Test
    fun deferredWaitIsMarkedAndUserInstallCanReplaceIt() {
        gateway.onInstall = { it.onUpdate(InstallUpdate(InstallPhase.PENDING)) }
        val m = manager()
        m.requestDeferredInstall()
        assertEquals(OcrModuleState.WAITING, m.current.state)
        assertTrue(m.current.deferred)
        m.requestUserInstall()
        assertEquals(1, gateway.installCalls)
        assertEquals(OcrModuleState.WAITING, m.current.state)
        assertFalse(m.current.deferred)
    }

    @Test
    fun resumeWhileDeferredWaitingDoesNotFlickerThroughChecking() {
        val m = manager()
        m.requestDeferredInstall()
        states.clear()
        m.onResume()
        assertTrue(states.none { it.state == OcrModuleState.CHECKING })
        assertEquals(OcrModuleState.WAITING, m.current.state)
        assertTrue(m.current.deferred)
    }

    @Test
    fun repeatedFailuresKeepASingleRetryTimer() {
        gateway.availabilityError = RuntimeException("offline")
        val m = manager()
        m.checkAvailability()
        assertEquals(1, scheduler.pending())
        m.onResume()
        assertEquals(1, scheduler.pending())
        assertEquals(listOf(2_000L, 4_000L), scheduler.delays)
    }
}
