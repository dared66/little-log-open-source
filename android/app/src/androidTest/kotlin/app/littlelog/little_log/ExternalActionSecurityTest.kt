package app.littlelog.little_log

import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.ParcelFileDescriptor
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.regex.Pattern

/** Run only with the memory-only voice harness on a disposable emulator. */
@RunWith(AndroidJUnit4::class)
class ExternalActionSecurityTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val device = UiDevice.getInstance(instrumentation)
    private val context get() = instrumentation.targetContext

    @Before fun isolatedEmulatorOnly() {
        assertTrue(Build.FINGERPRINT.contains("generic") || Build.MODEL.contains("sdk"))
        assertEquals("true", InstrumentationRegistry.getArguments().getString("isolatedVoiceQa"))
        device.wakeUp()
        device.executeShellCommand("wm dismiss-keyguard")
    }

    private fun launch(path: String, cold: Boolean = true) {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("littlelog://voice/$path"), context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            .putExtra("confirmed", true).putExtra("trusted", true)
            .putExtra(Intent.EXTRA_REFERRER, Uri.parse("android-app://com.google.android.googlequicksearchbox"))
        if (cold) intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TASK)
        context.startActivity(intent)
        assertTrue(device.wait(Until.hasObject(By.res("android:id/button1")), 10_000))
    }

    private fun cancel() {
        device.findObject(By.res("android:id/button2"))!!.click()
    }

    private fun marker(value: String) {
        val pattern = Pattern.compile("(?s).*VOICE_QA.*" + Pattern.quote(value) + ".*")
        assertTrue("Unexpected synthetic log state: $value",
            device.wait(Until.hasObject(By.desc(pattern)), 10_000) || device.hasObject(By.text(pattern)))
    }

    @Test fun cancellationAndSpoofedTrustFieldsCannotWrite() {
        launch("add_diaper?kind=wet")
        cancel()
        marker("wet=0 dirty=0 both=0 dry=0")
    }

    @Test fun approvalAppliesOnlyTheRequestShown() {
        launch("add_diaper?kind=wet")
        // A second external caller must not swap the action under the button.
        device.executeShellCommand("am start -W -n app.littlelog.little_log/.MainActivity -a android.intent.action.VIEW -d littlelog://voice/add_diaper?kind=dirty")
        device.waitForIdle()
        assertTrue(device.wait(Until.hasObject(By.text("Add wet diaper?")), 5_000))
        device.findObject(By.res("android:id/button1"))!!.click()
        marker("wet=1 dirty=0 both=0 dry=0")
    }

    @Test fun historyNeedsExplicitReadAloudConsent() {
        launch("last_feed")
        assertEquals("Read aloud", device.findObject(By.res("android:id/button1"))!!.text)
        cancel()
        marker("wet=0 dirty=0 both=0 dry=0")
        assertFalse(device.hasObject(By.text("When did the baby last feed?")))
        assertFalse(device.hasObject(By.desc("When did the baby last feed?")))
    }

    @Test fun backgroundingDiscardsUnapprovedCommands() {
        launch("sleep")
        device.pressHome()
        var stopped = false
        for (attempt in 0 until 100) {
            instrumentation.runOnMainSync {
                stopped = ActivityLifecycleMonitorRegistry.getInstance()
                    .getActivitiesInStage(Stage.STOPPED).any { it is MainActivity }
            }
            if (stopped) break
            Thread.sleep(50)
        }
        assertTrue("Home must stop the app before it is reopened", stopped)
        context.startActivity(Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        marker("sleepActive=0 sleepSaved=0")
        assertFalse(device.hasObject(By.res("android:id/button1")))
    }

    @Test fun forgedLauncherActionRequiresConfirmation() {
        context.startActivity(Intent(context, MainActivity::class.java)
            .setAction("app.littlelog.quick.nursing_left")
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK))
        assertTrue(device.wait(Until.hasObject(By.res("android:id/button1")), 10_000))
        cancel()
        marker("nursingActive=none")
    }

    @Test fun notificationComponentsRejectExternalCallers() {
        val manager = context.packageManager
        assertFalse(manager.getActivityInfo(ComponentName(context, TimerActionActivity::class.java), 0).exported)
        assertFalse(manager.getReceiverInfo(ComponentName(context, LiveTimerReceiver::class.java), 0).exported)
        val streams = instrumentation.uiAutomation.executeShellCommandRwe(
            "am start -n app.littlelog.little_log/.TimerActionActivity -a app.littlelog.timer.ACTION")
        streams[1].close()
        val result = ParcelFileDescriptor.AutoCloseInputStream(streams[0]).bufferedReader().use { it.readText() } +
            ParcelFileDescriptor.AutoCloseInputStream(streams[2]).bufferedReader().use { it.readText() }
        assertTrue("External caller must be denied", result.contains("Permission Denial") || result.contains("SecurityException"))
    }

    @Test fun legacyTimerIntentCannotBypassConfirmation() {
        context.startActivity(Intent(context, MainActivity::class.java)
            .setAction(LiveTimers.ACTION).putExtra("sessionId", "synthetic")
            .putExtra("timerAction", "finish").putExtra("revision", 0)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK))
        assertTrue(device.wait(Until.hasObject(By.res("android:id/button1")), 10_000))
        cancel()
        marker("sleepActive=0 sleepSaved=0")
    }
}
