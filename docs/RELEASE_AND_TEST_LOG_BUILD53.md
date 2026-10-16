# Little Log release and test log since build 50

This release brings a unified Log screen, broader Nara Baby imports, dark mode,
home-screen shortcuts, assistant actions, and spacing improvements across the
app. It covers changes since **1.0.0 build 50**, the last build received by both
Family beta and Reddit Beta users on October 8, 2026.

**Build 53 is available to Owner testing only.** Family beta and Reddit Beta
users remain on build 50. These notes capture the changes through build 53 for
the next broader release.

## Release scope

| Group | Latest assigned build | Status verified |
| --- | --- | --- |
| Family beta | 50 | Last shared release |
| Reddit Beta users | 50 | Last shared release |
| Owner testing | 53 | Internal only, in beta testing, one existing tester |

The comparison runs from build 50 source `c82bef0` to build 53 source `09912d3`,
preserved by tag `testflight-build53`. Builds 51 and 52 were owner releases.
Development has advanced to build 54, with the normal app installed and running
on both simulators.

## Release notes

### Log navigation and summaries

- **Today and History share one Log tab.** Choose a date from the header to see
  that day's entries and totals; Back to today returns to the current day.
- **View all exposes the activity filter.** The selected date and filter remain
  available when moving between Log and Settings.
- **At a glance is customizable.** Choose Nursing, Bottle, Diapers, Sleep and
  Pumped independently of Quick log. Selected metrics stay visible when their
  value is zero, and the choice is saved on this device.
- **Activity rows are easier to scan.** Category badges, titles, timestamps and
  expanded details share consistent alignment. The most recent entry in each
  category shows elapsed time, and equal-time entries have a consistent order.
- **Swipe actions are easier to discover.** Edit and Delete have clearer labels.
  An occasional demonstration stops after the user performs a swipe action.

### Dark mode and home-screen shortcuts

- **Settings → Appearance offers System, Light and Dark.** The preference
  survives relaunch. Activity colors retain their identity in both appearances,
  including each baby's selected background.
- **Long-press the phone's Little Log icon** to open Log diaper, Start nursing
  left, Start nursing right or Start sleep. The diaper shortcut opens the form;
  timer shortcuts start a durable session or open the session already running.
  Pumping is available through the app and assistant actions.

### Siri and Android assistant actions

- **Siri and Shortcuts actions on iOS 16 and later** cover wet, dirty, wet and
  dirty, and dry diapers; nursing on either side; and starting or finishing
  nursing, sleep and pumping. Pumping completion requires an amount and ml or
  US fluid ounces. Actions use the baby selected in Little Log.
- **Timer starts preserve an existing running session.** Paused nursing can
  resume on the requested side without losing accumulated time.
- **Assistant confirmations follow the local save.** A failed nursing write
  now returns an error instead of incorrectly confirming success. Requests
  also have duplicate-delivery, cancellation, timeout and baby-selection guards.
- **Android has matching care-action fulfillment routes.** Missing diaper or
  nursing details open the relevant form. Missing pumping amount or units open
  review while keeping the timer. Actual Gemini discovery and spoken invocation
  still require device acceptance; these routes are implemented and tested.

Registered request examples include “Add a wet diaper in Little Log,”
“Start nursing on the left side in Little Log,” “Start sleep in Little Log,”
and “Finish pumping in Little Log.” Spoken Siri recognition and parameter
conversations remain part of the tester pass below. Details are in
[Siri and Shortcuts](SIRI.md) and [Android voice actions](ANDROID_VOICE.md).

### Expanded Nara Baby import

- **CSV coverage now spans all ten Little Log activity categories and the baby
  profile.** This adds combo feeds, solids, growth, medical records, vaccines,
  routines and firsts/milestones to the earlier care mappings.
- **Compound rows become separate usable entries.** Combo feeds split into
  nursing and bottle records; multiple measurements, foods, medicines or
  vaccines split into individual records with stable identities.
