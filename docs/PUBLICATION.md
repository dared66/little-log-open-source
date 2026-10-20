# Maintaining the public/private repository boundary

## Repository roles

- `dared66/little-log-open-source` is the public source and contribution repository.
  Its independent history starts at audited snapshot
  `6e47da94afe8735a4cbe8d093696617f0be29f6a`.
- `dared66/little-log` is the private source repository, retaining its original
  history and existing development branches. Cleaning a source tree did not
  sanitize that history. Keep the repository private.
- `dared66/little-log-config` is the private maintainer configuration repository.
  Account references remain private; passwords, tokens and keys are encrypted
  with SOPS/age. The decryption key stays outside Git in the OS Keychain.

These repositories are not automatically synchronized. A build uses its current
checkout and does not automatically select the newest source from another repo.
Public main may lag private main; record and compare the exact revisions before
claiming they contain the same changes. Never change a repository's visibility to
publish an update.

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

Before distributing a release, identify the source repository, exact revision,
version/build and intended channels. Fetch that repository's main and run the
existing release baseline check. That check compares ancestry within the current
repository; it does not verify parity with the other repository. Compare source
changes explicitly when incorporating private fixes into a public-source build.
Preserve build 54/58 compatibility and the existing build-number/device policy.
Moving app-store release automation or publishing a release requires an explicit
release task; repository publication does not silently rewire those systems.

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
