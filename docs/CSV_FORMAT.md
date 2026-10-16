# Drive CSV storage — 2026-09-18

This document records the initial CSV design and later schema additions in
chronological order. Early verification counts and missing-feature statements
are historical, not a current release checklist. Production still uses one CSV
per family; the monthly-file permission probe is experimental.

## Decision being tested

The shared log uses one ordinary, family-owned CSV in Google Drive and Drive file operations instead of Sheets requests. The format and validation requirements below describe that storage contract.

## Implemented

- Replaced every runtime Sheets request with Drive file operations. CSV is uploaded with MIME type `text/csv`; it is not converted into a Google Sheet.
- Creation, listing, Google Picker selection, link parsing, joining, invitation permissions and the open-in-Drive link target the CSV.
- Existing OAuth `drive.file` scope and project are reused. No service account, server database, new billing service, broader OAuth scope or additional API is required. Drive and Picker must remain enabled. Sheets can remain enabled for legacy files but is no longer used by this build.
- Both caregivers select the SAME CSV through Picker to authorize it under `drive.file`. Drive editor permission and app authorization are distinct; a pasted link alone does not grant the latter.
- CSV contains the family identity and all completed bottle, nursing and diaper records. Local timers and JSON export continue to work.
- Metadata-only polling skips downloading unchanged files. Cache is separated by account and file. Cold/changed reads use metadata → download → metadata, retrying if the version changed during download.
- Drive v2 metadata supplies `etag` in JSON, avoiding reliance on browser visibility of response headers. Media writes use v2 `PUT` with `If-Match`. Discovery, creation and permissions use v3. Both are the Google Drive API, not Sheets.
- Each write merges pending IDs with the latest CSV. HTTP 412 triggers reread/merge/retry, at most four attempts. Uploads are reread and verified before acknowledging the local outbox. Lost-response retries deduplicate IDs.
- Creation reads the new file’s actual ETag, performs one matching-version write of the same EMPTY content, verifies that the ETag advances, then retries with the real stale ETag. Only 412 permits connection to proceed. If the service ignores the condition, the empty file is retained and publication stops. Never run this destructive-style probe against an existing family file.
- Missing/weak ETags, malformed/unknown CSV records, foreign family IDs, conflicting duplicate IDs and conflicting local/cloud contents stop sync without overwriting records.

## Why one CSV

Separate immutable files would avoid a shared write target, but a caregiver selecting one file under `drive.file` does not establish that the app can discover/access every other writer's newly created file. The app uses a single selected, shared resource. Safe conditional media writes are therefore a hard dependency, not an optional optimization.

## CSV format

UTF-8, comma separated, all cells quoted, embedded quotes doubled, CRLF row separators; parser also accepts LF and a UTF-8 BOM. Newlines inside quoted cells are preserved.

The first row is the fixed header:

```
record_type,format_version,family_name,baby_name,id,family_id,time_utc,method,amount_ml,minutes,note,caregiver,schema_version,ended_at_utc,left_seconds,right_seconds,diaper_kind
```

The second row has `record_type=family`, `format_version=1`, names and `family_id`; unused cells are empty. Remaining rows have `record_type=event`, `format_version=1`, empty name columns, and the existing 13-column event schema (v1 bottle/manual nursing; v2 completed left/right nursing and diapers). Timestamps are UTC. Stable IDs determine identity. Duplicate identical records are deduplicated; conflicting same-ID payloads are an error.

To reduce formula execution when opened in a spreadsheet, cells beginning with apostrophe, `=`, `+`, `-`, `@`, tab, CR or LF receive one leading apostrophe. The reader removes that one prefix only when followed by a listed character. This convention is part of the open format; generic spreadsheet edits that reinterpret values are not supported. No app secret is required to decode these files.

## Existing spreadsheet families

Old persisted `sheetId` values are retained as `legacySheetId`, never reinterpreted as CSV IDs. Those logs become local in this build. The UI explains that **Create family file in Drive** copies records already on THIS device into a new CSV. Publishing atomically requeues all this family's local records, including previously acknowledged ones. Other families are untouched. The old Google spreadsheet is not modified or deleted. Records present only in the old cloud spreadsheet are NOT fetched by this migration: download/export them using the previous build first. All caregivers must move to the same new CSV.

