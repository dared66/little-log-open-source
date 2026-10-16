# Migration mapping and fidelity decisions

These mappings are implemented for the observed baby CSV types. The fixtures
ground parsing and fidelity decisions; future parent/pregnancy scope stays separate. Current source contracts are in
[activity_details.dart](../../../lib/activity_details.dart),
[nara_csv.dart](../../../lib/services/nara_csv.dart) and
[IMPORT_MIGRATION.md](../../IMPORT_MIGRATION.md).

## Current coverage

The CSV importer supports all thirteen baby activity Type values in the final
fixture plus child Profile. It produces 30 activities + profile by default and
32 activities + profile with both unassigned pumps included. Every completed baby
source row is represented. See [validation.json](validation.json).

Parent/pregnancy profiles are rejected. Other types, unknown populated columns,
unfinished sleep and ambiguous compound entries are explicit exclusions requiring
supported-only consent. Unassigned pumps retain their separate opt-in. Original
supported-type IDs are unchanged; new split records use stable component IDs.
Source-group checks prevent a changed list with new component IDs from appending
a conflicting second copy. The tests cover disk persistence, backups, editing,
repeat import, undo/removal and synthetic two-device CSV sync.

## All ten Little Log activities

| Little Log category | Observed Nara source | Implemented mapping / fidelity policy |
| --- | --- | --- |
| Bottle | Bottle Feed; bottle component of Combo Feed | Convert ML and US FLOZ exactly (1 FLOZ = 29.5735295625 ML). Preserve breast milk/formula amounts independently, formula name and original units. Mixed combo has no total; sum normalized components. Cross-check totals when present; do not double-count components plus total. |
| Nursing | Breastfeed; nursing component of Combo Feed | Preserve left/right seconds and begin/end side including `.nonTimer`. Manual and completed timer are sampled. No exported elapsed end; preserve source marker rather than inventing end time. |
| Diaper | Diaper | Wet, Dirty, Dirty Wet and Dry sampled. Blowout/Rash, all six offered colors and all five offered textures sampled in one multiselect record. Missing observations remain unknown; selected observations are affirmative. Existing mapping translates MUSH/RUN/MUCOUS/PEBBLE/SOLID to mushy/watery/mucousy/hard/formed. |
| Sleep | Sleep | Completed intervals map to `at`/`endedAt`; reconcile duration with epoch difference. Keep seconds even though display rounds to minutes. Open timer cannot satisfy the current completed-record validator; report it as an exclusion requiring supported-only consent. Do not end it at import time. |
| Pumping | Pump | Preserve total and side volumes, units and interval in source. Use explicit total or normalized side sum; validate if both present. Volume-only source exports zero duration and start=end. Do not create a sleep-style positive-duration requirement. Both samples are unassigned; retain opt-in and never infer baby identity. |
| Solids | Solid Feed | Food cell contains per-food allergy, amount, preparation, preference and note; shared Meal is also exported. Current destination has only food and allergy-reaction fields. LOVE/LIKE are preference values, not allergy reactions. Nara’s checkbox is labeled Allergic Reaction: true maps to Reaction observed, explicit false to No reaction observed, absent to Not recorded. Create one record per food; preserve meal and per-food attributes in source metadata, and include the per-food note with the shared note. |
| Growth | Growth | Split one source into one record per populated Weight, Height, Head Size. Destination measurement labels are Weight, Length, Head circumference. Preserve KG/LB and CM/IN. 12 lb 3.5 oz exports as `12.21875` LB, with no separate ounces column. Missing measurements create no record. One metric row, one mixed-unit row and one head-only IN row sampled. Date-only source uses local midnight. |
| Health | Medical; Vaccine | Create one record per medication or vaccine. Medical temperature becomes one standalone temperature record per source entry, separate from medicines; it is not duplicated across medicines. Missing medication dose displays Not recorded, without inferring an amount. Dose units sampled across profiles are ML/MG/TAB/DROP/TSP. Child temperature-only row has no Medication cell. Child symptoms and doctor visits lack native CSV evidence in this collection. |
| Routine | Routine | Map the exact selected/custom name to details.name; keep shared notes/time. Child Bath sampled; custom Schema walk sampled in postpartum only. The picker selected one routine per entry; no multi-routine or duration source established. |
| Milestone | Baby First; Milestone | Both source types map to milestone details.name. Preserve distinction in source: free Baby First text versus curated checklist Milestone text. No curated backend ID is exported; do not invent one. |

