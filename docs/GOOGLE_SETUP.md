# Google integration setup

Little Log uses Google Identity and Drive directly from the app. Each
distributor or fork must use its own Google Cloud project. There is no server
credential and no client secret in the Flutter application.

## Little Log production configuration

Production uses the existing project `little-log-509004` (`259649378161`)
and the same iOS and native server client IDs already shipped to testers.
Public IDs are recorded in `config/google.production.json`; it contains no secrets.
The separate `little-log-production-509904` project is retired and must not be
used in releases. Keep future development/testing in a separate project.

```sh
python3 scripts/configure_google.py --production
```

This selects the public release IDs and generates the matching ignored iOS
callback. Selecting a different project preserves the prior local configuration
as `config/google.testing.local.json` and drops its Picker API key. Selecting the
same project preserves its Picker key and the Play billing public key.
Native iOS does not require a web Picker API key. Android must retain the existing
OAuth clients matching its signing certificates; changing publishing status does
not require registering them in a different project.

Publishing the existing OAuth app changes its audience status, not its app
identity. Existing users with valid sessions should continue syncing the saved
CSV file ID without sign-in or Picker reselection. Expired or revoked sessions
use the existing Sign in with Google / Connect Google Drive recovery controls.
Local history, timers and pending entries remain intact. Do not create a
replacement CSV because Google access expired.

The configuration and a same-identity upgrade regression test enforce this
release strategy. Cross-project migration tests remain as defensive coverage;
they do not describe the intended user upgrade. Live session continuity still
requires verification with signed-in test accounts. Publication and branding
status must be checked in Google Auth Platform before release.

## Reusable Google Cloud access

Use Google's official Cloud CLI with one local login:

```sh
gcloud auth login
python3 scripts/google_cloud_check.py
```

The checker only describes the explicitly selected production project and lists
enabled APIs, then validates the project number and Drive/Picker availability.
It does not enable APIs, change IAM, create keys, or read family files. It reuses
the standard gcloud credential store; no service-account key or additional IAM
grant is needed. OAuth publication, branding and app-client configuration remain
console checks. `gcloud iam oauth-clients` manages workforce OAuth applications,
not these Google Identity/Drive application clients.

The official CLI was installed and authorized locally on October 4, 2026.
Live project/API verification was completed in the authenticated browser.
The managed shell sandbox blocks gcloud's writable credential store even for
read-only commands, so the CLI checker has not completed a live run from that
sandbox. In a normal terminal it can reuse the approved login. A sandbox runner
needs access to the standard local gcloud credential store; do not copy tokens
into the repository to work around it. Prefer a narrow command rule for this
checker if the runner offers reusable approvals.