- **Original information stays attached to imported records.** Source rows,
  notes, caregiver details and units are retained through edits, backups and
  sync. Missing doses or end times are not invented.
- **Exclusions remain visible before saving.** Open sleep records and ambiguous
  compound records require explicit supported-only consent. Unassigned pumping
  entries have a separate inclusion control. Parent and pregnancy profiles,
  mismatched babies, invalid values and conflicting source groups are rejected.
- **Reimport and recovery cover the expanded mappings.** Repeated imports do
  not duplicate entries or silently resurrect removed records. Removing Nara
  imports and undo preserve manual history and reject conflicting later edits.

The observed child fixture contains 23 source activities and produces 30 Little
Log activities, or 32 when both unassigned pumps are included, plus the profile.
The higher count comes from split records. See
[Nara Baby file import](IMPORT_MIGRATION.md) for mapping details.

### Spacing, account safety and purchase recovery

- **Android spacing was reviewed across the app.** Onboarding, Log/history,
  activity selection, all ten entry and edit forms, timers, settings pages,
  baby management, imports and dialogs were inspected with synthetic data.
- **Headers, cards and controls use consistent content edges.** Standalone
  pages share a bounded frame; short pages begin below the header; long page
  titles grow with accessibility text. The activity chooser's extra inset and
  mismatched onboarding edges are corrected.
- **Google account changes invalidate stale authorization results.** A delayed
  permission or token response cannot connect Drive for an account that is no
  longer selected.
- **Optional tips have four supported amounts and stronger recovery.** Apple
  unfinished transactions are checked on startup, resume and Retry. Duplicate
  completion events are handled once per session, stalled operations remain
  retryable, and Retry appears when recovery or catalog loading needs it.

## Automated and native test log

The runs below cover different stages of the release and overlap. Their counts
must not be added together as a unique-test total. Care records, imports and
account/store fixtures used isolated databases; production logs and connected
Drive files were not modified for testing.

| Stage | Recorded result | Evidence |
| --- | --- | --- |
| Build 51 purchase recovery | 14 focused purchase regression tests passed; the native StoreKit catalog returned all four configured tip products. Checkout remains a manual acceptance item | [Tip jar validation](TIP_JAR.md) |
| Build 52 consolidation | 372 Flutter tests and 24 script tests passed; complete Android and iOS native batches passed 296 checks each | [Consolidation milestone](MILESTONES.md) |
| Full build 53 branch pass, `bb3262c` | 406 Flutter tests and 24 script tests passed; analysis clean | [Full branch report](../../output/branch-validation-2026-10-13/REPORT.txt) |
| Broad native branch pass | iOS: 296 passed. Android: 295 passed with one profiling connection failure; the corrected focused Android batch passed 37 checks | Same full branch report |
| Focused native usability and assistants | Android: 37 passed; iOS: 32 passed. Native iOS Siri/launcher bridge: 6 passed. Native Android parser and fulfillment: 11 passed | Same full branch report |
| Native Android file picker | One end-to-end picker/import/removal/undo check passed with a synthetic CSV | Same full branch report |
| Import crash recovery | All six interruption scenarios passed; no partial import survived and committed imports retained undo | Same full branch report |
| Large import and persistence | 4,600 source activities produced 6,400 records plus a profile; deduplication, backups, reopening, malformed-row rejection, receipts and undo passed | Same full branch report |
| Process and device recovery | On each platform, three termination/relaunch cycles and one reboot preserved selected baby, appearance, care records and active timer identities | Same full branch report |
| Large log performance | Loading, repeated navigation and saving with 10,000 records passed; 10,001 records persisted afterward | Same full branch report |
| Final spacing delta, `09912d3` | 84 Flutter checks, 30 script checks, four focused Android native checks and two iOS native checks passed; analysis and formatting clean | [Final delta results](../../output/android-layout-audit-2026-10-14/RESULTS.txt) |
| Release packaging and delivery | Android release App Bundle and iOS release compilation passed during the branch pass. Final signed iOS build 53 verified app/extension versions, signatures, Google configuration, seven Siri actions and seven shortcuts | [Archive verification](../../output/release53/archive-verification.json) |

