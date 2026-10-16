# Public configuration and private maintainer settings

This repository contains example configuration, synthetic fixtures and public
production OAuth identifiers. A normal checkout must build and run its unit and
widget tests without access to any maintainer account or private repository.
`config/google.production.json` preserves the identifiers used by shipped apps;
these are public identifiers, not passwords. Forks should create their own clients.

Real test account addresses, Drive file references and maintainer configuration
belong in a separate private configuration repository. Passwords, tokens and
private keys must be encrypted before they enter even that private repository.
The maintainer repository uses SOPS with age; its decryption key stays in macOS
Keychain, outside both repositories. Its restore helper materializes ignored
local files and refuses conflicting files unless explicitly asked to replace them.

## Independent development

Copy `config/google.example.json` to `config/google.local.json` and configure
your own project using [Google setup](GOOGLE_SETUP.md). No Google configuration
is needed for local-only development or the ordinary test suite. Native iOS
Google configuration is generated with `python3 scripts/configure_google.py`.
Use `--dart-define-from-file=config/google.local.json` for Google-enabled builds.

For private live tests, copy `config/live-tests.example.json` to
`config/live-tests.local.json`. Fill in dedicated test accounts and a disposable
test file; leave `RUN_LIVE_DRIVE` false until intentionally running a live test.
`LIVE_ACCOUNT` is the account running the probe; `LIVE_OWNER` owns the test file.
`LIVE_RECIPIENT` is required only for the explicitly selected `create` mode,
which creates a synthetic file and sends a real Drive invitation. `LIVE_QA_BABY`
selects the synthetic profile for the Android diagnostic tool.

Live tests reject missing settings and example email addresses before signing
in, then check the signed-in account before reading or writing Drive files.
Run them only on disposable test devices with synthetic profiles. For example:

```sh
flutter test integration_test/production_restore_probe_test.dart \
  -d <disposable-simulator-id> --no-uninstall \
  --dart-define-from-file=config/google.local.json \
  --dart-define-from-file=config/live-tests.local.json \
  --dart-define=RUN_LIVE_DRIVE=true
```

Never include live-test definitions in distributable app builds. Dart build
definitions are extractable from binaries and cannot protect secrets. Google
authentication uses the platform SDK; test account passwords are not build settings.

## Source control and CI

- Commit example files and synthetic test data only.
- Keep `config/*.local.json`, `.secrets/`, signing keys and signing passwords ignored.
- Keep public pull-request CI independent of private configuration and credentials.
- Use reviewed, trusted workflows for live tests or signed releases.
- Never print account addresses, file references, records or credentials in probe output.
- Source cleanup does not erase earlier commits, branches or hosted logs. Audit
  those separately before changing repository visibility; rotate any exposed secrets.

Apple signing identities remain in the operating-system Keychain. Android release
signing remains optional and local in ignored `android/key.properties` and
`android/.signing/`; debug builds require neither.
