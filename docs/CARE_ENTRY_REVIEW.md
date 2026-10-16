# Bottle, nursing and diaper entry review

## Problems corrected

- Choosing Bottle opened a generic feeding form with a Nursing switch. Replaced it with a dedicated Bottle entry; manual nursing has its own form and remains accessible from Nursing → Add a past nursing session. Buttons now say Save bottle or Save nursing.
- Diapers previously stored only Wet/Dirty/Both/Dry and notes. Dirty and Both now expose poop color, consistency and blowout. Rash is available for every diaper type.
- Detailed observations now appear under the activity title in the shared record component used by Today and History. They are structured fields in local storage, CSV sync and JSON export.
- Forms capture their child when opened. Saving after a child change fails with an actionable message instead of recording under the new child. This correction also covers the other activity forms.
- Bottle/nursing timestamps are checked at the controller boundary, not only by the form.

## Field behavior

| Field | Options | Default |
| --- | --- | --- |
| Contents | Wet, Dirty, Both, Dry | Wet |
| Poop color | Yellow, Mustard, Orange, Green, Brown, Black, Red, White, Gray, Other | Not recorded |
| Consistency | Watery, Loose, Seedy, Mushy, Pasty, Formed, Hard / pellets, Mucousy, Other | Not recorded |
| Blowout | Yes, No, Not recorded | Not recorded |
| Diaper rash | Yes, No, Not recorded | Not recorded |
| Time | Date and time | Now |
| Notes | Optional text, up to 2,000 characters | Empty |

Color, consistency and blowout apply to Dirty/Both. Switching to Wet/Dry clears these fields to prevent stale observations from being saved. Rash and notes are independent. Switching Dirty ↔ Both preserves poop observations. Selecting Not recorded clears that observation. Existing records have no inferred observations.

## Verification scope

Automated coverage exercises every color/consistency combination through JSON and CSV; explicit false versus missing values; invalid payloads; old records; persistent database reopen; export; conditional-write retry after a lost response; and retrieval by a second simulated caregiver. Phone tests use the real entry points and verify saved types, Today/History rendering, clearing of incompatible details, the original-child guard, and 320-pixel screens with 180% text and keyboard space.

The review used synthetic widget renders kept outside the repository. They are
not live browser, Google Drive or physical-device verification. Existing
live-sharing acceptance work remains open.

## Results

- Full regression suite: 58 tests passed; static analysis clean.
- Five real-widget review images generated and visually inspected for the bottle, nursing, expanded diaper, selected observations and saved-record states.
- The large-text test exposed an existing Quick log heading overflow, which is corrected with a wrapping layout.
- Configured web, Android debug and unsigned iPhone builds completed. No physical-device installation performed.
