package app.littlelog.little_log

import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class LiveTimersTest {
    @Test fun pausedNotificationsRemainWithResumeFinishAndSurviveManagerRestart() {
        assertTrue(Build.FINGERPRINT.contains("generic") || Build.MODEL.contains("sdk"))
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val manager = context.getSystemService(NotificationManager::class.java)
        val name = "qa-live-${UUID.randomUUID()}.json"
        val live = LiveTimers(context, name)
        val id = UUID.randomUUID().toString()
        fun notification() = manager.activeNotifications.first { it.tag == id }.notification
        fun awaitActions(expected: List<String>) {
            for (attempt in 0 until 200) {
                val current = manager.activeNotifications.firstOrNull { it.tag == id }?.notification
                if (current?.actions?.map { it.title.toString() } == expected) return
                Thread.sleep(10)
            }
            fail("Notification did not publish actions: $expected")
        }
        fun act(action: String, revision: Int) = live.receive(Intent(context, LiveTimerReceiver::class.java)
            .setAction(LiveTimers.ACTION).putExtra("sessionId", id).putExtra("timerAction", action).putExtra("revision", revision))
        try {
            live.update(listOf(mapOf("id" to id, "familyId" to "synthetic-qa", "method" to "pumping",
                "title" to "Synthetic QA · Pumping", "detail" to "Timer running", "phase" to "running",
                "startedAt" to (System.currentTimeMillis() / 1000.0 - 600), "elapsedSeconds" to 600.0, "revision" to 0)))
            awaitActions(listOf("Pause"))
            assertEquals(listOf("Pause"), notification().actions.map { it.title.toString() })
            assertTrue(notification().extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER))
            assertTrue(act("pause", 0))
            awaitActions(listOf("Resume", "Finish"))
            assertEquals(listOf("Resume", "Finish"), notification().actions.map { it.title.toString() })
            assertFalse(notification().extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER))
            assertTrue(notification().flags and Notification.FLAG_ONGOING_EVENT != 0)
            assertTrue(NotificationCompat.isRequestPromotedOngoing(notification()))
            assertEquals(1, LiveTimers(context, name).pending().size)
            assertTrue(act("resume", 1))
            awaitActions(listOf("Pause"))
            assertTrue(notification().extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER))
            assertFalse(act("finish", 1))
            assertTrue(act("pause", 2))
            assertTrue(act("finish", 3))
            awaitActions(listOf("Add amount"))
            assertEquals(listOf("Add amount"), notification().actions.map { it.title.toString() })
            assertFalse(notification().extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER))
            assertEquals(listOf("pause", "resume", "pause", "finish"), LiveTimers(context, name).pending().map { it["action"] })
            assertFalse(act("resume", 4))
        } finally {
            live.update(emptyList()); manager.cancel(id, 1)
            File(context.filesDir, name).delete()
            File(context.filesDir, "$name.bak").delete()
        }
    }
}
