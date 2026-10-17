---
name: operating-frappe-on-kubernetes
description: Use when operating, upgrading, or debugging a Frappe / ERPNext instance running on Kubernetes (Helm chart under ArgoCD, external MariaDB + Redis/Valkey, DB + sites PVCs). Covers the config-on-PVC law (common_site_config on the sites PVC masks image/Helm config — only `bench set-config -g` sticks, and it is not in git); the two PVCs and where encryption_key + the hashed DB name live; greenfield first-site bootstrap (chart setup Jobs churn under ArgoCD, so create the first site with a one-time Job — seed common_site_config.json before `set-config -g`, and set encryption_key deterministically with the bench venv python); major-version upgrades (v15→v16 `bench migrate` is fix-forward-only, the frappe.social orphan Module Def, no version skipping, back up both PVCs, maintenance-mode 503) and the Helm chart 7→8 Redis→Valkey backend flip plus the migrate Job that churns under ArgoCD; and instance debugging — Error Log triage (method-column title, secret leakage, auto-purge), Email Account / SMTP setup + Email Queue verification, headless chromium / PDF, and why Script Reports read as permission-locked without their mandatory filters. Triggers: bench new-site, bench migrate, set-config, encryption_key, Valkey, Error Log, Email Account, chromium, Scheduled Job Type.
---

# Operating Frappe / ERPNext on Kubernetes

The manual for keeping a **Frappe / ERPNext instance alive** on a Kubernetes cluster — platform config,
major-version upgrades, and instance debugging. This is the *platform & health* layer; ledger data and
reports (GL/JE writes, dashboards) are out of scope. Keep your instance's own facts (site name,
namespace, companies) in a project skill in the repo that deploys it.

## When to use

- Standing up the **first site** on a fresh deploy (greenfield bootstrap — `bench new-site`).
- A `bench migrate` / major-version upgrade (v15→v16) or a Helm chart bump.
- Config that "won't take" (chromium_path, host_name, server_script_enabled, maintenance flags).
- Debugging Error Logs, email/SMTP, PDF/chromium, or "permission-locked" financial reports.
- Any direct MariaDB access (dumps, raw SQL) below the bench layer.

## The deployment shape

A typical deploy: a Frappe/ERPNext **Helm chart under ArgoCD** rendering `gunicorn`
(web), `nginx`, `scheduler`, and `worker` pods; **external MariaDB and Redis/Valkey** (not the chart's
bundled ones); and **two PVCs** — the MariaDB data volume and the Frappe **sites** volume. You reach
the app through the gunicorn pod's `bench`.

### Reaching bench

Run Python against the live site by copying a script into a gunicorn pod and `exec`-ing it in the bench
console. Look the pod up every time; its name changes on every redeploy.

```bash
NS=<namespace>; SITE=<site-name>
POD=$(kubectl -n $NS get pods -l 'app.kubernetes.io/component=gunicorn' \
      -o jsonpath='{.items[0].metadata.name}')
kubectl -n $NS cp /tmp/x.py $POD:/tmp/x.py
kubectl -n $NS exec -i $POD -- \
  bench --site $SITE console <<< "exec(open('/tmp/x.py').read(), {})" \
  2>&1 | tr '\n' ' ' | grep -o 'MARK{.*}' | sed 's/^MARK//'
```

- Start the script with `import frappe, json` and `frappe.set_user("Administrator")`.
- Print **one line** of JSON behind a unique marker, `print("MARK" + json.dumps(out, default=str))`, and
  grep for it without a `^` anchor: the console echoes `In [N]:` prompts mid-line.
- **Never pipe multi-block Python in inline.** A heredoc's blank lines make the IPython console silently
  skip `if` / `for` / `def` bodies. `cp` the file in; inline `<<<` is only safe for a few flat statements.
- Pass an explicit globals dict (`exec(..., {})`) so names don't leak between runs.

## The config-on-PVC law (read this first)

Frappe's runtime site config lives in **`sites/common_site_config.json` on the sites PVC**. Because the
PVC is mounted over the image, **any config baked into the image layer or set through Helm values is
masked by the volume and does nothing.** The only thing that actually changes runtime config is:

```bash
kubectl -n <ns> exec -i <gunicorn-pod> -- bench set-config -g <key> <value>
```

Consequences a future operator must internalize:
- Keys that only work this way: `chromium_path`, `host_name`, `server_script_enabled`,
  `maintenance_mode`, log/mail settings, etc.
- **It is NOT in git.** If the site or the sites PVC is ever recreated, every `set-config -g` value is
  gone and must be re-applied. Keep a checklist of the ones your instance needs.
- A "config change that had no effect" is almost always something set in the image/Helm instead of via
  `set-config -g`.

## The two PVCs (and what only lives there)

- **DB PVC** — the MariaDB datadir. The database name is a **random hash** (`_<hex16>`), *not* the site
  name — read it from `frappe.conf.db_name` or `sites/<site>/site_config.json` before any direct dump.
- **sites PVC** — `sites/<site>/`: `site_config.json` (holds `db_name` **and** `encryption_key`),
  `private/backups/` (where `bench backup` lands), and `common_site_config.json`. **The `encryption_key`
  lives only here** — a backup that snapshots the DB PVC but not the sites PVC loses the key and can't
  decrypt stored passwords. Always back up **both**.

## Reference files

- `bootstrapping-a-new-site.md` — greenfield first-site bootstrap: why the chart setup Jobs churn (use
  a one-time Job instead), the three traps (seed `common_site_config.json` before `set-config -g`;
  `encryption_key` isn't created by `new-site` — set it deterministically with the venv python, never an
  empty one; `frappe.utils.health` 417s → probe `/api/method/ping`), and the `new-site` flags.
- `upgrading-frappe-major-versions.md` — the v15→v16 playbook: pre-flight, the Helm 7→8 Redis→Valkey
  backend flip + the churning migrate Job, `bench migrate` fix-forward discipline, the `frappe.social`
  orphan `Module Def`, and direct-dump mechanics (the hashed DB name).
- `debugging-error-logs-and-email.md` — Error Log triage, Email Account / SMTP + Email Queue proof,
  headless chromium / PDF, and Script-Reports-need-filters.

## Related

- Ledger data and reports (GL/JE writes, dashboards, multi-currency, bank feeds) are a separate concern;
  use a data-ops skill for those if your setup has one.
