# Fork Sync Workflow

How to keep this fork in sync with upstream PocketBase releases.

## Sync Status

**Current:** synced to upstream **v0.39.4** (`507ecb26`) on 2026-06-18.
WebAuthn library `go-webauthn/webauthn` **v0.17.4**; `modernc.org/sqlite` **v1.52.0**.
Tests: full `go test ./...` green on `feat/webauthn-passkey-support` and
`deploy/azure` (the known macOS `fsnotify` flakes
`TestNotifyWatcher_CollectionsUpdate` / `TestNotifyWatcher_SettingsUpdate` are
ignored; the Docker build/health-check smoke test runs in CI).

| Synced to | Date | WebAuthn | Notes |
| --- | --- | --- | --- |
| v0.39.4 (`507ecb26`) | 2026-06-18 | v0.17.4 | OAuth2 RedirectURL validator removed; goja bumped to 20260607; dlclark/regexp2→v2; golang.org/x/sync v0.21.0; UI: relation-field sorting, sortable index count fix, tooltip fixes. Zero overlap with deploy layer. |
| v0.39.3 (`465cfb52`) | 2026-06-11 | v0.17.4 | modernc 1.51→1.52; upstream field-settings UI refactor, number `0`-max validator fix, extra SQL write keywords, cron panic-recover. `feat`/`deploy/azure` had drifted behind `master` at v0.39.0 — rebuilt by sourcing the fork delta from `master` to avoid regression. |
| v0.39.1 (`5631d9b1`) | 2026-06-07 | v0.17.4 | Prior production deploy to Azure. |
| v0.39.0 (`aeb78e51`) | 2026-05 | v0.17.4 | `PasskeyResetToken` secret redaction re-added. |

> The old standalone `FORK.md` status page was removed; sync status now lives in
> this section.

## Prerequisites

This clone uses the **conventional** remote layout:

| Remote | URL | Role |
| --- | --- | --- |
| `origin` | `https://github.com/doodlemania2/pocketbase.git` | Our fork — push target |
| `upstream` | `https://github.com/pocketbase/pocketbase.git` | Upstream — fetch only, never push |

Verify with `git remote -v` before running any of the commands below. If your
clone has the inverted layout (`origin` = upstream, `fork` = our fork — historical
on some clones), swap the remote names in every command accordingly.

```bash
# One-time setup for a fresh clone matching this doc's layout:
# git clone https://github.com/doodlemania2/pocketbase.git
# cd pocketbase
# git remote add upstream https://github.com/pocketbase/pocketbase.git
# git fetch upstream
```

## Sync Procedure

### Step 1: Fetch upstream

```bash
git fetch upstream   # pocketbase/pocketbase
git fetch origin     # our fork
```

### Step 2: Rebase WebAuthn branch onto upstream

```bash
git checkout feat/webauthn-passkey-support
git rebase upstream/master
```

**If conflicts occur**, they will be limited to these files:

