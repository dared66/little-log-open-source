#!/usr/bin/env python3
"""Describe a Nara CSV without importing or changing any records.

Values are omitted by default. --synthetic-values is only for an export made
entirely from synthetic test profiles; shared names, notes and IDs stay omitted.
"""
import argparse
import csv
import hashlib
import io
import json
from collections import Counter, defaultdict
from pathlib import Path


REQUIRED = {'Type', 'Profile Name', 'Start Date/time (Epoch)',
            '_familyKey', '_profileKey', '_activityKey'}
CURRENT_TYPES = {
    'Diaper', 'Bottle Feed', 'Breastfeed', 'Pump', 'Profile', 'Combo Feed',
    'Sleep', 'Solid Feed', 'Growth', 'Medical', 'Vaccine', 'Routine',
    'Baby First', 'Milestone',
}


def analyze(path, synthetic_values=False):
    raw = Path(path).read_bytes()
    rows = csv.reader(io.StringIO(raw.decode('utf-8-sig'), newline=''))
    header = next(rows, [])
    if not header or len(header) != len(set(header)) or any(not h.strip() for h in header):
        raise ValueError('Missing, unnamed, or duplicate CSV columns.')
    missing = REQUIRED - set(header)
    if missing:
        raise ValueError('Missing Nara columns: ' + ', '.join(sorted(missing)))
    counts, populated = Counter(), defaultdict(Counter)
    values = defaultdict(lambda: defaultdict(set))
    widths, empty_profiles = Counter(), Counter()
    for row_number, cells in enumerate(rows, 2):
        if not cells or not any(cells):
            continue
        widths[len(cells)] += 1
        if len(cells) > len(header):
            raise ValueError(f'Row {row_number}: too many columns.')
        row = dict(zip(header, cells + [''] * (len(header) - len(cells))))
        kind = row['Type']
        if not kind:
            raise ValueError(f'Row {row_number}: missing activity type.')
        shortened_profile = (kind == 'Profile' and len(cells) == len(header) - 1
                             and header[-1] == '_activityKey')
        if len(cells) != len(header) and not shortened_profile:
            raise ValueError(f'Row {row_number}: incomplete row.')
        counts[kind] += 1
        if not row['_profileKey'] and not row['Profile Name']:
            empty_profiles[kind] += 1
        for key, value in row.items():
            if value:
                populated[kind][key] += 1
                if synthetic_values and key.startswith('['):
                    values[kind][key].add(value)
    return {
        'source_sha256': hashlib.sha256(raw).hexdigest(),
        'column_count': len(header), 'columns': header,
        'row_count': sum(counts.values()),
        'observed_row_widths': {str(k): v for k, v in sorted(widths.items())},
        'types': {
            kind: {
                'count': counts[kind],
                'recognized_by_current_csv_importer': kind in CURRENT_TYPES,
                'rows_without_profile': empty_profiles[kind],
                'populated_columns': dict(sorted(populated[kind].items())),
                **({'synthetic_activity_values': {
                    key: sorted(v) for key, v in sorted(values[kind].items())
                }} if synthetic_values else {}),
            } for kind in sorted(counts)
        },
        'limitations': [
            'A recognized type can still contain fields or values the importer rejects.',
            'Only populated fields in this export are observed; blank fields do not prove absence.',
            'This inventory is not an import validation or proof of complete activity coverage.',
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('export', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--synthetic-values', action='store_true')
    args = parser.parse_args()
    try:
        result = analyze(args.export, args.synthetic_values)
    except (OSError, UnicodeError, csv.Error, ValueError) as error:
        parser.exit(1, f'{error}\n')
    text = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    if args.output:
        if args.output.resolve() == args.export.resolve():
            parser.error('Output must not replace the input export.')
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding='utf-8')
    else:
        print(text, end='')


if __name__ == '__main__':
    main()
