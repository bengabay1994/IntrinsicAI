# Rule #1 Benchmark Dataset

This directory stores the benchmark ticker set used to hand-verify IntrinsicAI Rule #1 outputs.

Primary files:
- `docs/specs/benchmark-ticker-set-v1.md`: benchmark framework and policy.
- `docs/benchmarks/rule1_benchmark_ticker_set_v1.json`: benchmark dataset.

## Validation Process

1. Choose one `entries[]` record in `rule1_benchmark_ticker_set_v1.json`.
2. Run IntrinsicAI analysis for that ticker and capture produced outputs.
3. Add external references under `validation.reference_checks`.
4. Keep `result: pending` until manual checks are complete.
5. Compare analyzer outputs with references/manual calculations.
6. Fill verified `expected_outputs` values and set a `tolerance` where needed.
7. Set each reference check result to `matched` or `mismatch` and document notes.
8. Update `last_reviewed_at` and `review_notes`.
9. Bump `dataset_version` whenever expected values change.

## Placeholder Rules

- Do not enter unverified numeric values as expected truth.
- Use `pending_manual_verification` with `null` expected values until validated.
- Keep `locator`, `checked_by`, and `checked_at` as `TBD` only until actual verification occurs.
