# Nara feature comparison and implementation

Reviewed September 18, 2026 against the publisher's [Nara listing](https://apps.apple.com/us/app/nara-baby-pregnancy-tracker/id1444639029) and [Nara FAQ](https://nara.com/pages/nara-baby-app-faqs). This comparison describes Little Log's activity coverage; later changes are noted below.

## Added

| Area | Available now |
| --- | --- |
| Sleep | Manual start/end entry, persistent local timer, last-sleep wake interval, daily completed-sleep totals split at local midnight |
| Pumping | Milk volume in ml, persistent local timer, daily pumped total kept separate from bottle intake |
| Solids | Food names, explicitly selected observed reaction, notes and time |
| Growth | Weight (kg/lb), length and head circumference (cm/in), dated measurement history |
| Health | Medication name and administered dose with unit, vaccines, temperature (C/F), symptoms and doctor visits |
| Routines | Named routine entries, timestamps and notes, including tummy time/bath/story time |
| Milestones | Named milestones and dated notes |
| Diapers | Wet, dirty, both and dry; dirty/both support poop color, consistency and blowout; all kinds support rash. Optional observations distinguish unrecorded from explicit yes/no. Details display in Today and History and persist through export/sync. |
| History | Date picker, previous/next day, activity filtering, daily totals and caregiver attribution |
| Storage | All new completed entries use the offline queue, CSV merge/sync and JSON export; sleep/pumping timers survive reopening |

Existing bottles, manual nursing, per-side nursing timers, family switching, caregiver sharing and local export remain available. No Nara account or real baby data was accessed for development.

## Compatibility

CSV adds a final `details_json` column; new categories use event schema 3; diapers with observations use event schema 4 in the same 18-column file. Plain diapers retain schema 2. Existing 17-column CSVs and event schemas 1/2 are still readable. Existing event rows keep their canonical identity during migration. Unsupported versions fail closed. Update all caregivers before syncing a newly written 18-column CSV: an older build will reject the new header rather than silently drop new activities. JSON export is schema 3 and includes separate activities and active timers.

Timers remain device-local. Completed entries participate in the existing family sync; this change does not establish that live Drive conditional writes or two-account sharing work. Those acceptance checks remain open from the CSV spike. Day totals use the device's local timezone; active sleep is shown by its timer and is excluded from completed-sleep totals.

## Remaining gaps compared with Nara

- Scheduled/background notifications, wake-window reminders and appointments.
- WHO growth percentile charts and reference datasets; current growth history stores measurements without interpreting them.
- Curated age-based developmental checklists and preloaded food lists; current entries are user-authored.
- Weekly comparison charts and custom tracking visibility.
- Parent pregnancy/postpartum profiles, vitals, mood and journals.
- Apple Watch, Siri and general home-screen widgets. iOS timer Live Activities are implemented.
- Live shared timers and per-side pumping. Nursing pause/resume is implemented in build 24.

These are separate follow-on implementations; this release adds the missing core baby activity categories and daily history, not complete parity with Nara.

## Permanently excluded

Photos, image attachments, and image sharing/sync are excluded by the owner's
October 13, 2026 decision. They are not future feature or migration work. The
measured Nara CSV fixtures contain no image bytes or attachment URLs; their larger
Little Log backups come from retained textual source details.


## Bottle and diaper correction

Bottle entry, manual nursing and diapers now have separate entry points and fixed forms. Bottle entry cannot change into nursing. Each screen has a specific title and save action. Diaper observations are optional; switching from Dirty/Both to Wet/Dry clears poop color, consistency and blowout but retains rash. Historical missing observations are never inferred as negatives. See [detailed verification](CARE_ENTRY_REVIEW.md).

## Build 24: migration fidelity and entry features

Mixed diaper colors/textures, bottle milk/formula components, duration-only nursing,
durable nursing pause/resume, baby birth date/age/sex/night-hour settings, and
source-aware import with caregiver mapping are implemented. Settings contains
Import and recovery (paste export, preview, duplicate checks, transactional apply,
and undo). Nara import supports the observed bottle, nursing, and diaper records;
unsupported categories fail without partial imports. Original source payloads
are retained. Legacy CSV rows retain their identities.

Profile snapshots sync as versioned events; calendar-day history is unchanged.
These changes do not implement the broader reminders, percentile-chart,
shared-timer, per-side-pumping, journal, or long-term-trend gaps listed above.

Validation: all 111 existing/added regression tests passed, including the full
flow journey, plus the new screen review test. Static analysis passed. Screen
captures use synthetic Robin data. Build 24 is based on b73791e plus working
changes; physical-device installation is verified separately in the task output.
