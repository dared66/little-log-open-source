package app.littlelog.little_log

import android.content.Intent
import android.app.NotificationManager
import android.content.pm.ShortcutManager
import android.net.Uri
import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.regex.Pattern
import java.io.File

/** Compile tool/voice_action_review.dart; never reads the production database. */
@RunWith(AndroidJUnit4::class)
class VoiceEntryPointsTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val device = UiDevice.getInstance(instrumentation)
    @Before fun isolatedEmulatorOnly() {
        assertTrue(Build.FINGERPRINT.contains("generic") || Build.MODEL.contains("sdk"))
        assertEquals("true", InstrumentationRegistry.getArguments().getString("isolatedVoiceQa"))
    }
    private fun command(path: String, cold: Boolean = false) {
        val context = instrumentation.targetContext
        val launch = Intent(Intent.ACTION_VIEW, Uri.parse("littlelog://voice/$path"), context, MainActivity::class.java)
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (cold) launch.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TASK)
        context.startActivity(launch)
        approve()
    }
    private fun approve() {
        val button = device.wait(Until.findObject(By.res("android:id/button1")), 10_000)
        assertNotNull("External commands must require confirmation", button)
        button!!.click()
    }
    private fun marker(part: String) {
        val pattern = Pattern.compile("(?s).*VOICE_QA.*" + Pattern.quote(part) + ".*")
        val found = device.wait(Until.hasObject(By.desc(pattern)), 15_000) || device.hasObject(By.text(pattern))
        if (!found) {
            val directory = instrumentation.targetContext.getExternalFilesDir(null)!!
            device.dumpWindowHierarchy(File(directory, "voice-qa-failure.xml"))
            device.takeScreenshot(File(directory, "voice-qa-failure.png"))
        }
        assertTrue("Native command did not produce $part", found)
    }
    private fun pause(method: String) {
        val paused = if (method == "nursing") "nursingPaused=true" else "pumpingPhase=paused"
        val pausedMarker = By.desc(Pattern.compile("(?s).*VOICE_QA.*" + Pattern.quote(paused) + ".*"))
        val exact = By.desc("Pause $method").enabled(true)
        val fullControl = device.findObject(exact)
        if (fullControl != null) {
            fullControl.click()
        } else {
            // Flutter can merge the row's accessibility label with its action.
            // A row tap opens controls, where the labeled button is unambiguous.
            val row = device.wait(Until.findObject(By.desc(Pattern.compile("(?is).*pause\\s+$method.*")).enabled(true)), 10_000)
                ?: device.findObject(By.desc("Pause").enabled(true))
            assertNotNull("Running $method must offer Pause", row)
            row!!.click()
            if (!device.wait(Until.hasObject(pausedMarker), 1_000)) {
                val control = device.wait(Until.findObject(exact), 5_000)
                assertNotNull("Session controls must offer Pause $method", control)
                control!!.click()
            }
        }
        marker(paused)
        device.findObject(By.desc("Close"))?.click()
    }

    @Test fun launcherMenuStillContainsOnlyTheRequestedFourActions() {
        val shortcuts = instrumentation.targetContext.getSystemService(ShortcutManager::class.java).manifestShortcuts
        assertEquals(setOf("diaper", "nursing_left", "nursing_right", "sleep"), shortcuts.map { it.id }.toSet())
    }

    @Test fun trustedPumpingNotificationStillOpensTheAmountForm() {
        command("pumping", cold = true)
        marker("pumpingActive=1")
        pause("pumping")
        val manager = instrumentation.targetContext.getSystemService(NotificationManager::class.java)
        var action: android.app.Notification.Action? = null
        for (attempt in 0 until 100) {
            action = manager.activeNotifications.flatMap { it.notification.actions?.toList() ?: emptyList() }
                .firstOrNull { it.title.toString() == "Finish" }
            if (action != null) break
            Thread.sleep(50)
        }
        assertNotNull("Paused pumping needs its Finish notification action", action)
        assertTrue(action!!.actionIntent.isImmutable)
        action.actionIntent.send()
        assertTrue(device.wait(Until.hasObject(By.desc("Save pumping")), 10_000) ||
            device.hasObject(By.text("Save pumping")))
        assertFalse("Our protected notification must not need external-link confirmation",
            device.hasObject(By.res("android:id/button1")))
        marker("pumpingActive=1 pumpingSaved=0")
    }

    @Test fun realHistoryQuestionsShowAnswersAndDoNotChangeLogsOrTimers() {
        fun answer(text: String) {
            val pattern = Pattern.compile("(?s).*" + Pattern.quote(text) + ".*")
            assertTrue("History answer was not displayed", device.wait(Until.hasObject(By.text(pattern)), 15_000) ||
                device.hasObject(By.desc(pattern)))
            val done = device.findObject(By.text("Done")) ?: device.findObject(By.desc("Done"))
            assertNotNull("History answer needs a dismiss action", done)
            done!!.click()
        }
        command("last_feed", cold = true)
        answer("No feeds are logged for Robin QA.")
        marker("wet=0 dirty=0 both=0 dry=0")
        command("add_diaper?kind=wet")
        marker("wet=1")
        command("last_diaper")
        answer("Robin QA’s last wet diaper was")
        marker("wet=1 dirty=0 both=0 dry=0")
        command("sleep")
        marker("sleepActive=1")
        command("sleep_status")
        answer("Robin QA has an active sleep timer")
        marker("sleepActive=1 sleepSaved=0")
        command("last_wake")
        answer("No wake-up times are logged for Robin QA.")
        marker("sleepActive=1 sleepSaved=0")
    }
    @Test fun realLauncherActionsOpenFormsAndPreserveRunningTimers() {
        val context = instrumentation.targetContext
        fun shortcut(action: String, cold: Boolean = false) {
            val launch = Intent(context, MainActivity::class.java)
                .setAction("app.littlelog.quick.$action")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (cold) launch.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TASK)
            context.startActivity(launch)
            approve()
        }
        shortcut("nursing_right", cold = true)
        marker("nursingActive=right")
        shortcut("nursing_left")
        marker("nursingActive=right")
        shortcut("sleep")
        marker("sleepActive=1")
        shortcut("sleep")
        marker("sleepActive=1")
        shortcut("diaper")
        assertTrue(device.wait(Until.hasObject(By.desc("Save diaper")), 10_000) ||
            device.hasObject(By.text("Save diaper")))
        marker("wet=0 dirty=0 both=0 dry=0")
        marker("nursingActive=right")
        marker("sleepActive=1")
    }
    @Test fun realColdAndWarmCommandsSaveAllFourActivityCategories() {
        command("add_diaper?kind=wet", cold = true)
        marker("wet=1")
        command("add_diaper?kind=dirty")
        marker("dirty=1")
        command("add_diaper?kind=both")
        marker("both=1")
        command("add_diaper?kind=dry")
        marker("dry=1")
        command("sleep")
        marker("sleepActive=1")
        command("finish_sleep")
        marker("sleepActive=0 sleepSaved=1")
        command("nursing?side=left")
        marker("nursingActive=left")
        pause("nursing")
        command("finish_nursing")
        marker("nursingActive=none nursingSaved=1")
        command("nursing?side=right")
        marker("nursingActive=right")
        pause("nursing")
        command("finish_nursing")
        marker("nursingActive=none nursingSaved=2")
        command("pumping")
        marker("pumpingActive=1")
        pause("pumping")
        command("finish_pumping?amount=90&unit=ml")
        marker("pumpingActive=0 pumpingSaved=1 pumpingMl=90.0")
        command("pumping")
        marker("pumpingActive=1")
        pause("pumping")
        command("finish_pumping")
        assertTrue(device.wait(Until.hasObject(By.desc("Save pumping")), 10_000) ||
            device.hasObject(By.text("Save pumping")))
        marker("pumpingActive=1 pumpingSaved=1")
    }
}