The final delta's coverage includes small screens, wide layouts, 200% text,
onboarding alignment, navigation, activity forms, settings, imports and purchase
UI. Native review used Android 16/API 36 on emulator-5580 and iPhone 17 Pro/iOS
26.5 on the iOS simulator. Android's verified display is 1080 × 2400 at its native
420 dpi, with no display override.

The earlier Android visual baseline used a 280 dpi override and was rejected
for visual acceptance. Behavior results remain recorded, but final visual
acceptance uses native-density captures. Flutter screenshot-surface conversion
also stalled during the broad review; full emulator screenshots replaced it.
Intermediate harness failures are retained, and corrected focused runs provide
the final results.

The broad performance run recorded 234 ms for disk reopen/initialization,
532 ms to the first settled frame and 126 ms for a saved entry on the Android
debug emulator. These measurements preceded the final spacing refinements and
are not physical-device release benchmarks.

## Tester pass for the next Family and beta update

1. **Update an existing installation.** Check the selected baby, saved history,
   unit preferences and running or paused timers before and after relaunch.
2. **Use the combined Log screen.** Open today, a previous day and a day in a
   different month. Use View all, filter activities, switch to Settings and
   return. Confirm the chosen day's records and totals remain consistent.
3. **Customize summaries and Quick log separately.** Include Pumped, remove a
   metric, reorder quick activities, relaunch and switch babies. Check that
   summary customization does not change the quick buttons.
4. **Check appearance and layout.** Try System, Light and Dark, larger system
   text, the keyboard, and a smaller or landscape screen. Check readable titles,
   matching card edges and reachable Save, Close and Back controls.
5. **Try all four app-icon shortcuts.** Test with Little Log closed and open,
   with multiple babies, and with a session already running. Check that the
   selected baby is correct and an existing timer is not restarted.
6. **Exercise Siri's four care categories.** Try each diaper kind, both nursing
   sides, sleep start/finish and pumping start/finish. Check prompts for missing
   details, pumping units and the baby named in the response. Confirm the saved
   record or durable timer in Little Log after each command.
7. **Recheck Gemini separately on Android.** Test recognition and discovery of
   the same categories, then inspect the record, timer or review form. Native
   route tests establish fulfillment, not assistant speech recognition.
8. **Import a suitable Nara export.** Review split entries and exclusions,
   compare times and units, import again, edit an imported entry, remove Nara
   imports and undo. Confirm manual entries remain and the correct baby receives
   the import.
9. **Test sharing with two accounts.** Check a previously connected log,
   account switching during authorization, caregiver access, offline saves and
   reconnection. Live Google authorization and cross-account mobile acceptance
   remain part of this pass.
10. **Exercise optional tips in the store test environment.** Check catalog
    loading, cancellation, pending approval, leaving Settings, relaunch and
    retry after interruption. Automated fake-store tests and catalog checks
    do not establish successful checkout. Android checkout requires the Play
    billing setup and a Play-installed test build.

For a problem report, include the build number, phone and OS, selected appearance
and text size, steps, expected result, actual result and a screenshot with private
care or account details hidden. Physical-device performance, battery behavior and
manual VoiceOver/TalkBack acceptance remain outside the automated results above.

## Release verification

Apple accepted **1.0.0 build 53** and reported `VALID`, `INTERNAL_ONLY` and
`IN_BETA_TESTING`. Owner testing contains the build and its one existing tester;
Family beta and Reddit Beta users do not contain it. Beta notes were saved and
read back. The exact release source is `09912d32438dab57e9f824d1c68ead10f9e55a37`.

The [TestFlight receipt](../../output/release53/testflight-verification.json) and
[signed archive receipt](../../output/release53/archive-verification.json) are
retained locally. The final Android and iOS simulator installations run normal
development build 54; they are separate from the distributed build 53 artifact.
