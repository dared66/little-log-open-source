# Nara Baby file import

Settings → Import and recovery → Choose file opens the platform file picker. The page previews the selected file before any write. Supported inputs are Nara CSV, the existing Nara JSON conversion, and Little Log CSV/JSON backups.

The [Nara schema reference](reference/nara/README.md) tracks sample collection and
mapping decisions for additional activity types and future Little Log features.
It includes verified exports, implemented mappings and formats still awaiting
app-generated evidence.

## CSV contract

The exported baby’s name must match the selected baby in Little Log, ignoring capitalization and surrounding spaces. A mismatch rejects the file before saving and displays: “Baby name doesn’t match the selected baby.” Files containing multiple babies are rejected separately.

Identification uses the CSV contents, not its filename. Nara recognition requires Type, Profile Name, Start Date/time (Epoch), _familyKey, _profileKey, and _activityKey headers. Duplicate or unnamed columns, missing IDs/types, and invalid rows are rejected before saving. This verifies format compatibility; CSV has no signature proving which app created it. Little Log backups remain accepted through their own strict validation.

Column names, sparse activity columns, epoch milliseconds, FLOZ volumes, manually entered nursing markers, and the shortened Profile row are grounded in the user-supplied October 8, 2026 Nara export. The checked-in fixture contains synthetic data only.

Supported baby CSV types: Diaper, Bottle Feed, Breastfeed, Combo Feed, Pump, Sleep, Solid Feed, Growth, Medical, Vaccine, Routine, Baby First, Milestone, and child Profile. Other activity types and unknown populated columns appear in the exclusion report, with source row, activity type, timestamp, record ID, and reason. Saving supported rows requires explicit consent when unsupported entries exist. Invalid values, duplicate IDs, malformed CSV, mixed babies/families, or conflicting existing entries stop the import. No silent row loss.

Combo feeds split into nursing and bottle activities. Growth rows split into one record per populated measurement; solids, medicines and vaccines split into individual entries. Medical temperatures become one standalone temperature entry per source row, regardless of medicine count. Every component retains the complete source row and a stable component identity. Changed source groups are rejected instead of appending replacement components alongside old ones.

Solids map the explicit allergic-reaction flag, never LOVE/LIKE preference, to the reaction field. Missing flags stay “Not recorded.” Food-specific notes appear with the entry; meal, preparation, amount eaten and preference are preserved in source metadata. Medication names without an exported dose display “Not recorded.” Open sleep entries and ambiguous repeated food/medicine/vaccine names are listed as exclusions and require supported-only consent; no end time or missing dose is invented. Parent and pregnancy profiles are rejected because Little Log imports baby activities.

The October 13 app-generated child fixture has 23 source activities. It produces 30 Little Log activities by default, or 32 with both unassigned pumps included, plus the baby profile. All completed baby source entries are represented; split records explain the higher destination count. Native Nara CSV omits appointments and attachments, so this import cannot recover them.

Photos and image attachments are permanently out of scope, including future
migration support. The measured CSVs already contain no images; their storage
size includes textual activity details and import source metadata.

Pumping entries without a child assignment are excluded by default and listed individually. A separate control explicitly includes them for the selected baby. The preview date range and counts update when the choice changes.

Epoch timestamps are authoritative. Volumes use exact US-fluid-ounce conversion. Nursing retains left/right seconds and never invents an end time. Raw populated source fields, notes, caregiver names, and timezone are retained in record source metadata.

## Provenance and recovery

Imported records carry `source.system = Nara Baby` and the original record ID and fields. Nara Baby appears on the collapsed history row and the expanded details. Existing edit paths preserve source metadata; CSV and JSON backups preserve it as well.

Undo last import is available for the latest mutation. Remove Nara Baby imports previews a count and requires confirmation; it soft-deletes only Nara-sourced records in the current baby, including edits derived from those records. Manual entries remain. Removal itself can be undone. Stale previews and changes during confirmation are rejected atomically. Undo refuses to overwrite subsequent edits.

Import reports are saved atomically with records and survive reopening the database. They retain exclusion details, counts, source IDs, and undo status. Reports are local to the importing device; record provenance is carried in the shared log. Deleted source entries remain deduplicated on reimport rather than being silently resurrected.

## Test suite

- `test/import/nara_full_csv_test.dart`: all observed baby types, split records, stable group identity, units, allergy semantics, open-sleep exclusions, cross-midnight intervals, incremental coverage, backup/storage/undo and full CSV sync.
- `test/import/nara_csv_test.dart`: exact mappings, CSV quoting, Unicode, header reordering, BOM, numeric/unit validation, malformed input, explicit partial import, and duplicate/conflict handling.
- `test/import/file_import_test.dart`: selection/cancellation, replacement failures, preview before save, races, repeated taps, small screens/large text, excluded-row consent, reports, and Nara-only removal/undo.
- `test/import/import_sync_test.dart`: two isolated devices sharing a synthetic CSV cloud, caregiver corrections, stale removal, offline retry, lost upload responses, and removal/undo convergence.
- `test/import/import_edit_provenance_test.dart`: imported profile edits and resumed nursing preserve source tags; nursing notes survive pause/restart/finish.
- `test/import/import_storage_test.dart`: disk reopen, recovery receipts, no partial writes, preserved manual history, and persisted exclusion reports.
- Existing import confirmations and history conversion tests remain part of regression coverage.
- `integration_test/import_harness_test.dart` runs the dedicated suite on iOS simulators and Android emulators. Picker return values are injected for deterministic automated coverage.
- `tool/import_picker_review.dart` runs the actual app UI with an isolated in-memory log for manual native-picker verification. It never opens the user's production database.
- `tool/run_android_import_picker.sh emulator-5554` builds the in-memory harness and runs the Android DocumentsUI test through import, Nara-only removal, and undo, saving screenshots and a test result under `build/import-picker-qa`. It rejects physical devices. Pass a second argument to choose an artifact directory. The test uses the synthetic CSV in Downloads.
- `tool/import_crash_probe.dart`: force-kills subprocesses before, during, and after a 1,500-record import; checks atomic records/report/receipt recovery and undo against temporary on-disk databases.
- `tool/import_upgrade_probe.dart`: seeds a specifically named QA database using the prior build, then verifies an in-place upgrade preserves settings, manual history, a paused nursing timer, and legacy undo. Compile the old build with `QA_UPGRADE_SEED=true`, and the candidate without it. Run only on emulators.
- `tool/check_private_import.dart` validates a private export without writing records. Private inputs and reports remain outside Git.

Build numbers stay unchanged during development. No production log, Drive file, or physical phone is modified by this test workflow.

## Release validation boundaries

The native picker test selects a local synthetic file. Expired provider access, interrupted streams, and misleading file sizes are covered with simulated provider failures; a live iCloud/Google Drive file-provider download is not verified by those tests. Two-device sync tests use an isolated CSV-backed fake cloud rather than a production account.

Build release artifacts in a separate checkout from concurrent debug builds. Run `flutter build apk --release` with dependency/plugin regeneration enabled; `--no-pub` can retain debug registration for integration_test while the release Gradle configuration excludes that plugin. iOS release validation compiles without signing; simulator runs are debug builds and are not a signed TestFlight installation.
