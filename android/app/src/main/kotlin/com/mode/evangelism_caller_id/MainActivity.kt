package com.mode.evangelism_caller_id

import android.Manifest
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.role.RoleManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.mode.evangelism_caller_id/caller_id"
    private val REQUEST_ID_CALL_SCREENING = 1001
    private val REQUEST_ID_NOTIFICATION_PERMISSION = 1002
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        createNotificationChannel()
        requestNotificationPermissionIfNeeded()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isCallScreeningRoleHeld" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        val roleManager = getSystemService(Context.ROLE_SERVICE) as? RoleManager
                        val isHeld = roleManager?.isRoleHeld(RoleManager.ROLE_CALL_SCREENING) ?: false
                        result.success(isHeld)
                    } else {
                        result.success(false)
                    }
                }
                "requestCallScreeningRole" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        val roleManager = getSystemService(Context.ROLE_SERVICE) as? RoleManager
                        if (roleManager != null && !roleManager.isRoleHeld(RoleManager.ROLE_CALL_SCREENING)) {
                            pendingResult = result
                            val intent = roleManager.createRequestRoleIntent(RoleManager.ROLE_CALL_SCREENING)
                            startActivityForResult(intent, REQUEST_ID_CALL_SCREENING)
                        } else {
                            // Role is already held
                            result.success(true)
                        }
                    } else {
                        result.error(
                            "UNSUPPORTED_VERSION",
                            "Call screening requires Android 10 (API 29) or higher",
                            null
                        )
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "evangelism_caller_id",
                "Evangelism Caller ID",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Shows caller identity for known evangelism contacts"
                enableVibration(true)
                setShowBadge(true)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val permission = Manifest.permission.POST_NOTIFICATIONS
            if (checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED) {
                requestPermissions(arrayOf(permission), REQUEST_ID_NOTIFICATION_PERMISSION)
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_ID_CALL_SCREENING) {
            val isSuccess = resultCode == Activity.RESULT_OK
            pendingResult?.success(isSuccess)
            pendingResult = null
        }
    }
}
