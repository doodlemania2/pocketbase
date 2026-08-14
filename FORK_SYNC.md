# Fork Sync Workflow

How to keep this fork in sync with upstream PocketBase releases.

## Sync Status

**Current:** synced to upstream **v0.39.11** (`5d217ddb`) on 2026-08-14 (a
two-version jump, v0.39.10 + v0.39.11). WebAuthn library
`go-webauthn/webauthn` **v0.17.4** (already latest — Step 3b found no newer
release); `modernc.org/sqlite` bumped **v1.54.0 → v1.55.0** by upstream, which
also updated `modernc_versions_check.go` itself (libc unchanged at v1.74.1) —
no fork-side follow-up needed. Tests: full `go test ./...` green on
`feat/webauthn-passkey-support` (34/34 packages, first run, zero flakes);
`deploy/azure` 33/34 with the allowlisted `core/TestNotifyWatcher_SettingsUpdate`
macOS `fsnotify` flake, which passed 3/3 on isolated re-run. `golangci-lint`
v2.6.2 and `gofmt -l`: **0 issues on both branches**. WebAuthn/Passkey suite
green (`go test -run 'WebAuthn|Webauthn|Passkey' ./apis/... ./core/...`).
The Docker build/health-check smoke test runs in CI — no local container
runtime was available this sync either, so it was deferred to CI; a **native**
binary smoke test was run instead (`go build ./examples/base` + `serve`):
`/api/health` 200, the deploy-layer `/passkeys` self-service page 200, and the
embedded admin UI `/_/` 200.

**`npm install` vs `npm ci` — new gotcha this sync.** Step 4's `ui/dist`
rebuild must use `npm ci`, never `npm install`. The local toolchain is Node
**v22.22.2** / npm **10.9.7** while `release.yaml` pins `node-version:
'>=25.2.1'`; npm 10 rewrites `ui/package-lock.json` and **strips the `libc`
fields** (`glibc`/`musl`) from the platform-specific optional `rolldown`
binaries that npm 11 writes. Committing that lock would break the Linux CI
install. If you see a lockfile diff that is pure `-  "libc": [` deletions,
`git checkout -- ui/package-lock.json` and re-install with `npm ci`.

**Dependabot vite/postcss bump is now obsolete.** The v0.39.9 follow-up commit
`deps(ui): bump vite 8.0.14 -> 8.1.5, postcss 8.5.15 -> 8.5.23` was **dropped**
during this rebase: upstream v0.39.11's own `ui/package-lock.json` already
ships **vite 8.2.1 / postcss 8.5.26**, which supersedes it. After the go.mod
and lockfile conflicts were resolved the commit retained nothing but stale
`ui/dist` hashes, so it was reset away and replaced by a single clean
`vite build`.

## CI coverage

Workflows and what actually gates a push:

| Workflow | File | Runs on |
| --- | --- | --- |
| `basebuild` | `.github/workflows/release.yaml` | push to all branches + tags — builds UI, `go test ./...`, GoReleaser |
| `Test` | `.github/workflows/test.yml` | push/PR to `master`, `deploy/azure`, `feat/*` — `go test -v --cover`, **golangci-lint**, **Docker build + `/api/health` smoke test** |
| `Deploy to Azure` | `.github/workflows/deploy.yml` | push to `deploy/azure` — real Container Apps deploy |

> **Gotcha that hid a gap for many syncs.** A GitHub Actions workflow only runs
> if the workflow file exists **on the branch being pushed**. `test.yml` is a
> deploy-layer file, so it lives on `master`/`deploy/azure` but *not* on
> `feat/webauthn-passkey-support` — yet its only push trigger was
> `feat/webauthn-passkey-support`. Result: the workflow never fired, on any
> branch, ever (`gh run list --workflow=test.yml` returned zero runs), and this
> fork also syncs by force-push rather than PRs, so the `pull_request` trigger
> never fired either. `golangci-lint` and the Docker smoke test were silently
> not running. Fixed at v0.39.9 by adding `master` + `deploy/azure` to the push
> triggers. If you ever move `test.yml` between layers, re-check this.
>
> Also fixed at the same time: the lint step pinned
> `golangci/golangci-lint-action@v6`, which installs golangci-lint **v1** — but
> `golangci.yml` is schema `version: "2"`. It would have failed to parse on the
> first real run. Now `@v7` with an explicit `version: v2.6.2`.

