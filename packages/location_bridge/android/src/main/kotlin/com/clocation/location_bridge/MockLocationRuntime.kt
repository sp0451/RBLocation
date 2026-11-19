package com.clocation.location_bridge

import android.Manifest
import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Criteria
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.SystemClock
import com.clocation.location_bridge.generated.*
import java.util.UUID

/** The native main queue owns snapshots, commands, providers and service lifetime together. */
internal class MockLocationRuntime private constructor(private val context: Context) {
    companion object {
        @Volatile private var instance: MockLocationRuntime? = null

        fun get(context: Context): MockLocationRuntime = instance ?: synchronized(this) {
            instance ?: MockLocationRuntime(context.applicationContext).also { instance = it }
        }

        private const val RECOVERY_KEY = "provider_cleanup_unconfirmed"
        private const val SERVICE_TIMEOUT_MILLIS = 8_000L
        private const val OBSERVATION_TIMEOUT_MILLIS = 15_000L
        private val PROVIDERS = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
    }

    private val main = Handler(Looper.getMainLooper())
    private val manager = context.getSystemService(LocationManager::class.java)
    private val preferences = context.getSharedPreferences("clocation_native_session", Context.MODE_PRIVATE)
    private val gate = NativeCommandGate()
    private val runtimeId = UUID.randomUUID().toString()
    private var sequence = 0L
    private var sessionId: String? = null
    private var connection = WireConnection.DISCONNECTED
    private var operation: WireOperation? = null
    private var failure: WireFailure? = null
    private var sample: WireSample? = null
    private var recoveryRequired = preferences.getBoolean(RECOVERY_KEY, false)
    private var service: MockLocationService? = null
    private val providerLease = NativeProviderLease(PROVIDERS,
        add = { provider ->
            @Suppress("DEPRECATION")
            manager.addTestProvider(provider, false, false, false, false, true, true, true,
                Criteria.POWER_LOW, Criteria.ACCURACY_FINE)
        },
        enable = { manager.setTestProviderEnabled(it, true) },
        remove = { manager.removeTestProvider(it) },
    )
    private var pending: PendingSet? = null
    private var activeRequest: WireLocationRequest? = null
    private var eventSink: ((WireSnapshot) -> Unit)? = null
    private var observing = false
    private var observationStartedNanos = 0L
    private var awaitingRecoveryObservation = false

    private data class PendingSet(
        val ticket: NativeCommandGate.Ticket,
        val request: WireLocationRequest,
        val callback: (Result<WireSnapshot>) -> Unit,
    )

    private class RuntimeFailure(val detail: WireFailure) : Exception(detail.message)

    private val serviceTimeout = Runnable {
        if (pending != null) {
            failSet(error("operationTimedOut", "前台定位服务启动超时，请保持应用在前台后重试。", "service"))
        }
    }

    private val observationTimeout = Runnable {
        // Provider removal and a fresh real-world location are separate evidence.
        awaitingRecoveryObservation = false
        if (activeRequest == null) stopObserving()
        publish()
    }

    private val injection = object : Runnable {
        override fun run() {
            val request = activeRequest ?: return
            if (gate.isStopping || service == null) return
            try {
                ensureReady()
                inject(request)
                main.postDelayed(this, 1_000)
            } catch (cause: Exception) {
                gate.beginStop()
                activeRequest = null
                val cleanup = removeProviders()
                failure = cleanup ?: mapError(cause, "inject")
                operation = operation?.copy(state = WireCommandState.FAILED, failure = failure)
                connection = WireConnection.LOST
                recoveryRequired = true
                stopService()
                gate.finishStop()
                publish()
            }
        }
    }

    private val listener = object : LocationListener {
        override fun onLocationChanged(location: Location) {
            // Ignore samples queued before the latest set/clear, including cached mock positions.
            if (location.elapsedRealtimeNanos < observationStartedNanos ||
                !isValidCoordinate(location.latitude, location.longitude) ||
                !location.hasAccuracy() || !location.accuracy.isFinite() || location.accuracy < 0) return
            @Suppress("DEPRECATION")
            val simulated = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                location.isMock
            } else {
                location.isFromMockProvider
            }
            sample = WireSample(
                coordinate = WireCoordinate(location.latitude, location.longitude),
                accuracy = location.accuracy.toDouble(),
                timestampMillis = location.time,
                isSimulated = simulated,
            )
            if (awaitingRecoveryObservation && !simulated && activeRequest == null) {
                awaitingRecoveryObservation = false
                main.removeCallbacks(observationTimeout)
                // Only a new non-mock observation clears the recovery hint.
                if (preferences.edit().putBoolean(RECOVERY_KEY, false).commit()) {
                    recoveryRequired = false
                } else {
                    failure = error("resultUnknown", "已收到非模拟位置，但无法保存恢复记录。", "storage")
                }
            }
            publish()
        }

