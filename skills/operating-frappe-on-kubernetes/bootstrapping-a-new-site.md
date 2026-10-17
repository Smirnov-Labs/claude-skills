# Bootstrapping a NEW site (greenfield) on Kubernetes

Creating the **first** site on a fresh deploy — no existing DB/site to migrate. The chart's setup
Jobs are the obvious path and the wrong one; do it with a one-time Job instead. Worked live on a
greenfield ERPNext v16 deploy (external MariaDB + Redis, chart 8.x).

## Don't use the chart's setup Jobs — bootstrap by hand, once

`jobs.configure` / `jobs.createSite` / `jobs.migrate` carry **no Helm hook and a `now()`-timestamped
name**, so under ArgoCD auto-sync they re-create every reconcile (chronic `JobCompletionTimeExceeded`
churn — same reason `jobs.migrate` is disabled for upgrades). Keep **all three `enabled: false`** and
run a **one-time bootstrap Job you `kubectl apply` by hand** (the bootstrap exception, like the ArgoCD
Application manifests). Keep that Job **out of the kustomization** so ArgoCD never syncs/churns it.

The bootstrap Job replaces what `configure` + `createSite` would have done: write the runtime globals
to `common_site_config.json`, then `bench new-site`. It mounts the **sites** and **logs** PVCs and runs
`bench` from `/home/frappe/frappe-bench` (config-on-PVC law — see SKILL.md).

## The three greenfield traps (each cost a failed Job run)

**1. `bench set-config -g` needs `common_site_config.json` to already exist.** It reads-then-writes the
file; on a fresh **sites** PVC the file doesn't exist yet → `FileNotFoundError: .../sites/common_site_config.json`.
Also `sites/apps.txt` is masked by the empty PVC mount (the image's copy is hidden), so bench sees no
apps. Seed both first:

```bash
ls -1 apps > sites/apps.txt                                              # frappe, erpnext, …
[ -f sites/common_site_config.json ] || echo '{}' > sites/common_site_config.json
bench set-config -g db_host "erpnext-mariadb.<ns>.svc.cluster.local"
bench set-config -g redis_cache "redis://<cache-svc>:6379"
bench set-config -g redis_queue "redis://<queue-svc>:6379"
bench set-config -g redis_socketio "redis://<queue-svc>:6379"
```

**2. `encryption_key` is NOT created by `new-site` — set it deterministically, with the VENV python.**
`new-site` stores the admin password **hashed**, not encrypted, so it never needs (or creates) an
`encryption_key`. Frappe then generates one **lazily on first reversible-secret use** (e.g. saving an
Email Account password) — which is a **race** across the multiple gunicorn/worker pods sharing the RWX
**sites** volume, and it's **absent from any backup taken before that moment**. Set it once at bootstrap.

Two sharp edges when generating it:
- The **system `python` lacks `cryptography`** — it lives in the bench venv. Use **`env/bin/python`**.
  A `python -c 'from cryptography.fernet import Fernet; ...'` fails with `ModuleNotFoundError`, and under
  `set -euo pipefail` the failing **command substitution does not abort** the script — so
  `bench set-config encryption_key "$(…)"` silently writes an **empty** key (present-but-broken, worse
  than absent: Frappe won't regenerate a key that's present).
- Guard so an empty value is never written:

```bash
CUR=$(env/bin/python -c "import json,sys;sys.stdout.write(json.load(open('sites/$SITE/site_config.json')).get('encryption_key') or '')" 2>/dev/null || true)
if [ -z "$CUR" ]; then
  NEW=$(env/bin/python -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())')
  [ -n "$NEW" ] || { echo "encryption_key gen failed" >&2; exit 1; }
  bench --site "$SITE" set-config encryption_key "$NEW"
fi
```

A valid Fernet key is **44 chars**. Verify: `len(site_config['encryption_key']) == 44`.

**3. `frappe.utils.health` returns 417 on v16 — use `/api/method/ping` for health checks.** For a k8s
probe or a Prometheus ServiceMonitor, scrape **`/api/method/ping`** (guest-allowed, returns **200**).
`/api/method/frappe.utils.health` returns **417** on v16 and will read as a failing target.

## new-site flags

```bash
bench new-site "$SITE" --db-host "$DB_HOST" \
  --mariadb-root-password "$MYSQL_ROOT_PASSWORD" --admin-password "$ADMIN_PASSWORD" \
  --install-app erpnext --no-mariadb-socket
```

- `--no-mariadb-socket` makes the app DB user network-accessible (remote MariaDB). **Deprecated in v16**
  (warns, still works); successor is `--mariadb-user-host-login-scope='%'`. Switch it when you bump the image.
- The external MariaDB must accept **`root@'%'`** (set `MYSQL_ROOT_HOST='%'` on the StatefulSet) — bench
  connects as root over TCP from the pod network to create the site's DB + user.

## Bootstrap is idempotent + first-boot expectations

Make the Job idempotent: `if [ ! -d "sites/$SITE" ]; then new-site; else echo exists; fi`, then the
encryption_key guard (runs either way). Before the site exists the app pods **crashloop / serve 503** —
expected; they self-heal once the site appears on the shared PVC (no restart needed). Verify:

```bash
bench --site "$SITE" list-apps                 # frappe + erpnext present
curl -s -o /dev/null -w '%{http_code}' -H "Host: $SITE" http://<nginx-svc>:8080/   # 200
```
