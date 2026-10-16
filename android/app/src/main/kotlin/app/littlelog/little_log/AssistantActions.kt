package app.littlelog.little_log

import android.content.Intent
import android.os.Handler
import android.os.Looper
import java.util.UUID

/** Parses explicit App Actions fulfillments, without guessing omitted fields. */
object AssistantIntentParser {
    val historyQueries = setOf(
        "last_diaper", "last_wet_diaper", "last_dirty_diaper", "last_feed",
        "last_bottle", "last_nursing", "last_solids", "last_sleep", "last_wake",
        "last_pumping", "sleep_status"
    )
    fun parse(intent: Intent?): Map<String, Any>? {
        if (intent?.action != Intent.ACTION_VIEW) return null
        val uri = intent.data ?: return null
        if (uri.scheme != "littlelog" || uri.authority != "voice" || uri.fragment != null) return null
        val route = uri.path?.removePrefix("/") ?: return null
        if (route.isBlank() || route.contains('/')) return null
        val allowedKeys = when (route) {
            "add_diaper" -> setOf("kind")
            "nursing" -> setOf("side")
            "finish_pumping" -> setOf("amount", "unit")
            else -> emptySet()
        }
        if (!allowedKeys.containsAll(uri.queryParameterNames) ||
            uri.queryParameterNames.any { uri.getQueryParameters(it).size != 1 }) return null
        fun value(key: String) = uri.getQueryParameter(key)?.trim()?.takeIf { it.isNotEmpty() }
        fun normalize(value: String?) = value?.lowercase(java.util.Locale.US)
            ?.replace("&", "and")?.replace(Regex("\\s+"), " ")
        fun diaper(kind: String) = mapOf<String, Any>("action" to "add_diaper", "kind" to kind)
        if (route in historyQueries) return mapOf("action" to route)
        return when (route) {
            "diaper", "open_diaper" -> mapOf("action" to "open_diaper")
            "wet_diaper" -> diaper("wet")
            "dirty_diaper" -> diaper("dirty")
            "both_diaper" -> diaper("both")
            "dry_diaper" -> diaper("dry")
            "add_diaper" -> when (normalize(value("kind"))) {
                "wet", "pee" -> diaper("wet")
                "dirty", "poopy", "poop", "soiled" -> diaper("dirty")
                "both", "wet and dirty", "wet and poopy" -> diaper("both")
                "dry" -> diaper("dry")
                else -> mapOf("action" to "open_diaper")
            }
            "nursing", "open_nursing" -> when (normalize(value("side"))) {
                "left", "left side" -> mapOf("action" to "nursing_left")
                "right", "right side" -> mapOf("action" to "nursing_right")
                else -> mapOf("action" to "open_nursing")
            }
            "nursing_left", "nursing_right", "sleep", "pumping", "finish_sleep", "finish_nursing", "review_pumping" -> mapOf("action" to route)
            "finish_pumping" -> {
                val amount = value("amount")
                val unit = value("unit")
                if (amount == null || unit == null) return mapOf("action" to "review_pumping")
                val number = amount.toDoubleOrNull()?.takeIf { it.isFinite() } ?: return null
                val normalizedUnit = when (normalize(unit)) {
                    "ml", "milliliter", "milliliters", "millilitre", "millilitres" -> "ml"
                    "oz", "ounce", "ounces", "fl oz", "fluid ounce", "fluid ounces", "us fluid ounces" -> "oz"
                    else -> return null
                }
                mapOf("action" to "finish_pumping", "amount" to number, "unit" to normalizedUnit)
            }
            else -> null
        }
    }
}

/** Queues cold launches and deduplicates repeat delivery of the same Intent. */
class AndroidAssistantBridge(private val send: (String, Any) -> Unit) {
    private val handler = Handler(Looper.getMainLooper())
    private val pending = linkedMapOf<String, Map<String, Any>>()
    private val timeouts = mutableMapOf<String, Runnable>()
    private val completed = linkedSetOf<String>()
    private var listening = false
    private val requestIdKey = "app.littlelog.assistant.request_id"

    fun receive(intent: Intent?) {
        val fields = AssistantIntentParser.parse(intent) ?: return
        val id = intent?.getStringExtra(requestIdKey) ?: UUID.randomUUID().toString()
        if (id in pending || id in completed) return
        intent?.putExtra(requestIdKey, id)
        val at = System.currentTimeMillis()
        val payload = fields + mapOf("id" to id, "at" to at, "deadline" to at + 15_000L)
        pending[id] = payload
        val timeout = Runnable {
            if (complete(id)) send("cancelled", id)
        }
        timeouts[id] = timeout
        handler.postDelayed(timeout, 20_000L)
        if (listening) send("received", payload)
    }

    fun startListening(): List<Map<String, Any>> {
        listening = true
        return pending.values.toList()
    }

    fun complete(id: String): Boolean {
        if (pending.remove(id) == null) return false
        timeouts.remove(id)?.let { handler.removeCallbacks(it) }
        completed.add(id)
        if (completed.size > 64) completed.remove(completed.first())
        return true
    }

    fun dispose() {
        pending.keys.toList().forEach { id ->
            if (complete(id)) send("cancelled", id)
        }
        listening = false
    }
}
