package com.mode.evangelism_caller_id

import android.os.Build
import android.telecom.Call
import android.telecom.CallScreeningService
import android.util.Log
import androidx.annotation.RequiresApi

/**
 * EvangelismCallScreeningService
 *
 * An Android CallScreeningService that intercepts incoming phone calls
 * to identify known evangelism contacts.
 *
 * For Milestone 1 (Foundation), this is a skeleton implementation.
 * In Milestone 2, we will add matching logic and caller notification/overlay.
 */
@RequiresApi(Build.VERSION_CODES.Q)
class EvangelismCallScreeningService : CallScreeningService() {

    companion object {
        private const val TAG = "CallScreeningService"
    }

    override fun onScreenCall(callDetails: Call.Details) {
        val isIncoming = callDetails.callDirection == Call.Details.DIRECTION_INCOMING
        val handleUri = callDetails.handle
        val rawPhoneNumber = handleUri?.schemeSpecificPart ?: "Unknown"

        Log.d(TAG, "onScreenCall received: incoming=$isIncoming, number=$rawPhoneNumber")

        // For now, always allow the call without blocking or altering notifications.
        // We will implement actual contact matching in Milestone 2.
        val response = CallResponse.Builder()
            .setDisallowCall(false)
            .setRejectCall(false)
            .setSkipCallLog(false)
            .setSkipNotification(false)
            .build()

        respondToCall(callDetails, response)
    }
}