| File | Risk | Notes |
|------|------|-------|
| `go.mod` / `go.sum` | MEDIUM | Dependency version bumps. Accept upstream versions, then re-add `go-webauthn/webauthn`. |
| `core/collection_model_auth_options.go` | MEDIUM | Shared auth options struct. Merge carefully — our addition is the `WebAuthn` field. |
| `core/collection_model.go` | **HIGH** | Redaction block in `MarshalJSON` strips token secrets. If upstream adds a new `*ResetToken` (e.g. v0.39.0 added `PasskeyResetToken`), our fork MUST re-add the matching `alias.X.Secret = ""` line, otherwise the new secret leaks via the API. A stale "basebuild fix" commit from an earlier sync attempt can silently REVERT this on a later rebase — verify with `git log -G 'PasskeyResetToken.Secret' -- core/collection_model.go` after every rebase. |
| `core/app.go` | LOW | We add one hook method. Usually appended at end. |
| `core/base.go` | LOW | We add hook field + init. Usually appended at end. |
| `apis/record_auth.go` | LOW | We add route bindings. Usually appended at end of route list. |
| `core/collection_model_test.go` | LOW | JSON snapshot update — re-add `webauthn` field, and any new upstream `*ResetToken`/`*Template` fixture keys (e.g. `passkeyResetToken`, `passkeyResetTemplate`). |
| `core/collection_query_test.go` | LOW | System collection count — increment by 1 from upstream's new count. |
| `ui/dist/*` | LOW | Pre-built UI assets. On conflict, take `--theirs` (upstream's), then regenerate from source: `cd ui && npm ci && npm run build && cd .. && git add ui/dist && git commit -m "chore(ui): regenerate ui/dist after upstream sync"`. Do this on BOTH `feat/webauthn-passkey-support` and `deploy/azure`. |

**Resolution strategy:** Our changes are mostly additive (new fields, new methods, new constants). Accept upstream's version first, then re-apply our additions.

**Rebase pitfall — silently dropped commit content.** `git rebase` can keep a commit
in the log while dropping its diff if the commit's content is already-applied or
conflicts with later commits and is auto-resolved. After every rebase, verify the
intended diff is still present:

```bash
git log -G 'PasskeyResetToken.Secret' -- core/collection_model.go
git diff <pre-rebase-backup-ref>..HEAD -- core/collection_model.go
```

If the redaction line is missing, restore it as a new commit — do NOT amend old commits.

**Dropping obsolete webauthn duplicates during rebase.** If the rebase replays
old "basebuild fix" commits that have since been merged upstream (or that conflict
with the new upstream baseline), drop them via `GIT_SEQUENCE_EDITOR`:

```bash
GIT_SEQUENCE_EDITOR="sed -i '' -E '/^pick [0-9a-f]+ (basebuild|fix\\(basebuild)/d'" \
  git rebase -i upstream/master
```

Verify dropped commits don't undo intentional fork changes (e.g. token redaction)
before continuing.

### Step 3: Validate WebAuthn branch

```bash
make test
```

All 27 WebAuthn test scenarios must pass, plus all upstream tests.

### Step 3b: Opportunistic WebAuthn dependency check

While on `feat/webauthn-passkey-support`, check for newer releases of the
WebAuthn library and bump if patch/minor and non-breaking:

```bash
go list -m -u github.com/go-webauthn/webauthn github.com/go-webauthn/x
```

If a newer version is available:

1. Review the release notes at https://github.com/go-webauthn/webauthn/releases
   for **BREAKING CHANGES**. Pay particular attention to:
   - `webauthn.Config` field changes (esp. `RPTopOrigins`,
     `RPAllowCrossOrigin`, `RPTopOriginVerificationMode`)
   - `Credential` / `CredentialDescriptor` shape changes (e.g. the v0.17.0
     `AttestationType` → `AttestationFormat` split)
   - Removed constants (e.g. `protocol.CredentialTypeFIDOU2F`)
2. Grep for any affected APIs in `apis/record_auth_with_webauthn.go` and
   `core/webauthn_credential_model.go` before bumping.
3. Bump and tidy:

   ```bash
   go get github.com/go-webauthn/webauthn@vX.Y.Z
   go mod tidy
   go test -count=1 -run 'WebAuthn|Webauthn' ./apis/... ./core/...
   ```

4. Commit as `deps(webauthn): bump go-webauthn/webauthn vA -> vB` with the
   relevant release notes summarized in the body.
5. Update the WebAuthn version in the **Sync Status** section at the top of this
   file to match.

### Step 4: Rebuild deploy branch onto updated WebAuthn

> **Do NOT use `git rebase feat/webauthn-passkey-support` here.** `deploy/azure`
> has accumulated a deeply tangled history from prior syncs — merge commits plus
> dozens of duplicated webauthn/"Initial azure"/sync-doc commits that were
> force-pushed across earlier rounds. A plain rebase replays 100+ commits and
> produces spurious conflicts in `.gitignore`, `go.mod`/`go.sum`,
> `apis/record_auth*.go`, and `core/base.go`. It is not cleanly rebasable.

Instead, **rebuild** `deploy/azure` as a single clean delta on top of the freshly
rebased WebAuthn branch. This works because the deploy layer's *genuine*
customizations (Docker, Bicep infra, entrypoint, litestream, passkey self-service
reset flow, FORK docs) touch **zero** files that upstream changed — verify this
holds each sync before trusting the shortcut.

```bash
# 1. Identify the OLD feat tip that deploy/azure was previously built on. It is
#    the merge-base of the PRE-rebase feat branch and the current deploy branch,
#    and must be a direct ancestor of origin/deploy/azure:
OLD_FEAT=$(git merge-base <pre-rebase-feat-backup> origin/deploy/azure)
git merge-base --is-ancestor "$OLD_FEAT" origin/deploy/azure && echo "ok: ancestor"

# 2. Capture the deploy layer's genuine delta (everything deploy added/changed on
#    top of that old feat tip), EXCLUDING regenerated ui/dist artifacts:
git diff "$OLD_FEAT" origin/deploy/azure -- . ':(exclude)ui/dist' > /tmp/deploy_delta.patch

# 3. Reset deploy/azure to the NEW (v-bumped) feat tip and replay the delta:
git checkout deploy/azure
git reset --hard feat/webauthn-passkey-support
git apply --3way --whitespace=nowarn /tmp/deploy_delta.patch   # must exit 0

# 4. Regenerate ui/dist from source and commit:
cd ui && ./node_modules/.bin/vite build && cd ..   # NOTE: vite directly, not `npm run build`
git add -A
git commit -m "chore(deploy): rebuild deploy/azure onto upstream vX.Y.Z + webauthn"
```

**Sanity checks before trusting the rebuild** (all must hold):

```bash
# (a) deploy's genuine delta must touch NO upstream-changed file. Compare:
git diff --name-only vX.Y.0 vX.Y.1 | grep -v '^ui/dist/' | sort > /tmp/upstream_changed.txt
git diff --name-only "$OLD_FEAT" origin/deploy/azure -- . ':(exclude)ui/dist' | sort > /tmp/deploy_files.txt
comm -12 /tmp/upstream_changed.txt /tmp/deploy_files.txt   # for each shown file, confirm
# the deploy delta for it is empty: `git diff "$OLD_FEAT" origin/deploy/azure -- <file>` == 0 lines

# (b) upstream-only files in the rebuilt tree must equal the new feat tip (= vX.Y.1):
git diff --quiet HEAD feat/webauthn-passkey-support -- apis/realtime.go core/mfa_model.go && echo "upstream files = v-bumped"

# (c) deploy-only files (Dockerfile, infra/, passkey-reset) must still be present:
git ls-files Dockerfile infra/main.bicep apis/record_auth_passkey_reset_request.go
```

### Step 5: Validate deploy branch

```bash
# Full unit test suite (allow up to ~5 min)
go test ./... -timeout 6m

# Container build & smoke test. The macOS Docker CLI lives outside the default
# PATH used by some subagent shells — prefix with the explicit dir if needed:
#   export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
docker build -t pocketbase-fork:sync-test .
docker run --rm -d --name pb-sync-smoke -p 8090:8090 pocketbase-fork:sync-test
sleep 3
curl -sf http://localhost:8090/api/health && echo "OK" || echo "FAIL"
docker stop pb-sync-smoke
```

**Known upstream test flakes (allowlist).** These tests fail on macOS regardless
of our changes and are pre-existing in upstream PocketBase. Treat them as ignored
unless `make test` reports OTHER failures:

| Test                                       | Cause                                                |
|--------------------------------------------|------------------------------------------------------|
| `core/TestNotifyWatcher_CollectionsUpdate` | `fsnotify` flake on macOS — duplicate WRITE events.  |
| `core/TestNotifyWatcher_SettingsUpdate`    | Same `fsnotify`/macOS flake.                         |

Resolved driver-difference patch (do not revert during upstream sync):

- `apis/TestSQLRun/single_write_query` expects `affectedRows:1` for `CREATE TABLE` because `modernc.org/sqlite` reports 1 for DDL while upstream's `mattn/sqlite` reports 0.

If a NEW test starts failing after a rebase, fix it before pushing. Pay particular
attention to `core/TestCollectionModelMarshalJSON` and any `Marshal*` test — these
catch missing secret-redaction (see Step 2's HIGH risk row).

### Step 6: Update the Sync Status section

Update the **Sync Status** section at the top of this file (`FORK_SYNC.md`) with:

- The PocketBase version/commit you synced to (e.g. `465cfb52` / v0.39.3)
- Today's date
- Test status (including any allowlisted flakes)

Also add a new row to the sync-history table, noting any non-trivial upstream
additions (new auth option fields, new tokens, etc.) that required fork-side
follow-up.

## Pre-Rebase Checklist

- [ ] All local changes committed (clean working tree)
- [ ] Current tests pass (`make test`)
- [ ] Note the current upstream version for the sync status table

## Post-Rebase Checklist

- [ ] `make test` passes on `feat/webauthn-passkey-support`
- [ ] `make test` passes on `deploy/azure`
- [ ] `docker build` succeeds on `deploy/azure`
- [ ] Health check passes on built container
- [ ] WebAuthn endpoints respond correctly
- [ ] Sync Status section (top of `FORK_SYNC.md`) updated
- [ ] Force-push both branches (after confirming rebase is correct)

## Force Push (after successful rebase)

Push to the **`origin`** remote (which is our fork, `doodlemania2/pocketbase`).
`upstream` is `pocketbase/pocketbase` — never push to it.

```bash
git checkout feat/webauthn-passkey-support
git push --force-with-lease origin feat/webauthn-passkey-support

git checkout deploy/azure
git push --force-with-lease origin deploy/azure
```

> **Use `--force-with-lease`** instead of `--force` to prevent overwriting someone else's changes.
>
> **STOP and confirm with the human** before running these pushes. The fork's
> `master`, `feat/webauthn-passkey-support`, and `deploy/azure` are all consumed
> by CI/CD (Azure Container Apps deploy). A bad push triggers a real deploy.

## Step 7: Merge deploy/azure into fork's `master`

The fork's default branch is `master` on `origin` (doodlemania2/pocketbase). After
the rebased `deploy/azure` is force-pushed, fast-forward (or merge) it into
`master` so consumers of the fork's default branch pick up the sync.

Because `deploy/azure` is rebased onto fresh upstream, `origin/master` will have
diverged. Use a merge commit (matches the pattern of previous syncs):

```bash
git checkout master             # local tracking of origin/master
git fetch origin
git reset --hard origin/master  # ensure clean starting point
git merge --no-ff deploy/azure -m "Merge deploy/azure: upstream vX.Y.Z sync + webauthn vA.B.C"
git push origin master
```

The merge **will** conflict on regenerated `ui/dist/*` artifacts (rename/delete +
modify/delete churn) because the previous `master` and the rebuilt `deploy/azure`
generated differently-hashed asset filenames. The merge result for `master` should
simply equal `deploy/azure`'s tree, so resolve by resetting the merge tree to
`deploy/azure` (this keeps both parents):

```bash
git merge --no-ff deploy/azure -m "Merge deploy/azure: upstream vX.Y.Z sync + webauthn vA.B.C"
# ...conflicts in ui/dist/* and ui/dist/index.html...
git read-tree --reset -u deploy/azure   # make tree == deploy/azure, discard conflicts
git diff deploy/azure                    # must be empty
git commit --no-edit                     # creates the merge commit with both parents
git push origin master
```
