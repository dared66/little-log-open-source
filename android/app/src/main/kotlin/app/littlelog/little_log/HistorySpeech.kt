package app.littlelog.little_log

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import java.util.Locale

/** App Actions launch the app; Little Log reads history answers locally. */
class HistorySpeech(context: Context) {
    private val handler = Handler(Looper.getMainLooper())
    private var engine: TextToSpeech? = null
    private var ready = false
    private var unavailable = false
    private var disposed = false
    private var pending: String? = null

    init {
        engine = TextToSpeech(context.applicationContext) { status ->
            handler.post {
                if (disposed) return@post
                val language = if (status == TextToSpeech.SUCCESS) engine?.setLanguage(Locale.US) else null
                ready = language != null && language >= TextToSpeech.LANG_AVAILABLE
                unavailable = !ready
                val answer = pending
                pending = null
                if (ready && answer != null) speak(answer)
            }
        }
    }

    fun speak(answer: String) {
        if (disposed || unavailable) return
        if (!ready) { pending = answer; return }
        engine?.speak(answer, TextToSpeech.QUEUE_FLUSH, null, "littlelog-history")
    }

    fun stop() { pending = null; engine?.stop() }
    fun dispose() {
        disposed = true
        stop()
        engine?.shutdown()
        engine = null
    }
}