        override fun onProviderDisabled(provider: String) {
            if (activeRequest != null) {
                main.removeCallbacks(injection)
                main.post(injection)
            }
        }

        override fun onProviderEnabled(provider: String) = Unit

        @Deprecated("Compatibility for Android API 24 through 28")
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit
    }

    fun attach(sink: (WireSnapshot) -> Unit): WireSnapshot {
        assertMainQueue()
        eventSink = sink
        return snapshot()
    }

    fun detach() {
        assertMainQueue()
        eventSink = null
        // A Flutter engine detach is not an instruction to stop an Android session.
    }

    fun snapshot(): WireSnapshot {
        assertMainQueue()
        return WireSnapshot(
            runtimeId = runtimeId,
            generation = gate.generation,
            sequence = sequence,
            connection = connection,
            recoveryRequired = recoveryRequired,
            capabilities = capabilities(),
            sessionId = sessionId,
            operation = operation,
            sample = sample,
            failure = failure,
        )
    }

    fun capabilities(): WireCapabilities {
        assertMainQueue()
        val permission = hasLocationPermission()
        val location = isLocationEnabled()
        val mock = mockAppState()
        val notifications = hasNotificationPermission()
        return WireCapabilities(
            platform = WirePlatform.ANDROID,
            osVersion = "Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})",
            engineAvailable = true,
            supportsPairing = false,
            isPaired = false,
            prerequisites = listOf(
                WirePrerequisite(
                    id = "locationPermission", title = "精确定位权限",
                    detail = if (permission) "已授权；位置样本仅代表本应用的观测。" else "请允许使用应用期间访问精确位置。",
                    state = check(permission), requiredForConnect = true,
                    action = WireSetupTarget.LOCATION_PERMISSION,
                ),
                WirePrerequisite(
                    id = "locationEnabled", title = "系统定位开关",
                    detail = if (location) "系统定位已开启。" else "请开启手机的系统定位服务。",
                    state = check(location), requiredForConnect = true,
                    action = WireSetupTarget.LOCATION_SETTINGS,
                ),
                WirePrerequisite(
                    id = "mockApp", title = "模拟位置信息应用",
                    detail = if (mock == WireCheckState.SATISFIED) "系统已允许 CLocation 注入模拟位置。" else "在开发者选项中，将“选择模拟位置信息应用”设置为 CLocation。",
                    state = mock, requiredForConnect = true,
                    action = WireSetupTarget.DEVELOPER_SETTINGS,
                ),
                WirePrerequisite(
                    id = "notifications", title = "停止操作通知",
                    detail = if (notifications) "运行时会显示带停止按钮的持续通知。" else "请允许通知，确保可以从通知栏停止模拟。",
                    state = check(notifications), requiredForConnect = true,
                    action = WireSetupTarget.NOTIFICATION_PERMISSION,
                ),
            ),
        )
    }

    fun connect(operationId: String): WireSnapshot {
        assertMainQueue()
        if (gate.isStopping || pending != null) return rejected(operationId, WireOperationKind.CONNECT, busy())
        return try {
            ensureReady()
            if (sessionId == null) sessionId = UUID.randomUUID().toString()
            connection = WireConnection.READY
            failure = null
            operation = command(operationId, WireOperationKind.CONNECT, WireCommandState.ACKNOWLEDGED)
            startObserving()
            publish()
            snapshot()
        } catch (cause: Exception) {
            rejected(operationId, WireOperationKind.CONNECT, mapError(cause, "connect"))
        }
    }

    fun setLocation(request: WireLocationRequest, callback: (Result<WireSnapshot>) -> Unit) {
        assertMainQueue()
        if (!isValidCoordinate(request.coordinate.latitude, request.coordinate.longitude) ||
            !request.accuracy.isFinite() || request.accuracy <= 0 || request.accuracy > 10_000) {
            callback(Result.success(rejected(request.operationId, WireOperationKind.SET_LOCATION,
                error("invalidCoordinate", "请输入有效的 WGS84 经纬度和精度。", "coordinate"))))
            return
        }
        if (gate.isStopping) {
            callback(Result.success(rejected(request.operationId, WireOperationKind.SET_LOCATION, busy())))
            return
        }
        if (connection != WireConnection.READY) {
            callback(Result.success(rejected(request.operationId, WireOperationKind.SET_LOCATION,
                error("connectionLost", "请先完成设备准备并连接。", "connect"))))
            return
        }
        try {
            ensureReady()
        } catch (cause: Exception) {
            callback(Result.success(rejected(request.operationId, WireOperationKind.SET_LOCATION, mapError(cause, "set"))))
            return
        }
        cancelPending("已由更新的设置操作替换。")
        val ticket = gate.beginSet(request.operationId) ?: return
        pending = PendingSet(ticket, request, callback)
        operation = command(request.operationId, WireOperationKind.SET_LOCATION, WireCommandState.PENDING, request.coordinate)
        failure = null
        sample = null
        observationStartedNanos = SystemClock.elapsedRealtimeNanos()
        publish()
        if (service != null) {
            applyPending()
        } else {
            main.removeCallbacks(serviceTimeout)
            main.postDelayed(serviceTimeout, SERVICE_TIMEOUT_MILLIS)
            try {
                val intent = Intent(context, MockLocationService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent)
                else context.startService(intent)
            } catch (cause: Exception) {
                failSet(mapError(cause, "service"))
            }
        }
    }

    fun clearLocation(operationId: String, close: Boolean = false): WireSnapshot {
        assertMainQueue()
        if (gate.isStopping) return rejected(operationId, WireOperationKind.CLEAR_LOCATION, busy())
        gate.beginStop()
        cancelPending("设置操作已被停止。")
        main.removeCallbacks(serviceTimeout)
        main.removeCallbacks(injection)
        main.removeCallbacks(observationTimeout)
        activeRequest = null
        sample = null
        observationStartedNanos = SystemClock.elapsedRealtimeNanos()
        val kind = if (close) WireOperationKind.CLOSE_SESSION else WireOperationKind.CLEAR_LOCATION
        operation = command(operationId, kind, WireCommandState.PENDING)
        failure = null
        if (close) connection = WireConnection.CLOSING
        publish()
        // Explicit clear can remove test providers left by an earlier native process.
        val cleanup = removeProviders(recoverPreviousProcess = recoveryRequired)
        if (cleanup == null) {
            operation = command(operationId, kind, WireCommandState.ACKNOWLEDGED)
            awaitingRecoveryObservation = recoveryRequired
            if (awaitingRecoveryObservation) {
                startObserving()
                main.postDelayed(observationTimeout, OBSERVATION_TIMEOUT_MILLIS)
            }
        } else {
            failure = cleanup.copy(operationId = operationId)
            operation = command(operationId, kind, WireCommandState.FAILED, commandFailure = failure)
            recoveryRequired = true
        }
        stopService()
        if (close) {
            connection = WireConnection.DISCONNECTED
            sessionId = null
            if (!awaitingRecoveryObservation) stopObserving()
        }
        gate.finishStop()
        publish()
        return snapshot()
    }

    fun unsupportedPairing(operationId: String): WireSnapshot = rejected(
        operationId, WireOperationKind.PAIRING,
        error("unsupportedPlatform", "Android 使用系统模拟位置授权，无需设备配对。", "pairing", false),
    )

    fun stopFromNotification() {
        clearLocation("notification-${UUID.randomUUID()}", close = true)
    }

    fun onServiceReady(readyService: MockLocationService) {
        assertMainQueue()
        if (service === readyService && activeRequest != null && pending == null) return
        if (pending == null || gate.isStopping) {
            readyService.finish()
            return
        }
        service = readyService
        main.removeCallbacks(serviceTimeout)
        applyPending()
    }

    fun onServiceStartFailed(cause: Exception) {
        assertMainQueue()
        failSet(mapError(cause, "service"))
    }

    fun onServiceDestroyed(destroyedService: MockLocationService) {
        assertMainQueue()
        if (service !== destroyedService) return
        service = null
        main.removeCallbacks(injection)
        main.removeCallbacks(serviceTimeout)
        gate.beginStop()
        cancelPending("定位服务已结束。")
        activeRequest = null
        val cleanup = removeProviders()
        recoveryRequired = true
        connection = WireConnection.LOST
        failure = cleanup ?: error("connectionLost", "系统结束了定位服务，请先检查恢复状态。", "service")
        gate.finishStop()
        publish()
    }

    private fun applyPending() {
        val next = pending ?: return
        if (!gate.isCurrent(next.ticket)) return
        try {
            ensureReady()
            // Persist an uncertainty marker before the first system mutation. No coordinates or IDs.
            if (!preferences.edit().putBoolean(RECOVERY_KEY, true).commit()) {
                throw RuntimeFailure(error("resultUnknown", "无法保存恢复记录，未设置新的模拟位置。", "storage"))
            }
            recoveryRequired = true
            main.removeCallbacks(observationTimeout)
            awaitingRecoveryObservation = false
            providerLease.acquire()
            startObserving()
            inject(next.request)
            // The system call has completed; no send evidence is emitted before a write succeeds.
            operation = command(next.request.operationId, WireOperationKind.SET_LOCATION, WireCommandState.SENT, next.request.coordinate)
            publish()
            // Android LocationManager returned successfully for BOTH provider injections.
            // This is system API acceptance, never a claim about another app's location.
            activeRequest = next.request
            operation = command(next.request.operationId, WireOperationKind.SET_LOCATION, WireCommandState.ACKNOWLEDGED, next.request.coordinate)
            failure = null
            pending = null
            main.removeCallbacks(injection)
            main.postDelayed(injection, 1_000)
            publish()
            next.callback(Result.success(snapshot()))
        } catch (cause: Exception) {
            failSet(mapError(cause, "set"))
        }
    }

    private fun failSet(detail: WireFailure) {
        main.removeCallbacks(serviceTimeout)
        main.removeCallbacks(injection)
        val next = pending
        pending = null
        activeRequest = null
        gate.beginStop()
        // A binder failure can hide a completed add; inspect every known provider after mutation.
        val cleanup = removeProviders(recoverPreviousProcess = recoveryRequired)
        failure = (cleanup ?: detail).copy(operationId = next?.request?.operationId)
        if (next != null) {
            operation = command(next.request.operationId, WireOperationKind.SET_LOCATION, WireCommandState.FAILED,
                next.request.coordinate, failure)
        }
        if (recoveryRequired) awaitingRecoveryObservation = false
        connection = WireConnection.LOST
        stopService()
        gate.finishStop()
        publish()
        next?.callback?.invoke(Result.success(snapshot()))
    }

    private fun inject(request: WireLocationRequest) {
        for (provider in providerLease.providers) {
            manager.setTestProviderLocation(provider, Location(provider).apply {
                latitude = request.coordinate.latitude
                longitude = request.coordinate.longitude
                accuracy = request.accuracy.toFloat()
                altitude = 0.0
                speed = 0f
                bearing = 0f
                time = System.currentTimeMillis()
                elapsedRealtimeNanos = SystemClock.elapsedRealtimeNanos()
            })
        }
    }

    private fun removeProviders(recoverPreviousProcess: Boolean = false): WireFailure? =
        if (providerLease.release(recoverPreviousProcess).isEmpty()) null else
            error("clearFailed", "系统模拟位置清除失败，请重新选择本应用为模拟位置应用后重试。", "clear")

    private fun stopService() {
        val previous = service
        service = null
        previous?.finish()
    }

    private fun cancelPending(message: String) {
        val old = pending ?: return
        pending = null
        operation = command(old.request.operationId, WireOperationKind.SET_LOCATION, WireCommandState.CANCELLED,
            old.request.coordinate, error("operationCancelled", message, "set", true, old.request.operationId))
        publish()
        old.callback(Result.success(snapshot()))
    }

    private fun startObserving() {
        if (observing || !hasLocationPermission()) return
        var registered = false
        for (provider in PROVIDERS) {
            try {
                if (manager.allProviders.contains(provider)) {
                    manager.requestLocationUpdates(provider, 1_000, 0f, listener, Looper.getMainLooper())
                    registered = true
                }
            } catch (cause: Exception) {
                // Observation is independent of injection; expose absence through sample=null.
                failure = mapError(cause, "observe")
            }
        }
        observing = registered
    }

    private fun stopObserving() {
        if (!observing) return
        try {
            manager.removeUpdates(listener)
        } catch (cause: Exception) {
            failure = mapError(cause, "observeCleanup")
        } finally {
            observing = false
        }
    }

    private fun ensureReady() {
        if (!hasLocationPermission()) throw RuntimeFailure(error("permissionDenied", "需要精确定位权限。", "permission"))
        if (!isLocationEnabled()) throw RuntimeFailure(error("locationServicesDisabled", "请先打开系统定位开关。", "locationSettings"))
        when (mockAppState()) {
            WireCheckState.MISSING -> throw RuntimeFailure(error("mockAppNotSelected", "请在开发者选项中选择 CLocation 为模拟位置信息应用。", "mockApp"))
            WireCheckState.UNKNOWN -> throw RuntimeFailure(error("resultUnknown", "无法确认模拟位置授权，请检查开发者选项。", "mockApp"))
            WireCheckState.SATISFIED -> Unit
        }
        if (!hasNotificationPermission()) throw RuntimeFailure(error("permissionDenied", "请开启通知权限，以便从通知栏停止模拟。", "notification"))
    }

    private fun hasLocationPermission(): Boolean =
        context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED

    private fun hasNotificationPermission(): Boolean {
        val manager = context.getSystemService(android.app.NotificationManager::class.java)
        val runtimePermission = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        val channelEnabled = Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            manager.getNotificationChannel(MockLocationService.CHANNEL_ID)?.importance != android.app.NotificationManager.IMPORTANCE_NONE
        return runtimePermission && manager.areNotificationsEnabled() && channelEnabled
    }

    private fun isLocationEnabled(): Boolean = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        manager.isLocationEnabled
    } else {
        manager.isProviderEnabled(LocationManager.GPS_PROVIDER) || manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
    }

    private fun mockAppState(): WireCheckState = try {
        val appOps = context.getSystemService(AppOpsManager::class.java)
        @Suppress("DEPRECATION")
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_MOCK_LOCATION, Process.myUid(), context.packageName)
        } else {
            appOps.checkOpNoThrow(AppOpsManager.OPSTR_MOCK_LOCATION, Process.myUid(), context.packageName)
        }
        check(mode == AppOpsManager.MODE_ALLOWED)
    } catch (cause: Exception) {
        WireCheckState.UNKNOWN
    }

    private fun rejected(id: String, kind: WireOperationKind, detail: WireFailure): WireSnapshot {
        failure = detail.copy(operationId = id)
        operation = command(id, kind, WireCommandState.FAILED, commandFailure = failure)
        publish()
        return snapshot()
    }

    private fun publish() {
        sequence += 1
        eventSink?.invoke(snapshot())
    }

    private fun command(id: String, kind: WireOperationKind, state: WireCommandState,
        coordinate: WireCoordinate? = null, commandFailure: WireFailure? = null): WireOperation = WireOperation(
        id = id, kind = kind, state = state, occurredAtMillis = System.currentTimeMillis(),
        coordinate = coordinate, failure = commandFailure,
    )

    private fun error(code: String, message: String, stage: String, retryable: Boolean = true,
        operationId: String? = null) = WireFailure(code, message, stage, retryable, operationId)

    private fun busy() = error("operationInProgress", "正在停止模拟，请完成后重新设置。", "command")
    private fun check(satisfied: Boolean) = if (satisfied) WireCheckState.SATISFIED else WireCheckState.MISSING

    private fun mapError(cause: Exception, stage: String): WireFailure = when (cause) {
        is RuntimeFailure -> cause.detail
        is SecurityException -> error("permissionDenied", "系统拒绝定位操作，请检查权限与模拟位置授权。", stage)
        is IllegalStateException -> error("developerServiceUnavailable", "无法在当前状态启动定位服务，请返回前台后重试。", stage)
        else -> error("resultUnknown", "系统定位操作结果不明确，请检查恢复状态后重试。", stage)
    }

    private fun assertMainQueue() = check(Looper.myLooper() == Looper.getMainLooper()) { "Native location state must stay on the main queue" }
}
