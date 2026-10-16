package app.littlelog.little_log

import android.util.Base64
import android.accounts.Account
import android.app.Activity
import android.app.AlertDialog
import android.app.KeyguardManager
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.Toast
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.AuthorizationResult
import com.google.android.gms.common.api.Scope
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyFactory
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private var liveTimerChannel: MethodChannel? = null
    private var assistantChannel: MethodChannel? = null
    private var historySpeech: HistorySpeech? = null
    private var historySpeechAllowed = false
    private val externalConfirmation by lazy { ExternalActionConfirmation(this) }
    private val assistantBridge = AndroidAssistantBridge { method, value ->
        assistantChannel?.invokeMethod(method, value)
    }
    private var quickActionChannel: MethodChannel? = null
    private var quickActionListenerReady = false
    private var pendingQuickAction: String? = null
    private val quickActions = setOf("diaper", "nursing_left", "nursing_right", "sleep")
    private var invitationChannel: MethodChannel? = null
    private var invitationListenerReady = false
    private var pendingInvitationLink: String? = null
    private var pickerResult: MethodChannel.Result? = null
    private var requestedFileId: String? = null
    private val pickerRequestCode = 4712

    override fun onCreate(savedInstanceState: Bundle?) {
        pendingInvitationLink = invitationLink(intent)
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) receiveExternalAction(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        receiveExternalAction(intent)
        val link = invitationLink(intent) ?: return
        if (invitationListenerReady) {
            invitationChannel?.invokeMethod("received", link)
        } else {
            pendingInvitationLink = link
        }
    }

    override fun onDestroy() {
        externalConfirmation.onStop()
        LiveTimers.changed = null
        liveTimerChannel?.setMethodCallHandler(null)
        historySpeech?.dispose()
        assistantBridge.dispose()
        super.onDestroy()
    }

    override fun onStop() {
        externalConfirmation.onStop()
        historySpeechAllowed = false
        historySpeech?.stop()
        super.onStop()
    }

    override fun onPause() {
        historySpeechAllowed = false
        historySpeech?.stop()
        externalConfirmation.onPause()
        super.onPause()
    }

    override fun onUserLeaveHint() {
        externalConfirmation.onStop()
        super.onUserLeaveHint()
    }

    override fun onResume() {
        super.onResume()
        historySpeechAllowed = true
        externalConfirmation.onResume()
    }

    private fun receiveExternalAction(source: Intent?) {
        val fields = AssistantIntentParser.parse(source)
        if (fields != null) {
            val action = fields["action"] as String
            val approved = Intent(source).apply { removeExtra("app.littlelog.assistant.request_id") }
            externalConfirmation.request(externalActionTitle(action, fields["kind"] as? String,
                fields["amount"] as? Number, fields["unit"] as? String),
                readAloud = action in AssistantIntentParser.historyQueries) {
                assistantBridge.receive(approved)
            }
            return
        }
        quickAction(source)?.let { action ->
            externalConfirmation.request(externalActionTitle(action)) {
                if (quickActionListenerReady) quickActionChannel?.invokeMethod("received", action)
                else pendingQuickAction = action
            }
            return
        }
        // Existing notification intents from older builds still work after
        // confirmation. New notifications target the non-exported activity.
        if (source?.action == LiveTimers.ACTION) {
            val approved = Intent(source)
            externalConfirmation.request("Update this timer?") {
                LiveTimers(applicationContext).receive(approved)
            }
        }
    }

    private fun quickAction(intent: Intent?): String? {
        val raw = intent?.action ?: return null
        if (!raw.startsWith("app.littlelog.quick.")) return null
        val action = raw.removePrefix("app.littlelog.quick.")
        return if (action in quickActions) action else null
    }

    private fun invitationLink(intent: Intent?): String? {
        val uri = intent?.data ?: return null
        return if (intent.action == Intent.ACTION_VIEW &&
            uri.scheme == "littlelog" && uri.host == "join") uri.toString() else null
    }

    private fun finishPicker(value: AuthorizationResult, chooserWasShown: Boolean) {
        val ids = value.tokenResponseParams?.getString("picked_file_ids")?.split(",") ?: emptyList()
        val id = ids.firstOrNull { it.isNotBlank() }
        if (id == null && !chooserWasShown) {
            // Older Play services can ignore the picker request and return a
            // cached token. This is not cancellation: no picker was displayed.
            pickerResult?.error("picker_unavailable", "Google did not open the file chooser. Update Google Play services, then try Find shared log again.", null)
            AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Light_Dialog_Alert)
                .setTitle("Update Google Play services")
                .setMessage("Update Google Play services to choose a shared log. Your existing logs and entries stay saved.")
                .setNegativeButton("Not now", null)
                .setPositiveButton("Check for update") { _, _ ->
                    val market = Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=com.google.android.gms"))
                    try { startActivity(market) }
                    catch (_: android.content.ActivityNotFoundException) {
                        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=com.google.android.gms")))
                    }
                }.show()
        } else if (id == null) {
            pickerResult?.error("picker_empty", "No log was selected. Choose the shared Little Log file in Google Drive.", null)
        } else if (requestedFileId != null && id != requestedFileId) {
            pickerResult?.error("picker_wrong_file", "That is a different Drive file. Open the invitation link from the sender and try again.", null)
        } else if (value.accessToken.isNullOrBlank()) {
            pickerResult?.error("picker_token", "Google could not finish granting access. Please try again.", null)
        } else {
            pickerResult?.success(mapOf("fileId" to id, "accessToken" to value.accessToken))
        }
        pickerResult = null
        requestedFileId = null
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 4720) LiveTimers(applicationContext).refresh()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickerRequestCode) return
        if (resultCode != Activity.RESULT_OK) {
            pickerResult?.success(null)
            pickerResult = null
            requestedFileId = null
            return
        }
        try { finishPicker(Identity.getAuthorizationClient(this).getAuthorizationResultFromIntent(data), chooserWasShown = true) }
        catch (_: Exception) {
            pickerResult?.error("picker_failed", "Google could not open the selected log. Please try again.", null)
            pickerResult = null
            requestedFileId = null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val live = LiveTimers(applicationContext)
        liveTimerChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "little_log/live_activity")
        LiveTimers.changed = { liveTimerChannel?.invokeMethod("stopped", null) }
        liveTimerChannel!!.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "update" -> {
                        @Suppress("UNCHECKED_CAST")
                        val sessions = call.arguments as? List<Map<String, Any?>> ?: emptyList()
                        live.update(sessions)
                        val preferences = getSharedPreferences("live-timer-permission", MODE_PRIVATE)
                        if (sessions.isNotEmpty() && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED && !preferences.getBoolean("requested", false)) {
                            preferences.edit().putBoolean("requested", true).apply()
                            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 4720)
                        }
                        result.success(null)
                    }
                    "pendingStops" -> result.success(live.pending())
                    "acknowledgeStop" -> { live.acknowledge(call.arguments as String); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) { result.error("live_timer_storage", "Could not update live timers. Your sessions remain saved.", null) }
        }
        assistantChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.littlelog/assistant")
        assistantChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "listen" -> result.success(assistantBridge.startListening())
                "complete" -> {
                    val id = call.argument<String>("id")
                    val handled = id != null && assistantBridge.complete(id)
                    if (handled) {
                        val error = call.argument<String>("error")
                        val message = error ?: call.argument<String>("message")
                        if (!message.isNullOrBlank()) Toast.makeText(this, message,
                            if (error != null) Toast.LENGTH_LONG else Toast.LENGTH_SHORT).show()
                        val keyguard = getSystemService(KeyguardManager::class.java)
                        if (!message.isNullOrBlank() && call.argument<Boolean>("query") == true && historySpeechAllowed &&
                            !keyguard.isDeviceLocked && !keyguard.isKeyguardLocked && !isFinishing && !isDestroyed) {
                            // Speech-engine availability must not fail a valid history answer.
                            runCatching {
                                val speech = historySpeech ?: HistorySpeech(this).also { historySpeech = it }
                                speech.speak(message)
                            }
                        }
                    }
                    result.success(handled)
                }
                else -> result.notImplemented()
            }
        }
        quickActionChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.littlelog/quick_actions")
        quickActionChannel!!.setMethodCallHandler { call, result ->
            if (call.method == "listen") {
                quickActionListenerReady = true
                result.success(pendingQuickAction)
                pendingQuickAction = null
            } else result.notImplemented()
        }
        invitationChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.littlelog/invitation")
        invitationChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "listen" -> {
                    invitationListenerReady = true
                    result.success(pendingInvitationLink)
                    pendingInvitationLink = null
                }
                "share" -> {
                    val message = call.argument<String>("message")
                    if (message.isNullOrBlank()) {
                        result.error("share_empty", "There is no invitation to share.", null)
                    } else {
                        val share = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, message)
                        }
                        startActivity(Intent.createChooser(share, "Send Little Log invitation"))
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.littlelog/picker")
            .setMethodCallHandler { call, result ->
                if (call.method != "pickFamily") { result.notImplemented(); return@setMethodCallHandler }
                if (pickerResult != null) { result.error("busy", "Google Drive is already open.", null); return@setMethodCallHandler }
                val email = call.argument<String>("email")
                if (email.isNullOrBlank()) { result.error("account", "Sign in first.", null); return@setMethodCallHandler }
                pickerResult = result
                requestedFileId = call.argument<String>("fileId")
                val request = AuthorizationRequest.builder()
                    .setAccount(Account(email, "com.google"))
                    .setRequestedScopes(listOf(Scope("https://www.googleapis.com/auth/drive.file")))
                    .setOptOutIncludingGrantedScopes(true)
                    .setPrompt(AuthorizationRequest.Prompt.CONSENT)
                    .addResourceParameter(AuthorizationRequest.ResourceParameter.PICKER_OAUTH_TRIGGER, "true")
                    .addResourceParameter(AuthorizationRequest.ResourceParameter.PICKER_ALLOW_MULTIPLE, "false")
                    .addResourceParameter(AuthorizationRequest.ResourceParameter.PICKER_MIMETYPES, "text/csv,application/csv")
                    .apply {
                        requestedFileId?.let {
                            addResourceParameter(AuthorizationRequest.ResourceParameter.PICKER_FILE_IDS, it)
                        }
                    }
                    .build()
                Identity.getAuthorizationClient(this).authorize(request)
                    .addOnSuccessListener { authorization ->
                        try {
                            if (authorization.hasResolution()) {
                                startIntentSenderForResult(authorization.pendingIntent!!.intentSender, pickerRequestCode, null, 0, 0, 0)
                            } else { finishPicker(authorization, chooserWasShown = false) }
                        } catch (_: Exception) {
                            pickerResult?.error("picker_failed", "Google Drive could not be opened. Please try again.", null)
                            pickerResult = null
                            requestedFileId = null
                        }
                    }
                    .addOnFailureListener {
                        pickerResult?.error("picker_failed", "Google Drive could not be opened. Please try again.", null)
                        pickerResult = null
                        requestedFileId = null
                    }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "little_log/play_billing")
            .setMethodCallHandler { call, result ->
                if (call.method != "verify") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val valid = try {
                    val data = call.argument<String>("data") ?: ""
                    val key = call.argument<String>("publicKey") ?: ""
                    val signature = call.argument<String>("signature") ?: ""
                    val product = call.argument<String>("productId") ?: ""
                    val token = call.argument<String>("token") ?: ""
                    val publicKey = KeyFactory.getInstance("RSA").generatePublic(
                        X509EncodedKeySpec(Base64.decode(key, Base64.DEFAULT)))
                    val verifier = Signature.getInstance("SHA1withRSA")
                    verifier.initVerify(publicKey)
                    verifier.update(data.toByteArray(Charsets.UTF_8))
                    val signed = verifier.verify(Base64.decode(signature, Base64.DEFAULT))
                    val receipt = JSONObject(data)
                    signed && product.isNotEmpty() && token.isNotEmpty() &&
                        receipt.optString("packageName") == packageName &&
                        receipt.optString("productId") == product &&
                        receipt.optString("purchaseToken", receipt.optString("token")) == token &&
                        receipt.optInt("purchaseState", -1) == 0
                } catch (_: Exception) { false }
                result.success(valid)
            }
    }
}
