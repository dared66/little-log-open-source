# Project status

Little Log is pre-release software. The app supports local baby logs and
optional family-owned Google Drive CSV sync. New users can create a shared log,
join an invited log, or start on this device. Existing saved families continue
to open directly after an update.

## Available in the source

- Ten activity categories, timers, daily history, baby profiles, local import
  and export, quick log customization, and an optional tip jar.
- Optional elapsed time beside six Quick Log icons, read-only assistant
  history questions, and platform-specific assistant help in Settings.
- Read-only Nara export and local two-way file conversion; the bridge does not
  write to Nara Baby.
- Drive CSV creation, caregiver invitations, conditional writes, merge and
  retry, with a device-local outbox.
- A monthly-file permission probe behind
  `--dart-define=MONTHLY_PERMISSION_PROBE=true`. It is for synthetic developer
  tests; production sync remains a single CSV per family.

## Before a production release

Two-account Android/iOS emulator acceptance now covers sign-in, joining,
automatic foreground refresh, overlapping edits and offline recovery. Isolated
10,000-entry native storage/navigation/save tests pass on both platforms.
See [build 59 QA and release preparation](RELEASE_BUILD59.md) for the tested
scope, measurements and remaining limits. Physical-device testing is not a
requirement for this pass (maintainer decision).

Production sync remains one growing CSV with a 10 MiB application cap. It polls
every 30 seconds while foregrounded and on resume; it does not deliver changes
in the background. Bounded archives and large-history live Drive transfer
measurements remain future work. The original architectural review is retained
in [the production assessment](PRODUCTION_ASSESSMENT.md); the
[monthly permission test](MONTHLY_PERMISSION_TEST.md) covers one prerequisite
for a future bounded-file design.

The former chronological development log remains available in Git history.

The October 13 consolidation of Today and History into Log has a dated
[milestone and rollback reference](MILESTONES.md).

The [release and test log since build 50](RELEASE_AND_TEST_LOG_BUILD53.md)
covers changes since build 50, the previous shared release for Family beta and
Reddit Beta users, and includes the next tester pass.

Build 58 is available in all four TestFlight groups: Owner testing, Family beta,
Reddit Beta users and Open Beta. It includes optional elapsed time
in Quick Log, improved live timers, and Help with Siri commands, setup and
sharing. Build 54 remains the mandatory legacy compatibility baseline. Build 58
preserves build 57's app code with an external-eligible package. The source
is now at build 59, prepared from the public repository with nursing side
switching and more efficient history syncing. Build 59 has not been uploaded or
distributed. Its concise tester notes are in [BUILD59_TESTER_NOTES.txt](BUILD59_TESTER_NOTES.txt).
Distribution receipts and exact release
sources are recorded in [the milestones](MILESTONES.md).