## Verification

Automated tests use a stateful fake Drive HTTP service that honors ETags. They exercise concurrent two-client writes, stale preconditions, missing ETags, servers ignoring conditions, retries after lost responses, cache invalidation/isolation, rate/auth failures, malformed CSV, family identity checks, CSV quoting/Unicode/formula-like text, activity fields, migration and outbox preservation. Existing persistence and phone-layout tests are retained.

These tests prove client behavior under that contract; they do NOT establish that Google enforces the same contract.

Live verification on September 17, 2026:

- User completed authorization in the in-app browser. The initial fabricated-ETag probe returned HTTP 500 after creating an empty test CSV; that file is retained.
- The revised real-version probe passed against Drive: a matching conditional write succeeded, the ETag advanced, and the stale conditional write returned 412 (the only path allowing family creation to finish).
- The family then published its existing synthetic 90 ml bottle record. A new wet-and-dirty diaper and a completed nursing session (29 seconds left, 10 seconds right) synced successfully. Subsequent foreground polls retained exactly three events.
- Opened the actual CSV in the Google Drive viewer and independently verified its header, family ID, three event IDs, timestamps, 90 ml amount, diaper kind `both`, nursing end time, and both side durations. The private test-file URL is intentionally omitted. These are synthetic Demo Baby records.
- All 33 automated tests pass; static analysis and the configured web build pass.

This establishes actual Drive creation, version rejection, upload and readback for one account. Two-account sharing, concurrent device writes, mobile Picker and background/resume behavior remain unverified; this is not a production-readiness claim.

Authorization has a 45-second timeout with a recoverable message. The button now shows “Connecting to Google Drive…” during authorization and “Google Drive connected” after success. Migrated local records correctly display “Saved on this device,” even when they were acknowledged by the old spreadsheet implementation.

## Required live acceptance run

Use synthetic records only until all checks pass.

1. Sign into the configured preview as the already-authorized test account. Create a synthetic family and connect Drive. Create its CSV. The stale-version probe must receive 412; otherwise this design fails the first gate.
2. Save a bottle, a wet/dirty diaper and a completed left/right nursing session. Open/download the CSV in Drive and verify all fields. Repeat sync and reload: no duplicates and no lost history.
3. Authorize a chosen second caregiver test account and share the CSV with it. On their phone, choose the SAME CSV through Picker and confirm the family ID and history.
4. Add different records on both devices while disconnected. Reconnect both and trigger overlapping sync. Both histories and the Drive file must converge to the union. Verify the losing stale upload receives 412 against real Drive, not just our fake.
5. Interrupt a response after upload, then retry. Confirm one record per stable ID.
6. Background/resume both apps and record time-to-visible-update. Foreground polling is every 30 seconds; always-on background delivery is NOT implemented.
7. Revoke caregiver file access; remote access must stop and pending/local history must remain. Restore access and retry.
8. Download the CSV and inspect it independently. Retain a copy before changing provider or clearing app data.
9. Run on real Android and iPhone. Native Picker's pre-existing `https://localhost` origin/key restriction still needs resolution; native builds alone do not validate it.

## Limits and go/no-go

- Full CSV is downloaded on change and rewritten on a write. 10 MB maximum. A batch contains at most 100 pending records. This is not a delta-sync implementation or proof of 10,000-user economics.
- An unchanged sync uses one metadata read. Changed reads take two metadata reads and one download. Successful writes normally add a pre-write metadata check, upload, and a verified read. Conflicts add retries. Measure requests, bytes and daily quota before capacity claims.
- No editing/deletion UI or distributed active nursing timer. Out-of-band cloud row deletion does not delete retained local history. Interrupted file creation can leave an empty orphan CSV, which can be trashed manually.
- No CSV import-from-device UI yet; independent data access is through the actual Drive CSV and documented schema. Existing JSON export remains.
- If conditional writes are not enforced on the actual media endpoint, do NOT remove the precondition or ship a last-writer-wins fallback. Revisit immutable files and their authorization design.

