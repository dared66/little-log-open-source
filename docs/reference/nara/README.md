# Nara migration schema reference

Collected 2026-10-13 from Nara Baby Android **2.8.2 (405)** in the dedicated
`nara_schema_reference` Android 36 emulator. Synthetic child, postpartum and
pregnancy profiles were created through the app in a user-authorized test account.
Each available activity category was exercised, including upcoming and past
pregnancy appointments. Final CSVs contain **35 activities, 3 profiles and 26
unique Type values** (25 activity types plus Profile). Two additional saved
appointments are visible in the app but absent from the CSVs.

This reference supports migration planning and future Little Log entry types.
It documents the observed export format; it is not an exhaustive list of every
possible custom value, combination, timer state, or Nara backend field.
The CSV importer now covers every completed baby activity type in these fixtures
across all ten Little Log categories. The 23 baby source activities become **30
Little Log activities by default, or 32 including both unassigned pumps**, plus
one profile. Split combo feeds, growth measurements, foods, medicines and vaccines
account for the higher destination count. Parent/pregnancy activities remain
outside Little Log’s baby model; unfinished and ambiguous records are explicitly
reported. See [validation.json](validation.json) for verification.

## Files to use

- [FIELDS.md](FIELDS.md): exact populated columns and observed values for every
  exported type, including units and compound cells.
- [schema-catalog.json](schema-catalog.json): machine-readable per-file inventories,
  hashes, exact header order, row widths, counts, sample markers and stable
  synthetic source IDs.
- [validation.json](validation.json): fixture checks and implemented importer verification.
- [MAPPING.md](MAPPING.md): mappings and fidelity decisions for all ten Little Log
  activity categories, implemented coverage and future implementation checklist.
- [ui-only-observations.json](ui-only-observations.json): appointments, pregnancy
  due date and photo attachment evidence that the native CSV cannot represent.
- [fixtures/child-final.csv](fixtures/child-final.csv): 23 baby activities + profile;
  nursing manual/timer, bottle milk/formula, combo, solids, pumps, diapers, sleep,
  routine, baby first, milestone, growth, medical and vaccines.
- [fixtures/postpartum.csv](fixtures/postpartum.csv): seven postpartum activities
  + parent profile: hydration, nutrition, health, mood, journal, routine and sleep.
- [fixtures/pregnancy.csv](fixtures/pregnancy.csv): five pregnancy activities +
  pregnancy profile: vitals, medicines, symptoms, mood and journal.
- [fixtures/child-open-timer.csv](fixtures/child-open-timer.csv) and
  [fixtures/child-completed-baseline.csv](fixtures/child-completed-baseline.csv):
  before/after exports of the same sleep timer, with the same source ID.
- [fixtures/postpartum-after-appointments.csv](fixtures/postpartum-after-appointments.csv):
  second parent export confirming appointments did not appear there either.

The six repository fixtures replace only nonempty `_familyKey`, `_profileKey`,
`_activityKey` values with consistent synthetic IDs. All other decoded cells,
header order and row widths are preserved; CSV quoting is reserialized with CRLF.
Profile rows retain Nara's omitted final empty `_activityKey` cell. No password,
email, session credential or real family record is included. Original app exports
remain byte-for-byte in the local workspace under
`output/nara-schema-reference-2026-10-13/exports/` outside this repository. Both
original and fixture SHA-256 hashes are recorded in the catalog.

## Observed format and limits

The CSV is wide and sparse, with activity columns prefixed by the exact Type.
Headers vary with exported content; do not assume one fixed order or column count.
Epochs are milliseconds and should be authoritative. Human timestamps use seconds
and can omit subsecond precision. The sample timezone is `America/Los_Angeles`.
Growth observations use local midnight; do not interpret that as a measured time.

Multiple foods, medicines, vaccines and symptoms use newline-separated text inside
quoted CSV cells. Food attributes use `:` and `;`; medicine doses use a comma and
parenthesized unit. These are observed serializations, not proven unambiguous
parsers for arbitrary custom text. Preserve the entire original cell.

Both pump records have empty profile name and profile key although entered from
the child screen. They remain unassigned source records. One pump has separate
left/right FLOZ volumes and a 1,200-second interval. The total-only 110 ML pump
exports duration `0` and identical start/end epochs. Never infer a missing child
assignment or a positive duration from the displayed volume.

