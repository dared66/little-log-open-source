package app.littlelog.little_log

import android.content.Intent
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.StaleObjectException
import androidx.test.uiautomator.Until
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.regex.Pattern

/** Run only with tool/import_picker_review.dart on the dedicated emulator. */
@RunWith(AndroidJUnit4::class)
class ImportPickerTest {
    private val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
    private fun element(label: String): UiObject2 {
        val pattern = Pattern.compile("(?s).*" + Pattern.quote(label) + ".*")
        val deadline = android.os.SystemClock.uptimeMillis() + 15_000
        while (android.os.SystemClock.uptimeMillis() < deadline) {
            val found = device.findObject(By.desc(pattern)) ?: device.findObject(By.text(pattern))
            if (found != null) return found
            android.os.SystemClock.sleep(100)
        }
        shot("android-picker-failure")
        throw AssertionError("Missing UI: $label")
    }
    private fun shot(name: String) {
        val dir = InstrumentationRegistry.getInstrumentation().targetContext.getExternalFilesDir(null)!!
        device.takeScreenshot(File(dir, "$name.png"))
        device.dumpWindowHierarchy(File(dir, "$name.xml"))
    }
    @Test fun selectsCsvThroughSystemPickerAndImports() {
        assertTrue("Emulator only", android.os.Build.FINGERPRINT.contains("generic") || android.os.Build.MODEL.contains("sdk"))
        assertEquals("true", InstrumentationRegistry.getArguments().getString("isolatedImportQa"))
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)!!
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        context.startActivity(launch)
        element("Robin")
        element("Settings").click()
        element("Import and recovery").click()
        element("Choose file").click()
        assertTrue(device.wait(Until.hasObject(By.pkg("com.google.android.documentsui")), 10_000))
        shot("android-system-picker")
        // Navigate through the actual Android DocumentsUI, not a mocked return.
        val fileSelector = By.text("Nara-Robin-test.csv")
        if (!device.wait(Until.hasObject(fileSelector), 2_000)) {
            device.wait(Until.findObject(By.desc("Show roots")), 3_000)!!.click()
            val rootsDeadline = android.os.SystemClock.uptimeMillis() + 10_000
            var openedDownloads = false
            while (!openedDownloads && android.os.SystemClock.uptimeMillis() < rootsDeadline) {
                val downloads = device.wait(Until.findObject(By.res("android:id/title").text("Downloads")), 1_000)
                    ?: device.findObject(By.text("Downloads")) ?: continue
                try {
                    downloads.click()
                    openedDownloads = true
                } catch (_: StaleObjectException) {
                    // DocumentsUI can replace its roots while providers refresh.
                    android.os.SystemClock.sleep(100)
                }
            }
            assertTrue("Downloads root must be selectable", openedDownloads)
        }
        // Match the filename, not DocumentsUI's separate "Preview the file" action.
        val deadline = android.os.SystemClock.uptimeMillis() + 10_000
        var selected = false
        while (!selected && android.os.SystemClock.uptimeMillis() < deadline) {
            val file = device.wait(Until.findObject(fileSelector), 1_000) ?: continue
            try {
                file.click()
                selected = true
            } catch (_: StaleObjectException) {
                // DocumentsUI can replace a row while its provider refreshes.
                // Reacquire the exact filename rather than reusing that node.
                android.os.SystemClock.sleep(100)
            }
        }
        if (!selected) shot("android-picker-failure")
        assertTrue("Synthetic CSV must be selectable", selected)
        shot("android-after-file-selection")
        element("Review import")
        element("Nara-Robin-test.csv")
        element("1 entry not imported")
        shot("android-import-preview")
        var save = device.findObject(By.desc("Import these entries"))
        if (save == null) {
            device.swipe(device.displayWidth / 2, device.displayHeight * 3 / 4, device.displayWidth / 2, device.displayHeight / 3, 30)
            save = element("Import these entries")
        }
        save.click()
        element("Import saved on this device.")
        element("Remove Nara Baby imports")
        assertTrue(device.wait(Until.hasObject(By.desc("Undo last import").enabled(true)), 10_000))
        shot("android-import-saved")
        element("Remove Nara Baby imports").click()
        element("Remove imports").click()
        element("Undo removal").click()
        element("Restore imports").click()
        element("Nara Baby imports restored.")
        shot("android-import-restored")
    }
}
