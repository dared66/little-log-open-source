package app.littlelog.little_log

import android.app.Activity
import android.app.AlertDialog
import android.app.KeyguardManager
import android.view.MotionEvent

/** External intent fields and referrers never establish caller trust. */
class ExternalActionConfirmation(private val activity: Activity) {
    private var resumed = false
    private var pending: (() -> Unit)? = null
    private var title: String? = null
    private var readAloud = false
    private var dialog: AlertDialog? = null

    private fun unlocked(): Boolean {
        val keyguard = activity.getSystemService(KeyguardManager::class.java)
        return !keyguard.isDeviceLocked && !keyguard.isKeyguardLocked
    }

    fun request(title: String, readAloud: Boolean = false, action: () -> Unit) {
        // Never replace the action underneath a confirmation already on screen.
        if (pending != null || dialog != null) return
        this.title = title
        this.readAloud = readAloud
        pending = action
        showIfReady()
    }

    fun onResume() {
        resumed = true
        showIfReady()
    }

    fun onPause() {
        resumed = false
    }

    fun onStop() {
        resumed = false
        clear()
    }

    private fun clear() {
        pending = null
        title = null
        dialog?.dismiss()
        dialog = null
    }

    private fun showIfReady() {
        if (!resumed || pending == null || activity.isFinishing || activity.isDestroyed) return
        if (!unlocked()) { clear(); return }
        if (dialog != null) return
        val approvedAction = pending
        val confirmation = AlertDialog.Builder(activity)
            .setTitle(title)
            .setMessage("Use the baby currently selected in Little Log.")
            .setNegativeButton("Cancel") { _, _ -> clear() }
            .setPositiveButton(if (readAloud) "Read aloud" else "Continue") { _, _ ->
                val allowed = resumed && unlocked() && !activity.isFinishing && !activity.isDestroyed
                clear()
                if (allowed) approvedAction?.invoke()
            }
            .setOnCancelListener { clear() }
            .create()
        dialog = confirmation
        confirmation.show()
        confirmation.getButton(AlertDialog.BUTTON_POSITIVE).apply {
            filterTouchesWhenObscured = true
            setOnTouchListener { _, event ->
                event.flags and (MotionEvent.FLAG_WINDOW_IS_OBSCURED or
                    MotionEvent.FLAG_WINDOW_IS_PARTIALLY_OBSCURED) != 0
            }
        }
    }
}

fun externalActionTitle(action: String, kind: String? = null, amount: Number? = null, unit: String? = null): String = when (action) {
    "add_diaper" -> "Add ${when (kind) { "both" -> "wet and dirty"; "wet", "dirty", "dry" -> kind; else -> "a" }} diaper?"
    "nursing_left" -> "Start nursing on the left?"
    "nursing_right" -> "Start nursing on the right?"
    "sleep" -> "Start sleep?"
    "pumping" -> "Start pumping?"
    "finish_sleep" -> "Finish sleep?"
    "finish_nursing" -> "Finish nursing?"
    "finish_pumping" -> "Save pumping: ${amount.toString().removeSuffix(".0")} ${if (unit == "oz") "US fl oz" else "ml"}?"
    "review_pumping" -> "Review pumping?"
    "open_diaper", "diaper" -> "Open diaper entry?"
    "open_nursing" -> "Open nursing?"
    else -> "Read care history aloud?"
}
