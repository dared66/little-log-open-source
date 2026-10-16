# Monthly files: permission acceptance test

This is an experimental developer test, not the app's production storage mode.
The panel appears only with `--dart-define=MONTHLY_PERMISSION_PROBE=true`.
Use synthetic accounts and files only. Normal builds do not show it.

Status 2026-09-18: PASS for the live two-account monthly-file permission gate. Both accounts accessed app-created child CSVs automatically under drive.file after a single folder share, including new files created after initial access. Monthly partition helper and synthetic permission-test UI are implemented. Production sync still uses the existing single CSV; no family migration or monthly production switch has been performed.

The test used two explicitly selected development accounts. Only synthetic files may be shared. Test sharing uses sendNotificationEmail=false.

## What has passed

- Four partition tests: deterministic UTC start-month selection, year/timezone boundaries, late entries, retention beyond twelve months, self-contained CSV round-trip, and family isolation.
- Existing 33 tests plus these four passed together; static analysis and configured web build passed.
- Test interface only appears with --dart-define=MONTHLY_PERMISSION_PROBE=true. Normal builds omit it.

## Test sequence

1. Owner authorizes Drive in the preview. Create a synthetic test folder through the monthly test panel. Record its ID here.
2. Create 2026-09.csv. Verify owner can list, read, conditionally write and reread it.
3. Share only the marked test folder with the designated second account, without sending an email.
4. Sign in as the second account in Little Log and authorize the same drive.file scope. Enter the known folder ID. First try verification without selecting any file in Picker. This tests app-created-file access separately from human Drive permission.
5. If folder access is denied, investigate the supported one-time folder-selection flow. Never grant broad Drive access automatically and never manually authorize each monthly file to claim success.
6. After the second account has read September, owner creates 2026-10.csv in the same folder. Second account must discover, read and write October without new per-file selection or permission grants.
7. Second account creates 2026-11.csv. Owner must discover and read/write it. Both devices must retain earlier records.
8. Verify each file's readback contains the expected synthetic writer records. Record per-account results and which file-selection steps were required.

Pass: both accounts automatically access new child CSVs created after onboarding using the current narrow scope. Fail: monthly files require repeated manual selection, are invisible, or cannot be updated by an intended writer. A failed browser OAuth popup is a test-environment blocker, not evidence that Drive file sharing fails.

## Current live status

- Owner created a synthetic folder using the app with drive.file; its private ID is intentionally omitted.
- The folder was shared with the second test account as writer with email notifications disabled; UI confirmed success.
- Owner created `2026-09.csv` inside it. Owner verification reported: read, conditional write and readback passed; `appAuthorized=true`.
- The second browser app session authorized successfully. It listed, read, conditionally wrote and read back September with appAuthorized=true. No file-picker selection was performed for the folder or CSV. Owner then created October after this successful caregiver access. The caregiver immediately discovered October and completed read, conditional write and readback with appAuthorized=true; no new Picker selection or permission change occurred. Caregiver created November. Owner discovered November and completed read, conditional write and readback with appAuthorized=true. Owner also verified September and October again. All three monthly files are accessible to both accounts without per-file grants.
- The development OAuth test-user allowlist contained both synthetic test accounts.
- No production family migration or monthly-sync cutover performed. The existing Demo Baby CSV remains separate from this fixture.
- Two additional safety tests passed: probes refuse unmarked folders; sharing targets only the specified user as writer without notification. Total tests: 39 (37 full-suite pass followed by 2 additional passing tests).

## Monthly partition contract

Files are YYYY-MM.csv based on the record's UTC start time, so caregivers in different time zones select the same file. Display times remain local. Late records go to their historical month. Older files are retained, never expired after twelve months. Each CSV contains the existing family metadata and full event schema. This helper is not yet connected to production Drive sync: that integration depends on the permission test and an atomic file-discovery/creation protocol to prevent duplicate-month races.

## Interpretation and remaining work

The prior monthly-file authorization concern is resolved for files and folder created by this Google Cloud app, the current drive.file scope, and the two test accounts. This does not claim automatic access to arbitrary files created outside the app, Workspace-domain policies, or native Picker behavior. Folder sharing granted human access; app-created files were also app-authorized for both users. File ownership belongs to the creating Google user, so November is caregiver-created rather than necessarily owned by the folder owner.

Next implementation work is the monthly storage adapter and migration: stable month IDs, conditional manifest updates or another proven duplicate-creation protocol, retained offline outbox, historical-month updates, efficient discovery, and no destructive migration of the old CSV. This live test did not exercise simultaneous month creation or simultaneous edits; it establishes permissions and sequential cross-account writes.
