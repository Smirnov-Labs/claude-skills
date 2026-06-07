# Anti-Examples for the Rubric

For each pattern in `rubric.md`: one example that **should** be flagged and one similar-looking case that **should not**. Use these to suppress findings when the plan text resembles a "don't flag" example more than a "flag" example.

This file grows. Every false positive observed in real use becomes a new "don't flag" entry.

---

## Pattern 1 — Defensive validation in trusted flows

✅ **Flag:** "Add validation to `getUserById(id: number)` to ensure `id > 0` before querying the database."
*(`id` arrives from internal callers; the type system already guarantees `number`. The DB query will simply return null for unknown ids.)*

❌ **Don't flag:** "Validate the email format on the public `/register` endpoint before creating a user."
*(Public endpoint, untrusted input — validation is required at the system boundary.)*

## Pattern 2 — Error handling for impossible cases

✅ **Flag:** "Wrap the `JSON.stringify(internalConfig)` call in try/catch in case it throws."
*(`internalConfig` is a known plain object; `JSON.stringify` won't throw. The catch will never fire.)*

❌ **Don't flag:** "Wrap user-supplied JSON parsing in try/catch and return a 400 on failure."
*(User input is untrusted; `JSON.parse` will throw on malformed input.)*

## Pattern 3 — Premature abstraction

✅ **Flag:** "Define a `UserRepository` interface and a single `PostgresUserRepository` implementation. Inject the interface into the service."
*(One consumer, one implementation, no second backend planned. The interface is a name without substance.)*

❌ **Don't flag:** "Define a `Storage` interface with `S3Storage` and `LocalStorage` implementations, selected by environment."
*(Two real implementations exist; the interface is load-bearing.)*

## Pattern 4 — Speculative configuration

✅ **Flag:** "Add `MAX_RETRY_COUNT` env var (default 3) for the email retry logic."
*(No requirement to vary by environment; 3 is the value forever. Hardcode it.)*

❌ **Don't flag:** "Add `DATABASE_URL` env var for the Postgres connection string."
*(Connection strings legitimately differ across dev/staging/prod; this is correct configuration.)*

## Pattern 5 — Backwards-compat shims for greenfield code

✅ **Flag:** "Rename `processOrder` to `executeOrder`. Keep `processOrder` as a deprecated alias that delegates to the new name."
*(No callers exist outside this PR; just rename.)*

❌ **Don't flag:** "Rename the public API method `processOrder` to `executeOrder`. Keep `processOrder` as a deprecated alias for one release cycle."
*(Public API with external callers; backwards compatibility is required.)*

## Pattern 6 — Useless DRY

✅ **Flag:** "Extract `formatTimestamp(date)` helper used in 2 places (the email template and the audit log)."
*(Two callers, three lines each. Inline is clearer.)*

❌ **Don't flag:** "Extract `validateOrderTotal(order)` helper called from 6 places across pricing, checkout, refunds, and fraud detection."
*(Six callers, non-trivial logic — the abstraction earns its keep.)*

## Pattern 7 — Comment / docstring bloat

✅ **Flag:** "Add JSDoc to every exported function in `utils.ts`, including a `@param`, `@returns`, and `@example` for each."
*(Self-evident utilities; the names already say it.)*

❌ **Don't flag:** "Add a comment to `parsePhoneNumber` explaining the E.164 normalization quirk that handles Brazilian mobile numbers with the optional ninth digit."
*(Non-obvious WHY; comment is load-bearing.)*

## Pattern 8 — Over-tested impossible paths

✅ **Flag:** "Add a test that verifies `getUserById(id: number)` returns `null` when called with `undefined`."
*(TypeScript's `number` parameter type already prevents `undefined` from being passed at compile time.)*

❌ **Don't flag:** "Add a test that verifies `getUserById` returns `null` when the id doesn't exist in the database."
*(Real branch, real behavior, not type-system-guaranteed.)*

## Pattern 9 — Speculative extensibility

✅ **Flag:** "Design the email sender to support multiple providers (SendGrid today, Mailgun and SES eventually) via a strategy pattern."
*(Only SendGrid is on the roadmap; the strategy pattern is for hypothetical future providers.)*

❌ **Don't flag:** "Design the payment processor to support both Stripe (US) and Razorpay (India) — both are required for Q2 launch."
*(Two real consumers committed in scope; pluggability is justified.)*

## Pattern 10 — File proliferation for tiny modules

✅ **Flag:** "Create `feature-x/types.ts`, `feature-x/utils.ts`, `feature-x/constants.ts`, `feature-x/index.ts` for the new feature (estimated ~80 lines total)."
*(Eighty lines doesn't need four files.)*

❌ **Don't flag:** "Split the existing 1500-line `service.ts` into `service.ts` (entry), `service-pricing.ts`, `service-fulfillment.ts`."
*(Real size justifies the split.)*

## Pattern 11 — Custom error classes with no extra info

✅ **Flag:** "Define `class UserNotFoundError extends Error {}` to throw when a user lookup fails."
*(No extra fields, no error code, no special handling — a plain Error with message would do the same job.)*

❌ **Don't flag:** "Define `class RateLimitError extends Error` with `retryAfterMs: number` and `limitType: 'user' | 'global'` fields, used by the retry middleware."
*(Carries structured data the consumer reads.)*

## Pattern 12 — Multi-phase rollout for low-impact change

✅ **Flag:** "Roll out the new internal logging format behind a feature flag: 10% week 1, 50% week 2, 100% week 3."
*(Internal logging change with no user impact and no migration risk; just ship it.)*

❌ **Don't flag:** "Roll out the new search algorithm behind a feature flag: 5% canary, monitor relevance metrics for 1 week, then 50%, then 100%."
*(User-visible behavior change with measurable quality impact; staged rollout is required.)*

## Pattern 13 — Migration step for non-data change

✅ **Flag:** "Add a migration script `migrations/2026_05_06_rename_function.sql` to rename the `processOrder` function in code."
*(Code rename, not a database change; no migration needed.)*

❌ **Don't flag:** "Add a migration script to add a `phone_number` column to the `users` table with a backfill from the legacy `contacts` table."
*(Real schema and data change; migration is correct.)*
