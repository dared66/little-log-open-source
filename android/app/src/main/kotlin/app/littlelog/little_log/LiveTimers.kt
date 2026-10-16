package app.littlelog.little_log

import androidx.core.app.NotificationCompat
import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.AtomicFile
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

/** The system renders the clock; no background polling service is needed. */
class LiveTimers(private val context: Context, private val storageName: String = "live-timers.json") {
    companion object {
        const val ACTION = "app.littlelog.timer.ACTION"
        private const val CHANNEL = "live-care-timers"
        private val lock = Any()
        var changed: (() -> Unit)? = null
    }
    private val file get() = AtomicFile(File(context.filesDir, storageName))
    private val manager get() = context.getSystemService(NotificationManager::class.java)
    private fun read(): JSONObject = if (file.baseFile.exists())
        JSONObject(file.openRead().bufferedReader().use { it.readText() })
        else JSONObject().put("sessions", JSONArray()).put("actions", JSONArray()).put("dismissed", JSONArray())
    private fun write(value: JSONObject) {
        val stream = file.startWrite()
        try { stream.write(value.toString().toByteArray()); file.finishWrite(stream) }
        catch (error: Throwable) { file.failWrite(stream); throw error }
    }
    private fun objects(array: JSONArray): List<JSONObject> = (0 until array.length()).map { array.getJSONObject(it) }
    private fun asMap(value: JSONObject): Map<String, Any> = value.keys().asSequence().associateWith { value.get(it) }

