# Public source and private history

Read [the publication process](docs/PUBLICATION.md) before committing, opening a
pull request, building a release, or moving changes between repositories.

The sole active app repository for development, pull requests and release builds is
`dared66/little-log-open-source`, with `main` as the baseline (user decision,
October 21, 2026). The original app repository is a private historical backup; do
not continue app development or release builds there. The public history starts at the audited
snapshot `6e47da94afe8735a4cbe8d093696617f0be29f6a`; the original source repository
and configuration repository remain private with their existing histories.
Never publish those private histories: do not push their branches or tags, mirror
repositories, merge unrelated histories, or open a public PR from a private branch.
Transfer reviewed source changes onto a branch based on public main, audit every
outgoing commit and its metadata, then use a public pull request and required CI.

Keep real test account addresses, Drive references, family records, screenshots
with private content, tokens and keys out of public commits, PR text, logs and
artifacts. Local configuration stays ignored; passwords, tokens and private keys
belong in the encrypted private configuration store. Public OAuth client IDs in
`config/google.production.json` are intentional application identifiers.

Public CI must remain independent of private accounts and configuration. Keep
both `publication` and `test` checks required, secret scanning and push protection
enabled, and inspect CI for the exact resulting commit after publishing or merging.
Build official releases from a checkout of the public repository. Keep the
canonical-origin and audited-root checks in `scripts/release_preflight.py`;
never bypass them to build an old private checkout. Existing unfinished private
features require reviewed source transfers before further development in public.

# CI verification

After every merge or direct push to main, inspect GitHub Actions for the exact
resulting commit and wait for every required job to finish. Fix failures and
verify the follow-up run before reporting completion. Local tests do not replace
this check.

Use `krupa@krupapc.dev` for maintainer commit metadata (explicitly approved by
the maintainer on October 21, 2026), or a GitHub noreply identity. The publication
guard rejects other author/committer email addresses in outgoing commits.

# Backwards compatibility — absolute requirement

**NEVER break backwards compatibility.** This is a standing user directive set October 15, 2026, applying to every branch and release.

Build **58** was distributed to all TestFlight groups on October 15, 2026, at the user's request. Builds **55–57 were internal only**; build **54** was the preceding external release and remains the mandatory legacy compatibility baseline. Continue supporting caregivers on build 54 as well as build 58. Never retire the frozen build-54 readers or their compatibility gate merely because a newer build was distributed. An internal TestFlight upload, Owner distribution or release tag alone does not establish an external release.

New versions must continue reading existing local data, backups and shared logs. Data written by a new version must remain readable, editable and syncable by already-released versions. Caregivers must not need coordinated upgrades to keep using a shared log. Preserve existing values, record identities, deletion markers, import provenance and metadata through mixed-version round trips.

Before changing persistence, shared schemas, import/export formats or persisted timer/native-action state, verify the affected upgrade and mixed-version paths against the actual shipped readers and writers using frozen source or fixtures. Cover reads, writes, edits, deletions and sync/retry behavior where affected, and retain regression coverage. Migrations must preserve data and remain safe to retry.

The mandatory CI gate is `python3 scripts/check_build54_compatibility.py`. It verifies frozen build-54 reader/history hashes and runs the released-version and pumping regression suites. Keep this gate in CI and the released-version tests in the full native harness. Never weaken a frozen reader or rewrite its history fixture to make a new format pass.

Do not merge or distribute a change that breaks compatibility. Fix the implementation first. Documenting a version restriction, blocking older clients or telling caregivers to upgrade does not satisfy this requirement.

# Design review expectations

For routine iterations, use focused tests and inspect only affected screens, including relevant small-phone / large-text and validation states. Run a holistic navigation review for broad redesigns or navigation changes, not every local patch. User requested efficient builds and post-build work on September 18, 2026.

Use `lib/design.dart` as the single source for category colors. Each of the ten activities has its own accent and tint; the same activity keeps its identity across every entry point and saved record. Category color means identity only. Evergreen means an app action or selected control; errors and warnings retain their semantic colors. Summary surfaces are neutral, and any category mark reflects the actual record rather than a hard-coded default category. Keep labels and icons alongside color.

