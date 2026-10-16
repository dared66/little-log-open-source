# Android voice actions and Gemini recheck

Android uses the same care-action dispatcher as Siri. It has App Actions capability declarations, en-US query patterns, an `OPEN_APP_FEATURE` inventory, and native `littlelog://voice/` entry points.

External voice links and launcher commands require confirmation in the unlocked, foreground app before they can change records or read history. Intent extras and referrers cannot bypass confirmation. Cancelling or leaving the app discards an unapproved request.

These are declared Android fulfillment routes. They do not establish that Gemini recognizes or invokes them. Google documents Play publication and App Actions review for Assistant discovery; Gemini recognition needs a separate device check.

Try explicit app invocations such as:

- “Hey Google, open Little Log and add a wet diaper.”
- “Hey Google, open Little Log and start nursing on the left side.”
- “Hey Google, open Little Log and start sleep.”
- “Hey Google, open Little Log and finish sleep.”
- “Hey Google, open Little Log and finish nursing.”
- “Hey Google, open Little Log and start pumping.”
- “Hey Google, open Little Log and finish pumping with 90 milliliters.”

Diaper types include wet, dirty, wet and dirty, and dry. Nursing supports left and right. Start commands preserve an existing active timer. Finish commands save the current timer. Pumping requires both an amount and units (ml or US fluid ounces).

Missing diaper type or nursing side opens the matching form. Finishing pumping without amount and units opens the pumping review; its durable timer remains until a valid save. Confirmation and errors appear in the app. Android intent fulfillment does not provide Siri's spoken response or parameter conversation.

## History questions

Use “Hey Google, open Little Log and…” with these questions:

- “When was the last diaper?”
- “When was the last wet diaper?”
- “When was the last dirty diaper?”
- “When was the last feed?”
- “When was the last bottle?”
- “When was the last nursing session?”
- “When were solids last logged?”
- “When was the last pumping session?”
- “When did the last sleep start?”
- “When did my baby last wake up?”
- “Is my baby asleep?”

Additional registered phrases include “When was my baby last fed,” “When did
my baby last eat,” “When did my baby last fall asleep,” “How long has my baby
been awake,” “How long has my baby been asleep,” and “How long since the last
[diaper / wet diaper / dirty diaper / feed / bottle / nursing session / pumping session].”

These eleven read-only routes use the same answer service as Siri. Answers name
the selected baby and give local time/date and elapsed time. Feed combines
bottle, nursing and solids; wet/dirty includes combined diapers. Wake-up uses
an explicitly recorded sleep end. Active timers and missing history are reported
honestly, without inferring awake/asleep behavior or changing any timers or logs.

After you choose **Read aloud**, Little Log shows the complete answer in a dialog
and reads it through the device's English text-to-speech engine when available. Speech stops when the
app leaves the screen. This is app speech, not an Assistant-provided dialog;
ordinary logging commands retain their existing behavior. Discovery requires
Assistant App Actions support, en-US, Play registration/review, and a device
recognition check. Gemini invocation has not been verified.

Query routes include `littlelog://voice/last_diaper`, `last_feed`, `last_wake`,
and `sleep_status`; the complete list is in `assistant_history.dart`.
Sources: [custom intents](https://developer.android.com/develop/devices/assistant/custom-intents),
[Android text-to-speech](https://developer.android.com/reference/android/speech/tts/TextToSpeech).

The icon long-press menu remains Diaper, Nursing left, Nursing right, and Sleep. Additional voice inventory entries have no launcher intent, label, or icon.

## Isolate recognition from fulfillment

Native routes can be tested on an emulator without invoking Gemini:

```sh
adb -s <disposable-emulator-id> shell am start -a android.intent.action.VIEW \
  -d 'littlelog://voice/add_diaper?kind=wet' \
  -n app.littlelog.little_log/.MainActivity

adb -s <disposable-emulator-id> shell am start -a android.intent.action.VIEW \
  -d 'littlelog://voice/finish_pumping?amount=90&unit=ml' \
  -n app.littlelog.little_log/.MainActivity
```

Run logging commands only against synthetic emulator data. `tool/voice_action_review.dart` supplies an isolated in-memory baby log. Native `AssistantActionsTest` checks parsing and request delivery, and `VoiceEntryPointsTest` exercises the actual native-to-Flutter save paths. `ExternalActionSecurityTest` checks cancellation, spoofed trust fields, request replacement, backgrounding, history consent and protected notification components. These UI tests require the harness build and the `isolatedVoiceQa=true` instrumentation argument.

Run `tool/run_android_voice_actions.sh <disposable-emulator-id>` to build the isolated harness and check parsing, cold/warm saves, launcher delivery, and timeout cleanup. Use a disposable emulator only; the shared review emulator is rejected. This command leaves the synthetic QA harness on the disposable device.

Sources: [App Actions setup](https://developer.android.com/develop/devices/assistant/get-started), [capability schema](https://developer.android.com/develop/devices/assistant/action-schema), [custom intents and query patterns](https://developer.android.com/develop/devices/assistant/custom-intents).

New notification timer actions use immutable PendingIntents targeting non-exported components. Legacy timer intents delivered to the exported activity require confirmation; no stored timer schema changes.
