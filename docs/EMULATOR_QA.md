# Emulator QA harness

The native harness reuses `test/flow_journey_test.dart` on a real Flutter mobile engine. It uses synthetic data in a separate on-device database. It does not open the user's normal `little-log.db`, sign into Google, or send invitations.

## Run

Boot an iPhone simulator and Android emulator, then use their identifiers from `flutter devices`. From the repository root:

```sh
flutter pub get
flutter analyze
flutter test
flutter test --no-uninstall --no-pub integration_test/app_journey_test.dart -d DISPOSABLE_IPHONE_SIMULATOR_ID
flutter test --no-uninstall --no-pub integration_test/recovery_test.dart -d DISPOSABLE_IPHONE_SIMULATOR_ID
flutter test --no-uninstall --no-pub integration_test/app_journey_test.dart -d DISPOSABLE_ANDROID_EMULATOR_ID
flutter test --no-uninstall --no-pub integration_test/recovery_test.dart -d DISPOSABLE_ANDROID_EMULATOR_ID
```

Use a dedicated disposable device: native tests replace the normal app. Keep `--no-uninstall` even there. Never run a harness on the protected review devices or the signed-in sharing acceptance devices. Screenshots, when needed, require the separate host-side capture driver. Native tests use the actual platform and screen size; compact/landscape and 200% text tests run separately in `test/emulator_review_layout_test.dart`.

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
- `integration_test/performance_test.dart`: 10,000-record native database reopen, navigation timeline, and subsequent save. Use `python3 scripts/run_native_tests.py android performance --device <disposable-emulator-id>` or the equivalent `ios` command. Keep DDS enabled; the runner forwards Android profiling traffic. The test prints `LARGE_HISTORY_METRICS`; debug timings are observations, not release performance guarantees.
- `tool/recovery_probe.dart`: normal app UI with a separate synthetic database; logs durable record and timer state on each actual process launch. Terminate/relaunch and reboot the emulator externally, then compare JSONL state. Android release APKs require test signing before installation; these are not distribution artifacts.
- `tool/live_google_probe.dart`: Android-only acceptance probe using the normal database. Strictly requires the named synthetic baby configured in `LIVE_QA_BABY` and the authorized test account. It verifies live Drive records match locally created online/offline entries, then injects a 401 HTTP response while calling the real native token-clear SDK. This verifies bounded reconnect-error recovery, not successful silent token refresh. Results contain no credentials.

The September 23 follow-up results are in `../output/emulator-review/FOLLOWUP.md`; the build 24 rerun is in `../output/emulator-review/build24/REPORT.md`. Native OAuth and offline recovery were checked on Android; successful iOS OAuth and physical lock-screen presentation remain unverified. Battery endurance cannot be established from emulator measurements. Accessibility traversal, contrast, RTL/localization and dark mode were excluded by the user.


## Current acceptance, October 21, 2026

The September reports above are historical. Two-account sign-in/joining,
automatic foreground refresh, overlapping edits and offline durability have now
been checked on dedicated Android/iOS emulators. Both native 10,000-record tests
pass. See [build 59 QA](RELEASE_BUILD59.md) for results and precise limits.
Physical-device testing is not required for this pass by maintainer decision.

Focused automated checks:

```sh
flutter test test/sync_test.dart test/manual_sync_test.dart test/google_drive_test.dart test/sync_stress_test.dart
python3 scripts/check_build54_compatibility.py
```

For live automatic refresh, keep both normal apps open on the authorized synthetic
shared baby. Save on one device and wait for the other to update without tapping
Refresh. Repeat in the other direction, then background one app, change the log
on the other and reopen the first. Record save and arrival times; allow the
30-second polling interval plus network time. A failed request can add backoff.

For overlapping edits, open the same synthetic entry on both devices before
saving different values. Save both before either pulls the other's change;
verify both replacements and removal of the original on both devices. The
controlled HTTP regressions force the narrower simultaneous-write/412 race;
a UI exercise alone does not prove a 412 occurred. Remove temporary test entries
and verify their deletion reaches both devices, retaining the tombstones.

Keep live test identities, Drive references and screenshots outside public Git.
Never seed a large dataset into an existing real family log. Large-history
harnesses use isolated synthetic databases and a controlled cloud double.
