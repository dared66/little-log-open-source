# Maintaining the public/private repository boundary

## Repository roles

- `dared66/little-log-open-source` is the sole active app repository for
  development, contributions and official release builds. Use its `main` as the
  baseline for new work. This was confirmed by the maintainer on October 21, 2026.
  Its independent history starts at audited snapshot
  `6e47da94afe8735a4cbe8d093696617f0be29f6a`.
- `dared66/little-log` is a private historical backup, retaining its original
  history and unfinished branches. Do not continue app development, merge app
  changes or build releases there. Cleaning a source tree did not sanitize its
  history. Keep the repository private. Transfer any unfinished feature through
  the reviewed process below before continuing it in the public repository.
- `dared66/little-log-config` is the private maintainer configuration repository.
  Account references remain private; passwords, tokens and keys are encrypted
  with SOPS/age. The decryption key stays outside Git in the OS Keychain.

The private source repository is retained for recovery and reference, not as a
second main. No ongoing private-to-public synchronization is required: new app
work happens directly in public branches. The configuration repository remains
private and active. Never change its visibility or publish the historical source
repository to deliver an update.

## Moving a change into the public repository

1. Start with a clean branch from the latest public `origin/main`. Verify the
   remote points to `dared66/little-log-open-source` before pushing.
2. Review the selected private source diff locally and reproduce only the intended
   change in that public branch. Do not add the private repository as a public CI
   dependency. Never push private branches/tags, use a mirror push, merge private
   ancestry, or publish a PR with private commit history. Do not automatically
   cherry-pick private commits: their messages and authorship can contain private
   information even when their final source diff is safe.
3. Review all outgoing files and commit metadata. Include docs, fixtures, images,
   deleted files, messages, author/committer emails, tags, PR text and artifacts.
   Use example addresses and made-up test records. Choose a public-safe author
   and committer identity; the initial snapshot uses
   `Little Log Contributors <contributors@users.noreply.github.com>`.
4. Stage only reviewed files. Run the publication guard on staged content and on
   every outgoing commit, using the full public base SHA:

   ```sh
   python3 scripts/check_public_source.py --base <public-base-sha>
   gitleaks git . --log-opts='<public-base-sha>..HEAD' --redact --ignore-gitleaks-allow
   ```

   Maintainers should also supply `--private-config` with the local private
   live-test settings file to detect known account/file references. That file
   must never be added to public CI, commits or artifacts. CI scans the complete
   source archive as well as new commits; deleting a secret later does not make
   its earlier commit safe. Automated secret scans cannot identify every private
   name, email or image, so manual review remains required.
5. Run the checks appropriate to the change and open a public pull request. Keep
   required `publication` and `test` checks passing and review the final diff.
   After merging, verify every required CI job for the exact resulting main SHA.
   Do not force-push main or bypass its required checks.

## Builds and releases

Public checkout setup and CI use examples, synthetic fixtures and the intentional
public OAuth identifiers. They need no private account, private repository or
signing key. Public CI runs compatibility, analysis, tests and an Android debug
build; it does not distribute a signed release or verify live account flows.

Google-enabled maintainer builds explicitly load ignored `config/google.local.json`.
iOS helpers generate and verify the callback settings. Signed releases obtain
credentials through trusted local/private facilities, never public PR workflows.
Do not include live-test definitions, account passwords, tokens or signing secrets
in app build definitions: compiled definitions are extractable from binaries.
See [configuration storage](CONFIGURATION.md) for the existing setup commands.

Before distributing an official release, use a public-source checkout, fetch
public `origin/main`, and run `python3 scripts/release_preflight.py`. It rejects
an unexpected origin, history without the audited public starting commit, and
sources missing fixes already merged into public main. The iPhone release-build
helper runs this gate before building. Local-only development builds and public
PR CI require no signing secrets; they remain usable by contributors and forks.
Fork distributors must adapt the maintainer release policy for their own app.

Record the public source revision, version/build and intended channels for each
release. Preserve build 54/58 compatibility and the existing build-number/device
policy. Publishing a new App Store, TestFlight or Play release still requires an
explicit release task; selecting public source does not authorize distribution.
There is no hosted signed-release workflow to move: the existing CI builds a
public-source debug APK, while maintainer signing/install helpers run locally
from this public checkout with ignored local configuration.

## Existing protections and incident handling

Keep the publication guard, version-pinned Gitleaks source/history scans, required
CI, GitHub secret scanning and push protection enabled. Do not send private values
to scanner output or create private-value allowlists in public files. Recheck
repository protections after settings changes.

If private material reaches a public commit, branch, tag, PR, log or artifact,
stop further publication and assess all exposed surfaces. Revoke/rotate exposed
credentials promptly. A later deletion, a rewritten local branch or a passing
scan alone does not establish that hosted copies, PR references or downloaded
copies have been removed. Record the response privately without repeating the
sensitive values in public reports.
