# Azure Deployment Runbook

End-to-end deployment of this PocketBase fork to **Azure Container Apps**, with Litestream → Azure Blob backups, shared cross-RG observability (Log Analytics + Application Insights), and a custom domain.

> Throughout this document, replace `<...>` placeholders with values from your environment. The repo ships zero environment-specific defaults — real values live in `.azure/<envName>/.env` (gitignored).

## Topology

| Resource | Name pattern | RG | Notes |
|---|---|---|---|
| Resource group | `<rg-name>` (default `rg-<envName>`) | — | Created by deployment |
| ACR | `cr<resourceToken>` (Basic) | `<rg-name>` | Holds `pocketbase:latest` |
| Storage account | `<storage-account>` | `<rg-name>` | Azure Files share `pbdata` + blob container `pocketbase-backups` |
| Container Apps env | `cae-<envName>` | `<rg-name>` | Consumption profile, logs → shared LAW |
| Container App | `ca-<envName>` | `<rg-name>` | 1 vCPU / 2 GiB, **single replica** (SQLite) |
| Managed identity | `id-<envName>` | `<rg-name>` | AcrPull + Storage Blob Data Contributor |
| Log Analytics (shared) | `<law-name>` | `<shared-obs-rg>` | Cross-RG `existing` reference |
| App Insights (shared) | `<app-insights-name>` | `<shared-obs-rg>` | Cross-RG `existing` reference |

PocketBase data path **inside the container**: `/pb_data` (Azure Files mount).
Litestream replicates `data.db` and `auxiliary.db` to blob every 10 s; restores on cold start if `/pb_data/data.db` is missing.

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

### Verify Litestream is replicating
```sh
az storage blob list \
  --account-name <storage-account> \
  --container-name pocketbase-backups \
  --auth-mode login \
  --query "[].name" -o tsv | head -20
```
You should see `data.db/...` and `auxiliary.db/...` snapshot/WAL files updating every 10 s.

### Restore from blob (disaster recovery)
1. Scale the container app to 0 replicas (`az containerapp revision deactivate`).
2. Delete or rename `/pb_data/data.db` in the Azure Files share.
3. Scale back up — the entrypoint runs `litestream restore` automatically when `data.db` is missing and `LITESTREAM_REPLICA_URL` is set.

## Failure modes & fixes

| Symptom | Cause | Fix |
|---|---|---|
| Pass 3 fails with `Domain ownership verification failed` | DNS records not propagated yet | Re-check `dig`, wait, re-run `azd up` |
| Pass 1 fails with 403 on `listKeys` of LAW | Principal lacks reader/sharedKeys on `<law-name>` | Grant `Log Analytics Contributor` (or just `*/sharedKeys/action`) in `<shared-obs-rg>` |
| App returns 502 for 60–90 s after deploy | Litestream restoring `data.db` from blob | Expected on cold start; startup probe allows up to 90 s |
| `litestream replicate` logs auth errors | Storage key rotated | Rotate via `azd provision` — secret is re-fetched at deploy time |
| `customDomains` value rejected | Cert resource was deleted out-of-band | Set `CUSTOM_DOMAIN=` (empty) and re-deploy, then redo passes 2–3 |
| Two replicas running (data corruption risk) | Someone bumped `maxReplicas` | Revert — SQLite is single-writer; `maxReplicas: 1` is enforced in [infra/modules/container-app.bicep](infra/modules/container-app.bicep) |

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
- [litestream.yml](litestream.yml) — replica config (reads `LITESTREAM_AZURE_ACCOUNT_*`)
- [entrypoint.sh](entrypoint.sh) — restore → superuser upsert → replicate → serve
- [scripts/verify-dns.sh](scripts/verify-dns.sh) — generic DNS validator (CNAME + asuid TXT)