References: [gcloud authentication](https://docs.cloud.google.com/sdk/docs/authenticate),
[workforce OAuth applications](https://docs.cloud.google.com/iam/docs/workforce-manage-oauth-app),
[Google production readiness](https://developers.google.com/identity/protocols/oauth2/production-readiness/policy-compliance).

## 1. Create and configure a Google Cloud project

1. Create a Google Cloud project and configure its OAuth consent screen.
2. Enable the Google Drive API and Google Picker API.
3. Declare the basic sign-in scopes and
   `https://www.googleapis.com/auth/drive.file`. Do not request a broader Drive
   scope to work around sharing problems.
4. While the consent screen is in testing mode, add only accounts used for
   synthetic acceptance testing.

Create these application credentials:

- A web OAuth client. Add the exact development and production JavaScript
  origins that will host the web app. Local development normally needs
  `http://localhost`, `http://localhost:8787`, and
  `http://127.0.0.1:8787`.
- An Android OAuth client for the app's package name and the SHA-1 certificate
  fingerprint used by that build. Use a separate release signing key for
  distributed builds.
- An iOS OAuth client for the app's bundle identifier.

Google's current console labels can change, so consult the linked official
documentation if a field has moved.

## 2. Configure a local build

Copy the example file and fill in values from your project:

```sh
cp config/google.example.json config/google.local.json
```

- `GOOGLE_WEB_CLIENT_ID`: web OAuth client ID; also used as the native server
  client ID.
- `GOOGLE_IOS_CLIENT_ID`: iOS OAuth client ID.
Native apps use Google's OAuth file picker. Android uses Play Services
AuthorizationRequest with PICKER_OAUTH_TRIGGER. iOS uses an external
ASWebAuthenticationSession with PKCE, state validation, and the existing iOS
OAuth redirect scheme. The returned token is verified against the selected
Google account before any file is opened. No broader Drive scope is requested.
The JavaScript Picker key/project number remain necessary for the web picker.

The local file is ignored by Git. It must contain no OAuth client secret,
access token, refresh token, service-account key, or family data.

For iOS, generate the ignored callback build setting:

```sh
python3 scripts/configure_google.py
```

The helper validates OAuth client ID shapes and writes
`ios/Flutter/GoogleConfig.xcconfig`. It does not modify tracked files.

Build with the local definitions:

```sh
flutter run -d chrome --web-port 8787 \
  --dart-define-from-file=config/google.local.json
```

Use the same `--dart-define-from-file` option for Android and iOS builds.

## 3. Signing and application identifiers

Forks should change the Android application ID and Apple bundle identifiers to
identifiers they control, then create matching OAuth clients. Configure Android
release signing outside source control. Android release builds read the ignored
`android/key.properties` file (`storePassword`, `keyPassword`, `keyAlias`, and
`storeFile`, relative to the Android directory). The upload keystore belongs in
the ignored `android/.signing/` directory. Preserve both private files in your
secure backup; neither belongs in a Git commit. Without this configuration,
release builds remain unsigned and never fall back to the debug key.

When distributing through Google Play, register the **Play app-signing**
certificate SHA-1 for the Android OAuth client, rather than only the upload
certificate. Google Play signs the APK that users install with its app-signing
key; the locally generated upload key signs the submitted bundle.

Select an Apple development team in
your local Xcode environment; do not commit private keys or provisioning
profiles.

## 4. Acceptance test

Use synthetic entries and two test accounts:

1. Account A creates a local family and one test entry, signs in, connects
   Drive, and publishes the family CSV.
2. Verify the file contains the test entry once and can be opened independently
   as CSV.
3. A enters B’s Google email and taps “Share invitation”. Verify editor access
   is granted and the native share sheet opens. Send through an installed app
   and inspect the received HTTPS invitation. Drive notification email is disabled.
4. B opens the invitation and signs in with the invited account. The app first
   reads the exact invited file. If app authorization is missing, Google asks
   for access to that single file. Confirm the owner and tap “Join baby log”.
   B sees A’s entry and adds a different entry. Existing unrelated local logs
   must remain local and their history must remain unchanged.
5. A refreshes and sees B's entry. Reload both apps and verify exact-once
   persistence.
6. Add records while offline, reconnect, and verify pending status clears on
   both devices.
7. Revoke B's access and verify uploads stop while B's local pending records
   remain available.
8. Repeat sign-in and file selection on physical Android and iOS devices before
   claiming native Google integration is supported.

Google testing-mode authorizations can expire. Keep that behavior distinct from
production token lifecycle testing.

## Invitation delivery contract

Little Log grants editor access through Drive `permissions.create` with
`sendNotificationEmail=false`, then opens the native share sheet in the same
app action. Google’s notification template opens the CSV in Drive and cannot
provide the intended app handoff, so it is not used. There is no transactional
email service. “Invitation ready” confirms preparation; it does not claim that
an email or message was delivered. Copy and email-composition fallbacks remain
available if sharing fails or the user cancels the sheet.

Invitations use `https://krupapc.dev/apps/little-log/join/#…`. The fragment
contains the exact file, recipient and baby name; it is not included in the
website’s HTTP request. The hosted page’s “Open in Little Log” action uses the
existing `littlelog://join` scheme. Google still enforces file access; the link
itself grants no permission. The page offers a Drive-link fallback. Both people
need Little Log installed. Installation is arranged separately; there is no
verified public Play installation link or deferred-installation handoff.

Ownership and sharing status come from Drive metadata, not the signed-in account
or baby name. Joining a same-name log preserves both histories separately. Never
merge or delete a log based on its name. New and existing filenames keep
`Little Log · … .csv`; file IDs and the shared data format are unchanged.

Settings opens a dedicated invitation page with the common page frame and form
controls. Joining shows the invited account and then the baby/owner confirmation.
A mismatched account must switch before proceeding. Successful joining returns
to the log tab. Signing in to join does not back up unrelated local logs.
Backing up an existing local log is an explicit action on the selected log and
includes its complete history.

Run isolated simulated-service coverage with:

```sh
flutter test test/invitation_harness_test.dart test/backup_flow_test.dart
flutter test integration_test/invitation_harness_test.dart -d <disposable-simulator-id> \
  --no-uninstall --dart-define-from-file=config/google.local.json
```

These tests do not prove live authorization or message delivery. The opt-in
`tool/live_release_review.dart` entry point uses real Google services with
synthetic history in a separate device database. Keep its snapshots private.
The two-account emulator/simulator acceptance pass verified backup, both join
directions, complete history after restart, unchanged unrelated local logs and
an invitation delivered through Android sharing into Gmail. iOS native sharing
opened, but its simulator had no Mail/Messages targets configured. Physical-device
and production-package acceptance remain separate release checks.

First-time Android file authorization passed with Play services 26.11.36. The
older 25.26.35 test environment ignored the picker request; the app presents
update guidance rather than claiming a successful join. Retest the update and
retry path on a supported device.

`tool/sharing_workflow_review_test.dart` renders app screens with sample accounts
at standard and 200% text sizes. Run with `CAPTURE_INVITATIONS=true`. These sample
images are not evidence of live email, OAuth or Drive behavior.

## References

- [Drive API scopes](https://developers.google.com/workspace/drive/api/guides/api-specific-auth)
- [Drive sharing](https://developers.google.com/workspace/drive/api/guides/manage-sharing)
- [Google Picker for mobile](https://developers.google.com/workspace/drive/picker/guides/desktop-mobile-picker)
- [Google Picker for web](https://developers.google.com/drive/picker/guides/overview)
- [Flutter Google Sign-In package](https://pub.dev/packages/google_sign_in)

### Exact invitation access

Invitation and pasted Drive links first read and validate the specified file.
Already authorized files go straight to baby/owner confirmation, without Picker.
Only a not-found response (which can hide missing app authorization) or Google's
`appNotAuthorizedToFile` error triggers authorization for that exact file. Rate
limits, server failures, view-only access and known trashed files remain errors;
they do not launch Picker. Cancellation leaves the current log unchanged.
The invited account and selected file must still match. This does not assert
that every newly invited account can skip Google's per-file authorization.

### Hosted invitation handoff

Successful invitations return to the log tab and remove older join routes;
cancellation preserves the previous screen. Google’s native OAuth Picker still
requires explicit file selection and Insert for first-time authorization.
`file_ids` filters to the invited file; it does not preselect or authorize it.
Keep direct access first and the filtered picker only when required. Do not
claim Google’s last authorization step has been removed.
