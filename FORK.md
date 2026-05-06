# PocketBase Fork — WebAuthn/Passkey Support

This is a maintained fork of [PocketBase](https://github.com/pocketbase/pocketbase) that adds **WebAuthn/Passkey authentication** as a first-class auth method alongside password, OAuth2, and OTP.

## Why This Fork Exists

PocketBase does not natively support WebAuthn/Passkey authentication. This fork adds full server-side WebAuthn support following PocketBase's existing auth patterns, designed to stay in sync with upstream releases via a layered branch strategy.

## What's Changed

### Feature: WebAuthn/Passkey Authentication

Adds 7 API endpoints for passkey registration, login, and credential management:

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `/api/collections/{col}/auth-with-webauthn/register-begin` | POST | Authenticated | Start passkey registration |
| `/api/collections/{col}/auth-with-webauthn/register-finish` | POST | Authenticated | Complete passkey registration |
| `/api/collections/{col}/auth-with-webauthn/login-begin` | POST | Public | Start passkey login |
| `/api/collections/{col}/auth-with-webauthn/login-finish` | POST | Public | Complete passkey login |
| `/api/collections/{col}/auth-with-webauthn/credentials` | GET | Authenticated | List user's passkeys |
| `/api/collections/{col}/auth-with-webauthn/credentials/{id}` | DELETE | Authenticated | Delete a passkey |
| `/api/collections/{col}/auth-with-webauthn/credentials-by-record/{id}` | DELETE | Superuser | Admin clear all passkeys for a user |

**Configuration:** Enable via collection auth options (`webauthn.enabled: true`). Disabled by default.

**MFA Integration:** WebAuthn counts as a valid MFA method. Requires 2+ auth methods when MFA is enabled.

**Security:** Challenge sessions with 2-minute TTL, rate limiting (5 req/180s on login-finish), sign count validation, origin/RP validation, cascading credential deletion on user removal.

### Feature: Docker + Azure Deployment

Containerized deployment with continuous SQLite backup:

- **Dockerfile** — Multi-stage build (Go source → Alpine runtime + Litestream)
- **Litestream** — Continuous WAL streaming to Azure Blob Storage for disaster recovery
- **Azure Container Apps** — Bicep infrastructure with Azure Files persistent volume
- **docker-compose.yml** — Local development setup

## File Manifest

### WebAuthn — New Files (4)

| File | Purpose |
|------|---------|
| `core/webauthn_credential_model.go` | WebAuthnCredential model with field accessors, base64url encode/decode |
| `apis/record_auth_with_webauthn.go` | 7 API handlers (register, login, credential management) |
| `apis/record_auth_with_webauthn_test.go` | 27 test scenarios across 8 test functions |
| `migrations/1712966400_add_webauthn.go` | `_webauthnCredentials` system collection + indexes |

### WebAuthn — Modified Files (15)

| File | Change |
|------|--------|
| `core/collection_model_auth_options.go` | `WebAuthnConfig` struct, `WebAuthn` field in auth options |
| `core/events.go` | `RecordAuthWithWebAuthnRequestEvent` type |
| `core/app.go` | `OnRecordAuthWithWebAuthnRequest()` hook method |
| `core/base.go` | Hook field initialization, cascading delete on user deletion |
| `core/mfa_model.go` | `MFAMethodWebAuthn = "webauthn"` constant |
| `core/event_request.go` | `RequestInfoContextWebAuthn` constant |
| `apis/record_auth.go` | 7 route bindings with middleware (rate limiting, auth) |
| `apis/record_auth_methods.go` | `webauthn` field in auth methods response |
| `go.mod` / `go.sum` | `go-webauthn/webauthn v0.17.2` + transitive deps |
| `core/collection_model_test.go` | Updated JSON snapshot for webauthn field |
| `core/collection_query_test.go` | System collection count 16 → 17 |
| `apis/collection_test.go` | `totalItems` count 16 → 17 |
| `apis/collection_import_test.go` | `totalCollections` count 16 → 17 |
| `plugins/jsvm/binds_test.go` | Hook count 82 → 83 |
| `plugins/migratecmd/migratecmd_test.go` | Updated migration template snapshots |

### Docker/Azure — New Files (all on `deploy/azure` branch)

| File | Purpose |
|------|---------|
| `Dockerfile` | Multi-stage: Go build → Alpine + Litestream |
| `entrypoint.sh` | Env vars, superuser upsert, Litestream restore/replicate |
| `litestream.yml` | Replication config for Azure Blob Storage |
| `docker-compose.yml` | Local development compose |
| `.dockerignore` | Build context exclusions |
| `azure.yaml` | azd project definition |
| `infra/main.bicep` | Root Bicep orchestration |
| `infra/modules/container-app.bicep` | Container Apps + managed identity + RBAC |
| `infra/modules/storage.bicep` | Azure Files + Blob Storage |
| `infra/modules/acr.bicep` | Azure Container Registry |

## Branch Strategy

```
upstream/master (pocketbase/pocketbase)
    │
    │  git rebase upstream/master
    ▼
feat/webauthn-passkey-support    ← WebAuthn only (4 new + 15 modified files)
    │
    │  git rebase feat/webauthn-passkey-support
    ▼
deploy/azure                     ← Docker + infra + CI/CD + docs (zero conflict risk)
```

- **`feat/webauthn-passkey-support`** — Only WebAuthn changes against upstream. This is where rebase conflicts happen (limited to ~15 files).
- **`deploy/azure`** — All Docker/infra/docs files (all new, never conflicts with upstream). Deploy from this branch.

See [FORK_SYNC.md](FORK_SYNC.md) for the upstream sync workflow.

## Upstream Sync Status

| Field | Value |
|-------|-------|
| Based on PocketBase | `master` @ `0cf34c47` (v0.37.5) |
| Last sync | 2026-05-05 |
| WebAuthn tests | All 27 passing |

## Companion Packages

- **`pocketbase-webauthn`** (planned) — Standalone TypeScript package wrapping WebAuthn endpoints using the upstream JS SDK's `pb.send()`. No JS SDK fork needed.

## Quick Start

```bash
# Local development
docker compose up --build

# Deploy to Azure
azd up
```
