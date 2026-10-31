package com.civicbuddy.app

import android.app.Activity
import android.content.Intent
import com.google.android.gms.common.api.ResolvableApiException
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.LocationSettingsRequest
import com.google.android.gms.location.Priority
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingTurnOnResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOCATION_SETTINGS_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "requestTurnOn") {
                    requestTurnOn(result)
                } else {
                    result.notImplemented()
                }
            }
    }

    /**
     * Shows Google Play services' native "Turn on location?" dialog.
     * Replies "on", "declined" or "unavailable" (no Play services, or the
     * dialog cannot be shown).
     */
    private fun requestTurnOn(result: MethodChannel.Result) {
        if (pendingTurnOnResult != null) {
            result.success("declined")
            return
        }

        val settingsRequest = LocationSettingsRequest.Builder()
            .addLocationRequest(
                LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 10_000L).build(),
            )
            // Show the dialog even after the user once tapped "No thanks".
            .setAlwaysShow(true)
            .build()

        try {
            LocationServices.getSettingsClient(this)
                .checkLocationSettings(settingsRequest)
                .addOnSuccessListener { result.success("on") }
                .addOnFailureListener { error ->
                    if (error is ResolvableApiException) {
                        try {
                            pendingTurnOnResult = result
                            error.startResolutionForResult(this, REQUEST_TURN_ON_LOCATION)
                        } catch (_: Exception) {
                            pendingTurnOnResult = null
                            result.success("unavailable")
                        }
                    } else {
                        result.success("unavailable")
                    }
                }
        } catch (_: Exception) {
            result.success("unavailable")
        }
    }

    @Deprecated("Needed to receive the location dialog result from Play services.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_TURN_ON_LOCATION) {
            pendingTurnOnResult?.success(
                if (resultCode == Activity.RESULT_OK) "on" else "declined",
            )
            pendingTurnOnResult = null
            return
        }

        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }

    companion object {
        private const val LOCATION_SETTINGS_CHANNEL = "civicbuddy/location_settings"
        private const val REQUEST_TURN_ON_LOCATION = 7001
    }
}
