# Emulator QA harness

The native harness reuses `test/flow_journey_test.dart` on a real Flutter mobile engine. It uses synthetic data in a separate on-device database. It does not open the user's normal `little-log.db`, sign into Google, or send invitations.

## Run

Boot an iPhone simulator and Android emulator, then use their identifiers from `flutter devices`. From the repository root:

```sh
flutter pub get
flutter analyze
flutter test
REVIEW_OUTPUT=../output/emulator-review/ios flutter drive --no-pub --driver=test_driver/integration_test.dart --target=integration_test/app_journey_test.dart -d IPHONE_SIMULATOR_ID
REVIEW_OUTPUT=../output/emulator-review/ios-recovery flutter drive --no-pub --driver=test_driver/integration_test.dart --target=integration_test/recovery_test.dart -d IPHONE_SIMULATOR_ID
REVIEW_OUTPUT=../output/emulator-review/android flutter drive --no-pub --driver=test_driver/integration_test.dart --target=integration_test/app_journey_test.dart -d ANDROID_EMULATOR_ID
REVIEW_OUTPUT=../output/emulator-review/android-recovery flutter drive --no-pub --driver=test_driver/integration_test.dart --target=integration_test/recovery_test.dart -d ANDROID_EMULATOR_ID
```

Use a dedicated emulator: Flutter's driver installs and removes its test app. Screenshots are written by the host-side driver after the tests finish. Native tests use the actual platform and screen size; compact/landscape and 200% text tests run separately in `test/emulator_review_layout_test.dart`.

The polish unit checks run inside the full native harness: persisted weight/length/temperature defaults, exact conversion across repeated pill switches, medication with an optional temperature, and editing/removing that temperature. The native journey also verifies the defaults in Growth and Health.

The combined synthetic harness is `integration_test/full_harness_test.dart`. It includes the recent UI regressions; see [build 46 regression coverage](SESSION_REGRESSIONS.md) for assertions and commands.

## Coverage

- Journey: welcome validation, all ten activity forms, date/time dialogs, amounts and conversions, nursing side switching, sleep/pumping timers, review/back/cancel/save, persistent records, history/filter/day navigation, unit preferences, export dialog and swipe deletion.
- Recovery: native path-provider support directory, closing/reopening the database and controller, durable timer identity and start time, saved record and selected baby, simulated background/resume callbacks, adding/switching babies through the UI and system-back cancellation.
- Regression cases: imported dates outside the calendar range; local/shared deletion wording and cancellation.
- Existing unit/widget suite: edited records, invalid inputs, duplicate saves, storage, multi-baby rules, and simulated Drive sync failures/conflicts.

The recovery case is a database/controller restart, not an OS force-kill test. Tests do not verify live OAuth, native Picker, two-account sharing, airplane-mode network recovery, VoiceOver/TalkBack navigation, performance, or lock-screen Live Activity presentation. Add dedicated acceptance tests for those before claiming coverage.

## Evidence

Keep output logs, screenshot folders, source revision/dirty-state information and the tested build number together. Native screenshots are emulator captures. Regression-dialog captures mount the actual component in a minimal MaterialApp, so their default colors are not the app's visual theme.

## Extended acceptance probes

Use dedicated emulators and synthetic data. `scripts/android_qa.py` locates native UI controls from fresh UIAutomator snapshots; it masks password fields and restricts entry text to simple QA values. Credentials must be entered by the account owner directly.

- `integration_test/timer_edit_test.dart`: note-only edits of zero-second and five-hour saved nursing timers, on both native platforms.
- `integration_test/format_upgrade_test.dart`: mixed diaper and bottle forms, baby profile, and import preview on both native platforms.
- `integration_test/performance_test.dart`: 10,000-record native database reopen, navigation timeline, and subsequent save. Run in profile mode with `--no-dds`; the host driver writes `results.json`.
- `tool/recovery_probe.dart`: normal app UI with a separate synthetic database; logs durable record and timer state on each actual process launch. Terminate/relaunch and reboot the emulator externally, then compare JSONL state. Android release APKs require test signing before installation; these are not distribution artifacts.
- `tool/live_google_probe.dart`: Android-only acceptance probe using the normal database. Strictly requires the named synthetic baby configured in `LIVE_QA_BABY` and the authorized test account. It verifies live Drive records match locally created online/offline entries, then injects a 401 HTTP response while calling the real native token-clear SDK. This verifies bounded reconnect-error recovery, not successful silent token refresh. Results contain no credentials.

The September 23 follow-up results are in `../output/emulator-review/FOLLOWUP.md`; the build 24 rerun is in `../output/emulator-review/build24/REPORT.md`. Native OAuth and offline recovery were checked on Android; successful iOS OAuth and physical lock-screen presentation remain unverified. Battery endurance cannot be established from emulator measurements. Accessibility traversal, contrast, RTL/localization and dark mode were excluded by the user.
