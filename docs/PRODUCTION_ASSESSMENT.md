# Little Log: production assessment

This September 18 assessment is a historical architecture review. Some feature
gaps recorded below were subsequently addressed; consult the current README
and source before treating an item as still open. The growing single-file
production sync design and native acceptance gaps remain.

Update 2026-09-18: C11 monthly-file permissions passed the live two-account test; see MONTHLY_PERMISSION_TEST.md. Both accounts automatically accessed subsequent app-created monthly CSVs after one folder share, without Picker selection or broader scopes. The assessment below records the initial audit; its C11 uncertainty is now resolved for that tested configuration. Production monthly sync integration and native-device acceptance remain outstanding.

Assessed 2026-09-18. This supersedes blanket claims that CSV is unsafe for concurrency or that three successful cloud writes establish production readiness.

## Decision

Family-owned Drive storage is a credible product direction. CSV is a portable serialization format, not a concurrency protocol. A single ever-growing CSV rewritten and read back on every save is not an acceptable unbounded production design for quick sync over slow connections. Keep the ownership requirement and conditional-write/merge approach; bound the active transfer size before general release. Do not change to a company-owned primary database merely to avoid these problems.

The ownership promise is that completed uploads remain ordinary files in the family's Google account if our company or OAuth project disappears. Continued operation of our particular app forever is a separate promise and cannot be guaranteed. Published schema and an independent importer are required to make switching systems practical. Unsynced device-only records remain vulnerable to loss of that device.

## Evidence ledger

| ID | Concern | Evidence and status | Required resolution |
|---|---|---|---|
| C1 | Concurrent new entries overwrite each other | Real Drive accepted a matching ETag write, advanced its ETag, and rejected the stale version with 412. Fake-service tests cover two writers and lost responses. Actual simultaneous two-account writes are untested. Mechanism supported; integration acceptance still required. | Keep stable IDs, conditional writes, merge and bounded retries. Repeated real overlapping writes must preserve every distinct submitted ID. |
| C2 | Transfer grows with all history | Confirmed by code and actual encoder size measurement below. 10 MiB is an application cap, not a Drive limit. Structural issue for an unlimited-history promise. | Bound the active log and archive old history, with a restart-safe rollover protocol. Verify cross-account access to archives before adopting multiple files. |
| C3 | Local app slows with history | Every sync reads the full local history and merges every remote record, including an unchanged cached history. Timeline eagerly builds records with feeds.map. Known implementation costs. | Skip unchanged merges; upsert only changed records; paginate or lazily render history; measure representative phones. |
| C4 | Second caregiver cannot connect | One-account live success does not prove two-account file selection, permissions, offline convergence or access revocation. Native Picker currently uses a localhost WebView origin, previously flagged as unresolved. Launch blocker, not demonstrated impossibility. | Test owner plus invited Google account on physical Android/iOS, using least-privilege drive.file. |
| C5 | Repeated sign-in interrupts use | Web authorization tokens are session-memory state and expire. Reload required authorization again in live testing. Connected label is only last known state. Known UX/platform integration gap. | Native token lifecycle, account switching, expiry/revocation and interrupted-auth recovery tests. Do not promise web background sync from this popup token flow. |
| C6 | Background or instant sync | Current code polls every 30 seconds while foregrounded, syncs on resume and saves locally first. No background delivery. Active nursing timer is device-local. Product capability gap. | Specify foreground eventual consistency; retry on resume. Optional webhook/push service can accelerate notification but cannot guarantee mobile background execution. Shared timers need an explicit state protocol. |
| C7 | Editing/deleting existing records | Current merge handles unique append-only events. Different contents with the same ID halt sync; there is no edit/delete UI or tombstone protocol. Known missing product feature. | Represent corrections/deletions as versioned operations with deterministic conflict behavior; test offline edits and deletion resurrection. |
| C8 | Corrupt/deleted files and lost devices | Malformed CSV stops sync; local outbox survives transient errors. No complete backup/restore or CSV import flow. Drive editors can damage a shared file; revocation cannot erase their downloaded copies. | Independent validated snapshots and restore/import UX. Never silently reset the cloud file. Clearly distinguish local save from verified remote save. |
| C9 | User ownership after company shutdown | Actual ordinary CSV in the user's Drive was opened independently and contains complete synthetic event fields. Data access does not require our server. Replacement-app importer not yet built. | Publish schema and importer; demonstrate recovery with Little Log unavailable. User remains dependent on their own Google account, not our database. |
| C10 | API scale and operating cost | Current public Drive limits differ from Sheets' 300/minute premise. Published new-project minute limits leave room for illustrative polling scenario below. Project-console allocation and method accounting not verified. Whole-file bandwidth can become material. | Check project quota and usage metrics; budget active users, requests, bytes, burst headroom, backoff with jitter. Do not quote unknown future overage rates. |
| C11 | Multiple-file permission model | drive.file is per-file access. Selecting a folder cannot be assumed to authorize every future file created by another caregiver. Bounded-file proposal therefore has an unresolved onboarding/discovery gate. | Verify archive creation and second-account access with actual scope. Reject any design requiring repeated manual file selection for routine sync. Broader Drive scope is a separate privacy/verification decision, not an automatic fix. |
| C12 | Legacy migration | Only locally downloaded spreadsheet history is copied. Remote-only entries are omitted. Joining a new file with an existing same family ID/different storage is rejected. Known migration gap. | Explicit migration with complete counts and IDs, identity reconciliation and rollback; retain original spreadsheet. |

