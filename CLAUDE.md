# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A fork of PocketBase (Go backend with embedded SQLite, realtime subscriptions, file/user management, and an embedded Svelte admin UI) carrying two custom layers on top of upstream:

1. **WebAuthn/Passkey auth** (`feat/webauthn-passkey-support` branch)
2. **Docker + Azure Container Apps deployment** (`deploy/azure` branch — Dockerfile, `entrypoint.sh`, `litestream.yml`, `infra/` Bicep, `azure.yaml`, `DEPLOY.md`)

`master` is the fork default branch, produced by merging `deploy/azure` after each upstream sync. See `FORK.md` for current sync status and `FORK_SYNC.md` for the full sync runbook.

## Commands

```bash
make test          # go test ./... -v --cover
make lint          # golangci-lint run -c ./golangci.yml ./...
make test-report   # tests with HTML coverage report
make jstypes       # regenerate jsvm TS type declarations
```

- Single test: `go test -run TestRecordAuthWithWebAuthnRegisterBegin ./apis/...`
- WebAuthn suite: `go test -run 'WebAuthn|Webauthn' ./apis/... ./core/...`
- Run the app locally: `cd examples/base && go run main.go serve` (serves on http://localhost:8090 with the embedded admin UI)
- Requires Go 1.25+.

### Admin UI (`ui/`)

Svelte + Vite SPA, embedded into the Go binary via `//go:embed all:dist` in `ui/embed.go` (excludable with `-tags no_ui`). Requires Node 24+.

```bash
cd ui
npm install
npm run dev      # dev server on :5173, expects backend on :8090 (override via ui/.env.development.local)
npm run build    # regenerates ui/dist
```

`ui/dist` is committed. After any UI change: `npm run build`, then commit the regenerated `ui/dist`.

## Architecture

### Package layout

- `core/` — the engine: the `App` interface (`core/app.go`) and `BaseApp` implementation, `Collection`/`Record`/`Settings` models, DB layer, event definitions, system migrations runner.
- `apis/` — HTTP route handlers, bound in `apis/base.go` (records CRUD, auth flows including WebAuthn, collections, settings, files, backups, batch, realtime).
- `forms/` — validation/submit structs for record and collection upserts and auth.
- `tools/` — standalone utilities: `hook/` (the event system), `router/`, `auth/` (OAuth2 providers), `filesystem/`, `mailer/`, `cron/`, `subscriptions/` (realtime broker), `search/` (filter/sort parsing), `security/`.
- `plugins/` — `jsvm/` (Goja-based JS hooks runtime; hooks loaded from a `pb_hooks` dir), `migratecmd/` (user migration CLI), `ghupdate/`.
- `migrations/` — system schema migrations (the WebAuthn collection lives in `migrations/1712966400_add_webauthn.go`).
- `cmd/` — cobra commands: serve, superuser, version.
- `tests/` — test helpers: test app factory and the `ApiScenario` harness.
- `pocketbase.go` — top-level `PocketBase` struct wiring `BaseApp` + cobra CLI; `examples/base/main.go` is the canonical full setup with all plugins registered.

### Request lifecycle

Request → `tools/router` middleware chain (CORS, rate limit, token auth via `apis.RequireAuth` etc., security headers) → handler in `apis/` receives a `*core.RequestEvent` (carries `App`, `Auth`, request info) → handler typically drives a `forms/` submit which triggers the model hook chain → response.

### Hook/event system

Everything extends through `tools/hook` generic hooks exposed on the `App` interface: `OnModel{Validate,Create,CreateExecute,AfterCreateSuccess,...}`, `OnRecord*`/`OnCollection*` (typed proxies of the model hooks), `OnRecordAuthWith{Password,OAuth2,OTP,WebAuthnRequest}`, `OnBootstrap`, `OnServe`, `OnTerminate`. Handlers form a middleware chain — each must call `e.Next()` to continue. The jsvm plugin mirrors these hooks into JavaScript via reflection (`plugins/jsvm/binds.go`); `plugins/jsvm/binds_test.go` asserts exact bind counts, so adding a hook to `core.App` breaks that test until updated.

### Database layer

- Driver is **`modernc.org/sqlite`** (pure Go), not upstream's default mattn/go-sqlite3. `modernc_versions_check.go` pins expected sqlite/libc versions — keep it in sync when bumping.
- Two databases per instance: `data.db` (app data, via `app.DB()`) and `auxiliary.db` (logs/internal, via `app.AuxDB()`), each with separate concurrent/nonconcurrent `dbx` connections. WAL mode and pragmas are set in `core/db_connect.go`.
- Models implement `core.Model` (`TableName()`, `IsNew()`); `Collection` defines schema + API rules, `Record` is a dynamic row with rule-aware JSON export.

### Test conventions

API tests are table-driven `tests.ApiScenario` slices (method, URL, body, auth header, expected status/events/body substrings) executed against a throwaway test app from `tests/`. Core tests exercise models directly. Run `make test` before pushing — CI runs the full suite plus golangci-lint and a Docker build/health-check smoke test.

## Fork maintenance (critical)

- **Remotes**: `origin` = doodlemania2/pocketbase (push), `upstream` = pocketbase/pocketbase (fetch only).
- **Branch stack**: `upstream/master` → rebase `feat/webauthn-passkey-support` → rebuild `deploy/azure` on top → merge into `master`. `deploy/azure` is **not cleanly rebasable** — it is rebuilt by replaying its delta as a patch onto the fresh WebAuthn tip (FORK_SYNC.md Step 4). Linear history, force-push with `--force-with-lease`. Full procedure in `FORK_SYNC.md`; update `FORK.md` after each sync.
- **Token redaction pitfall**: `core/collection_model.go` `MarshalJSON` must blank the `Secret` of every `*ResetToken`-style auth token config. When upstream adds a new token type (e.g. `PasskeyResetToken` in v0.39.0), the rebase silently drops the redaction — re-add `alias.X.Secret = ""` or the secret leaks via the API.
- **modernc vs mattn divergence**: `apis/TestSQLRun/single_write_query` expects affected-rows = 1 for DDL under modernc (upstream's mattn reports 0). Keep the fork's value of 1 when the test conflicts on rebase.
- **Known flaky tests on macOS**: `core/TestNotifyWatcher_CollectionsUpdate` and `core/TestNotifyWatcher_SettingsUpdate` (fsnotify duplicate WRITE events) — not fork regressions.
- **Deployment constraint**: Azure Container Apps runs a **single replica** (SQLite single-writer) with Azure Files at `/pb_data` and Litestream replicating the WAL to Blob Storage; `entrypoint.sh` auto-restores from the replica on cold start. Don't introduce changes that assume horizontal scaling.
