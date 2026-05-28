# Fork Sync Workflow

How to keep this fork in sync with upstream PocketBase releases.

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
5. Update the version reference in `FORK.md` ("Modified Files" table) and
   `WEBAUTHN_PLAN.md` (status table) to match.

### Step 4: Rebase deploy branch onto updated WebAuthn

```bash
git checkout deploy/azure
git rebase feat/webauthn-passkey-support
```

This should be **conflict-free** — `deploy/azure` only adds new files (Dockerfile, Bicep, etc.) that don't exist upstream.

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

### Step 6: Update FORK.md

Update the "Upstream Sync Status" table in `FORK.md` with:

- The PocketBase version/commit you synced to (e.g. `aeb78e51` / v0.39.0)
- Today's date
- Test status (including any allowlisted flakes)

Also add a new row to the "Sync history" table immediately below it, noting any
non-trivial upstream additions (new auth option fields, new tokens, etc.) that
required fork-side follow-up.

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
- [ ] `FORK.md` sync status updated
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

If the merge conflicts (it normally won't, since `deploy/azure` already
contains everything that's on `master`), prefer `-X theirs` to take the
`deploy/azure` side, then re-run tests.
