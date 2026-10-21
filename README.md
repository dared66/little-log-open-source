# Little Log

This is the primary repository for app development and release source. Private
maintainer configuration is kept separately; see the
[publication process](docs/PUBLICATION.md).

Little Log is a local-first Flutter baby tracker with optional family-owned
CSV storage in Google Drive. It supports bottles, nursing, diapers, sleep,
pumping, solids, growth, health, routines, milestones, daily history, timers,
JSON export, Google sign-in, and caregiver sharing. See the
[feature comparison](docs/NARA_FEATURES.md) for details.

On iOS 16 and later, Siri and Shortcuts can add diapers and start or finish
sleep, nursing, and pumping. See [Siri commands](docs/SIRI.md). Android has
matching [voice-action entry points and Gemini recheck instructions](docs/ANDROID_VOICE.md).

The app has no Little Log server or service-account database. Completed
history and family metadata are stored in an ordinary CSV file owned by the
family, and Google access is limited to the `drive.file` scope. Without Google
configuration, the app works entirely on the device.

New installs choose “Set up my baby” or “Join an existing baby log.” Baby
setup then offers Google Drive for syncing and sharing, or storage only on
this device without a Google account. Existing installations keep their saved
families and open directly to the current log after an update.

> **Project status:** Little Log is pre-release software. The local experience
> is well tested, but two-account mobile sharing and email delivery,
> and the current growing-file sync design still have documented release gaps.
> Do not rely on it as the only copy of important care or medical information.

## Run locally

Install the stable Flutter SDK, then run:

```sh
flutter pub get
flutter run -d chrome --web-port 8787
```

Google Drive support is optional. For enabled builds, copy
`config/google.example.json` to `config/google.local.json`, fill in identifiers
from your own Google Cloud project, and follow [Google setup](docs/GOOGLE_SETUP.md).
For iOS, run the configuration helper once after filling in the file:

```sh
python3 scripts/configure_google.py
flutter run --dart-define-from-file=config/google.local.json
```

OAuth client IDs are public application identifiers, not confidential credentials. Even so, local configuration is
ignored so forks cannot accidentally use another distributor's Google project.
Never place client secrets or access/refresh tokens in the app.

See [configuration storage](docs/CONFIGURATION.md) for the separation between
public examples, private maintainer settings, encrypted keys and opt-in live tests.
Maintainers should also read the [publication process](docs/PUBLICATION.md) for
repository roles and safe updates from private development.

## Data and synchronization

Create a family CSV in Drive, invite a caregiver as an editor, and have them
open “Join an existing baby log” in Little Log, sign in with the invited
account, and select the baby from the available logs. Little Log merges stable record IDs
and uses Drive file ETags for conditional writes. A concurrent edit causes a
reread, merge, and bounded retry instead of an unconditional overwrite.
Malformed files, missing versions, and conflicting records stop synchronization
while retaining local entries.

Existing spreadsheet connections become local logs with their old file IDs
retained for reference. Creating a CSV uploads history already present on the
device; it does not fetch cloud-only rows from an older Sheets build. All
caregivers must move to the CSV build together.

The full format and failure semantics are documented in the
[CSV specification](docs/CSV_FORMAT.md). Known production limitations and
remaining acceptance work are tracked in the
[production assessment](docs/PRODUCTION_ASSESSMENT.md).

### Experimental monthly permission probe

Production sync still uses one CSV per family. A developer-only monthly-file
permission probe remains in the source and appears only when built with
`--dart-define=MONTHLY_PERMISSION_PROBE=true`. It uses synthetic test files;
it does not migrate families or enable monthly production sync. See the
[permission test](docs/MONTHLY_PERMISSION_TEST.md) for its findings and limits.

## Move history between Nara Baby and Little Log

Read-only Nara export and two-way local file conversion are described in the
[history bridge guide](docs/HISTORY_BRIDGE.md). The reverse output is a portable
Nara-shaped bridge file; these tools do not write to Nara Baby.

## Verification

```sh
flutter test
flutter analyze
python3 scripts/check_build54_compatibility.py
python3 -m unittest discover -s scripts -p 'test_*.py'
flutter build web
flutter build apk --debug
flutter build ios --simulator # macOS with Xcode
```

Use `python3 scripts/ios_phone_dev.py install` to install the verified iPhone
build. The iOS helper refuses to build without Google settings and checks the
compiled clients and callback before installation. Android release signing is
deliberately not stored in this repository; distributors must configure and
protect their own signing key.

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Please
report vulnerabilities using the private process in [SECURITY.md](SECURITY.md),
and use synthetic family data in reports and tests.

Little Log is available under the [MIT License](LICENSE).
Dependencies retain their own licenses; see [third-party notices](THIRD_PARTY_NOTICES.md).
