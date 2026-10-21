# iPhone development install

Run from the repository root:

```sh
python3 scripts/ios_phone_dev.py install
```

The script checks the development certificate and both provisioning profiles,
builds a signed release app, installs it in place on the configured iPhone,
verifies the installed version, and launches it. It does not uninstall the app
or clear its data.
The command requires the populated `config/google.local.json`, regenerates the
iOS Google sign-in callback setting, and includes the Google client definitions
in the Flutter build. It stops if any required setting is absent.
Use `python3 scripts/ios_phone_dev.py check` to verify signing without building.
Use `python3 scripts/ios_phone_dev.py build` to build and verify the
Google-enabled app when the phone is offline.

The ignored `config/ios_dev.local.json` holds this machine's team, device, and
API key *path*. The private key itself stays outside the repository. A template
is in `config/ios_dev.example.json`. The script uses local profiles while they
are valid and refreshes them through the Apple API if fewer than 30 days remain.
It keeps its API packages in the ignored `.venv-ios-dev` directory; Xcode
account sign-in is not part of the normal install path.

The configured development certificate is valid until July 2027. Apple must
issue a new certificate and corresponding signing key before that expires; the
current script reports that case clearly. The installed development profiles
were created on September 26, 2026 and expire on September 26, 2027. Store and
TestFlight distribution use separate signing profiles.

## iOS simulator

Run `python3 scripts/ios_simulator_dev.py install` to boot the configured
simulator, build, install, launch, and verify the app. Run
`python3 scripts/ios_simulator_dev.py run` for Flutter's interactive hot reload
loop. Both use `simulator_udid` in the same ignored local config file and require
the Google client definitions.

Keep this simulator and Android `emulator-5580` for persistent development state.
All checkouts share these devices and app IDs. Native integration tests must use
a separate disposable QA device, even when their database is synthetic: Flutter
uninstalls the app and deletes its container by default after integration tests.
The native test runner requires an explicit QA device and rejects the development
devices. Keep `--no-uninstall` on native test commands as an additional safeguard:

```sh
python3 scripts/run_native_tests.py ios --device <disposable-simulator-udid>
```

Simulator builds must keep code signing enabled. The simulator-only signing
configuration gives the app its own Keychain identity so Google Sign-In can
save credentials. The install script checks the signature and entitlements
before installation; `--no-codesign` builds can launch but fail sign-in with a
Keychain error. These simulator settings do not apply to device or TestFlight
signing.

The generic simulator build is restricted to arm64 in the Xcode project because
this machine is Apple Silicon. Without that setting, the installed Flutter/Xcode
combination sends `arm64 x86_64` as one architecture to Flutter's unpack step
and the build fails before compiling the app.

## Release source baseline

Build official releases from `dared66/little-log-open-source`. The old private
app repository is a history backup. Before any TestFlight archive, fetch the
public repository history and run:

```sh
git fetch origin
python3 scripts/release_preflight.py
```

The check requires the canonical public origin and audited public starting
commit, and refuses sources that omit commits already on public `origin/main`. The signed
iPhone build/install script also runs it automatically. Tests passing on an older
branch do not prove that earlier fixes are present: their tests may be missing too.
Run the full regression suite after integrating the release baseline. Simulator
builds remain available for reviewing work in progress.
