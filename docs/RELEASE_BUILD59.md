# Build 59 QA and release preparation

Updated October 21, 2026. Version: **1.0.0 (59)**. Development and release
source: `dared66/little-log-open-source`, based on public main. The retained
private app repository is an archived historical backup. Build 58 remains the
last distributed TestFlight build; build 59 preparation does not authorize an
upload or distribution. Exact source revisions, artifact hashes and build logs
belong in the local release receipt, outside public Git.

## Changes since the distributed build

- Switch nursing sides from the running timer, Android notification or iOS Live
  Activity while preserving elapsed time and saved side durations.
- Upload the complete pending outbox in one verified, conditional CSV replacement.
  Previously a 10,000-entry outbox caused 100 whole-file replacements.
- Avoid rewriting unchanged records locally on every successful poll.
- Preserve the shared format and frozen build-54 compatibility gate. Build 58
  uses the same supported shared-data format; no coordinated upgrade is required.

User-facing iPhone notes: [BUILD59_TESTER_NOTES.txt](BUILD59_TESTER_NOTES.txt).
Build 57's historical approved notes remain unchanged.

## Acceptance and regression coverage

All live acceptance uses a dedicated Android emulator and iPhone simulator,
two signed-in Google accounts and a synthetic shared baby. Account identities,
Drive references, device screenshots and detailed live evidence stay private.
The maintainer explicitly selected emulators/simulators for this pass.

| Check | Coverage and result |
| --- | --- |
| Sign-in and sharing | Android-created synthetic baby joined on iOS through the invited account; identity and records survive in-place app updates. |
| Automatic refresh | Android save appears on the open iPhone without Refresh. Foreground polling is every 30 seconds; the controller regression also checks pause/resume behavior. |
| Resume and deletions | iPhone deletion reached Android automatically. With iPhone backgrounded, Android removed the other temporary entry; reopening iPhone pulled that deletion without Refresh. Temporary entries from this pass were removed on both devices. |
| Overlapping real-account edits | Both devices opened the same bottle and saved different amounts before convergence. Both replacements reached both devices automatically; the original was removed. |
| Offline durability | An offline Android entry survived process restart, then reached iOS after reconnect and refresh; iOS retained it after restart (October 20). |
| Conditional conflict recovery | Two account-scoped clients deliberately race writes against a versioned Drive HTTP double. Edit/edit and edit/delete tests force a 412, converge, preserve tombstones and retain replacement IDs. |
| Large outbox and retry | 10,000 synthetic records upload in one conditional write, remain readable by the frozen shipped reader, and produce no record rewrites or downloads on an unchanged poll. A 1,001-record lost-response test keeps the outbox pending until retry acknowledges the existing remote IDs. |
| Native large local history | Isolated on-device databases seed 10,000 records, close/reopen, render/navigate the normal app and save a 10,001st record successfully on both platforms. |

Native measurements from this pass, in milliseconds:

| Platform | Seed | Reopen and initialize | First settled frame | Save and refresh |
| --- | ---: | ---: | ---: | ---: |
| Android emulator | 2552 | 254 | 543 | 112 |
| iPhone simulator | 1044 | 212 | 606 | 80 |

These are single-run debug emulator observations, not physical-device or release
performance guarantees. Large-outbox cloud tests use the real CSV/Drive client
against a controlled HTTP double, not a 10,000-record live Google transfer.

Local validation passed: 483 Flutter tests (13 existing optional skips), 54
Python build-script tests, Flutter analysis, and the mandatory frozen-reader
compatibility gate (24 tests). Public CI must also pass for the resulting main
revision before release packaging is considered ready.

## Remaining product limits

- One growing CSV per baby, with a **10 MiB application cap**. It is still read
  and replaced in full when changed. Monthly archives remain an experiment;
  this release does not claim unlimited history or bounded transfer per edit.
- Automatic refresh runs while foregrounded and on resume. Network errors use
  retry backoff. There is no background push delivery or five-second sync SLA.
- Concurrent edits preserve both replacements. Caregivers can remove the one
  they do not want; the app does not guess which caregiver's edit should win.
- Emulator acceptance does not establish battery endurance, real lock-screen
  behavior, every token expiry path or large-history live Drive latency.

## Prepare and verify a release

1. Merge the reviewed change into public main and wait for `publication` and
   `test` CI jobs on that exact resulting revision. Fetch origin and require a
   clean main checkout; run `python3 scripts/release_preflight.py`.
2. Run the compatibility gate, focused sync regressions, Flutter analysis and
   normal tests. Keep public CI independent of private configuration.
3. Build Google-enabled Android and iOS simulator apps from that main revision;
   install in place and launch on the review devices, preserving accounts and
   data. Native harnesses use separate disposable devices and `--no-uninstall`.
4. Create an isolated source snapshot from that verified public revision for
   release packaging. Restore only ignored local build settings. Keep signing
   profiles/keys, artifacts, hashes and receipts outside public Git. Verify iOS
   app/extension versions, signatures and Google callback/client definitions.
   Verify Android release packaging and record whether it is signed.
5. An explicit release request is still required to upload/distribute. Use the
   notes above, record channels and processing receipts, and move subsequent app
   development to build 60 after build 59's first upload.
