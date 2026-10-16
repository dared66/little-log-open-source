# Observed CSV fields

Generated from the final child, postpartum and pregnancy fixtures. Exact headers, row widths, hashes, per-file inventories and sample IDs are in [schema-catalog.json](schema-catalog.json). These are observed values, not exhaustive enums. Blank columns do not establish that a field is unavailable. All CSV cells are strings.

Common headers: `Type`, `Profile Name`, `Start Date/time`, `Start Date/time (Epoch)`, `Created By Caregiver`, `Last Updated By Caregiver`, `Note`, `Time Zone`, `_familyKey`, `_profileKey`, `_activityKey`.

## Baby First

Final rows: 1. Each field below includes the exact `[Baby First]` prefix in the CSV.

| Field after prefix | Observed nonempty values |
| --- | --- |
| Baby First | `Schema first smile` |

## Bottle Feed

Final rows: 2. Each field below includes the exact `[Bottle Feed]` prefix in the CSV.

| Field after prefix | Observed nonempty values |
| --- | --- |
| Breast Milk Volume | `3.5` |
| Breast Milk Volume Unit | `FLOZ` |
| Formula Name | `Aptamil` |
| Formula Volume | `90` |
| Formula Volume Unit | `ML` |
| Type | `Breast Milk`<br>`Formula` |

## Breastfeed

Final rows: 2. Each field below includes the exact `[Breastfeed]` prefix in the CSV.

| Field after prefix | Observed nonempty values |
| --- | --- |
| Begin Side | `LEFT` |
| End Side | `RIGHT`<br>`RIGHT.nonTimer` |
| Left Duration (Seconds) | `264`<br>`600` |
| Right Duration (Seconds) | `300`<br>`33` |

## Combo Feed

Final rows: 1. Each field below includes the exact `[Combo Feed]` prefix in the CSV.

| Field after prefix | Observed nonempty values |
| --- | --- |
| Begin Side | `LEFT` |
| Breast Milk Volume | `1.5` |
| Breast Milk Volume Unit | `FLOZ` |
| End Side | `RIGHT.nonTimer` |
| Formula Name | `Aptamil` |
| Formula Volume | `60` |
| Formula Volume Unit | `ML` |
| Left Duration (Seconds) | `360` |
| Right Duration (Seconds) | `180` |
| Type | `Breast Milk Formula` |

## Diaper

Final rows: 4. Each field below includes the exact `[Diaper]` prefix in the CSV.

| Field after prefix | Observed nonempty values |
| --- | --- |
| Detail | `Blowout Rash` |
| Dirty Color | `BLACK BROWN GRAY GREEN RED YELLOW` |
| Dirty Texture | `MUCOUS MUSH PEBBLE RUN SOLID` |
| Type | `Dirty`<br>`Dirty Wet`<br>`Dry`<br>`Wet` |

## Growth

Final rows: 3. Each field below includes the exact `[Growth]` prefix in the CSV.

| Field after prefix | Observed nonempty values |
| --- | --- |
| Head Size | `15.25`<br>`40.5` |
| Head Size Unit | `CM`<br>`IN` |
| Height | `23.75`<br>`62` |
| Height Unit | `CM`<br>`IN` |
| Weight | `12.21875`<br>`6.4` |
| Weight Unit | `KG`<br>`LB` |

## Medical

Final rows: 2. Each field below includes the exact `[Medical]` prefix in the CSV.

| Field after prefix | Observed nonempty values |
| --- | --- |
| Medication | `Amoxicillin, 1.25 (ML)\nPanadol, 2.5 (MG)` |
| Temperature | `36.6`<br>`99.1` |
| Temperature Unit | `C`<br>`F` |

## Milestone

Final rows: 1. Each field below includes the exact `[Milestone]` prefix in the CSV.

| Field after prefix | Observed nonempty values |
| --- | --- |
| Milestone | `Looks at your face` |

## Postpartum Diet

Final rows: 1. Each field below includes the exact `[Postpartum Diet]` prefix in the CSV.

| Field after prefix | Observed nonempty values |
| --- | --- |
| Food | `Schema salad: foodCategoryKey=GRAIN; note=Synthetic parent food note` |
| Meal | `LUNCH` |

## Postpartum Health

Final rows: 1. Each field below includes the exact `[Postpartum Health]` prefix in the CSV.

| Field after prefix | Observed nonempty values |
| --- | --- |
| Medicine | `Schema supplement, 1 (TAB)` |
| Symptom | `Constipation\nHeadache` |
| Temperature | `36.7` |
| Temperature Unit | `C` |

## Postpartum Hydration

Final rows: 1. Each field below includes the exact `[Postpartum Hydration]` prefix in the CSV.

| Field after prefix | Observed nonempty values |
| --- | --- |
| Volume | `1.5` |
| Volume Unit | `GLASS` |

## Postpartum Journal

Final rows: 1. Each field below includes the exact `[Postpartum Journal]` prefix in the CSV.

