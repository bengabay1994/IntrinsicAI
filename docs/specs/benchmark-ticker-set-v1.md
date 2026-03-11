# IntrinsicAI Benchmark Ticker Set Specification v1

Status: Draft  
Issue: IntrinsicAI-s4v  
Owner: bengabay1994  
Last updated: 2026-03-11

## 1. Purpose

Define a benchmark ticker set and a hand-verified expected-output framework that guards Rule #1 formula behavior from silent drift.

This benchmark set is intentionally reference-driven:
- Expected values must come from external references and/or reproducible manual calculations.
- Unknown values must remain explicit placeholders until verified.
- No benchmark entry should imply fabricated financial facts.

## 2. Scope

In scope:
- Benchmark ticker categories and minimum coverage targets.
- Canonical benchmark data format and required fields.
- Template fields for expected outputs and validation notes.
- Validation and update workflow.

Out of scope:
- Automatic benchmark execution harness (tracked separately).
- Golden test enforcement wiring (tracked separately).

## 3. Benchmark Category Coverage

The starter dataset should include representative tickers across categories:

1. `established_compounder`
2. `volatile_high_growth`
3. `mature_or_slow_growth`
4. `cyclical`
5. `turnaround_or_inconsistent`
6. `negative_or_missing_metric_case`
7. `non_us_exchange_format_case`

Notes:
- A ticker may belong to more than one category when justified.
- Category assignment is descriptive, not a buy/sell signal.

## 4. Canonical Data Format

Benchmark dataset file:
- `docs/benchmarks/rule1_benchmark_ticker_set_v1.json`

Top-level fields:
- `schema_version`: benchmark schema version.
- `dataset_version`: benchmark set revision label.
- `status`: `draft` or `approved`.
- `last_updated`: ISO date.
- `entries`: list of benchmark ticker entries.

Per-entry required fields:
- `benchmark_id`: stable unique id (for tests/reports).
- `ticker_input`: ticker as a user would type it.
- `expected_normalized_ticker`: canonical ticker format expected from app normalization.
- `company_name`: informational label.
- `categories`: list of category tags.
- `expected_outputs`: template for expected analysis outputs.
- `validation`: external reference linkage and notes.
- `notes`: free-form context.

## 5. Expected Output Template

Each entry must define this structure under `expected_outputs`:

- `data_quality_tier`
  - One of: `reliable`, `partial`, `insufficient`, `pending_manual_verification`.
- `analysis_status`
  - One of: `green`, `yellow`, `red`, `pending_manual_verification`.
- `big5`
  - Keys: `eps_growth_10y`, `equity_growth_10y`, `revenue_growth_10y`, `free_cash_flow_growth_10y`, `operating_cash_flow_growth_10y`.
  - Each key contains:
    - `expected_state` (for example: `valid`, `turnaround`, `missingData`, `invalid`, `pending_manual_verification`)
    - `expected_value` (numeric ratio or `null`)
    - `tolerance` (numeric or `null`)
    - `source_reference_ids` (list of ids from `validation.reference_checks`)
- `roic_10y_avg`
  - Same subfields as a Big 5 metric (`expected_state`, `expected_value`, `tolerance`, `source_reference_ids`).
- `valuation`
  - Keys: `sticker_price`, `mos_price`.
  - Same subfields as above.

Rule:
- Use `pending_manual_verification` + `null` values until reference checks are completed.

## 6. Validation Template

Each entry must define this structure under `validation`:

- `reference_checks`: list of external checks where each item has:
  - `reference_id` (local stable id)
  - `provider` (for example: `GuruFocus`, `Macrotrends`, `Company 10-K`)
  - `locator` (URL, export path, or document locator)
  - `fields_to_compare` (which output fields this reference validates)
  - `checked_by`
  - `checked_at` (ISO timestamp)
  - `result` (`pending`, `matched`, `mismatch`, `not_comparable`)
  - `notes`
- `manual_calc_artifacts`: optional list of calculation file paths/spreadsheet tabs.
- `last_reviewed_at`: ISO timestamp or `TBD`.
- `review_notes`: free-form notes that explain discrepancies or assumptions.

## 7. Validation and Update Workflow

1. Pick a benchmark entry and run current analyzer output for that ticker.
2. Collect external references (at least one trusted source per key metric family).
3. Record references in `validation.reference_checks` with `result: pending` first.
4. Compare analyzer outputs against references and/or manual calculations.
5. Replace placeholder expected values with verified values and set tolerances.
6. Update `result` to `matched`/`mismatch` and add discrepancy notes.
7. Bump `dataset_version` when any expected value changes.
8. Keep placeholder values explicit when verification is incomplete.

Change policy:
- Never overwrite previous reasoning without updating `review_notes`.
- If a trusted reference changes methodology, document that in `review_notes` before changing expected values.

## 8. Starter Dataset Policy

The initial dataset may include real ticker symbols with placeholder expected values.

Allowed in starter entries:
- Ticker metadata, categories, and normalization expectations.
- Explicit `pending_manual_verification` states.

Not allowed in starter entries:
- Unverified numerical financial truths presented as expected outcomes.
