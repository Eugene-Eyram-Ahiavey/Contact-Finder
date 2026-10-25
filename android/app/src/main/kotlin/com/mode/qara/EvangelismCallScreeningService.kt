package com.mode.qara

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.telecom.Call
import android.telecom.CallScreeningService
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.annotation.RequiresApi

/**
 * EvangelismCallScreeningService
 *
 * Intercepts incoming phone calls at the OS level (Android 10+ / API 29+).
 *
 * Core Workflow:
 * 1. Android OS fires `onScreenCall(callDetails)`.
 * 2. Normalizes the incoming phone number (e.g. Ghana 024... -> +23324...).
 * 3. Queries the local SQLite database (`evangelism_caller_id.db`) directly in read-only mode (<10ms).
 * 4. If MATCH found:
 *    - Displays a Truecaller-style floating overlay card directly on top of the ringing screen
 *      (via `SYSTEM_ALERT_WINDOW` / `WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY`).
 *    - Also posts a High-Priority notification in the notification shade as a persistent log.
 * 5. If NO match:
 *    - Remains completely silent (zero false identifications).
 * 6. Always allows the cellular call to ring through without interference.
 */
@RequiresApi(Build.VERSION_CODES.Q)
class EvangelismCallScreeningService : CallScreeningService() {

    companion object {
        private const val TAG = "CallScreeningService"
        const val CHANNEL_ID = "qara_caller_id"
        const val CHANNEL_NAME = "Qara Caller ID"

        // Static reference to track active overlay across instances
        private var activeOverlayView: View? = null
    }

    data class ContactMatch(
        val id: String,
        val name: String,
        val rawPhone: String,
        val location: String?,
        val notes: String?,
        val lastOutcome: String?,
        val lastDate: String?
    )

    override fun onScreenCall(callDetails: Call.Details) {
        val isIncoming = callDetails.callDirection == Call.Details.DIRECTION_INCOMING
        val handleUri = callDetails.handle
        val rawPhoneNumber = handleUri?.schemeSpecificPart ?: ""

        Log.d(TAG, "Incoming call received: isIncoming=$isIncoming, number=$rawPhoneNumber")

        if (isIncoming && rawPhoneNumber.isNotBlank()) {
            val normalized = normalizePhoneNumber(rawPhoneNumber)
            val digitsOnly = rawPhoneNumber.replace(Regex("[^0-9+]"), "")

            Log.d(TAG, "Normalized lookup candidates: normalized='$normalized', raw='$digitsOnly'")

            val match = lookupContact(normalized, digitsOnly)
            if (match != null) {
                Log.d(TAG, "Matched contact: '${match.name}', location='${match.location}'")
                // 1. Post notification for notification shade log
                showCallerNotification(match)
                // 2. Display the Truecaller-style floating overlay directly on the ringing screen
                showFloatingOverlay(match)
            } else {
                Log.d(TAG, "No matching evangelism contact found for: $rawPhoneNumber")
            }
        }

        // Always allow the cellular call to ring through to the user's phone normally
        val response = CallResponse.Builder()
            .setDisallowCall(false)
            .setRejectCall(false)
            .setSkipCallLog(false)
            .setSkipNotification(false)
            .build()

        respondToCall(callDetails, response)
    }