| Synced to | Date | WebAuthn | Notes |
| --- | --- | --- | --- |
| v0.39.11 (`5d217ddb`) | 2026-08-14 | v0.17.4 | Two-version jump (v0.39.10 `0a74d2f2` + v0.39.11). Small release — **3 backend Go files touched in total**. `core/field_file.go`: `FileField.toSliceValue` now nil-guards `*filesystem.File` and `[]*filesystem.File` entries so a non-initialized `*filesystem.File` no longer panics. `pocketbase.go`: [#7781](https://github.com/pocketbase/pocketbase/issues/7781) **reverted** the v0.39.7 `routine.SafeWrap`/`FireAndForget` autorecover wrapping for the two CLI goroutines in `Execute()` (signal listener + `RootCmd.Execute`) back to plain `go func()` — the panic-recover swallowed CLI command panics. `modernc_versions_check.go`: `expectedDriverVersion` v1.54.0→v1.55.0, bumped by upstream itself alongside `modernc.org/sqlite`; libc stays v1.74.1. Deps: `golang.org/x/{crypto 0.54→0.55, image 0.44→0.45, net 0.57→0.58, mod 0.37→0.40, text 0.40→0.41, tools 0.47→0.49}`; release workflow min Go 1.26.5→1.26.6; js-sdk `pocketbase` 0.27.0→0.27.3; `vite.config.js` `__dirname`→`import.meta.dirname`. UI: logs chart loading placeholder + staggered chart init, API preview example fixes ([#7782](https://github.com/pocketbase/pocketbase/issues/7782)) incl. verification-request samples, relation-field collection editing on a duplicated collection, sortable/dropdown-keyboard-nav/codeEditor fixes, shablon update. **Rebase conflicts**: `go.mod` ×1 (standard "take upstream versions + re-add `tinylib/msgp`/`x448/float16` webauthn indirects" resolution) and `ui/dist` rename/rename churn ×2 — both `ui/dist` regenerate commits were dropped and replaced by one fresh `vite build`; the Dependabot `vite`/`postcss` bump commit was dropped as superseded by upstream's own lockfile (see Sync Status). **Deploy-rebuild overlap: non-empty** — deploy's genuine delta touches 2 upstream-changed files, `.github/workflows/release.yaml` (deploy adds a top-of-file `permissions: contents: write`; upstream bumped `go-version` at line 34) and `pocketbase.go` (deploy adds `bindPreRestartSignal(pb)` in `NewWithConfig` at line 161; upstream's revert is in `Execute()` at lines 191/200). Both pairs of hunks are disjoint, `git apply --3way` exited 0, and the rebuilt files carry both sides — verified by grep. Verified post-rebuild: all 6 token-config secrets redacted in `core/collection_model.go` (5 upstream + fork `PasskeyResetToken`), no `go-ozzo` import, and every deploy-only file (`Dockerfile`, `infra/main.bicep`, `entrypoint.sh`, `litestream.yml`, `azure.yaml`, `apis/record_auth_passkey_reset_*.go`) present. Upstream still has **no** `PasskeyResetToken` — Step 2 HIGH-risk redaction warning dormant. |
| v0.39.9 (`0cbfc046`) | 2026-07-27 | v0.17.4 | Small deps/UI release — **zero backend Go logic changes**. Upstream touched only `CHANGELOG*`, `go.mod`/`go.sum`, `tools/search/filter_test.go`, and 4 `ui/` source files. Deps: goja 20260701→20260722 (fixes the reported `regexp2` dep regression for empty-string matches with lookahead patterns; pulls `dlclark/regexp2/v2` 2.2.2→2.5.2), `ganigeorgiev/fexpr` v0.5.0→v0.6.0 (large-string-literal optimization + control-character handling — `tools/search/filter_test.go` expectations updated upstream to match), `google/pprof` bumped. UI: `Shift+Click` range bulk selection workaround for Firefox ([#7771](https://github.com/pocketbase/pocketbase/issues/7771)) across `logsList.js`/`recordsList.js`/`pageExportCollections.js`. Rebase conflicts were confined to `go.mod` (×2, both the standard "take upstream versions + re-add `go-webauthn`" resolution) and `go.sum` (×2, resolved with `go mod tidy`); the two `ui/dist` regenerate commits went empty and were dropped, replaced by one fresh `vite build`. **Deploy-rebuild overlap: empty** — deploy's genuine delta touches none of the upstream-changed files, so the Step 4 shortcut applied cleanly (`git apply --3way` exit 0) and the rebuilt `deploy/azure` tree differs from the previous one by *exactly* the upstream v0.39.9 delta. Verified post-rebuild: all 6 token-config secrets redacted in `core/collection_model.go` (5 upstream + fork `PasskeyResetToken`) and no `go-ozzo` import remained. Upstream still has **no** `PasskeyResetToken` — Step 2 HIGH-risk redaction warning dormant. |
| v0.39.8 (`cc4e8570`) | 2026-07-20 | v0.17.4 | Two-version jump (v0.39.7 + v0.39.8). **v0.39.7**: upstream replaced `github.com/go-ozzo/ozzo-validation` with the `github.com/pocketbase/ozzo-validation` fork (original library changed ownership) — this is most of the 6k-line diff (import-path churn across ~90 files). Required **fork-side follow-up**: swap the `go-ozzo` import for the `pocketbase` fork in every fork-added file — `apis/record_auth_with_webauthn.go` (feat) and `apis/record_auth_passkey_reset_{confirm,request}.go` (deploy); go.mod resolved to drop `go-ozzo`, keep `go-webauthn` + `pocketbase/ozzo`, `go mod tidy` swapped the go.sum hashes. Also v0.39.7: internal worker goroutines wrapped in `routine.SafeWrap` (panic→error, security fix [#7762]); View collection `*` validator + friendlier field errors ([#7761]); import-collection `fields` access fix ([#7760]). **v0.39.8**: JSVM `$app` global reset fix for pooled executors; `modernc.org/sqlite` v1.52→v1.54.0 (SQLite 3.53.3); `golang.org/x/*` indirect security bumps; UI number-input leading-0 + `Shift+Click` range select. **Deploy-rebuild overlap (non-empty this sync)**: deploy's genuine delta touched 5 upstream-changed files — `core/base.go`, `core/collection_model.go`, `core/collection_model_auth_options.go`, `plugins/jsvm/binds_test.go`, `pocketbase.go`. `git apply --3way` fell back to direct application and landed every hunk cleanly (disjoint regions); verified post-apply that the 6-token redaction (5 upstream + fork `PasskeyResetToken`) survived in `collection_model.go` and no `go-ozzo` import remained. Upstream still has **no** `PasskeyResetToken` — Step 2 HIGH-risk redaction warning dormant. |
| v0.39.6 (`de3c3f71`) | 2026-07-10 | v0.17.4 | Deps + minor backend hardening. goja bumped 20260618→20260701 (`WeakMap` regression fixes); `golang.org/x/crypto` 0.52→0.53, `net` 0.55→0.56, `mod`/`sys`/`text`/`tools` bumped; min Go GH action 1.26.4→1.26.5. Backend: `tools/auth/microsoft.go` — Microsoft OAuth2 hardening (configurable preferred safe email extraction); `tools/mailer/sendmail.go` — `Cc`/`Bcc` on the dev sendmail command; `tools/dbutils/index_test.go` — test typo. **First non-empty deploy overlap since v0.39.2**: `.github/workflows/release.yaml` — deploy adds a top-of-file `permissions: contents: write` block while upstream bumped `go-version` 1.26.4→1.26.5 at line 31 (disjoint hunks → 3-way merged cleanly; rebuilt file carries permissions + go-version 1.26.5 + fork's `goreleaser-action@v7`). feat-branch `go.mod` conflict resolved by taking upstream `golang.org/x/*` versions + re-adding `tinylib/msgp`/`x448/float16` webauthn indirects. Upstream still has **no** `PasskeyResetToken` — Step 2 HIGH-risk redaction warning dormant (5 upstream token configs + fork's own `PasskeyResetToken` all redacted). |
| v0.39.5 (`667a7650`) | 2026-07-02 | v0.17.4 | UI/deps-only upstream release: goja bumped 20260607→20260618 (`TypedArray` fixes); dlclark/regexp2/v2 2.2.1→2.2.2; UI — ellipsis for long `url` field values, readded editor "fullscreen" option + TinyMCE preload ([#7746]), force-close modals on record/collection deletion. **Zero backend Go logic changes** (upstream touched only go.mod/go.sum/CHANGELOG/ui). Deploy delta overlap with upstream-changed files = empty. Note: upstream still has **no** `PasskeyResetToken` — the Step 2 HIGH-risk redaction warning is dormant for this version (only the 5 existing token configs need redaction, all present). |
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
#    NOTE: `npm ci`, never `npm install` — npm 10 strips the `libc` fields from
#    package-lock.json's optional rolldown binaries and breaks the Linux CI install.
#    NOTE: run vite directly, not `npm run build` (that also runs `dprint fmt`).
rm -rf ui/dist
cd ui && npm ci && ./node_modules/.bin/vite build && cd ..
git diff --quiet ui/package-lock.json || echo "WARN: lockfile changed — revert it"
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

**Known flaky tests (allowlist).** These flake for environment reasons (macOS fs
events, CI timing) rather than fork changes, and are pre-existing in upstream
PocketBase. Treat them as ignored unless `make test`/CI reports OTHER failures;
re-run the specific test to confirm before investigating:

| Test                                       | Cause                                                |
|--------------------------------------------|------------------------------------------------------|
| `core/TestNotifyWatcher_CollectionsUpdate` | `fsnotify` flake on macOS — duplicate WRITE events.  |
| `core/TestNotifyWatcher_SettingsUpdate`    | Same `fsnotify`/macOS flake.                         |
| `apis/TestDefaultRateLimitMiddleware`      | Timing-sensitive rate-limit windows (subtest `#rate/a#03`); flakes under CI load on Linux (`goreleaser` "Run tests" step), passes locally. Re-run to clear. Confirmed a flake in the v0.39.5 sync: `feat` basebuild red on it while `master`/`deploy/azure` basebuild were green on identical code. |
| `tools/cron/TestCronStartStop`             | Timing-sensitive scheduler start/stop assertions; flakes under CI load on Linux (`goreleaser` "Run tests" step), passes locally. Re-run to clear. First seen in the v0.39.8 sync: `feat` basebuild red on it while `master`/`deploy/azure` basebuild were green on identical content in concurrent runs (`tools/cron` is byte-identical to upstream — the fork never touches it); passed 5/5 locally and cleared on `gh run rerun --failed`. |

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
- [ ] `make lint` clean on **both** branches — `golangci.yml` is schema v2, so
      you need golangci-lint v2 (`go install
      github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.6.2`). Fork-added
      files drift out of gofmt easily during rebases (import regrouping).
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
