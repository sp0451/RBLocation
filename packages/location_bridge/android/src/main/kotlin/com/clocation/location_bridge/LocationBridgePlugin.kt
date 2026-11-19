package com.clocation.location_bridge

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import com.clocation.location_bridge.generated.*
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry.RequestPermissionsResultListener
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlin.coroutines.suspendCoroutine

/** Pigeon transport and Android permission UI; the runtime owns all location state. */
class LocationBridgePlugin : FlutterPlugin, ActivityAware, NativeLocationApi, RequestPermissionsResultListener {
    companion object {
        private const val PERMISSION_REQUEST = 24602
    }

    private lateinit var runtime: MockLocationRuntime
    private lateinit var events: NativeLocationEvents
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var permissionCallback: ((Result<Unit>) -> Unit)? = null
    private var eventScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        runtime = MockLocationRuntime.get(binding.applicationContext)
        eventScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        events = NativeLocationEvents(binding.binaryMessenger)
        NativeLocationApi.setUp(binding.binaryMessenger, this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        runtime.detach()
        eventScope.cancel()
        NativeLocationApi.setUp(binding.binaryMessenger, null)
        failPendingPermission("应用窗口已关闭，请重新打开后授权。")
    }

    override suspend fun attach(): WireSnapshot = runtime.attach { snapshot ->
        eventScope.launch {
            // An absent Flutter receiver must not turn a running native session into a failure.
            runCatching { events.onSnapshot(snapshot) }
        }
    }

    override suspend fun getCapabilities(): WireCapabilities = runtime.capabilities()
    override suspend fun getSnapshot(): WireSnapshot = runtime.snapshot()
    override suspend fun connect(operationId: String): WireSnapshot = runtime.connect(operationId)
    override suspend fun setLocation(request: WireLocationRequest): WireSnapshot = suspendCoroutine { continuation ->
        runtime.setLocation(request) { continuation.resumeWith(it) }
    }
    override suspend fun clearLocation(operationId: String): WireSnapshot = runtime.clearLocation(operationId)
    override suspend fun closeSession(operationId: String): WireSnapshot = runtime.clearLocation(operationId, close = true)
    override suspend fun startPairing(operationId: String): WireSnapshot = runtime.unsupportedPairing(operationId)
    override suspend fun respondToPairing(response: WirePairingResponse) {
        throw FlutterError("unsupportedPlatform", "Android 无需设备配对。", "pairing")
    }
    override suspend fun cancelPairing() = Unit
    override suspend fun detach() = runtime.detach()
    override suspend fun openSetup(target: WireSetupTarget) = suspendCoroutine { continuation ->
        openSetupInternal(target) { continuation.resumeWith(it) }
    }

    private fun openSetupInternal(target: WireSetupTarget, callback: (Result<Unit>) -> Unit) {
        val foreground = activity
        if (foreground == null) {
            callback(Result.failure(FlutterError("activityUnavailable", "请返回应用前台后打开系统设置。", "setup")))
            return
        }
        if (permissionCallback != null) {
            callback(Result.failure(FlutterError("operationInProgress", "请先完成当前权限请求。", "setup")))
            return
        }
        try {
            when (target) {
                WireSetupTarget.LOCATION_PERMISSION -> requestPermissions(foreground,
                    arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION), callback)
                WireSetupTarget.NOTIFICATION_PERMISSION -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                        foreground.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        requestPermissions(foreground, arrayOf(Manifest.permission.POST_NOTIFICATIONS), callback)
                    } else {
                        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, foreground.packageName)
                        } else {
                            appSettings(foreground)
                        }
                        foreground.startActivity(intent)
                        callback(Result.success(Unit))
                    }
                }
                WireSetupTarget.EXTERNAL_TUNNEL -> callback(Result.failure(
                    FlutterError("unsupportedPlatform", "Android 的系统模拟位置无需外部隧道。", "setup")))
                else -> {
                    val intent = when (target) {
                        WireSetupTarget.DEVELOPER_SETTINGS -> Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS)
                        WireSetupTarget.LOCATION_SETTINGS -> Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
                        else -> appSettings(foreground)
                    }
                    if (intent.resolveActivity(foreground.packageManager) == null) {
                        foreground.startActivity(appSettings(foreground))
                    } else foreground.startActivity(intent)
                    callback(Result.success(Unit))
                }
            }
        } catch (cause: Exception) {
            permissionCallback = null
            callback(Result.failure(FlutterError("setupUnavailable", "无法打开系统设置，请从手机设置中完成授权。", "setup")))
        }
    }

    private fun requestPermissions(foreground: Activity, permissions: Array<String>, callback: (Result<Unit>) -> Unit) {
        permissionCallback = callback
        foreground.requestPermissions(permissions, PERMISSION_REQUEST)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        val callback = permissionCallback
        permissionCallback = null
        if (grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }) {
            callback?.invoke(Result.success(Unit))
        } else {
            callback?.invoke(Result.failure(FlutterError("permissionDenied", "权限尚未授予，请在系统设置中检查授权。", "permission")))
        }
        return true
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() = releaseActivity()

    override fun onDetachedFromActivity() {
        releaseActivity()
        failPendingPermission("应用窗口已关闭，请返回前台后重新授权。")
    }

    private fun releaseActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }

    private fun failPendingPermission(message: String) {
        val callback = permissionCallback
        permissionCallback = null
        callback?.invoke(Result.failure(FlutterError("operationCancelled", message, "permission")))
    }

    private fun appSettings(foreground: Activity) = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
        Uri.parse("package:${foreground.packageName}"))

}