    /**
     * Displays a Truecaller-style floating card directly on top of the phone screen
     * while the incoming call is ringing.
     */
    private fun showFloatingOverlay(match: ContactMatch) {
        if (!Settings.canDrawOverlays(applicationContext)) {
            Log.w(TAG, "SYSTEM_ALERT_WINDOW permission not granted; cannot display floating card")
            return
        }

        Handler(Looper.getMainLooper()).post {
            try {
                val windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager

                // Remove any previous active overlay
                activeOverlayView?.let {
                    try { windowManager.removeView(it) } catch (_: Exception) {}
                    activeOverlayView = null
                }

                val layoutParams = WindowManager.LayoutParams(
                    WindowManager.LayoutParams.MATCH_PARENT,
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                            WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
                    PixelFormat.TRANSLUCENT
                ).apply {
                    gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                    y = dp(230) // Positioned safely below the native call pop-up
                }

                // Card container styling
                val cardLayout = LinearLayout(applicationContext).apply {
                    orientation = LinearLayout.VERTICAL
                    setPadding(dp(18), dp(12), dp(18), dp(16))
                    val bg = GradientDrawable().apply {
                        setColor(Color.parseColor("#1A237E")) // Deep Royal Indigo
                        cornerRadius = dp(16).toFloat()
                        setStroke(dp(2), Color.parseColor("#3F51B5")) // Electric Indigo border
                    }
                    background = bg
                    elevation = dp(14).toFloat()
                }

                // Drag handle pill at the top
                val dragHandle = View(applicationContext).apply {
                    val handleBg = GradientDrawable().apply {
                        setColor(Color.parseColor("#5C6BC0"))
                        cornerRadius = dp(2).toFloat()
                    }
                    background = handleBg
                }
                val handleParams = LinearLayout.LayoutParams(dp(40), dp(4)).apply {
                    gravity = Gravity.CENTER_HORIZONTAL
                    bottomMargin = dp(8)
                }
                cardLayout.addView(dragHandle, handleParams)

                // Outer root with screen margin
                val rootLayout = FrameLayout(applicationContext).apply {
                    setPadding(dp(14), dp(8), dp(14), dp(8))
                    addView(cardLayout, FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.WRAP_CONTENT
                    ))
                }

                // Touch and drag listener so user can slide card anywhere on screen,
                // or swipe horizontally to dismiss it instantly
                var initialY = 0
                var initialTouchY = 0f
                var initialTouchX = 0f
                var isDragging = false

                cardLayout.setOnTouchListener { _, event ->
                    when (event.action) {
                        MotionEvent.ACTION_DOWN -> {
                            initialY = layoutParams.y
                            initialTouchY = event.rawY
                            initialTouchX = event.rawX
                            isDragging = false
                            true
                        }
                        MotionEvent.ACTION_MOVE -> {
                            val deltaY = (event.rawY - initialTouchY).toInt()
                            val deltaX = Math.abs(event.rawX - initialTouchX)
                            if (Math.abs(deltaY) > dp(4) || deltaX > dp(4) || isDragging) {
                                isDragging = true
                                layoutParams.y = (initialY + deltaY).coerceAtLeast(dp(20))
                                try {
                                    windowManager.updateViewLayout(rootLayout, layoutParams)
                                } catch (_: Exception) {}
                            }
                            true
                        }
                        MotionEvent.ACTION_UP -> {
                            val deltaX = Math.abs(event.rawX - initialTouchX)
                            if (deltaX > dp(90)) {
                                // Horizontal swipe-to-dismiss gesture
                                try {
                                    windowManager.removeView(rootLayout)
                                    activeOverlayView = null
                                } catch (_: Exception) {}
                            } else if (!isDragging) {
                                val clickIntent = Intent(applicationContext, MainActivity::class.java).apply {
                                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                                    putExtra("contact_id", match.id)
                                    putExtra("phone_number", match.rawPhone)
                                }
                                applicationContext.startActivity(clickIntent)
                            }
                            true
                        }
                        else -> false
                    }
                }

                // Header Row (Badge + Dismiss ✕ button)
                val headerRow = LinearLayout(applicationContext).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                }

                val badge = TextView(applicationContext).apply {
                    text = "✝ QARA • OUTREACH CONTACT"
                    textSize = 11f
                    setTextColor(Color.parseColor("#90CAF9"))
                    typeface = Typeface.DEFAULT_BOLD
                }
                val badgeParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                headerRow.addView(badge, badgeParams)

                val closeBtn = TextView(applicationContext).apply {
                    text = "✕"
                    textSize = 20f
                    setTextColor(Color.WHITE)
                    setPadding(dp(12), dp(2), dp(6), dp(2))
                    setOnClickListener {
                        try {
                            windowManager.removeView(rootLayout)
                            activeOverlayView = null
                        } catch (_: Exception) {}
                    }
                }
                headerRow.addView(closeBtn)
                cardLayout.addView(headerRow)

                // Contact Name
                val nameView = TextView(applicationContext).apply {
                    text = match.name
                    textSize = 22f
                    setTextColor(Color.WHITE)
                    typeface = Typeface.DEFAULT_BOLD
                    setPadding(0, dp(4), 0, dp(2))
                }
                cardLayout.addView(nameView)

                // Location / Area
                if (!match.location.isNullOrBlank()) {
                    val locationView = TextView(applicationContext).apply {
                        text = "📍 Location: ${match.location}"
                        textSize = 14f
                        setTextColor(Color.parseColor("#E0E0E0"))
                        setPadding(0, 0, 0, dp(2))
                    }
                    cardLayout.addView(locationView)
                }

                // Outreach Notes (if present)
                if (!match.notes.isNullOrBlank()) {
                    val notesView = TextView(applicationContext).apply {
                        text = "📝 Notes: ${match.notes}"
                        textSize = 13f
                        setTextColor(Color.parseColor("#B0BEC5"))
                        setPadding(0, 0, 0, dp(2))
                    }
                    cardLayout.addView(notesView)
                }

                // Last interaction outcome (if present)
                if (!match.lastOutcome.isNullOrBlank()) {
                    val followUpView = TextView(applicationContext).apply {
                        text = "📞 Last interaction: ${match.lastOutcome}"
                        textSize = 12f
                        setTextColor(Color.parseColor("#80CBC4"))
                        setPadding(0, dp(2), 0, 0)
                    }
                    cardLayout.addView(followUpView)
                }

                windowManager.addView(rootLayout, layoutParams)
                activeOverlayView = rootLayout
                Log.d(TAG, "Floating overlay card displayed successfully on screen!")

                // Auto-dismiss floating card after 18 seconds if unanswered
                Handler(Looper.getMainLooper()).postDelayed({
                    try {
                        if (activeOverlayView == rootLayout) {
                            windowManager.removeView(rootLayout)
                            activeOverlayView = null
                        }
                    } catch (_: Exception) {}
                }, 18000)

            } catch (e: Exception) {
                Log.e(TAG, "Failed to display floating overlay: ${e.message}", e)
            }
        }
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }

    /**
     * Normalizes phone numbers using the same rules as the Flutter PhoneNumberNormalizer.
     * E.g. Ghana local "0241234567" -> "+233241234567"
     */
    private fun normalizePhoneNumber(phone: String): String? {
        val trimmed = phone.trim()
        if (trimmed.isEmpty()) return null
        val digitsOnly = trimmed.replace(Regex("[^0-9+]"), "")
        if (digitsOnly.isEmpty()) return null

        // Ghana 10-digit national number starting with 0
        if (digitsOnly.startsWith("0") && digitsOnly.length == 10) {
            return "+233" + digitsOnly.substring(1)
        }
        // 233... without leading plus
        if (digitsOnly.startsWith("233") && !digitsOnly.startsWith("+")) {
            return "+$digitsOnly"
        }
        // Already starts with +
        if (digitsOnly.startsWith("+")) {
            return digitsOnly
        }
        return "+$digitsOnly"
    }

    /**
     * Queries the app's SQLite database directly from native Kotlin.
     */
    private fun lookupContact(normalized: String?, raw: String): ContactMatch? {
        val dbFile = applicationContext.getDatabasePath("qara.db").takeIf { it.exists() }
            ?: applicationContext.getDatabasePath("evangelism_caller_id.db")
        if (!dbFile.exists()) {
            Log.w(TAG, "SQLite DB file does not exist yet at: ${dbFile.absolutePath}")
            return null
        }

        var db: SQLiteDatabase? = null
        return try {
            db = SQLiteDatabase.openDatabase(dbFile.absolutePath, null, SQLiteDatabase.OPEN_READONLY)

            val query = """
                SELECT c.id, c.name, c.phone_number, c.location, c.notes,
                       i.outcome, i.date
                FROM contacts c
                LEFT JOIN interactions i ON i.contact_id = c.id
                WHERE c.normalized_phone_number = ? OR c.phone_number = ? OR c.phone_number = ?
                ORDER BY i.date DESC
                LIMIT 1
            """.trimIndent()

            val searchArgs = arrayOf(normalized ?: "", raw, normalized ?: "")
            val cursor = db.rawQuery(query, searchArgs)

            var match: ContactMatch? = null
            if (cursor.moveToFirst()) {
                match = ContactMatch(
                    id = cursor.getString(0),
                    name = cursor.getString(1),
                    rawPhone = cursor.getString(2),
                    location = if (!cursor.isNull(3)) cursor.getString(3) else null,
                    notes = if (!cursor.isNull(4)) cursor.getString(4) else null,
                    lastOutcome = if (!cursor.isNull(5)) cursor.getString(5) else null,
                    lastDate = if (!cursor.isNull(6)) cursor.getString(6) else null
                )
            }
            cursor.close()
            match
        } catch (e: Exception) {
            Log.e(TAG, "Error querying SQLite database: ${e.message}", e)
            null
        } finally {
            db?.close()
        }
    }

    /**
     * Posts a High-Priority notification in the system drawer as a persistent log.
     */
    private fun showCallerNotification(match: ContactMatch) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Shows caller identity for known evangelism contacts"
                enableVibration(true)
                setShowBadge(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            notificationManager.createNotificationChannel(channel)
        }

        val intent = Intent(applicationContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("contact_id", match.id)
            putExtra("phone_number", match.rawPhone)
        }

        val pendingIntent = PendingIntent.getActivity(
            applicationContext,
            match.id.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val subtitle = buildString {
            if (!match.location.isNullOrBlank()) {
                append("📍 ")
                append(match.location)
            }
            if (!match.lastOutcome.isNullOrBlank()) {
                if (isNotEmpty()) append(" • ")
                append("Last: ")
                append(match.lastOutcome)
            }
        }.ifEmpty { "Qara Outreach Contact" }

        val bigText = buildString {
            append("Phone: ").append(match.rawPhone)
            if (!match.location.isNullOrBlank()) {
                append("\nLocation: ").append(match.location)
            }
            if (!match.notes.isNullOrBlank()) {
                append("\nNotes: ").append(match.notes)
            }
            if (!match.lastOutcome.isNullOrBlank()) {
                append("\nLast Interaction: ").append(match.lastOutcome)
                if (!match.lastDate.isNullOrBlank()) {
                    append(" (").append(match.lastDate).append(")")
                }
            }
        }

        val notification = Notification.Builder(applicationContext, CHANNEL_ID)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("📞 Outreach: ${match.name}")
            .setContentText(subtitle)
            .setStyle(Notification.BigTextStyle().bigText(bigText))
            .setCategory(Notification.CATEGORY_CALL)
            .setPriority(Notification.PRIORITY_HIGH)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()

        notificationManager.notify(match.id.hashCode(), notification)
    }
}
