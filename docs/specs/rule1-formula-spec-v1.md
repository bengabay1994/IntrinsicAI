# IntrinsicAI Canonical Formula Specification v1

Status: Draft for review  
Issue: IntrinsicAI-9s0  
Owner: bengabay1994  
Last updated: 2026-03-08

## 1. Purpose

This document defines the canonical, decision-auditable math and data rules used by IntrinsicAI for Rule #1 analysis. It standardizes formulas, edge-case handling, and assumptions so outputs are deterministic across Updater and MainApp.

This version is intentionally aligned to current code behavior where possible, and flags places that need explicit product decisions.

## 2. Scope

In scope:
- Ticker normalization rules.
- Data sufficiency and threshold semantics.
- Growth metric calculations (CAGR) for Big 5 metrics.
- ROIC derivation and averaging.
- Sticker Price and Margin of Safety (MOS) calculations.
- Mapping from formulas to implementation locations.

Out of scope:
- AI qualitative scoring model.
- Portfolio construction or position sizing.
- Broker/execution integration.

## 3. Canonical Inputs and Units

### 3.1 Input source priority
- Financial statement source of truth: EODHD fundamentals JSON ingested by Updater.
- Database source of truth for analysis: SQLite `financials` table and `companies` table.

### 3.2 Units and conventions
- Monetary fields are stored as raw provider numeric values (currency not normalized in current architecture).
- `roic` and CAGR values are decimal ratios in storage and math (`0.10` means 10%).
- UI presentation multiplies by 100 for percent display.

## 4. Ticker Normalization Contract

### 4.1 Updater normalization
- If a ticker has no exchange suffix (`.` absent), Updater assumes US and appends `.US`.
- If suffix exists, Updater uses ticker as provided.

### 4.2 MainApp normalization
- On analysis request, MainApp uppercases input.
- If no suffix exists, MainApp appends `.US`.
- If suffix exists, MainApp uses provided symbol.

### 4.3 Canonical rule
- Canonical internal ticker format is `<SYMBOL>.<EXCHANGE>`.
- Current default exchange fallback is `.US`.

## 5. Data Sufficiency and Threshold Semantics

### 5.1 Data quality tiers
- `reliable`: years >= 8.
- `partial`: 3 <= years < 8.
- `insufficient`: years < 3.

### 5.2 Rule #1 threshold constants
- Growth threshold: `0.10` (10%).
- ROIC threshold: `0.10` (10%).

### 5.3 Evaluation window behavior
- Growth metrics are computed for 10y, 5y, and 1y windows where data allows.
- Financial query currently retrieves max 11 annual rows; this supports 10-year CAGR as start and end points.

## 6. Big 5 Growth Metrics: CAGR Canonical Formula

### 6.1 Metrics covered
- EPS growth.
- Equity (book value) growth.
- Revenue growth.
- Free cash flow growth.
- Operating cash flow growth.

### 6.2 Standard CAGR formula

For positive start/end values:

`CAGR = (end / start)^(1 / years) - 1`

### 6.3 Canonical edge-case handling

Given `start`, `end`, `years`:
- If `start` or `end` is null: status `missingData`.
- If `start == 0` and `end == 0`: status `invalid` (`bothZero`).
- If `start == 0`: status `invalid` (`fromZero`).
- If `end == 0`: status `invalid` (`toZero`).
- If `start < 0` and `end > 0`: status `turnaround` (`negativeToPositive`).
- If `start > 0` and `end < 0`: status `turnaround` (`positiveToNegative`).
- If `start < 0` and `end < 0`: status:
  - `improvingLoss` when `abs(end) < abs(start)`.
  - `worseningLoss` otherwise.
- If `years <= 0`: status `invalid` (`invalidPeriod`).

No CAGR numeric value is emitted for turnaround or invalid statuses.

## 7. ROIC Canonical Formula and Averaging

### 7.0 Terms and definitions
- `EBIT` = Earnings Before Interest and Taxes.
- `NOPAT` = Net Operating Profit After Tax.
- In current implementation, `EBIT` is read directly from provider data (`Financials -> Income_Statement -> yearly -> ebit`), not reconstructed from lower-level fields.

### 7.1 Updater ROIC derivation (per fiscal year)

ROIC is derived during ingestion using:
- `NOPAT = EBIT * (1 - taxRate)`
- `taxRate` default = `0.25`
- if `incomeBeforeTax != 0` and `taxProvision` exists:
  - `taxRate = taxProvision / incomeBeforeTax`
- `totalDebt = longTermDebt + shortTermDebt` (missing values treated as 0)
- `investedCapital = totalEquity + totalDebt - cash`
- if `investedCapital != 0`:
  - `roic = NOPAT / investedCapital`
- else `roic = null`

### 7.2 ROIC average calculation in MainApp
- 10y/5y/1y values are arithmetic mean of available ROIC values in each period slice.
- Null ROIC values are excluded.
- If no valid values in period: status `missingData` (`noValidValues`).
- Flags:
  - all values negative: `allNegative`
  - some values negative: `negativeYears`
  - any value > 1.0: `extremeOutlierHigh`
  - any value < -0.5: `extremeOutlierLow`

## 8. Sticker Price and MOS Canonical Formula

### 8.1 Growth and P/E input selection
- Candidate growth rates are:
  - valid 10y EPS CAGR
  - valid 5y EPS CAGR
  - valid 10y Equity CAGR
  - valid 5y Equity CAGR
