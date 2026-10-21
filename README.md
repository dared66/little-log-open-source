# Little Log

**Simple baby tracking. Always free. Your data belongs to you.**

Little Log helps you keep track of feeds, sleep, diapers and the rest of your
baby’s day. Quick logging, easy timers and a clear daily history make it simple
to record what happened and pick up where another caregiver left off.

## Built around you and your family

- **Simple and intuitive.** Log an activity, start a timer or check the day’s
  history without digging through menus. Customize Quick Log and your preferred
  units to fit your routine.
- **Always free.** Every feature is free and always will be. There are no
  subscriptions or paid upgrades. Optional tips support development and unlock
  nothing; everyone gets the same app.
- **Privacy-minded.** Keep your records on your device, or choose Google Drive
  to sync and share with caregivers. You decide whether to connect an account
  and who to share your log with.
- **Complete ownership of your data.** Your records stay on your device and,
  when you enable sync, in your own Google Drive. Export your history, keep your
  own backups and take your data with you. Little Log has no separate account
  or central database for your family’s records.
- **Open source.** Read the code, suggest improvements or make it your own under
  the [MIT License](LICENSE).

## Keep up with the everyday details

Track bottles, nursing, pumping, sleep, diapers, solids, growth, health,
routines and milestones. Use timers for nursing, sleep and pumping, then review
your entries in the daily log.

Share a baby’s log with other caregivers through Google Drive. Entries save on
your device while offline and sync when you’re connected again with the app
open. On iPhone, Siri and Shortcuts can log diapers and start or finish timers.

You can also bring existing history into Little Log and export it again using
the [import and export tools](docs/HISTORY_BRIDGE.md).

See the [feature guide](docs/NARA_FEATURES.md), [Siri commands](docs/SIRI.md) and
[Android voice controls](docs/ANDROID_VOICE.md) for more details.

## Choose how you keep your log

Start with **Set up my baby** and choose storage on your device or Google Drive.
You can use the app without a Google account. To share, connect Drive and invite
a caregiver; they choose **Join an existing baby log** and sign in with the
account you invited.

Shared logs are ordinary CSV files in the family’s Google Drive. Little Log
requests access only to files you create or explicitly open with the app.
Your device also keeps a local copy of your log.

Little Log is currently in beta. Shared logs check for updates every 30 seconds
while the app is open and when you return to it. Each shared CSV currently has a
10 MiB limit. See [project status](docs/STATUS.md) and
[current QA results](docs/RELEASE_BUILD59.md) for tested behavior and limitations.

## Run it yourself

Little Log is built with Flutter for iOS, Android and the web. With the stable
Flutter SDK installed:

```sh
flutter pub get
flutter run -d chrome --web-port 8787
```

The app works on your device without Google configuration. To enable Drive,
copy `config/google.example.json` to `config/google.local.json`, configure your
own Google project using the [Google setup guide](docs/GOOGLE_SETUP.md), then run:

```sh
python3 scripts/configure_google.py
flutter run --dart-define-from-file=config/google.local.json
```

Keep local configuration out of Git. OAuth client IDs are public application
identifiers; passwords, access tokens, refresh tokens and signing keys must
never be included in the app. See [configuration storage](docs/CONFIGURATION.md).

## Contribute

Bug reports, clearer wording and code contributions are welcome. Read
[CONTRIBUTING.md](CONTRIBUTING.md) to get started, and use synthetic family data
in issues and tests. Report security vulnerabilities through the private process
in [SECURITY.md](SECURITY.md).

Run the checks before submitting a code change:

```sh
flutter analyze
flutter test
python3 scripts/check_build54_compatibility.py
python3 -m unittest discover -s scripts -p 'test_*.py'
```

This is the active repository for development and releases. Maintainers should
follow the [publication process](docs/PUBLICATION.md) to keep private
configuration and historical repositories separate from public source.

Little Log uses the [MIT License](LICENSE). Dependencies retain their own
licenses; see [third-party notices](THIRD_PARTY_NOTICES.md).
