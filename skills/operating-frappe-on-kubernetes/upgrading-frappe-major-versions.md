# Upgrading Frappe / ERPNext major versions

The playbook for a live major-version bump (worked example: **v15 → v16**, Helm chart **7 → 8**) on
Kubernetes. The whole job is: back up both PVCs → apply the chart carefully → `bench migrate` →
fix-forward through the one or two known snags.

## Pre-flight

- **No version skipping.** Be at the **tip of the current major** before jumping (v15 latest → v16).
  Frappe forbids skipping a major.
- **The prebuilt `frappe/erpnext` image bakes the runtime bumps** (e.g. Python 3.14 / Node 24), so the
  bare-metal `bench upgrade` pain from community guides does **not** apply — you're swapping an image,
  not rebuilding a bench.
- **Maintenance mode:** `bench --site <site> set-maintenance-mode on` → the site serves **HTTP 503**
  (verify 503, then 200 again after `off`).
- **Back up BOTH PVCs.** `bench --site <site> backup --with-files` writes the dump into the **sites**
  PVC at `sites/<site>/private/backups/` — but the DB lives on the **DB** PVC and the `encryption_key`
  on the **sites** PVC, so a complete restore point snapshots both (see the config-on-PVC law in
  SKILL.md). For a logical dump, see "Direct SQL" below.

## Helm chart 7 → 8: the backend flip (the deploy trap)

Chart 8.x makes **Valkey the default** cache/queue and **ships the bundled backends enabled**. Applying
old v7 values verbatim silently spins up unwanted `erpnext-valkey-*` (and `dragonfly-*`) StatefulSets
even when your DB/Redis are external. Fix:

- Explicitly set **all nine** bundled backends `enabled: false`:
  `mariadb-sts, postgresql-sts, valkey-cache, valkey-queue, dragonfly-cache, dragonfly-queue, mariadb,
  redis-cache, redis-queue`.
- Point `externalRedis.cache` / `externalRedis.queue` at the real `-master` services.
- **`jobs.migrate.enabled: false`.** The chart's migrate Job has **no Helm hook and a `now()`-timestamped
  name**, so under ArgoCD it churns/re-creates forever. Run migrate **by hand** instead (below).

## `bench migrate` — fix-forward only

`migrate` runs schema/data **patches in order** and is **idempotent** (completed patches are skipped on
re-run) — but there is **no reverse**. So:

- "Rollback" on a Frappe DB always means **restore-from-backup**, never a reverse-migrate.
- A failed migrate re-run hits the **identical** error until you fix the cause.
- On a mid-migrate abort: **confirm where it died.** If it aborted early (e.g. at `sync_all`'s
  module-import step, after only trivial idempotent patches like clearing expired OAuth tokens /
  truncating the Desktop Icon cache — i.e. no destructive schema write happened), apply the minimal
  metadata fix and **re-run once**. Fix-forward is strictly safer than a restore that would just replay
  the same failure.

```bash
kubectl -n <ns> exec -i <gunicorn-pod> -- bench --site <site> clear-cache
kubectl -n <ns> exec -i <gunicorn-pod> -- bench --site <site> migrate
```

## The `frappe.social` orphan (v15 → v16)

v16 removed the `frappe/social` module (gone from the filesystem + `modules.txt`), but a site upgraded
from v15 keeps a **stale standard `Module Def` "Social"** row, and `sync_all` aborts trying to import
it: `ModuleNotFoundError: No module named 'frappe.social'`. It's a **metadata-only** fix — do not roll
back.

1. **Diff all installed modules against the v16 image first** to confirm there's exactly **one** orphan
   (no whack-a-mole).
2. Delete it, clear cache, migrate once:
   ```sql
   DELETE FROM `tabModule Def` WHERE name='Social' AND app_name='frappe';   -- 1 row
   ```
   Migrate then **auto-removes** the now-unused doctypes from the other split-out modules
   (Newsletter / Blog / Transaction Log / backup integration) — you never delete those by hand.

## Direct SQL / logical dump — the DB name is a hash

When you go below bench for raw SQL or a `mariadb-dump`, the database is named like `_5e1c9f04b27a3d68`,
**not** after the site (`erp_example_com`):

- Get it from `frappe.conf.db_name` (in bench console) or `sites/<site>/site_config.json` → `db_name`.
- The MariaDB root password is in the mariadb pod's `$MYSQL_ROOT_PASSWORD` env.
- Verify a gzip'd dump with `gunzip -t` before trusting it:
  ```bash
  mariadb-dump -uroot -p"$MYSQL_ROOT_PASSWORD" _5e1c9f04b27a3d68 | gzip > /backup/pre-upgrade.sql.gz
  gunzip -t /backup/pre-upgrade.sql.gz && echo OK
  ```