Sources: https://developers.google.com/workspace/drive/api/reference/rest/v2/files
https://developers.google.com/workspace/drive/api/guides/manage-uploads
https://developers.google.com/workspace/drive/api/guides/api-specific-auth
https://developers.google.com/workspace/drive/api/guides/limits


## September 18 activity extension

The current writer adds an eighteenth column, `details_json`, and uses event schema 3 for sleep, pumping, solids, growth, health, routines and milestones. The decoder also accepts the original 17-column header and schemas 1/2. All caregivers must update before using a rewritten CSV. See [Nara feature comparison](NARA_FEATURES.md) for details and remaining gaps.


### Detailed diapers

Event schema 4 supports diapers with `poopColor`, `poopConsistency`, `blowout` and/or `rash` in `details_json`. The header remains 18 columns. Color and consistency use stable values from `diaper_details.dart`; blowout and rash are booleans. Omitted fields mean not recorded. Poop fields are accepted only for `dirty` and `both`. Unknown fields/values and inconsistent measurement columns fail validation. Old plain diaper rows keep schema 2. All caregivers need this version to sync files containing schema-4 events; older builds reject rather than discard them.

## Deleted entries (build 9)

Schema 5 is a deletion tombstone with the same ID, family, time and method as the original entry. Its `details_json` stores the original validated row as a JSON array; the other optional columns are empty. Deletions win when merging the same original record, and stay in the CSV so an offline caregiver cannot restore a removed entry during sync. Different original contents still cause a conflict. The visible log, totals and JSON export exclude deleted entries. Older clients reject schema 5 rather than silently losing it; all caregivers must update before syncing deletions.

## Event schema 6 (build 24)

The 18-column CSV header and file format version 1 are unchanged. Readers still
accept event schemas 1–5 with their original canonical rows. Schema 6 uses
`details_json` as an envelope containing `details` and `source` objects. Older
apps reject schema 6; update all devices before importing these records.

- Diapers support unique `poopColors` and `poopConsistencies` arrays. Legacy
  singular values remain readable. Missing observations remain unrecorded.
- Bottles optionally store `breastMilkMl`, `formulaMl`, and `formulaName`.
  Components must be finite, nonnegative, and equal the bottle total.
- Nursing can store per-side seconds with an empty `ended_at_utc`. An unknown
  end is not inferred from duration. Nara millisecond durations remain in the
  source metadata as well as the untouched original record.
- Source metadata records the source system, original record ID, caregiver ID,
  original timezone, and complete original payload. Caregiver display names are
  supplied during import, or distinct numbered labels are used.
- `profile` events hold `birthDate`, `gender`, `nightStart`, and `nightEnd`.
  They sync through the same durable event protocol. The newest active profile
  wins by timestamp then ID; profiles are excluded from the activity timeline.
  Night hours are stored/displayed settings; daily totals remain calendar-based.
- Deletions retain schema 5 and the exact prior canonical row. Corrections use
  a tombstone plus a new ID rather than overwriting an existing synced ID.

Settings → Import and recovery accepts pasted Little Log CSV, JSON backups
(schema 3/4 without running timers), and the Nara skill's `{profile, tracks}`
export. Nara import currently supports the verified breast/bottle/diaper schemas;
unknown categories/units stop the entire preview. This is not a universal Nara
export parser. JSON backup schema 4 also carries profiles and source metadata.

Import previews validate the complete input, check baby identity, retain
unrelated records, skip identical IDs, and reject conflicting IDs. Commit is one
local transaction guarded against history changes since preview, including a
persistent prior-state receipt. Undo creates deletions/restorations that sync
normally and refuses to overwrite post-import edits. Source-deleted IDs remain
deleted on repeat imports. Running timers are not imported or discarded.

Medication health records may include optional `temperature` (a positive finite number) and `temperatureUnit` (`°C` or `°F`) together in `details_json`. Both describe the same event and timestamp as the medication. Medication-only records remain valid. Caregivers need the polish update before sharing records with these fields; older validators do not recognize them.