| Field after prefix | Observed nonempty values |
| --- | --- |
| None | Content is in shared `Note`. |

## Postpartum Mood

Final rows: 1. Each field below includes the exact `[Postpartum Mood]` prefix in the CSV.

| Field after prefix | Observed nonempty values |
| --- | --- |
| Mood | `HAPPY` |
| Strength | `MEDIUM` |

## Postpartum Routine

Final rows: 1. Each field below includes the exact `[Postpartum Routine]` prefix in the CSV.

| Field after prefix | Observed nonempty values |
| --- | --- |
| Routine | `Schema walk` |

## Postpartum Sleep

Final rows: 1. Each field below includes the exact `[Postpartum Sleep]` prefix in the CSV.

| Field after prefix | Observed nonempty values |
| --- | --- |
| Duration (Seconds) | `1800` |
| End Date/time | `2026-10-13 11:59:38` |
| End Date/time (Epoch) | `1791917978000` |

## Pregnancy Health

Final rows: 1. Each field below includes the exact `[Pregnancy Health]` prefix in the CSV.

| Field after prefix | Observed nonempty values |
| --- | --- |
| Diastolic Blood Pressure | `80` |
| Diastolic Blood Pressure Unit | `MMHG` |
| Glucose | `5.3` |
| Glucose Unit | `MMOLL` |
| Systolic Blood Pressure | `120` |
| Systolic Blood Pressure Unit | `MMHG` |
| Temperature | `98.2` |
| Temperature Unit | `F` |
| Weight | `160.5` |
| Weight Unit | `LB` |

## Pregnancy Journal

Final rows: 1. Each field below includes the exact `[Pregnancy Journal]` prefix in the CSV.

| Field after prefix | Observed nonempty values |
| --- | --- |
| None | Content is in shared `Note`. |

## Pregnancy Medicines

Final rows: 1. Each field below includes the exact `[Pregnancy Medicines]` prefix in the CSV.

| Field after prefix | Observed nonempty values |
| --- | --- |
| Medicine | `Schema drops, 2 (DROP)\nSchema syrup, 0.5 (TSP)` |

## Pregnancy Mood

Final rows: 1. Each field below includes the exact `[Pregnancy Mood]` prefix in the CSV.

| Field after prefix | Observed nonempty values |
| --- | --- |
| Mood | `ANXIOUS` |
| Strength | `LOW` |

## Pregnancy Symptoms

Final rows: 1. Each field below includes the exact `[Pregnancy Symptoms]` prefix in the CSV.

| Field after prefix | Observed nonempty values |
| --- | --- |
| Symptom | `Fatigue\nNausea\nSchema symptom` |

## Profile

Final rows: 3. Each field below includes the exact `[Profile]` prefix in the CSV.

| Field after prefix | Observed nonempty values |
| --- | --- |
| Birth Date | `2026-09-13` |
| Birth Date (Adjusted) | `2026-10-13` |
| Sex | `FEMALE` |
| Type | `CHILD`<br>`PARENT`<br>`PREGNANCY` |

## Pump

Final rows: 2. Each field below includes the exact `[Pump]` prefix in the CSV.

| Field after prefix | Observed nonempty values |
| --- | --- |
| Duration (Seconds) | `0`<br>`1200` |
| End Date/time | `2026-10-13 11:38:46`<br>`2026-10-13 13:03:00` |
| End Date/time (Epoch) | `1791916726441`<br>`1791921780000` |
| Left Volume | `1.25` |
| Left Volume Unit | `FLOZ` |
| Right Volume | `0.75` |
| Right Volume Unit | `FLOZ` |
| Total Volume | `110` |
| Total Volume Unit | `ML` |

## Routine

Final rows: 1. Each field below includes the exact `[Routine]` prefix in the CSV.

| Field after prefix | Observed nonempty values |
| --- | --- |
| Routine | `Bath` |

## Sleep

Final rows: 2. Each field below includes the exact `[Sleep]` prefix in the CSV.

| Field after prefix | Observed nonempty values |
| --- | --- |
| Duration (Seconds) | `2700`<br>`586` |
| End Date/time | `2026-10-13 11:33:38`<br>`2026-10-13 11:43:38` |
| End Date/time (Epoch) | `1791916418000`<br>`1791917018000` |

## Solid Feed

Final rows: 1. Each field below includes the exact `[Solid Feed]` prefix in the CSV.

| Field after prefix | Observed nonempty values |
| --- | --- |
| Food | `Apple: allergy=true; amountKey=ALL; preparationKeyz=PUREE; reactionKey=LOVE; note=Synthetic food note\nBanana: amountKey=SOME; preparationKeyz=RAW; reactionKey=LIKE` |
| Meal | `BREAKFAST` |

## Vaccine

Final rows: 1. Each field below includes the exact `[Vaccine]` prefix in the CSV.

| Field after prefix | Observed nonempty values |
| --- | --- |
| Vaccine | `DTaP\nHepB` |