    fun pending(): List<Map<String, Any>> = synchronized(lock) { objects(read().getJSONArray("actions")).map(::asMap) }
    fun acknowledge(id: String) = synchronized(lock) {
        val value = read()
        value.put("actions", JSONArray(objects(value.getJSONArray("actions")).filter { it.getString("id") != id }))
        write(value)
    }
    private fun apply(session: JSONObject, action: String, revision: Int, now: Long): JSONObject? {
        if (session.optInt("revision") != revision) return null
        val phase = session.optString("phase", "running")
        val method = session.getString("method")
        val next = JSONObject(session.toString())
        when (action) {
            "pause" -> {
                if (phase != "running" || method == "sleep") return null
                next.put("elapsedSeconds", ((now / 1000.0) - session.getDouble("startedAt")).coerceAtLeast(0.0))
                next.put("phase", "paused").put("detail", "Paused")
            }
            "resume" -> {
                if (phase != "paused") return null
                next.put("startedAt", now / 1000.0 - session.getDouble("elapsedSeconds"))
                next.put("phase", "running").put("detail", "Timer running")
            }
            "finish" -> {
                if (method != "sleep" && phase != "paused") return null
                next.put("phase", if (method == "pumping") "review" else "finished")
                next.put("detail", if (method == "pumping") "Add pumped amount" else "Finished")
            }
            "review" -> if (phase != "review") return null else return next
            else -> return null
        }
        next.put("revision", revision + 1)
        return next
    }
    fun update(sessions: List<Map<String, Any?>>) = synchronized(lock) {
        val value = read()
        val previous = objects(value.getJSONArray("sessions"))
        val pending = objects(value.getJSONArray("actions"))
        val next = sessions.map { source ->
            var state = JSONObject(source)
            pending.filter { it.optString("sessionId") == state.getString("id") }.forEach { request ->
                state = apply(state, request.getString("action"), request.getInt("revision"), request.getLong("stoppedAt")) ?: state
            }
            state
        }.filter { it.optString("phase") != "finished" }
        value.put("sessions", JSONArray(next))
        val ids = next.map { it.getString("id") }.toSet()
        val hidden = value.optJSONArray("dismissed") ?: JSONArray()
        value.put("dismissed", JSONArray((0 until hidden.length()).map { hidden.getString(it) }.filter { it in ids }))
        write(value)
        previous.filter { it.getString("id") !in ids }.forEach { manager.cancel(it.getString("id"), 1) }
        show(value)
    }
    fun receive(intent: Intent?): Boolean {
        if (intent?.action != ACTION) return false
        synchronized(lock) {
            val value = read()
            val id = intent.getStringExtra("sessionId") ?: return false
            val action = intent.getStringExtra("timerAction") ?: return false
            if (action == "dismiss") {
                val hidden = value.optJSONArray("dismissed") ?: JSONArray()
                hidden.put(id); value.put("dismissed", hidden); write(value); return true
            }
            val sessions = objects(value.getJSONArray("sessions"))
            val current = sessions.firstOrNull { it.getString("id") == id } ?: return false
            val revision = intent.getIntExtra("revision", -1)
            val now = System.currentTimeMillis()
            val next = apply(current, action, revision, now) ?: return false
            val request = JSONObject().put("id", UUID.randomUUID().toString()).put("sessionId", id)
                .put("familyId", current.getString("familyId")).put("method", current.getString("method"))
                .put("action", action).put("revision", revision).put("stoppedAt", now)
            value.getJSONArray("actions").put(request)
            value.put("sessions", JSONArray(sessions.map { if (it.getString("id") == id) next else it }
                .filter { it.optString("phase") != "finished" }))
            write(value)
            if (next.optString("phase") == "finished") manager.cancel(id, 1)
            show(value)
        }
        Handler(Looper.getMainLooper()).post { changed?.invoke() }
        return true
    }
    fun refresh() = synchronized(lock) { show(read()) }
    private fun actionIntent(session: JSONObject, action: String, activity: Boolean = false): PendingIntent {
        val intent = Intent(context, if (activity) TimerActionActivity::class.java else LiveTimerReceiver::class.java)
            .setAction(ACTION).setData(Uri.parse("littlelog://timer/${session.getString("id")}/$action/${session.optInt("revision")}"))
            .putExtra("sessionId", session.getString("id")).putExtra("timerAction", action)
            .putExtra("revision", session.optInt("revision"))
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return if (activity) PendingIntent.getActivity(context, 0, intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP), flags)
            else PendingIntent.getBroadcast(context, 0, intent, flags)
    }
    private fun duration(seconds: Double): String {
        val total = seconds.toInt().coerceAtLeast(0)
        return if (total >= 3600) "%d:%02d:%02d".format(total / 3600, total / 60 % 60, total % 60)
            else "%d:%02d".format(total / 60, total % 60)
    }
    private fun show(value: JSONObject) {
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "Live timers", NotificationManager.IMPORTANCE_LOW))
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val hidden = value.optJSONArray("dismissed") ?: JSONArray()
        val dismissed = (0 until hidden.length()).map { hidden.getString(it) }.toSet()
        objects(value.getJSONArray("sessions")).filter { it.getString("id") !in dismissed }.forEach { session ->
            val id = session.getString("id")
            val phase = session.optString("phase", "running")
            val running = phase == "running"
            val elapsed = session.optDouble("elapsedSeconds", 0.0)
            val builder = NotificationCompat.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_live_timer).setContentTitle(session.getString("title"))
                .setContentText(if (running) session.optString("detail", "Timer running") else "${duration(elapsed)} · ${session.optString("detail")}")
                .setCategory(Notification.CATEGORY_STOPWATCH).setOngoing(true).setOnlyAlertOnce(true)
                .setVisibility(Notification.VISIBILITY_PRIVATE).setUsesChronometer(running).setShowWhen(running)
                .setWhen((session.getDouble("startedAt") * 1000).toLong())
                .setContentIntent(PendingIntent.getActivity(context, id.hashCode(), Intent(context, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
                .setDeleteIntent(actionIntent(session, "dismiss"))
            val actions = if (phase == "review") listOf("review") else if (phase == "paused") listOf("resume", "finish")
                else if (session.getString("method") == "sleep") listOf("finish") else listOf("pause")
            actions.forEach { action ->
                val label = when (action) { "review" -> "Add amount"; "resume" -> "Resume"; "pause" -> "Pause"; else -> "Finish" }
                builder.addAction(NotificationCompat.Action.Builder(0, label,
                    actionIntent(session, action, session.getString("method") == "pumping" && action in listOf("finish", "review"))).build())
            }
            if (Build.VERSION.SDK_INT >= 36) {
                builder.setRequestPromotedOngoing(phase != "review")
                if (!running) builder.setShortCriticalText(duration(elapsed))
            }
            manager.notify(id, 1, builder.build())
        }
    }
}

class LiveTimerReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // A failed durable write must leave the displayed timer unchanged.
        runCatching { LiveTimers(context.applicationContext).receive(intent) }
    }
}