Use `test/flow_journey_test.dart` when a holistic review is warranted. Avoid regenerating full capture sets or reports for routine edits. Run relevant tests and analysis once, then build, install and verify the build number once; repeat only after a failure or material change. Do not generate PDFs unless the user explicitly asks; this project-wide preference was set September 18, 2026. Identify the build and source revision in the artifact. Clearly distinguish test-rendered sample screens from physical-device verification. Do not claim a new build is on the phone until installation succeeds.

# Build and device policy

After app changes, refresh and launch the latest build on both the Android emulator and iOS simulator. This standing user instruction was set October 9, 2026.

Use emulators and simulators for routine builds, installation, launches, and QA. Install on a physical phone only when the user explicitly requests it. The user explicitly authorized installing build 51 on their iPhone on October 9, 2026. Routine QA remains emulator-only.

After a build has been uploaded to TestFlight, use the next build number for subsequent changes and installations. Do not reuse an uploaded build number. Build 58 was uploaded and distributed to Owner testing, Family beta, Reddit Beta users and Open Beta on October 15, 2026, from `932af77e873d41395583538e7e4ccb593dd05384`. It preserves build 57's app code; a new build number was required because Apple prohibits external distribution of the internal-only build 57. Current development and release preparation use version 1.0.0+59. Build 59 has not yet been uploaded; after its first upload use build 60 for further app changes. Do not advance the number merely for release bookkeeping. Build 58 excludes all work from the separate telemetry/anonymous diagnostics branch. This standing user instruction was set October 9, 2026 and supersedes the earlier published-baseline rule.

# UI writing

Standing user directive, October 22, 2026: minimize quips, secondary labels,
subtitles and explanatory copy. Do not narrate obvious controls, add cheerful
filler, or repeat a heading in helper text. Customers should feel respected,
not coached through obvious actions. Default to the label alone. Add secondary
copy only for a necessary permission, a consequential choice, or actionable
error recovery. Review each screen for text that can simply be deleted.
Do not explain invitation capabilities beneath the email field (for example,
“They’ll be able to view, add and edit entries”). Do not duplicate the invited
email above the account card or narrate paste, browse, or manage-access buttons.
Audit the full affected flow before presenting it, rather than waiting for the
user to identify each redundant sentence.

Invitation links already identify their exact log. Attempt direct access first;
never require recipients to browse/select a known file when the app can read it.
Retain Google's narrowly scoped authorization only as a fallback when needed.

Write iPhone TestFlight notes for the people using the app: short, plain-language descriptions of relevant new features and what to try. Keep internal compatibility repairs, unreleased-build history, engineering/test details, telemetry bookkeeping and Android information out of iPhone tester notes. For build 57, the user requested only three points: optional elapsed time under Quick Log → Customize, improved live timers to try in the app and on the Lock Screen, and the new Help screen with Siri commands and other help. This standing preference was clarified October 15, 2026.

Keep labels, controls, and helper text concise and respectful. Do not add infantilizing explanations, obvious definitions, redundant details, or commentary that merely restates what a label or unit already communicates. Add helper text only when it helps the user make a meaningful decision or prevents a likely mistake. For example, a Length unit selector needs no explanation that it also applies to head circumference. This standing user instruction was set October 8, 2026.

# Import testing and production data

Treat user-supplied exports as read-only fixtures. Run imports, removals, and recovery checks only in isolated local test databases and emulators. Never modify production logs or connected Drive files to test migration. Do not commit private exports or real family records; use synthetic fixtures preserving the verified file format. This standing user instruction was set October 8, 2026.

# Product scope

User photos, image attachments, and image sharing/sync are permanently out of scope. Do not add or enable those features or include them in future migration plans. This user instruction was set October 13, 2026. Static app artwork and development screenshots are separate from activity attachments.

# Preserve shared simulator state

The configured iOS development simulator (`D0317E7F-CC69-4B2D-AD9E-65B9897DF9D0`) and Android `emulator-5580` are persistent user review devices shared by every checkout. Never run native integration tests on them, uninstall Little Log, clear app data, or erase either device. Routine app updates must install in place and preserve local profiles, logs, settings and sign-in. Use host widget tests for layout samples and a separate disposable simulator/emulator for native tests. Always pass `--no-uninstall` to native `flutter test` commands as an additional safeguard; a synthetic database does not protect the installed app container from Flutter's default uninstall cleanup. Do not leave test profiles or test harness builds on the review devices.

On October 15, 2026, telemetry integration tests from another checkout ran on these shared devices without `--no-uninstall`, deleting development app state. Keep tests isolated across branches and checkouts, not only within the database.
