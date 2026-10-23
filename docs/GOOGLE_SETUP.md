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
3. A invites account B as an editor. Verify Google Drive’s email includes the
   sender, baby, Little Log name, invited account, and joining instructions.
4. B opens Little Log, taps “Join an existing baby log”, and signs in with the invited
   account. If A’s log is already listed, B chooses it directly. Otherwise B
   taps “Add a shared log from Google Drive”, chooses A’s file, and grants
   Little Log access. Google’s picker may include unrelated CSVs; the app
   checks the selected file before joining. Sharing with a Google account
   alone does not establish app authorization for a new file. Confirm the owner
   and file reference before “Join baby log”. B sees A’s entry and adds a
   different entry.
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
`sendNotificationEmail=true` and a plain-text `emailMessage`. Google Drive sends
its own sharing notification. A successful request confirms permission creation,
not inbox delivery. There is no Little Log email service. The separately shared joining message includes a `littlelog://join` app link and a Google Drive file-link fallback. Native app links require Little Log to be installed; some email and messaging clients do not make custom schemes clickable. There is no hosted HTTPS invitation page or deferred installation handoff.
The app lists accessible Little Log CSVs and checks content-editing permission
before joining. Both people need an installed copy of Little Log. Installation is arranged separately by the sender; this change does not establish a public app-store installation link. Copyable instructions provide a fallback
when Google’s notification is missing or incomplete.

Run the isolated fake-service harness with:

```sh
flutter test test/invitation_harness_test.dart
flutter test integration_test/invitation_harness_test.dart -d <simulator-id> \
  --dart-define-from-file=config/google.local.json
```

The harness sends no real email and cannot validate Google delivery, native OAuth,
or live `drive.file` sharing. The two-account acceptance test above is still needed.

## References

- [Drive API scopes](https://developers.google.com/workspace/drive/api/guides/api-specific-auth)
- [Drive sharing](https://developers.google.com/workspace/drive/api/guides/manage-sharing)
- [Google Picker for mobile](https://developers.google.com/workspace/drive/picker/guides/desktop-mobile-picker)
- [Google Picker for web](https://developers.google.com/drive/picker/guides/overview)
- [Flutter Google Sign-In package](https://pub.dev/packages/google_sign_in)

## Log identity and notification limits

Ownership and sharing status come from Drive metadata, not the signed-in
account or the baby name. They are cached locally for display; CSV contents
and family IDs are unchanged. Joining a same-name log explicitly preserves
both histories separately. Never merge or delete a log based on its name.

The sender requests a Drive email with `emailMessage`. A successful permission
request is not evidence of email delivery or rendered content. The app offers a visible Share invitation action plus copyable joining instructions as an independent handoff. Android installation currently requires the
sender's test build; there is no verified public Play installation link.

The invitation harness models sharing permission and per-account app access
separately. Native harness success does not prove Google’s live authorization
or notification behavior. Inspect a real received email and restart both
real-account apps as part of release acceptance.


## Sharing workflow branch (October 22, 2026)

- Google's notification uses a short message identifying the sender, baby and
  invited account, with setup/Settings joining steps. Permission creation does
  not establish inbox delivery.
- Share invitation is marked Optional and immediately available after permission creation. The
  native share sheet sends the existing app link, bound to the file and invited
  email, plus manual Drive-link instructions. Share failures stay visible with
  compose/copy fallbacks. Existing native account checks and baby/owner
  confirmation still apply; a link grants no permission itself.
- The joining screen labels the active account. A failed file preview explains
  account, Editor access and per-file authorization checks without claiming
  which one caused Google's 403/404 response.
- The caregiver list links directly to the log in Drive, where users open Share
  to manage permissions. New and existing filenames keep `Little Log · … .csv`;
  discovery and old clients continue using the same names and file IDs.

Remaining acceptance work: receive a real Google notification in a second
account, inspect its visible filename/custom message, then exercise warm/cold
app links, account switching, file authorization, joining, restart, and revoked
access on Android and iOS. Use isolated synthetic logs; don't send real family
invitations for QA. A branded HTML email/Join button requires a verified sender
and email service. A clickable HTTPS invitation and installation fallback need
an owned hosted domain and platform association files. Neither is configured by
this branch.


### Sharing screen redesign

Settings opens a dedicated invitation page. It uses the standard page frame,
input styling and spacing. Successful permission creation and a requested Drive
notification show a completion card and Done; optional direct sharing is a
secondary action. Email/copy alternatives live in an overflow menu.

Joining shows one stage at a time: invited account, Drive selection, then baby
and owner confirmation. A mismatched account gets an actionable Switch account
button. Confirmation removes the previous selection controls and technical file
reference, while preserving exact file and account checks and duplicate-name
protection. No shared data format or permission scope changes.

`tool/sharing_workflow_review_test.dart` renders the actual screens with synthetic
accounts at standard and 200% text sizes. Run with `CAPTURE_INVITATIONS=true`;
images are written to `/tmp/little-log-invitation-review/`. These captures do not
establish real Google email delivery or native Picker behavior.


### Exact invitation access

Invitation and pasted Drive links first read and validate the specified file.
Already authorized files go straight to baby/owner confirmation, without Picker.
Only a not-found response (which can hide missing app authorization) or Google's
`appNotAuthorizedToFile` error triggers authorization for that exact file. Rate
limits, server failures, view-only access and known trashed files remain errors;
they do not launch Picker. Cancellation leaves the current log unchanged.
The invited account and selected file must still match. This does not assert
that every newly invited account can skip Google's per-file authorization.
