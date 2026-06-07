# Overengineering Rubric

The 13-pattern catalogue used by the `detect-overengineering` skill. Each pattern has a plan-level signal (what to look for in the plan text) and a typical edit (what slimming looks like).

Calibration:
- **high**: clear bloat, flag confidently
- **context-dep**: flag with "verify against requirements" caveat — could be justified by stated goals

Anti-examples (what NOT to flag) live in `examples.md`. Always cross-reference before emitting a finding.

## Defensive coding (1–2)

### 1. Defensive validation in trusted flows  [high]

**Signal:** "validate inputs", "guard against null/undefined", "check that X is not empty" on functions called only from internal/trusted code.

**Edit:** Strike the validation. Trust internal callers and the type system.

### 2. Error handling for impossible cases  [high]

**Signal:** try/catch around code with no realistic throw path. "Fallback if X fails" when X cannot fail (e.g., wrapping `JSON.stringify` of a known-good object).

**Edit:** Remove the handler. Let it throw if it ever does.

## Abstraction (3, 6, 9)

### 3. Premature abstraction  [high]

**Signal:** "Define a service layer", "create an interface for X", "introduce an adapter / factory / strategy" with one concrete consumer in scope.

**Edit:** Inline the implementation at the call site.

### 6. Useless DRY  [high]

**Signal:** "Extract a helper for…" when the duplication is 2–3 similar lines used in 1–2 places.

**Edit:** Leave the duplication. Three similar lines is better than premature abstraction.

### 9. Speculative extensibility  [context-dep]

**Signal:** "Design for future X", "make Y pluggable", "keep this open for Z" without a current second use case.

**Edit:** Build for the one case you have. Add the abstraction when the second case arrives.

## Configuration & process (4, 12, 13)

### 4. Speculative configuration  [high]

**Signal:** Env vars, feature flags, config files for values that aren't reconfigured between environments or over time.

**Edit:** Hardcode the value.

### 12. Multi-phase rollout for low-impact change  [context-dep]

**Signal:** "Feature flag → 10% → 50% → 100%" or "canary → staging → prod" for a refactor with no user-visible impact.

**Edit:** Ship it directly. No rollout needed.

### 13. Migration step for non-data change  [context-dep]

**Signal:** "Add a migration script" / "data migration" listed when no schema or data shape changes.

**Edit:** Strike the migration step.

## Compatibility (5)

### 5. Backwards-compat shims for greenfield code  [high]

**Signal:** "Keep old name as alias", "add deprecation comment", "re-export for migration" — when there are no existing consumers.

**Edit:** Delete the shim. Rename directly.

## Documentation (7)

### 7. Comment / docstring bloat  [high]

**Signal:** "Add JSDoc to all exports", multi-paragraph explanatory comments for self-evident code.

**Edit:** Remove. Rely on names.

## Testing (8)

### 8. Over-tested impossible paths  [context-dep]

**Signal:** Tests for branches the type system or framework already guarantees (e.g., "test that the function returns a number" when the type is `number`).

**Edit:** Remove those test cases.

## Structure (10, 11)

### 10. File proliferation for tiny modules  [context-dep]

**Signal:** Splitting <100 lines of code across `types.ts` / `utils.ts` / `index.ts` / `constants.ts` from the start.

**Edit:** Single file until it grows.

### 11. Custom error classes with no extra info  [context-dep]

**Signal:** "Define a custom error type X" that wraps a string message without adding fields, codes, or behavior.

**Edit:** Throw a plain `Error`.
