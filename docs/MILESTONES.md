# Development milestones

## 2026-10-13 — Today and History merged into Log

Today and History now share the Log tab. The date control opens past days;
Back to today returns to the current day. View all expands that day's entries
and exposes the activity filter. Summary metrics can be customized separately
from Quick log.

Rollback reference: annotated tag `before-today-history-merge-2026-10-13`,
commit `db9f0775a8c631369c7911818082bc19e7b96cec`. This is the main version with
separate Today and History tabs, before this consolidation.

Completed milestone: annotated tag `today-history-merged-2026-10-13`.
The combined application source tested for this milestone is commit
`0c13220367327ba83f2659b33e4fa1c7c6564b3e`, development build 52.

Consolidation order:

1. Retain the Settings branch history; its changes were already applied to main.
2. Merge Google production identity and account-change protections, keeping all
   existing native regression checks.
3. Merge the Nara CSV migration and complete Log navigation, summary and tip
   recovery polish.
4. Preserve the existing GoogleUtilities 8.1.4 package resolution.

Onboarding, invitations, shared-log discovery and earlier polish were already
included in main. All local and fetched remote branch tips are ancestors of the
consolidated main. There were no open pull requests at consolidation time.

To inspect or build the prior version without changing main or rewriting
history, create a separate branch from the rollback tag. These tags restore
source versions; they do not remove records from a baby log or reverse a saved
import.

Validation on the combined main application source:

- Static analysis: no issues.
- Full Flutter suite with the public production Google client definitions:
  372 tests passed.
- Python script suite: 24 tests passed.
- Full native heavy harness: 296 tests passed on Android API 36 and 296 on
  iOS 26.5. Both completed as full passing runs.
- Large Nara CSV probe: 4,600 source activities became 6,400 activities and one
  profile. Coverage, unique IDs, reimport, backups, disk reopen, malformed-row
  rejection, atomic reports, undo and deleted-record deduplication passed.
- Six interrupted-import recovery cases passed.
- Both native suites passed loading, navigating and saving 10,000 records.

The initial Android run was interrupted after 257 passing checks by a host
emulator crash. Its macOS crash report recorded SIGABRT in a gRPC callback.
The emulator was restarted without wiping data and the entire suite repeated;
the subsequent 296-test run passed. No application source changes were required.

No merge-blocking issues were found. Validation used synthetic records and
isolated databases. Live Google account continuity, cross-account sharing and
real store purchases were not repeated in this pass; physical-device acceptance
remains a release consideration. Development build 52 was rebuilt, installed and
launched on the Android emulator and iOS simulator.

The milestone commit adds only this documentation and its status-page link after
the application tests. Local detailed logs are retained in
`output/main-consolidation-2026-10-13/` beside the repository.

The first published-main CI run exposed two test assumptions just after UTC
midnight: default one-hour sleep/pumping entries start on the previous day.
The journey and form tests now select the saved entry's day, and the form fixture
disables the separately tested gesture hint to avoid pending background writes
during teardown. All 372 tests passed again in UTC with production public client
definitions. This follow-up changes tests and documentation only; the application
source at the milestone tag is unchanged.

## 2026-10-13 — Build 52 released to owner TestFlight

Little Log 1.0.0 (52) was archived from validated main commit
`f544644ab2fee6f925d4c050198b147b44685fcc` and uploaded as internal-only.
The app and timer extension versions, distribution profiles, code signatures,
and Google client definitions/callback were verified before upload.

App Store Connect build `8202ad4f-815f-44f4-92ff-34698a8f4802` was verified
`VALID`, `INTERNAL_ONLY`, and `IN_BETA_TESTING`. It is assigned to the existing
Owner testing group containing one tester. Family beta and Reddit Beta users
do not contain this build. Test notes were saved and read back successfully.

Annotated tag `testflight-build52` preserves the exact release source. The
signed archive, IPA, verification receipts and upload log are retained locally
in `output/release52/` beside the repository. Local development advanced to
build 53 under the uploaded-build policy, with both emulators refreshed.

## 2026-10-13 — Build 53 released to owner TestFlight

Little Log 1.0.0 (53) was archived from
`09912d32438dab57e9f824d1c68ead10f9e55a37`. It includes dark appearance,
home-screen shortcuts, Siri and Android care actions, assistant nursing error
propagation, and the Android screen review's shared spacing and alignment fixes.
Standalone pages share their content frame, short pages start below the header,
and long headers accommodate accessibility text.

The delta from the last full pass (`bb3262c`) passed 84 Flutter checks, 30 script
checks, four focused Android native checks and two iOS native checks. Android
captures use native 420 dpi; final page and recovery captures show the complete
emulator screen with synthetic data. Evidence is retained beside the repository
in `output/android-layout-audit-2026-10-14/`. Earlier capture and harness failures
are retained and are not counted as passing checks.

App Store Connect build `da364647-f0ae-4b79-849b-7b7376e15de6` was verified
`VALID`, `INTERNAL_ONLY`, and `IN_BETA_TESTING`. Owner testing contains the build
and its one existing tester. Family beta and Reddit Beta users do not contain
it. Beta notes were saved and read back. Signing, app and extension versions,
Google configuration, seven Siri actions and seven shortcuts were verified.

Tag `testflight-build53` preserves the release source. The signed archive, IPA,
upload log and distribution receipts are in `output/release53/`. Both normal
simulator apps were refreshed and launched at development build 54. No physical
device was used for this pass.

