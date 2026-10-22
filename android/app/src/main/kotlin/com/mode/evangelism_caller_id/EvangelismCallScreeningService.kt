package com.mode.evangelism_caller_id

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.os.Build
import android.telecom.Call
import android.telecom.CallScreeningService
import android.util.Log
import androidx.annotation.RequiresApi

/**
 * EvangelismCallScreeningService
 *
 * Intercepts incoming phone calls at the OS level (Android 10+ / API 29+).
 *
 * Core Workflow (Milestone 2 & Milestone 4):
 * 1. Android OS fires `onScreenCall(callDetails)`.
 * 2. Service extracts and normalizes the incoming phone number (e.g., Ghana 024... -> +23324...).
 * 3. Opens the local SQLite database (`evangelism_caller_id.db`) in read-only mode.
 * 4. Queries `contacts` and `interactions` tables for an exact normalized number match.
 * 5. If MATCH found:
 *    - Displays a High-Priority Heads-Up Notification with the person's name, location, and notes.
 *    - Tapping the notification opens the app to their contact profile.
 * 6. If NO match:
 *    - Remains completely silent (no false identifications).
 * 7. Calls `respondToCall` allowing the normal phone call to ring through without interruption.
 */
@RequiresApi(Build.VERSION_CODES.Q)
class EvangelismCallScreeningService : CallScreeningService() {

    companion object {
        private const val TAG = "CallScreeningService"
        const val CHANNEL_ID = "evangelism_caller_id"
        const val CHANNEL_NAME = "Evangelism Caller ID"
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
                showCallerNotification(match)
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
        val dbFile = applicationContext.getDatabasePath("evangelism_caller_id.db")
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
     * Posts a High-Priority Heads-Up Notification displaying the contact's details.
     */
    private fun showCallerNotification(match: ContactMatch) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Ensure NotificationChannel is configured
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

        // Tap action: opens app to the contact
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
        }.ifEmpty { "Evangelism Outreach Contact" }

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
