# Siri and Shortcuts

Available on iOS 16 and later. Little Log opens to run the command, and the device may need to be unlocked. Actions use the baby currently selected in the app. Siri's confirmation names that baby.

Say:

- “Hey Siri, add a wet diaper in Little Log.”
- “Hey Siri, add a dirty diaper in Little Log.”
- “Hey Siri, add a wet and dirty diaper in Little Log.”
- “Hey Siri, add a dry diaper in Little Log.”
- “Hey Siri, start nursing on the left side in Little Log.”
- “Hey Siri, start nursing on the right side in Little Log.”
- “Hey Siri, start sleep in Little Log.”
- “Hey Siri, finish sleep in Little Log.”
- “Hey Siri, finish nursing in Little Log.”
- “Hey Siri, start pumping in Little Log.”
- “Hey Siri, finish pumping in Little Log.”

“Log” and “Record” also work for the registered diaper phrases. “Start a nap in Little Log” is another sleep phrase. If a diaper type or nursing side is omitted, Siri asks for it.

Diapers are saved at the time of the request, without opening an entry form. Siri confirms after the local save; Google Drive sync follows the usual app behavior. These commands do not support spoken backdated entries.

For pumping, Siri asks for the pumped amount and whether it is in milliliters or US fluid ounces before saving. “Stop” and “End” also work for the registered finish phrases. Finishing sleep or nursing saves the active timer immediately.

An active nursing, sleep, or pumping timer continues unchanged, and Siri reports that it is already running. Starting nursing from a paused session resumes the requested side without discarding accumulated time.

The same actions are available in Apple's Shortcuts app. Create a personal shortcut named “Add a wet diaper” with the **Add a diaper** action set to **wet** to use that shorter phrase without saying the app name.

The phone home-screen diaper shortcut continues to open the diaper form. Siri's direct-save action is separate.

## History questions

Queries use the selected baby and never add or change a record. Siri speaks
the answer; Little Log also displays it. Examples:

- “Hey Siri, when was the last diaper in Little Log?”
- “Hey Siri, when was the last wet diaper in Little Log?”
- “Hey Siri, when was the last dirty diaper in Little Log?”
- “Hey Siri, when was the last feed in Little Log?”
- “Hey Siri, when was the last bottle in Little Log?”
- “Hey Siri, when was the last nursing session in Little Log?”
- “Hey Siri, when was the last solids meal in Little Log?”
- “Hey Siri, when was the last pumping session in Little Log?”
- “Hey Siri, when was the last sleep in Little Log?”
- “Hey Siri, when did my baby last wake up in Little Log?”
- “Hey Siri, is my baby asleep in Little Log?”

“How long since the last [activity] in Little Log” works for the same activity
choices. “When was my baby last fed,” “When did my baby last eat,” “How long
has my baby been awake,” and “How long has my baby been asleep” are also
registered with “in Little Log.” The **Last activity** Shortcuts action lets
you choose the activity; **Last wake-up** and **Sleep status** are separate actions.

Answers include the baby's name, local time/date and elapsed time. Feed includes
bottle, nursing and solids. Wet/dirty queries include wet-and-dirty diapers.
Timed activities report their start, including an active or paused session.
Wake-up uses the latest explicitly recorded sleep end; duration-only entries
do not supply a precise wake time. Sleep status reports the active timer,
and does not infer that the baby is awake when no timer exists. Missing history
is reported explicitly. Older history is not limited to a one-day cutoff.

The provider has ten shortcuts total, preserving the seven care shortcuts.
Source: [Apple App Shortcuts](https://developer.apple.com/design/human-interface-guidelines/app-shortcuts).
