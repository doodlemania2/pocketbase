# Fork Sync Workflow

How to keep this fork in sync with upstream PocketBase releases.

## Prerequisites

```bash
# Add upstream remote (one-time setup)
git remote add upstream https://github.com/pocketbase/pocketbase.git
```

## Sync Procedure

### Step 1: Fetch upstream

```bash
git fetch upstream
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

```bash
git checkout feat/webauthn-passkey-support
git push --force-with-lease origin feat/webauthn-passkey-support

git checkout deploy/azure
git push --force-with-lease origin deploy/azure
```

> **Use `--force-with-lease`** instead of `--force` to prevent overwriting someone else's changes.
