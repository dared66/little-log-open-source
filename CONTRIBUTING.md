# Contributing to Little Log

Thanks for helping improve Little Log.

## Development setup

1. Install the stable Flutter SDK described by `.metadata`.
2. Run `flutter pub get`.
3. Run `flutter test` and `flutter analyze` before submitting a change.

Google integration is optional for local development. To test it, copy
`config/google.example.json` to the ignored `config/google.local.json`, add
your own Google Cloud identifiers, and follow `docs/GOOGLE_SETUP.md`. Never
commit tokens, client secrets, signing keys, real family records, or the local
configuration file.

See [configuration storage](docs/CONFIGURATION.md) for local and live-test setup.
Ordinary tests and public pull-request CI must not require private configuration.

## Pull requests

- Keep each change focused and explain its user-visible effect.
- Add or update tests for behavior changes.
- Preserve compatibility with released builds 54 and 58, including mixed-version
  edits and sync. Run `python3 scripts/check_build54_compatibility.py`; do not
  modify the frozen readers or fixtures to make a change pass.
- Use synthetic family data in tests, screenshots, logs, and bug reports.
- Do not weaken the `drive.file` scope, API-key restrictions, conditional
  writes, or CSV validation to make a test pass.

By contributing, you agree that your contribution is licensed under the MIT
License included in this repository.

## Publication checks

After staging a change, run `python3 scripts/check_public_source.py`. This checks
the staged content even if the working copy was subsequently cleaned. CI also
checks new commits for private files and real live-test settings, and runs a
version-pinned Gitleaks scanner against the current source and every new commit.
Deleting a secret in a later commit does not make the earlier commit safe.

Maintainers can add `--private-config /path/to/private/live-tests.json` locally
to detect exact private test references. The file and its values are never
included in CI or printed by the check. CI cannot identify arbitrary personal
information, so review screenshots, fixtures and prose before publishing.

See [third-party notices](THIRD_PARTY_NOTICES.md) when adding dependencies or assets.

Maintainers moving changes from private development must follow the
[publication process](docs/PUBLICATION.md), including review of outgoing commit
history and metadata.
