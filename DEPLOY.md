# Azure Deployment Runbook

End-to-end deployment of this PocketBase fork to **Azure Container Apps**, with PocketBase's native scheduled backups, shared cross-RG observability (Log Analytics + Application Insights), and a custom domain.

> **Litestream is disabled and has been since 2026-05-25.** The binary is still
> baked into the image and `litestream.yml` still ships, but no `LITESTREAM_*`
> env var is set, so `entrypoint.sh` skips both restore and replicate. Durability
> comes from the persistent NFS `/pb_data` volume plus PocketBase's built-in
> backup cron. See [Backups & disaster recovery](#backups--disaster-recovery)
> before you rely on anything in this file for a restore.

> Throughout this document, replace `<...>` placeholders with values from your environment. The repo ships zero environment-specific defaults — real values live in `.azure/<envName>/.env` (gitignored).

## Topology

| Resource | Name pattern | RG | Notes |
|---|---|---|---|
| Resource group | `<rg-name>` (default `rg-<envName>`) | — | Created by deployment |
| ACR | `cr<resourceToken>` (Basic) | `<rg-name>` | Holds `pocketbase:latest` |
| Storage account | `<storage-account>` | `<rg-name>` | Premium **FileStorage**, NFS share `pbdata`. No blob endpoint — this kind cannot host one |
| Container Apps env | `cae-<envName>` | `<rg-name>` | Consumption profile, logs → shared LAW |
| Container App | `ca-<envName>` | `<rg-name>` | 1 vCPU / 2 GiB, **single replica** (SQLite) |
| Managed identity | `id-<envName>` | `<rg-name>` | AcrPull |
| Log Analytics (shared) | `<law-name>` | `<shared-obs-rg>` | Cross-RG `existing` reference |
| App Insights (shared) | `<app-insights-name>` | `<shared-obs-rg>` | Cross-RG `existing` reference |

PocketBase data path **inside the container**: `/pb_data`, an **NFS** Azure Files
mount that persists across pod restarts and across PocketBase's own
`syscall.Exec` self-restart. NFS (not SMB) is required: SMB does not honor the
POSIX byte-range locks SQLite WAL mode needs, and an SMB mount crashlooped with
`SQLITE_BUSY (5)` (fixed in `6a4f04df`). That in turn is why the environment is
VNet-integrated and the storage account is Premium FileStorage — Container Apps
only supports NFS Azure Files under those conditions.

## Prerequisites (one-time)

1. `az login` and `azd auth login`.
2. The signed-in principal needs:
   - `Contributor` on the subscription (or on `<rg-name>` after first create).
   - `Reader` + `Microsoft.OperationalInsights/workspaces/sharedKeys/action` on `<law-name>` in `<shared-obs-rg>` (the deployment calls `listKeys()` on it).
3. Set required azd env vars (all values stay in the gitignored `.azure/<envName>/.env`):
   ```sh
   azd env new <envname>           # e.g. prod
   azd env set AZURE_LOCATION       <region>           # e.g. westus
   azd env set PB_ADMIN_EMAIL       you@example.com
   azd env set PB_ADMIN_PASSWORD    '<strong-pass>'    # quote to survive zsh
   azd env set SHARED_OBS_RG        <shared-obs-rg>
   azd env set SHARED_LAW_NAME      <law-name>
   azd env set SHARED_AI_NAME       <app-insights-name>
   azd env set AZURE_STORAGE_NAME   <storage-account>  # 3-24 chars, lowercase alphanumeric
   # Optional — defaults to rg-<envName> if unset:
   azd env set AZURE_RG_NAME        <rg-name>
   ```

## Three-pass deployment

The custom-domain + free managed cert flow has an unavoidable chicken-and-egg step: domain ownership must be verified at the DNS layer **before** Azure will issue the cert. So the first deploy is intentionally bare, then you add DNS records, then you re-deploy to bind the domain + cert.

### Pass 1 — initial deploy (no custom domain)

```sh
azd up
```

This builds the image, pushes to ACR, and stands up everything except the custom domain binding. When it finishes, capture two values:

```sh
azd env get-value AZURE_CONTAINER_APP_FQDN
azd env get-value AZURE_CONTAINER_APP_CUSTOM_DOMAIN_VERIFICATION_ID
```

Sanity check the app responds:

```sh
curl -fsS "https://$(azd env get-value AZURE_CONTAINER_APP_FQDN)/api/health"
```

### Pass 2 — add DNS records

Add the following records at your DNS provider for `<your-domain>` (replace `<host>` with the subdomain, e.g. `auth`):

| Type | Host | Value | TTL |
|------|------|-------|-----|
| `CNAME` | `<host>` | `<AZURE_CONTAINER_APP_FQDN>` | 1 hr |
| `TXT` | `asuid.<host>` | `<AZURE_CONTAINER_APP_CUSTOM_DOMAIN_VERIFICATION_ID>` (raw, no quotes) | 1 hr |

Wait 5–15 minutes, then verify both records resolve:

```sh
./scripts/verify-dns.sh <host>.<your-domain> <rg-name> ca-<envName>
```

Do **not** proceed to pass 3 until both checks return `OK`. The cert resource will hard-fail validation otherwise and the deployment rolls back.

> **Never delete the `asuid` TXT record** — Azure re-checks it on every cert renewal.

### Pass 3 — bind domain + issue managed cert

```sh
azd env set CUSTOM_DOMAIN <host>.<your-domain>
azd up
```

This:
1. Creates `Microsoft.App/managedEnvironments/managedCertificates` named after the domain (dots replaced with dashes).
2. Validates the CNAME + asuid TXT records.
3. Issues a free DigiCert TLS cert tied to the env (auto-renews).
4. Binds the cert to the Container App ingress with `SniEnabled`.

Verify:

```sh
curl -fsS https://<host>.<your-domain>/api/health
```

HTTP → HTTPS redirect is automatic (`allowInsecure: false`).

## Common operations

### Push code-only changes (no infra change)
```sh
azd deploy
```

### Force an infra-only update
```sh
azd provision
```

### Rotate the PocketBase admin password
```sh
azd env set PB_ADMIN_PASSWORD '<new>'
azd provision
```
The entrypoint runs `pocketbase superuser upsert` on next start.

### View logs
Either:
```sh
az containerapp logs show -n ca-<envName> -g <rg-name> --follow
```
Or in the shared LAW (logs flow there via `appLogsConfiguration`):
```kusto
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == "ca-<envName>"
| order by TimeGenerated desc
| take 200
```

## Backups & disaster recovery

Durability rests on two independent things — **neither of them is Litestream**:

1. **The persistent NFS `/pb_data` volume.** Survives pod restarts, revision
   swaps, and PocketBase's `syscall.Exec` self-restart.
2. **PocketBase's native backup cron.** Configured in the superuser dashboard
   under *Settings → Backups*, currently running daily at midnight with an S3
   target. This is the only off-box copy of the data.

### Verify backups are landing

There is no blob replica to inspect — the storage account is FileStorage and has
no blob endpoint. Check the backup list through the API instead:

```sh
TOKEN=$(curl -s -X POST https://<custom-domain>/api/collections/_superusers/auth-with-password \
  -H 'Content-Type: application/json' \
  -d '{"identity":"<admin-email>","password":"<password>"}' | jq -r .token)
curl -s https://<custom-domain>/api/backups -H "Authorization: $TOKEN" | jq '.[].key'
```

The newest entry should be from the last 24 h. Also confirm the S3 bucket
directly — the API list reflects the configured storage, but a bucket-side check
is the one that proves the object actually landed.

> **Backup failures can be silent.** `CreateBackup` reports errors through
> `app.Logger()`, which writes to `auxiliary.db`. If that database is damaged the
> error may never reach the log — and note that the batch writer at
> [core/base.go](core/base.go) swallows per-row write errors (it prints them to
> stderr and returns `nil`, so the transaction still commits), meaning log loss
> is silent and partial rather than a loud failure. The only other alarm is the
> superuser email from `sendSystemAlertToAllSuperusers`, which needs working
> SMTP. Treat "no errors in the log" as weak evidence; check the bucket.

### Restore (disaster recovery)

**Do not delete `/pb_data/data.db` expecting an automatic restore.** There is no
replica to restore from. `litestream_restore()` in [entrypoint.sh](entrypoint.sh)
is gated on `LITESTREAM_REPLICA_URL`, which is unset, so it is a no-op —
PocketBase would simply create an empty database and the deleted data would be
gone. (Earlier revisions of this runbook documented exactly that procedure. It
was correct only while Litestream was enabled, before 2026-05-25.)

To restore, use the dashboard: *Settings → Backups → upload/select a backup →
Restore*. PocketBase swaps `pb_data` and self-restarts via `syscall.Exec`.
Expect to lose up to one backup interval (24 h) of writes — for this app that
means recently enrolled passkeys, whose owners will need to re-register.

### Recovering a corrupt `auxiliary.db`

`auxiliary.db` holds only the `_logs` table
([migrations/1640988000_aux_init.go](migrations/1640988000_aux_init.go)), so it is
safe to set aside. Symptom is `database disk image is malformed (11)` spamming
the console on request-log writes.

**Confirming it, without a shell.** In the dashboard, open *Logs* and read the
newest entry's timestamp. If it is frozen days or months in the past while the
console error is still streaming, logging is dead. Do not infer health from
"I can see logs" — the UI happily renders frozen history. Corroborate on the
volume: a healthy `auxiliary.db-wal` grows continuously; a **0-byte WAL beside a
stale `auxiliary.db` mtime means nothing is being written**.

**`az containerapp exec` needs a real TTY** and fails with
`termios.error: (19, 'Operation not supported by device')` from a non-interactive
shell. Wrap it, and note that nested `sh -c '...'` quoting does not survive the
websocket — issue one plain command per call. The exec endpoint also rate-limits
aggressively (HTTP 429, `retry-after: 600`), so batch your intent into as few
calls as possible.

```sh
REV=$(az containerapp show -g <rg-name> -n ca-<envName> --query properties.latestReadyRevisionName -o tsv)

# preserve rather than delete — matches the existing .recover-YYYY-MM-DD convention in /pb_data
script -q /dev/null az containerapp exec -g <rg-name> -n ca-<envName> --revision "$REV" \
  --command "mkdir -p /pb_data/.recover-$(date +%F)"
script -q /dev/null az containerapp exec -g <rg-name> -n ca-<envName> --revision "$REV" \
  --command "mv /pb_data/auxiliary.db /pb_data/auxiliary.db-wal /pb_data/auxiliary.db-shm /pb_data/.recover-$(date +%F)/"

az containerapp revision restart -g <rg-name> -n ca-<envName> --revision "$REV"
```

The `ReapplyCondition` on the aux-init migration recreates `_logs` on next boot.
Verify by confirming a fresh small `auxiliary.db` plus a **growing** WAL, and that
new entries appear in the dashboard *Logs* view.

**This recurs.** It has happened at least twice — `/pb_data/.recover-2026-06-09`
is the first occurrence, and the replacement corrupted again three days later on
**2026-06-12 at 00:00**, staying dead until 2026-08-15. The suspected cause is
contention at midnight, where three jobs hit `auxiliary.db` at once:
`__pbDBOptimize__` (`0 0 * * *`) runs `PRAGMA wal_checkpoint(TRUNCATE)` on the aux
DB, `__pbLogsCleanup__` (`0 */6 * * *`) bulk-deletes from `_logs`, and the backup
cron opens `AuxRunInTransaction` plus a second truncating checkpoint while
archiving the same files — all over NFS. This is correlational, not proven.
**Cheapest mitigation: move the backup cron off midnight** (e.g. `0 2 * * *` in
*Settings → Backups*). It costs nothing and, if corruption stops recurring,
confirms the diagnosis.

## Failure modes & fixes

| Symptom | Cause | Fix |
|---|---|---|
| Pass 3 fails with `Domain ownership verification failed` | DNS records not propagated yet | Re-check `dig`, wait, re-run `azd up` |
| Pass 1 fails with 403 on `listKeys` of LAW | Principal lacks reader/sharedKeys on `<law-name>` | Grant `Log Analytics Contributor` (or just `*/sharedKeys/action`) in `<shared-obs-rg>` |
| App returns 502 briefly after deploy | New revision still starting | Expected; startup probe allows up to 90 s |
| `database disk image is malformed (11)` spam in logs | `auxiliary.db` corrupt | See [Recovering a corrupt `auxiliary.db`](#recovering-a-corrupt-auxiliarydb) |
| Container crashloops with `SQLITE_BUSY (5)` | `/pb_data` mounted over SMB instead of NFS | SMB lacks POSIX byte-range locks. Storage must be Premium FileStorage + NFS, env VNet-integrated (`6a4f04df`) |
| `customDomains` value rejected | Cert resource was deleted out-of-band | Set `CUSTOM_DOMAIN=` (empty) and re-deploy, then redo passes 2–3 |
| Two replicas running (data corruption risk) | Someone bumped `maxReplicas` | Revert — SQLite is single-writer; `maxReplicas: 1` is enforced in [infra/modules/container-app.bicep](infra/modules/container-app.bicep) |

## Telemetry — OTLP export to SigNoz

PocketBase's logger writes to `auxiliary.db`. When that database broke on
2026-06-12 every request log was dropped and nothing said so for two months
(see [Recovering a corrupt `auxiliary.db`](#recovering-a-corrupt-auxiliarydb)).
[core/logger_otel.go](core/logger_otel.go) adds a second, independent sink: the
same records also go to the self-hosted OTLP collector, so a local-sink failure
is visible immediately instead of silently.

This follows the shared parish contract — `docs/observability/otlp-onboarding.md`
in the **STFoA-Church** repo. Read that first; it is canonical if anything here
disagrees.

### Turning it on

Everything is driven by GitHub repo variables plus one secret. With
`OTLP_ENDPOINT` unset, export is disabled and PocketBase logs exactly as
upstream does — no code path is entered.

| Setting | Kind | Value |
|---|---|---|
| `OTLP_ENDPOINT` | variable | `https://otlp.thedoodleproject.net` (endpoint **root** — the SDK appends `/v1/logs`) |
| `OTLP_AUTH_HEADER` | **secret** | `Authorization=Bearer <ingest-token>` |
| `OTEL_SERVICE_NAME` | variable | `stfoa-auth` (default). One per app, and **never change it** — it is the key SigNoz groups on |
| `OTEL_ENVIRONMENT` | variable | `production` (default) \| `staging` \| `development` |
| `OTEL_MIN_LEVEL` | variable | optional `DEBUG`\|`INFO`\|`WARN`\|`ERROR` — see cost note below |

Read the ingest token off the cluster and store it as a repo secret; it is one
shared token for all three signal paths:

```sh
kubectl -n signoz get secret otlp-ingest-token -o jsonpath='{.data.token}' | base64 -d
```

`OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf` is set unconditionally in
[infra/modules/container-app.bicep](infra/modules/container-app.bicep) whenever an
endpoint is configured. Do not remove it. The collector is reached through a
Cloudflare Tunnel carrying HTTP only — an SDK that defaults to gRPC on 4317
exports nothing **and reports no error**; the app simply never appears in SigNoz.

### The sink-failure signal

The local `_logs` sink reports its own failures on the OTLP sink. This is the
part that was missing while `auxiliary.db` was dead from 2026-06-12 to
2026-08-15: PocketBase's batch writer reports a rejected row with a stdlib
`log.Println` to stderr, which never crosses `app.Logger()` and so never reached
a collector, and `PB_OTEL_MIN_LEVEL=WARN` filtered the INFO request logs whose
disappearance was the only other clue. SigNoz could not tell a dead sink from an
idle app.

Two messages now carry that state, both emitted straight to the OTLP handler —
never through `app.Logger()`, which is the sink that just failed:

| Message | Level | Meaning |
|---|---|---|
| `local log sink write failed` | ERROR | rows are being rejected; attributes carry `sink`, `failedRecords`, `attemptedRecords`, `failedBatches` and the SQLite `error` |
| `local log sink recovered` | WARN | the first clean batch after a failing run — the all-clear for the alert |

Both **bypass `PB_OTEL_MIN_LEVEL`** on purpose; trimming request-log volume must
not also silence the reason the second sink exists. The failure record is rate
limited to one per 5 minutes and accumulates its counts in between, so a fully
corrupt database costs 288 records a day instead of 8,600 while still reporting
the true number of dropped rows.

**Alert on `local log sink write failed`** in SigNoz, and clear on
`local log sink recovered`.

### Ingestion cost

Every request is logged at INFO, and the startup/liveness probes hit
`/api/health` every 10 s — roughly 8.6k records a day before any real traffic.
Set `OTEL_MIN_LEVEL=WARN` to cap what crosses the wire. It does not affect what
PocketBase stores locally, so the dashboard *Logs* view keeps full detail either
way.

### Verify

```sh
# 1. the gate rejects an unauthenticated request
curl -s -o /dev/null -w '%{http_code}\n' -X POST https://otlp.thedoodleproject.net/v1/traces \
  -H 'Content-Type: application/json' -d '{"resourceSpans":[]}'          # expect 401

# 2. the app is exporting: exporter errors go to stderr, never through
#    app.Logger() (that would feed failures back into the failing sink)
az containerapp logs show -g <rg-name> -n ca-<envName> --tail 50 --type console | grep '\[otel\]'
```

Then find the service in SigNoz under `service.name=stfoa-auth` with the right
`deployment.environment`. An empty `resourceSpans` array returns `200` without
proving anything reached ClickHouse — only a real record does.

## Litestream: why it is off, and what re-enabling would take

Litestream was configured early on and **deliberately disabled on 2026-05-25**
(`f9cac5e0`). Do not switch it back on without reading this — the failure mode
was worse than having no replica at all.

**Why it was turned off.** PocketBase's dashboard backup-restore performs an
in-process `syscall.Exec` self-restart. The supervising `litestream` process
survives that exec holding an open FD on the *pre-restore* inode, so it keeps
replicating the orphaned file. A consented dashboard restore left a **10 KB
malformed snapshot as the only replica**, and the entrypoint's cold-start restore
would then write that corruption onto a fresh pod. Litestream was manufacturing
bad backups and then restoring them.

**The fix exists but was never wired up.** `0d82e286` added a fork-local
`OnTerminate` hook that signals PPID before `execve`, so a supervisor can recycle
Litestream across a restore:

- [pre_restart_signal.go](pre_restart_signal.go) (unix) /
  [pre_restart_signal_other.go](pre_restart_signal_other.go) (stub)
- wired at [pocketbase.go](pocketbase.go) via `bindPreRestartSignal(pb)`
- env: `PB_PRE_RESTART_SIGNAL` (SIGTERM|SIGUSR1|SIGHUP|SIGUSR2|SIGINT|SIGQUIT),
  `PB_PRE_RESTART_DELAY_MS` (default 500). Unset = upstream behavior.

Still outstanding if you ever want the replica back:

1. Provision a **StorageV2** account with a blob container. The current
   FileStorage account cannot host one, and `storage.bicep` dropped the blob
   wiring in `6a4f04df`.
2. Add `trap "kill -TERM $LITESTREAM_PID; wait $LITESTREAM_PID" USR1` to
   [entrypoint.sh](entrypoint.sh) — it currently traps only `TERM INT`.
3. Set `PB_PRE_RESTART_SIGNAL=SIGUSR1` and the three `LITESTREAM_*` vars on the
   container app. `entrypoint.sh` and `litestream.yml` need no other changes.
4. Write a test for the pre-restart hook — there is none, so its behavior is
   unexercised.

**Is it worth it?** Against a working daily backup cron the only real gain is
RPO — seconds instead of up to 24 h. That matters here only if losing a day of
passkey enrollments is unacceptable. Weigh that against re-entering a code path
that has already caused one data-loss incident.

## Tear-down

```sh
azd down --purge
```
`--purge` is required to actually delete the ACR and Key Vault soft-delete tombstones. Then manually delete the DNS records at your provider.

## Files

- [azure.yaml](azure.yaml) — azd service definition
- [infra/main.bicep](infra/main.bicep) — subscription-scope deployment entry
- [infra/main.parameters.json](infra/main.parameters.json) — azd env var bindings
- [infra/modules/acr.bicep](infra/modules/acr.bicep)
- [infra/modules/storage.bicep](infra/modules/storage.bicep)
- [infra/modules/container-app.bicep](infra/modules/container-app.bicep) — managed env, cert, ingress, app
- [infra/modules/network.bicep](infra/modules/network.bicep) — VNet + delegated subnet (required for NFS)
- [litestream.yml](litestream.yml) — replica config, **inert**: no `LITESTREAM_*` env is set
- [entrypoint.sh](entrypoint.sh) — (restore) → superuser bootstrap → (replicate) → serve; both parenthesized steps are skipped while `LITESTREAM_REPLICA_URL` is unset
- [scripts/verify-dns.sh](scripts/verify-dns.sh) — generic DNS validator (CNAME + asuid TXT)