- Estimated growth = arithmetic mean of valid candidate growth rates.
- Growth cap for valuation safety: `estimatedGrowth = min(estimatedGrowth, 0.25)`.
- Future PE = median of last 20 annual P/E values.
- If fewer than 20 years are available, use median of available years.
- If no valid P/E history is available, Sticker Price is null.

Note: The Future PE history source is now part of the canonical formula, but still requires implementation work in data ingestion/storage before this can execute end-to-end.

### 8.2 Sticker Price formula
- Preconditions: current EPS > 0, estimatedGrowth > 0, futurePE > 0.
- `futureEPS = currentEPS * (1 + estimatedGrowth)^10`
- `futurePrice = futureEPS * futurePE`
- Discount at MARR 15%:
  - `stickerPrice = futurePrice / (1 + 0.15)^10`

### 8.3 MOS formula
- `mosPrice = stickerPrice * 0.5`

If preconditions are not met, Sticker Price and MOS are null.

## 9. Analysis Status Determination Contract

Starting status: `green`, then downgraded by rules:

1. Data quality:
- `insufficient` -> `red`
- `partial` -> at least `yellow` (unless already red)

2. Big 5 growth checks (10y):
- turnaround/missing data -> at least `yellow` (unless already red)
- valid and >= 10% -> pass for that metric
- valid and >= 8% but < 10% -> `yellow`
- valid and < 8% -> `red`

3. ROIC checks (10y average):
- >= 10% -> pass for ROIC threshold
- >= 8% but < 10% -> `yellow`
- < 8% -> `red`
- negative pattern flags -> at least `yellow` (unless already red)

4. If no reasons collected, emit pass reason.

## 10. Implementation Mapping (Current)

- Config constants and quality thresholds:
  - `MainApp/lib/core/config/app_config.dart`
- CAGR and sticker price math:
  - `MainApp/lib/core/analysis/math_core.dart`
- Status logic and growth/ROIC period evaluation:
  - `MainApp/lib/core/analysis/rule1_analyzer.dart`
- DB read contract and max 11-year fetch:
  - `MainApp/lib/core/database/database_service.dart`
- Ticker normalization in analysis entry:
  - `MainApp/lib/core/analysis/rule1_analyzer.dart`
- Updater ticker fallback and ingest orchestration:
  - `Updater/src/ingest.py`
- ROIC derivation and financial field extraction:
  - `Updater/src/ingest.py`

## 11. Confirmed Policy Decisions

The following decisions are confirmed by product owner review:

1. ROIC benchmarking target:
- IntrinsicAI ROIC behavior should be calibrated to match trusted external references (specifically GuruFocus) as closely as possible.

2. Tax-rate handling direction:
- Preferred behavior is to align with GuruFocus-style handling for years with unusable tax-rate inputs.
- Until exact parity behavior is documented, current default-tax fallback remains as an interim behavior.

3. Currency policy:
- No cross-company currency normalization is required for current Rule #1 growth/ratio interpretation.
- Mixed-currency values inside a single issuer's official reporting are not treated as an expected operating scenario.

4. Data reliability threshold:
- `reliable` requires 8 or more years of history.

5. Missing/turnaround status policy:
- Keep current yellow behavior for missing/turnaround cases.

## 12. Known Gaps vs Production-Grade Expectations

- No explicit schema version table yet (migration behavior is ad hoc).
- No confidence score output yet (quality tier exists but no composite score).
- No explicit provenance payload per metric in current API/DTO.
- No benchmark/golden test suite enforcing this spec yet.
- Future P/E median method needs historical P/E data pipeline support.

### 12.1 Gap handling plan (do not ignore)

Each gap is tracked and should be fixed as part of the productionization roadmap.

1. Schema versioning and migrations
- Problem: schema evolution is currently managed by inline SQL checks (ad hoc), which is hard to audit.
- Action: implement explicit schema versioning and migration tracking.
- Tracking issue: `IntrinsicAI-st2`.

2. Investment confidence scoring model
- Problem: no canonical score exists that represents business investment attractiveness.
- Action: define a company-quality-first score (Big 5 + ROIC + management/letters), with data quality as a cap/penalty rather than a direct positive contributor.
- Tracking issue: `IntrinsicAI-e15`.

3. Provenance payload per metric
- Problem: analysis output does not yet carry structured metadata showing exact years/fields used for each metric.
- Action: add explicit provenance fields in analysis output contract and surface in UI.
- Tracking issues: `IntrinsicAI-fy9` and `IntrinsicAI-mxg`.

4. Benchmark and golden validation
- Problem: no enforced benchmark suite currently guards formula drift.
- Action: maintain benchmark set and compare against trusted references (including manual GuruFocus comparisons), then enforce via golden tests.
- Tracking issues: `IntrinsicAI-s4v`, `IntrinsicAI-oms`, `IntrinsicAI-66z`.

5. Future P/E history dependency
- Problem: canonical Future PE now depends on long-horizon P/E history not yet available in pipeline.
- Action: add historical P/E ingestion and storage path for median(20y) calculation.
- Tracking issue: `IntrinsicAI-owc`.

## 13. Acceptance Criteria for IntrinsicAI-9s0

- A versioned formula specification exists and is committed.
- Every core metric and status rule is documented with deterministic logic.
- All formulas map to concrete implementation files.
- Open decisions are explicitly listed for stakeholder approval.
