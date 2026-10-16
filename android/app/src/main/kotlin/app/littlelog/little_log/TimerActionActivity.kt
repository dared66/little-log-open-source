package app.littlelog.little_log

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/** Only our immutable notification PendingIntents can enter this activity. */
class TimerActionActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) LiveTimers(applicationContext).receive(intent)
        // MainActivity has a separate task affinity. Reuse its existing task
        // instead of creating a second Flutter engine inside this trampoline.
        startActivity(Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP))
        finish()
    }
}
