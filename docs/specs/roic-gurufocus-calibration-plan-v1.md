# ROIC and Tax Handling Calibration Plan vs GuruFocus v1

Status: Draft (implementation-aligned planning)
Issue: IntrinsicAI-66z
Owner: bengabay1994
Last updated: 2026-03-11

## 1. Purpose

This document defines a practical calibration framework to compare IntrinsicAI ROIC and tax handling outputs against GuruFocus reference values. The goal is to detect and reduce systematic drift while keeping the workflow offline-friendly and reproducible without live scraping or secrets.

## 2. Scope

In scope:
- ROIC parity checks at yearly and averaged-window levels (10y, 5y, 1y).
- Tax-rate handling parity checks that influence NOPAT and ROIC.
- Comparison metrics, acceptance thresholds, and sign-off rules.
- Reusable data capture template for manual or scripted benchmark runs.

Out of scope:
- Building a live GuruFocus scraper.
- Storing private credentials or paid API tokens.
- Replacing current production formulas in this issue.

## 3. Baseline Formula Context (Current IntrinsicAI)

Current Updater derivation (source of computed ROIC) is implemented in `Updater/src/ingest.py`:
- `taxRate` defaults to `0.25`.
- If `incomeBeforeTax != 0` and `taxProvision` is present, `taxRate = taxProvision / incomeBeforeTax`.
- `NOPAT = EBIT * (1 - taxRate)`.
- `investedCapital = totalEquity + totalDebt - cash`.
- `ROIC = NOPAT / investedCapital` when invested capital is non-zero.

MainApp averaging behavior is implemented in `MainApp/lib/core/analysis/rule1_analyzer.dart`:
- 10y/5y/1y ROIC outputs are arithmetic means across available annual ROIC values.
- Null values are excluded.

This calibration plan validates these outputs and informs follow-on adjustments.

## 4. Calibration Methodology

Use a two-pass approach for each sampled ticker/year:

### 4.1 Pass A: Observed parity
- Record IntrinsicAI computed values and GuruFocus reference values as observed.
- Do not alter formulas during capture.

### 4.2 Pass B: Diagnostic attribution
- Classify variance cause using one primary reason code:
  - `tax_fallback_default_25` (default-tax path likely diverges)
  - `tax_ratio_outlier` (taxProvision/incomeBeforeTax creates extreme rate)
  - `invested_capital_component_gap` (debt/equity/cash mapping mismatch)
  - `period_alignment_mismatch` (fiscal year windows differ)
  - `rounding_or_display_only`
  - `unclassified`

### 4.3 Execution principles
- Keep benchmark snapshots static per run (manual exports, copied values, or curated fixtures).
- Store date-stamped benchmark files under repo docs/templates or test fixtures.
- Avoid network-dependent calibration gates in CI.

## 5. Sampling Strategy

Use a stratified sample to avoid overfitting one profile.

### 5.1 Minimum initial sample
- 24 tickers total.
- At least 8 sectors.
- Include at least:
  - 8 large-cap stable earners
  - 8 cyclical or margin-volatile businesses
  - 4 financial-statement edge cases (negative tax years, near-zero incomeBeforeTax)
  - 4 turnaround or distressed profiles

### 5.2 Time coverage
- Prefer latest 10 fiscal years where available.
- Require at least 5 fiscal years for inclusion in aggregate threshold checks.

### 5.3 Refresh cadence
- Re-run full sample monthly during calibration rollout.
- Re-run targeted subset on every ROIC/tax formula change.

## 6. Comparison Metrics

Compute metrics at both row-level (ticker-year) and aggregate-level (run summary).

### 6.1 Row-level metrics
- `abs_delta = abs(intrinsicai_roic - gurufocus_roic)`
- `signed_delta = intrinsicai_roic - gurufocus_roic`
- `rel_delta_pct = abs_delta / max(abs(gurufocus_roic), 0.01)`

Tax diagnostics:
- `tax_rate_delta = intrinsicai_tax_rate - gurufocus_tax_rate` (when both available)
- `tax_mode_match` boolean (fallback/default vs derived/observed handling classification)

### 6.2 Aggregate metrics
- Mean absolute error (MAE) of ROIC.
- Median absolute error (MedAE) of ROIC.
- 90th percentile absolute error (P90 abs delta).
- Bias (mean signed delta).
- Tax fallback incidence rate (% rows using default tax path).

## 7. Acceptance Thresholds

Thresholds are intentionally practical and can tighten after stabilization.

### 7.1 Per-row expectations
- Target: `abs_delta <= 0.020` (2.0 percentage points ROIC) for most rows.
- Soft fail band: `0.020 < abs_delta <= 0.040` requires reason code.
- Hard fail: `abs_delta > 0.040` requires explicit triage note.

### 7.2 Aggregate run acceptance
- MAE <= `0.015`.
- MedAE <= `0.010`.
- P90 abs delta <= `0.030`.
- Absolute bias <= `0.005`.
- At least 85% of rows within `abs_delta <= 0.020`.

If any aggregate threshold fails, mark run as `needs_calibration`.

## 8. Data Capture Workflow (No Live Scraping)

1. Build or update local IntrinsicAI data using existing Updater flow.
2. Populate reference columns from pre-collected GuruFocus snapshots (manual copy/import).
3. Calculate deltas and reason codes in the template.
4. Produce run summary metrics and mark pass/fail status.
5. Store completed artifact with date suffix (for example: `roic-gurufocus-comparison-2026-03-11.csv`).

Recommended location for completed run artifacts:
- `docs/templates/calibration-runs/` (create when first run artifact is added).

## 9. Follow-On Implementation Touchpoints

Expected files for follow-on parity work:

Updater:
- `Updater/src/ingest.py`
  - Tax-rate fallback behavior.
  - Guardrails for pathological effective tax rates.
  - Optional diagnostics output for tax path selection.
- `Updater/tests/test_ingest_fixtures.py`
  - Fixture-based tests for tax handling edge cases and ROIC parity regression.

MainApp:
- `MainApp/lib/core/analysis/rule1_analyzer.dart`
  - Ensure averaging windows and null handling match calibration assumptions.
- `MainApp/lib/core/database/database_service.dart`
  - Verify annual row ordering/window selection consistency for parity checks.

Cross-cutting:
- Add golden/benchmark tests tied to static calibration fixtures once variance targets are stable.

## 10. Reporting Format and Sign-Off

Each calibration run should include:
- Run metadata (date, data source snapshot date, analyst).
- Row-level comparison records.
- Aggregate metrics section.
- Final decision: `pass`, `pass_with_notes`, or `needs_calibration`.

Sign-off recommendation:
- Require two consecutive `pass` runs on unchanged formula inputs before tightening thresholds.

## 11. Non-Goals and Safety Notes

- No credentials are required for this framework.
- No production data writes are required beyond existing local updater flow.
- No automated extraction from GuruFocus is introduced in this issue.
