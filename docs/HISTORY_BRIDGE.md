# Nara Baby ↔ Little Log file conversion

These scripts make local files. They never create, edit, or delete Nara Baby
activities, and they do not upload a Little Log CSV to Google Drive. Keep exports
private: they contain your child's activity history and original Nara record
metadata. Use `private-exports/` (ignored by Git) or another private folder.

## Read Nara and create a Little Log CSV

On macOS with the [nara-baby skill](https://github.com/jfchenier/nara-baby-tracker-api)
installed and configured in Keychain:

```sh
~/.local/share/skill-keychain/venv/bin/python scripts/export_nara_to_little_log.py \
  --child "Robin" --output private-exports/robin.csv
```

This reads the named child's verified profile and complete activity history
through the skill's read-only client. The child name must identify one profile.
It uses the timezone and family saved by the skill. Override them with
`--timezone America/Los_Angeles` and `--family KEY` when needed. The script
ignores unrelated old preference fields without changing the preference file.
The converter currently supports the verified Nara diaper, breast nursing,
and bottle schemas. Unknown activity types or volume encodings stop conversion
before replacing the output file. Original Nara records, including millisecond
nursing durations and source timezone, are retained in CSV schema 6 metadata.
A missing nursing end time stays missing.

To preserve an existing Little Log family ID and merge rather than start a new
family CSV, add `--base-csv path/to/existing.csv`. Existing rows and deletion
markers are retained; identical entries are skipped; conflicting IDs stop the
conversion. To replace earlier approximate entries, use Little Log's in-app
Import and recovery preview. The script does not delete unrelated records.

Caregiver names can be supplied with an optional private JSON mapping:

```json
{"NARA_CAREGIVER_KEY": "Caregiver name"}
```

Pass it with `--caregivers private-exports/caregivers.json`. Without a mapping,
distinct caregivers get numbered labels. Do not put real caregiver keys in Git.

An existing exported `{ "profile": ..., "tracks": ... }` Nara JSON can be
converted offline without the Nara login:

```sh
dart run tool/history_bridge.dart from-nara \
  --input private-exports/nara.json --output private-exports/robin.csv
```

## Convert Little Log CSV back to a Nara-shaped file

```sh
python3 scripts/little_log_to_nara.py \
  --input private-exports/robin.csv --output private-exports/robin.nara-bridge.json
```

This creates **Nara-shaped bridge JSON**, not a file accepted by the Nara app or
a Nara API write request. It contains `profile` and `tracks` for inspection, plus
a `littleLogRecord` field on every track. That field preserves all Little Log
categories, source details, baby profile, exact timestamps, and deletion markers.
The bridge can be converted back to the same CSV:

```sh
dart run tool/history_bridge.dart from-nara \
  --input private-exports/robin.nara-bridge.json \
  --output private-exports/robin-roundtrip.csv
```

The offline tool uses Little Log's own CSV parser, validation, and event mapping.
It accepts `--base-csv` and `--caregivers` for Nara-to-CSV conversion. Both
commands write a temporary file and replace the output only after conversion
succeeds. Use distinct input and output paths.

## Verification

```sh
python3 -m unittest scripts/test_history_bridge.py
flutter test test/history_bridge_test.dart
flutter analyze
```

Tests use synthetic records and mocked Nara access. Do not commit real exports,
credentials, or caregiver mappings.