## Measured CSV capacity

Command: Dart VM, actual lib/services/family_csv.dart, tool/csv_capacity_audit.dart. Desktop measurements, one warm-up plus median of three runs. No mobile, browser, HTTP, disk-database or rendering latency is included. Synthetic UUID records, bottle values, caregiver email and 50-character ASCII notes; mixed activities, longer notes and Unicode change size. 20 entries/day is a scenario, not measured usage.

| Entries | History at 20/day | Bytes | Encode ms | Decode ms |
|---:|---|---:|---:|---:|
| 1,000 | 50 days | 237,338 | 2.211 | 5.600 |
| 7,300 | 1 year | 1,730,438 | 17.000 | 33.241 |
| 21,900 | 3 years | 5,190,638 | 49.934 | 99.985 |
| 36,500 | 5 years | 8,650,838 | 90.989 | 176.798 |

A warm uncontended write normally entails an initial metadata read, another pre-write metadata read, upload, then metadata-download-metadata verification: six HTTP requests, including one whole-file upload and one download. Another caregiver must download the changed file. Cold caches, concurrent changes, reconnect batches and retries cost more.

At symmetric 1 Mbps, just the writer's upload plus verification download takes at least 27.7 / 83.1 / 138.4 seconds for the one / three / five year samples, before request overhead. This is cloud acknowledgment latency, not local record-save latency. Current per-request timeout is 25 seconds, which also makes sufficiently slow large transfers fail and retry. Raising the timeout alone does not fix transfer growth.

## Illustrative account scale

Assume two users per family, 20 events/family/day, two full downloads per event (writer verification and one observing caregiver), no retries/cold starts. Actual caregiver batching can reduce downloads; other factors can increase them. Decimal GB/TB.

| Users | Families | Drive downloads/day with 1-year files | With 3-year files |
|---:|---:|---:|---:|
| 1,000 | 500 | 34.61 GB | 103.81 GB |
| 10,000 | 5,000 | 346.09 GB | 1,038.13 GB |

Uploads are additional and equal half those download bytes under these assumptions. Ten thousand users are not ten thousand simultaneous writers to one family file.

Polling every 30 seconds while every user is active produces 2,000 metadata reads/minute at 1,000 users and 20,000 at 10,000. At the published 5 units/read these are 10,000 and 100,000 units/minute, excluding writes/downloads/discovery. The current published new-project quota is 1,000,000 units/minute, with a 400,000,000-unit daily billing threshold and 1 TB/day egress threshold. Older projects can retain earlier quotas. Therefore neither '300/minute means impossible' nor '10,000 users is free' is defensible.

Published future over-threshold billing prices are not supplied on the limits page as checked today; it promises at least 90 days' notice. There is no AI API call in this sync implementation. No defensible fixed monthly total can be supplied without actual usage assumptions, account quotas and any hosting/push service choice.

## Shipping gates and recommended design

Retain local-first records and ordinary user-owned Drive files. Keep current file-version conflict protection. Design a bounded active log plus readable archives, provided C11 is resolved without unacceptable permission UX. Use a documented versioned-operation format for edits, deletion and optional cross-device timer state. Keep derived local indexes disposable and rebuildable from family files. A notification service, if added, must be optional for foreground sync and must not become the sole data authority.

Release gates are C4/C11 (cross-account and mobile authorization), C1/C7 (no missing/duplicated/resurrected operations under collisions and offline recovery), C2/C3 (bounded transfer plus acceptable phone latency), C5/C6 (honest and reliable sync experience), and C8/C9/C12 (recovery and portability). Proposed acceptance targets, not achieved results: local save visible within 200 ms p95 on target phones; foreground peer convergence within 5 seconds on a defined normal network; tested recovery after offline use; 10,000 synthetic overlapping operations with exact final IDs/content; recover all confirmed records without Little Log running. The current 30-second poll does not meet a five-second target; poll/notification design must change if that target is retained.

Engineering verdict: no demonstrated fatal obstacle to family-owned Drive storage or CSV concurrency. Current growing-file implementation is no-go for an unbounded quick-sync production promise. Cross-account bounded-file access is the key unresolved architecture gate. Market demand and willingness to pay have not been validated by these engineering results.

## Primary sources

- https://developers.google.com/workspace/drive/api/guides/limits
- https://developers.google.com/workspace/drive/api/guides/api-specific-auth
- https://developers.google.com/workspace/drive/api/guides/push
- https://developers.google.com/identity/oauth2/web/guides/use-token-model
- https://developer.android.com/identity/authorization
- https://developer.apple.com/videos/play/wwdc2025/227/