`Combo Feed` uses a stable one-to-many conversion into nursing and bottle.
Do not discard a populated component because the other component is missing or
unsupported. Reconcile by source entry and component rather than equating CSV
rows with destination record counts.

## Parent and pregnancy future scope

| Exact Type | Future destination considerations |
| --- | --- |
| Postpartum Hydration | Volume with GLASS unit. No glass capacity exported: never assume an ML conversion. |
| Postpartum Diet | Meal plus food, foodCategoryKey and per-food note. Selected category is single-valued (last selection won). |
| Postpartum Health | Medicine (different header from child Medication), Symptom, Temperature/Unit. Preserve subject and multi-value health details. |
| Postpartum Mood | Mood HAPPY; UI Moderate exports strength MEDIUM. Future parent mood model required. |
| Postpartum Journal | Shared Note only; Unicode, quoting and line breaks verified. |
| Postpartum Routine | Routine name; custom example. |
| Postpartum Sleep | Completed interval with seconds and end epoch. |
| Pregnancy Health | Weight, temperature, glucose, systolic/diastolic pressure with separate units. Sample LB/F/MMOLL/MMHG; no assumptions about other available units. |
| Pregnancy Medicines | Medicine cell, newline-separated doses; sample DROP and TSP. |
| Pregnancy Symptoms | Symptom cell, newline-separated predefined and custom names. |
| Pregnancy Mood | ANXIOUS; UI Mild exports LOW. Other enum values unverified. |
| Pregnancy Journal | Shared Note; attached image absent from export. |
| Profile PARENT/PREGNANCY | Keep separate subject identity. Never import these activities into a baby simply because a child export/import destination is selected. |
| Appointments (UI only) | Date/time, appointment type, questions/notes, optional photo control. Upcoming and Past sampled, neither exported. Needs another authorized source or explicit manual transfer; no CSV parser can recover absent entries. |

Pregnancy due date and appointment records need independent collection if
future Little Log features support them. UI-only field labels are not API keys.
Do not route maternal symptoms or appointments to child health automatically.

Photos and image attachments are permanently excluded from Little Log by the
owner's October 13, 2026 decision. Attachment observations remain export-format
evidence only; do not plan another media source or future attachment migration.

## Identity, parsing and validation

- Preserve current IDs for already supported types. New split mappings need a
  deterministic source-ID + component identity (for example growth:weight,
  combo:nursing, combo:bottle), with no collisions with existing import IDs.
  Medication, food and vaccine component IDs use the exact name rather than list
  index or dose, so reordering does not change IDs. Duplicate names are explicitly
  excluded as ambiguous. Changing any original source field blocks reimport of
  that source group, including when all component names were replaced.
- Group split records with source system, source ID, component and original fields.
  Reimport, edit, deduplication, sync, soft deletion, remove-imports and undo must
  reconcile the entire group without resurrecting deleted records.
- Use a proper multiline CSV parser first. Then parse compound cells only under
  a verified grammar. Custom names/notes may contain delimiters; preserve the raw
  cell and report ambiguity instead of silently truncating or guessing.
- Unit validation must be specific to the source type and field. Keep exact unit
  tokens in provenance. Empty cells are missing information, not zeros or negative
  observations, except where the source explicitly exports `0`.
- Epoch milliseconds take precedence; preserve timezone and date-only semantics.
  Confirm subsecond precision, daylight-saving and cross-midnight behavior using
  additional fixtures before claiming those edge cases are covered.
- For each new mapping, add focused tests using these fixtures: expected fields
  and record counts, exclusions, mixed supported/unsupported rows, edits, repeated
  import, duplicate/conflict handling, provenance, undo/removal and sync. Test
  open-timer policy and multi-component identity separately.

## Verified sample groups

Child markers 01–18 cover the first baseline. Added markers 33, 33b, 34, 35 and
36 cover imperial/head-only growth, temperature-only Medical, total-only Pump and
side-switching nursing timer. Postpartum markers 19–25 cover all seven categories.
Pregnancy markers 26–30 cover all five exported categories; 31/32 are saved
appointments absent from CSV. The catalog links each marker to its fixture and
synthetic source ID. No marker 37 was saved: its unused bottle draft was discarded.