## 2026-10-13 — Build 54 distributed to all TestFlight groups

Little Log 1.0.0 (54) was archived from
`f6cf11dcd043666a1e5f23880306d2467b26aa21`, preserving the tested build 53
application code with an external-eligible export. The signed app and timer
extension, Google configuration, seven Siri actions, and seven shortcuts passed
package verification. Existing application test evidence is unchanged.

App Store Connect build `4c1cff8f-a222-4979-8062-21a7b59ace46` was verified
`VALID`, `APP_STORE_ELIGIBLE`, and `IN_BETA_TESTING` for both internal and
external testing. Owner testing, Family beta, and Reddit Beta users each contain
the build. The approved tester-facing release notes were published and read
back exactly, with all tip references removed. Automatic tester notifications
are enabled; existing testers and invitation settings were preserved.

Tag `testflight-build54` preserves the release source. Signed artifacts, upload
logs, approved notes, and distribution receipts are retained locally in
`output/release54/` beside the repository. The subsequent dark palette change
(`082961f`) is outside this release. The user stopped build 55 preparation;
no build 55 was prepared, uploaded, or installed.

## 2026-10-15 — Build 55 released to owner TestFlight

Little Log 1.0.0 (55) was archived from
`f56988431bc798a36a0d1b5b4a186cad214bb309` on
`design/elapsed-activity-icons`. The source includes the current main-branch
bottom navigation spacing fix. All 422 Flutter tests passed after that merge,
and Flutter analysis was clean. The preceding branch validation also exercised
native iOS and Android recovery, navigation, large text, layouts, and voice
bridges; live Siri/Google speech recognition remains unverified.

This build adds optional elapsed lettering in six Quick Log icons, read-only
assistant history questions, and platform-specific Settings Help. Regular icons
remain the default, and All Activities retains all ten regular activity icons.
The signed app and timer extension, Google configuration, and ten Siri shortcuts
passed archive verification.

App Store Connect build `544feb03-95af-47a8-aa26-613e97015d82` was verified
`VALID`, `INTERNAL_ONLY`, and `IN_BETA_TESTING`. Owner testing contains the build
and its one existing tester. Family beta, Reddit Beta users, and Open Beta do
not contain build 55. The tester notes were published and read back exactly.

Tag `testflight-build55` preserves the release source. Signed artifacts, upload
logs, notes, and verification receipts are retained in `output/release55/`
beside the repository. Local development advances to `1.0.0+56` under the
uploaded-build policy; no physical-device installation was performed.

## 2026-10-15 — Build 57 released to owner TestFlight

Little Log 1.0.0 (57) was archived from main at
`78b60cc8d12d440c0fa5a868384796964302eb8e`. It includes optional Quick Log
elapsed time, improved in-app and Lock Screen live timers, and Settings Help.
The separate telemetry/anonymous diagnostics work is excluded.

The full harness passed: 471 host tests with 13 existing skips, 402 Android
native checks, 396 iOS native checks, two density checks per platform, 15 Android
system checks and 13 iOS system checks. Analysis, script checks, production OAuth
checks and CI passed. The 24-test build-54 compatibility gate passed again
before packaging. Build 54 remains the public compatibility baseline.

The signed app and timer extension, Google configuration, production entry
point and internal-only export passed package verification. App Store Connect
build `497a55cf-3e50-45c8-8199-bf3144b17239` was verified `VALID`,
`INTERNAL_ONLY` and `IN_BETA_TESTING`. Owner testing contains the build and its
one existing tester. Family beta, Reddit Beta users and Open Beta do not contain
build 57. The approved three-point iPhone tester notes were published and read
back exactly.

Tag `testflight-build57` preserves the archived source. Signed artifacts,
upload logs, notes and verification receipts are retained in `output/release57/`
beside the repository; full harness evidence is in `output/build57-full-harness/`.
The source stays at `1.0.0+57` for release bookkeeping; subsequent app changes
and installations require build 58. No physical-device installation was performed.

## 2026-10-15 — Build 58 distributed to all TestFlight groups

At the user's request, Little Log 1.0.0 (58) was archived from main at
`932af77e873d41395583538e7e4ccb593dd05384` for external TestFlight distribution.
Apple's internal-only restriction prevents distributing build 57 externally,
so a new build number was necessary. The app code, native code and dependency
lockfile are identical to build 57; the only application-source change is
`1.0.0+57` to `1.0.0+58`. Build 57's complete harness evidence still applies,
and the 24-test build-54 compatibility gate passed again before packaging.
Telemetry remains excluded.

The signed app and timer extension, Google configuration, production entry
point and external-eligible export passed package verification. App Store
Connect build `5d038ba1-8016-4958-9048-bea0c8c61723` was verified `VALID`,
`APP_STORE_ELIGIBLE`, and `IN_BETA_TESTING` for internal and external testers.
Owner testing, Family beta, Reddit Beta users and Open Beta each contain the
build. The approved three-point tester notes were read back exactly, and
automatic tester notifications are enabled. Existing testers and invitation
settings were preserved. This distributes a beta; it does not publish an
App Store release.

Tag `testflight-build58` preserves the archived source. Signed artifacts,
upload logs, approved notes and distribution receipts are retained locally in
`output/release58/` beside the repository. Build 54 remains the mandatory legacy
compatibility baseline. Source remains `1.0.0+58` for bookkeeping; subsequent
app changes and installations require build 59. No physical-device installation
was performed.
