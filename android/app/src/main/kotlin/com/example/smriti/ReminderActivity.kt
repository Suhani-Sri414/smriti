package com.example.smriti

import android.app.KeyguardManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class ReminderActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
            keyguardManager?.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun getDartEntrypointFunctionName(): String {
        return "reminderMain"
    }

    override fun getDartEntrypointArgs(): List<String> {
        val medicationId = intent?.getStringExtra("medicationId") ?: ""
        val reminderEventId = intent?.getStringExtra("reminderEventId") ?: ""
        val step = intent?.getIntExtra("step", 0)?.toString()
            ?: (intent?.getStringExtra("step") ?: "0")
        return listOf(medicationId, reminderEventId, step)
    }
}
