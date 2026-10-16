package app.littlelog.little_log

import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class AssistantActionsTest {
    private fun intent(path: String) = Intent(Intent.ACTION_VIEW, Uri.parse("littlelog://voice/$path"))
    private fun parse(path: String) = AssistantIntentParser.parse(intent(path))
    @Before fun emulatorOnly() {
        assertTrue("Emulator only", Build.FINGERPRINT.contains("generic") || Build.MODEL.contains("sdk"))
    }

    @Test fun allFourDiaperKindsUseDirectSaves() {
        for (kind in listOf("wet", "dirty", "both", "dry")) {
            assertEquals("add_diaper", parse("add_diaper?kind=$kind")!!["action"])
            assertEquals(kind, parse("add_diaper?kind=$kind")!!["kind"])
        }
        assertEquals("both", parse("add_diaper?kind=wet%20and%20dirty")!!["kind"])
        assertEquals("wet", parse("wet_diaper")!!["kind"])
    }

    @Test fun missingOrUnknownDiaperAndSideDetailsOpenFormsWithoutGuessing() {
        assertEquals("open_diaper", parse("add_diaper")!!["action"])
        assertEquals("open_diaper", parse("add_diaper?kind=unknown")!!["action"])
        assertEquals("open_nursing", parse("nursing")!!["action"])
        assertEquals("open_nursing", parse("nursing?side=unknown")!!["action"])
        assertEquals("nursing_left", parse("nursing?side=left%20side")!!["action"])
        assertEquals("nursing_right", parse("nursing?side=right")!!["action"])
    }

    @Test fun timerStartAndFinishRoutesPreserveTheirIdentities() {
        for (action in listOf("sleep", "pumping", "nursing_left", "nursing_right", "finish_sleep", "finish_nursing")) {
            assertEquals(action, parse(action)!!["action"])
        }
        assertEquals("review_pumping", parse("finish_pumping")!!["action"])
        assertEquals("review_pumping", parse("finish_pumping?amount=90")!!["action"])
    }

    @Test fun historyQueriesCannotBecomeWritesOrAcceptExtraParameters() {
        val actions = setOf("last_diaper", "last_wet_diaper", "last_dirty_diaper", "last_feed",
            "last_bottle", "last_nursing", "last_solids", "last_sleep", "last_wake", "last_pumping", "sleep_status")
        assertEquals(actions, AssistantIntentParser.historyQueries)
        for (action in actions) {
            assertEquals(mapOf("action" to action), parse(action))
            assertNull(parse("$action?kind=wet"))
            assertNull(parse("$action?amount=90"))
        }
        assertNull(parse("last_unknown"))
    }

    @Test fun pumpingCarriesDecimalAmountAndExplicitUnits() {
        val ounces = parse("finish_pumping?amount=2.5&unit=US%20fluid%20ounces")!!
        assertEquals("finish_pumping", ounces["action"])
        assertEquals(2.5, ounces["amount"])
        assertEquals("oz", ounces["unit"])
        assertEquals("ml", parse("finish_pumping?amount=90&unit=milliliters")!!["unit"])
        assertNull(parse("finish_pumping?amount=unknown&unit=ml"))
        assertNull(parse("finish_pumping?amount=Infinity&unit=ml"))
        assertNull(parse("finish_pumping?amount=90&unit=unknown"))
    }

    @Test fun unrelatedLinksMalformedRoutesAndAmbiguousParametersAreRejected() {
        assertNull(AssistantIntentParser.parse(Intent(Intent.ACTION_VIEW, Uri.parse("littlelog://join?file=example"))))
        assertNull(AssistantIntentParser.parse(Intent(Intent.ACTION_VIEW, Uri.parse("https://voice/sleep"))))
        assertNull(parse("delete_all"))
        assertNull(parse("sleep/extra"))
        assertNull(parse("add_diaper?kind=wet&kind=dirty"))
        assertNull(parse("sleep?amount=90"))
        assertNull(parse("sleep#unexpected"))
    }

    @Test fun coldLaunchIsQueuedAndDuplicateIntentCompletesOnce() {
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            val sent = mutableListOf<Pair<String, Any>>()
            val bridge = AndroidAssistantBridge { method, value -> sent.add(method to value) }
            val launch = intent("add_diaper?kind=wet")
            bridge.receive(launch)
            bridge.receive(launch)
            assertTrue(sent.isEmpty())
            val packet = bridge.startListening().single()
            assertEquals("add_diaper", packet["action"])
            assertEquals("wet", packet["kind"])
            assertTrue((packet["deadline"] as Long) > (packet["at"] as Long))
            val id = packet["id"] as String
            assertTrue(bridge.complete(id))
            assertFalse(bridge.complete(id))
            bridge.receive(launch)
            assertTrue(bridge.startListening().isEmpty())
            bridge.dispose()
        }
    }

    @Test fun warmRequestsAreDeliveredAndSeparateInvocationsRemainSeparate() {
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            val sent = mutableListOf<Pair<String, Any>>()
            val bridge = AndroidAssistantBridge { method, value -> sent.add(method to value) }
            assertTrue(bridge.startListening().isEmpty())
            bridge.receive(intent("pumping"))
            bridge.receive(intent("pumping"))
            assertEquals(2, sent.size)
            assertTrue(sent.all { it.first == "received" })
            val queued = bridge.startListening()
            assertEquals(2, queued.map { it["id"] }.toSet().size)
            bridge.dispose()
            assertEquals(2, sent.count { it.first == "cancelled" })
            assertTrue(bridge.startListening().isEmpty())
        }
    }

    @Test fun nativeTimeoutCancelsAndRemovesThePendingRequest() {
        val cancelled = CountDownLatch(1)
        lateinit var bridge: AndroidAssistantBridge
        lateinit var id: String
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            bridge = AndroidAssistantBridge { method, value ->
                if (method == "cancelled" && value == id) cancelled.countDown()
            }
            bridge.receive(intent("sleep"))
            id = bridge.startListening().single()["id"] as String
        }
        assertTrue("The native deadline must cancel a stalled request", cancelled.await(25, TimeUnit.SECONDS))
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            assertTrue(bridge.startListening().isEmpty())
            assertFalse(bridge.complete(id))
            bridge.dispose()
        }
    }
}
