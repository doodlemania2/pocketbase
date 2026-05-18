# Fork Sync Workflow

How to keep this fork in sync with upstream PocketBase releases.

## Prerequisites

This clone uses an **inverted** remote layout (historical):

| Remote | URL | Role |
| --- | --- | --- |
| `origin` | `https://github.com/pocketbase/pocketbase.git` | **Upstream** — fetch only, never push |
| `fork` | `https://github.com/doodlemania2/pocketbase.git` | Our fork — push target |

Verify with `git remote -v` before running any of the commands below. If your
clone has the conventional layout (`origin` = fork, `upstream` = upstream),
swap the remote names in every command accordingly.

```bash
# One-time setup for a fresh clone matching this doc's layout:
# git clone https://github.com/pocketbase/pocketbase.git
# cd pocketbase
# git remote add fork https://github.com/doodlemania2/pocketbase.git
# git fetch fork
```

## Sync Procedure

### Step 1: Fetch upstream

```bash
git fetch origin   # upstream pocketbase/pocketbase
git fetch fork     # our fork (for tracking branches)
```

### Step 2: Rebase WebAuthn branch onto upstream

```bash
git checkout feat/webauthn-passkey-support
git rebase origin/master
```

**If conflicts occur**, they will be limited to these files:

| File | Risk | Notes |
|------|------|-------|
| `go.mod` / `go.sum` | MEDIUM | Dependency version bumps. Accept upstream versions, then re-add `go-webauthn/webauthn`. |
| `core/collection_model_auth_options.go` | MEDIUM | Shared auth options struct. Merge carefully — our addition is the `WebAuthn` field. |
| `core/app.go` | LOW | We add one hook method. Usually appended at end. |
| `core/base.go` | LOW | We add hook field + init. Usually appended at end. |
| `apis/record_auth.go` | LOW | We add route bindings. Usually appended at end of route list. |
| `core/collection_model_test.go` | LOW | JSON snapshot update — re-add `webauthn` field. |
| `core/collection_query_test.go` | LOW | System collection count — increment by 1 from upstream's new count. |

**Resolution strategy:** Our changes are mostly additive (new fields, new methods, new constants). Accept upstream's version first, then re-apply our additions.

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
make test
docker build -t pocketbase-fork .
docker run --rm -p 8090:8090 pocketbase-fork &
sleep 3
curl -sf http://localhost:8090/api/health && echo "OK" || echo "FAIL"
```

### Step 6: Update FORK.md

Update the "Upstream Sync Status" table in `FORK.md` with:
- The PocketBase version/commit you synced to
- Today's date
- Test status

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

Push to the **`fork`** remote (which is our fork). `origin` is the upstream
pocketbase/pocketbase — never push to it.

```bash
git checkout feat/webauthn-passkey-support
git push --force-with-lease fork feat/webauthn-passkey-support

git checkout deploy/azure
git push --force-with-lease fork deploy/azure
```

> **Use `--force-with-lease`** instead of `--force` to prevent overwriting someone else's changes.

## Step 7: Merge deploy/azure into fork's `master`

The fork's default branch is `master` on `fork` (doodlemania2/pocketbase). After
the rebased `deploy/azure` is force-pushed, fast-forward (or merge) it into
`master` so consumers of the fork's default branch pick up the sync.

Because `deploy/azure` is rebased onto fresh upstream, `fork/master` will have
diverged. Use a merge commit (matches the pattern of previous syncs):

```bash
git checkout master           # local tracking of fork/master
git fetch fork
git reset --hard fork/master  # ensure clean starting point
git merge --no-ff deploy/azure -m "Merge deploy/azure: upstream vX.Y.Z sync + webauthn vA.B.C"
git push fork master
```

If the merge conflicts (it normally won't, since `deploy/azure` already
contains everything that's on `master`), prefer `-X theirs` to take the
`deploy/azure` side, then re-run tests.