The open sleep timer exports its start and note, with duration/end columns empty.
After completion the same ID has duration `586` seconds and end epoch exactly
586,000 milliseconds later. Nursing manual entries export an end-side marker
such as `RIGHT.nonTimer`; the completed side-switching timer exports `RIGHT`,
left `264` and right `33` seconds. Neither nursing form exports an elapsed end
column. Do not invent one by adding active feeding time to the start.

The child profile exports birth date, adjusted birth date and `FEMALE`. Parent
and pregnancy profiles export `PARENT` and `PREGNANCY`; pregnancy due date is not
in the CSV. Appointments created before the pregnancy and second parent exports
are absent from both files. A saved journal with a synthetic image exports only
its note: no attachment column, URL or image bytes. The Nara UI screenshots are retained privately and excluded from the public
source; the observed fields remain recorded in `ui-only-observations.json`. These limits
apply to the tested version and export path, not every possible Nara export.

The quoted, comma-containing, multiline Unicode journal note round-trips intact.
No separate child symptom/doctor-visit activity was observed in the enabled child
Health forms; those Little Log destinations need separate source evidence. Parent
symptoms and pregnancy appointments are not child records.

## Implemented import verification

All 112 import regression tests passed, including full fixture mappings, native
preview controls, editing, backups, disk persistence, deduplication, undo/removal
and synthetic two-device sync. Static analysis passed. Little Log 1.0.0 (51) was
installed and launched on the dedicated Android emulator and iPhone 17 Pro iOS
simulator. These builds include the migration changes on top of the recorded
baseline; source file hashes are in validation.json.

The original Nara child export was selected through Android DocumentsUI and
imported into a fresh **local-only Schema Baby** log on emulator-5580. The
[saved native report](evidence/little-log-import-saved.png) confirms 32 activities
added, with the baby profile included and no unsupported exclusions. The
[preview](evidence/little-log-import-preview.png) shows counts across all ten
categories. Selecting the same file again reported 33 already imported and no
new entries. The original export SHA-256 remained unchanged. iOS was built and
launched; this native file-picker import was exercised on Android.

## Heavy validation on the polish branch

The combined `polish/activity-rows-swipe-reminders` worktree passed 346 host
Flutter tests, 8 Python tests, static analysis and 270 native checks on each
platform. Android needed three targeted reruns after fixing two test assumptions
and connecting the local profiler; all passed. A derived CSV with 4,600 source
activities produced 6,400 activities plus profile and passed backups, disk reopen,
malformed-row rejection, undo and deduplication. Six interrupted-import recovery
scenarios also passed. See [heavy-validation.json](heavy-validation.json).

Run the repeatable bulk CSV check from the repository root:

```sh
dart run tool/nara_csv_stress_probe.dart
```

These checks used the existing uncommitted polish changes together with this
migration. The commit contains migration files and scoped fixes for the menu
locator and test viewport; other polish changes remain in the worktree.

## Reuse when adding migration support

From the Little Log repository root, inventory a new wholly synthetic export:

```sh
python3 scripts/analyze_nara_export.py path/to/synthetic-nara.csv \
  --synthetic-values --output path/to/inventory.json
```

The tool reads without importing records. Values are omitted unless requested;
shared names, notes and IDs are always omitted from its inventory output. Use
`--synthetic-values` only with synthetic inputs. It validates unique headers and
row widths, including the shortened Profile row. Type recognition alone does not
prove that the importer accepts every row or preserves every field.

For a new Little Log feature, start with the relevant fixture and mapping, add
expected destination records and fidelity decisions, then focused import tests.
Keep the original source fields, attribution, units and identity. Update this
reference when a mapping ships or a new app-generated variant is captured.

Remaining variants needing separate evidence include cross-midnight sleep,
paused/open nursing and pump timers, edited/deleted activity exports, additional
caregiver attribution, mixed-content Bottle Feed, custom child foods/vaccines,
other mood strengths and all offered built-in option values. Cross-midnight behavior has a derived synthetic importer test; it was not separately
created in Nara. The mixed nursing +
bottle sample is a verified `Combo Feed`; it does not establish a mixed Bottle
Feed UI workflow. Do not claim those variants have been verified by these fixtures.

Little Log baseline: `db9f0775a8c631369c7911818082bc19e7b96cec`. APK installed
from APKPure; signing certificate SHA-1
`698f7c70131714d8b5175c20ad385dad9c197bd3`. Exports were generated through
Account → Family → profile → Export Data and saved through a local share receiver
with no network permission. No production import or connected Drive write was run.
