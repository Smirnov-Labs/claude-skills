# Debugging: Error Logs, email, PDF, reports

Instance-health debugging that isn't about the ledger. Run these from the bench console (see
*Reaching bench* in `SKILL.md`).

## Error Log triage

The `Error Log` doctype is where Frappe records tracebacks. Two non-obvious facts:

- **The human-readable title is in the `method` column** (there is no `title` field) — aggregate
  signatures by `GROUP BY method`.
- When one `method` bucket has mixed root causes (e.g. every bank-feed sync failure lands under one
  method), **re-bucket by the last non-empty traceback line** to separate them.

```python
# top signatures over the retained window
frappe.db.sql("SELECT method AS title, COUNT(*) cnt, MAX(creation) latest FROM `tabError Log` "
              "WHERE creation >= NOW() - INTERVAL 30 DAY GROUP BY method ORDER BY cnt DESC LIMIT 40",
              as_dict=True)
# split a noisy method into real root causes
from collections import Counter
c = Counter()
for r in rows:
    c[(r["error"] or "").splitlines()[-1][:160]] += 1
```

Two traps:
- **It's a historical ledger, not a live status board.** Fixing a root cause stops *new* rows but never
  erases old ones — and Frappe **Log Settings auto-purge** them (~30 days), so "the error is gone" may
  just mean it aged out. Judge by `MAX(creation)`, not by presence.
- **Tracebacks can leak plaintext secrets** (e.g. an integration's `client_id`/`secret` fragments). Rotating a key
  does **not** scrub old rows — treat the Error Log as sensitive, and purge/patch rows that captured a
  live credential.

## A report crashing at a fixed wall-clock time = an Auto Email Report

If an Error Log shows a Query/Script Report failing at a recurring clock time (18:00, 19:00…), the
trigger is almost always a scheduled **`Auto Email Report`** running it — not a user. Check it directly;
a PDF-format one additionally needs the chromium/PDF path healthy (below).

```python
frappe.get_all("Auto Email Report", filters={"report": "<Report Name>"},
               fields=["name", "enabled", "frequency", "email_to", "format"])
```

## Script Reports need mandatory filters (the fake "permission wall")

P&L, **Balance Sheet**, **Trial Balance**, Cash Flow, General Ledger, AR/AP, Gross Profit are **Script
Reports that require `company` + a period/fiscal-year filter.** Called bare (e.g. by an LLM over the MCP
connector) they return empty or error — which *reads* like a permission block. It isn't: the permission
check is just `frappe.has_permission("Report", "read", <name>)`, and `Accounts Manager` + `Accounts
User` already pass. **The fix is usage, not config** — always pass the filters:

```python
from frappe.desk.query_report import run
run("Balance Sheet", filters={"company": "<Company>", "fiscal_year": "2026",
                              "period_start_date": "2026-01-01", "period_end_date": "2026-12-31"})
```

## Email Account / SMTP — set it up and prove it

Create the outbound `Email Account` idempotently (keyed on `email_id`). Assigning `doc.password`
triggers Frappe's **at-rest encryption**. Non-obvious required fields:

- `login_id_is_different = 1` + `login_id` — many providers use a fixed username (e.g. Resend's is
  `resend`), not the from-address.
- `use_tls = 1` for STARTTLS on 587.
- `always_use_account_email_id_as_sender = 1` — forces a verified-domain `From`, else the provider
  rejects per-user senders.

**Proving it actually sends is the part people skip.** `frappe.sendmail(now=True)` does **not** guarantee
a synchronous send — it can leave an `Email Queue` row at status **"Not Sent"** for the background
worker. A *clean* send **removes** the queue row entirely; a *failed* send leaves `status="Error"` +
traceback. So flush and verify the **stored encrypted** credential authenticates for real:

```python
# definitive: decrypt stored pw + connect + STARTTLS + AUTH, using no test creds
frappe.get_doc("Email Account", "<name>").get_smtp_server().session
```

## Headless chromium / PDF

v16 renders PDFs with headless chromium. The stock image **does** ship `/usr/bin/chromium-headless-shell`,
but Frappe's `find_or_download_chromium_executable()` **ignores it unless `chromium_path` is set** and
instead tries to self-download to `{bench}/chromium/` → `Popen returncode: 127`, which surfaces as the
misleading **"Chromium took too long to start"**. Fix (per the config-on-PVC law):

```bash
bench set-config -g chromium_path /usr/bin/chromium-headless-shell
```

Verify by instantiating `ChromePDFGenerator()` in a **fresh** process — but note it forks ~6 orphan
chromium procs you must then kill, and `pgrep` isn't in the slim image, so walk `/proc/*/comm`.
