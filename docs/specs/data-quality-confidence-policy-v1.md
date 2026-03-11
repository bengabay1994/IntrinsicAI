# IntrinsicAI Data Quality Confidence Policy v1

Status: Draft  
Issue: IntrinsicAI-2uh  
Owner: bengabay1994  
Last updated: 2026-03-11

## 1. Purpose

Define deterministic data-quality confidence rules for analysis outputs so users can distinguish:

- `investment_score`: business quality and investment attractiveness
- `data_confidence`: confidence in the evidence quality behind that analysis

This policy explicitly aligns with the approved scoring philosophy: investment quality scoring is company-quality-first and is not boosted by data completeness.

## 2. Scope

In scope:
- Data quality tier definitions.
- Deterministic confidence cap and flag rules.
- UI/API output contract for confidence display.
- Tie-breaking and precedence when multiple confidence constraints apply.

Out of scope:
- Big 5/ROIC/management/moat point allocations.
- Any change to canonical investment-grade thresholds.
- Portfolio sizing and allocation guidance.

## 3. Policy Alignment

1. Quality score and confidence are separate signals.
2. Better data cannot add quality points.
3. Weak or incomplete data can only reduce certainty via caps/tiers/flags.
4. Rules must be deterministic and auditable from raw inputs.

## 4. Output Contract

Each analysis output must include:

- `investment_score` (0-100): unchanged business quality score.
- `data_confidence_score` (0-100): deterministic evidence confidence score.
- `data_confidence_tier`: one of `high`, `medium`, `low`, `insufficient`.
- `confidence_cap` (0-100): hard cap applied to confidence score.
- `confidence_flags`: ordered list of machine-readable reasons.
- `confidence_summary`: short human-readable sentence for UI.

Optional but recommended:
- `confidence_inputs`: structured details used to compute confidence (years available, missing metric counts, staleness days, turnaround counts).

## 5. Data Quality Tiers

Tier assignment is based on final `data_confidence_score` after cap logic:

- `high`: 80-100
- `medium`: 60-79
- `low`: 40-59
- `insufficient`: 0-39

Display policy:
- Tier label must always be shown near score/grade output.
- `insufficient` tier requires a prominent caution badge.

## 6. Deterministic Confidence Scoring Model

## 6.1 Inputs

- `years_of_history`: count of annual rows available for analysis windows.
- `missing_big5_10y_count`: number of Big 5 metrics without valid 10y result.
- `roic_missing_years_10y`: count of missing ROIC annual values over last 10 years.
- `source_age_days`: days since most recent financial update.
- `turnaround_metric_count`: count of Big 5 metrics currently in turnaround states.

## 6.2 Base confidence score

Start with:

`base_confidence_score = 100`

Apply additive penalties:

- Years of history:
  - `< 3`: -60
  - `3-4`: -40
  - `5-7`: -25
  - `>= 8`: 0
- Missing 10y Big 5 metrics:
  - `1`: -10
  - `2`: -20
  - `>= 3`: -35
- ROIC missing years (10y window):
  - `1-3`: -10
  - `4-6`: -20
  - `>= 7`: -35
- Data staleness:
  - `201-400 days`: -10
  - `> 400 days`: -25
- Turnaround concentration:
  - `1`: -8
  - `2`: -16
  - `>= 3`: -28

Clamp after penalties:

`raw_confidence_score = max(0, min(100, base_confidence_score - total_penalties))`

## 6.3 Cap rules

Compute `confidence_cap` as the minimum of all applicable caps; default `100`.

- `years_of_history < 8`: cap `69`
- `years_of_history < 5`: cap `59`
- `missing_big5_10y_count >= 2`: cap `64`
- `roic_missing_years_10y >= 4`: cap `64`
- `source_age_days > 400`: cap `64`
- `turnaround_metric_count >= 2`: cap `69`

Final score:

`data_confidence_score = min(raw_confidence_score, confidence_cap)`

## 6.4 Precedence and tie rules

- All penalties are cumulative.
- All caps are non-cumulative; only the strictest cap (lowest numeric value) applies.
- If two tiers are possible due to rounding, use floor behavior on `data_confidence_score`.

## 7. Confidence Flags (Required)

For each triggered condition, emit exactly one machine-readable flag:

- `insufficient_history_under_3_years`
- `limited_history_under_5_years`
- `limited_history_under_8_years`
- `missing_big5_10y_1_metric`
- `missing_big5_10y_2plus_metrics`
- `roic_missing_10y_1to3_years`
- `roic_missing_10y_4plus_years`
- `stale_financials_over_200_days`
- `stale_financials_over_400_days`
- `multiple_turnaround_metrics`

Flag ordering in output:
1. History-related flags
2. Missing-data flags
3. Staleness flags
4. Turnaround flags

## 8. Display Requirements

UI must show confidence as a first-class companion to score, not as hidden metadata.

Minimum display requirements:
- Always display `data_confidence_tier` and `data_confidence_score` near `investment_score`.
- If any cap is active (`confidence_cap < 100`), show a `capped_confidence` badge.
- Show up to 3 highest-priority `confidence_flags` inline; remaining flags can be collapsed.
- Tooltip/details panel must expose full flags list and cap value.
- Confidence messaging must avoid implying a company-quality downgrade; it describes evidence certainty.

Recommended copy pattern:
- "Confidence: Medium (64/100) - Capped due to limited history and missing 10y metrics."

## 9. Worked Examples

### 9.1 Strong history, clean data
- Inputs: 10 years, 0 missing Big 5, 0 ROIC missing, 120 stale days, 0 turnarounds.
- Penalties: 0; cap 100.
- Final confidence: 100 (`high`).

### 9.2 Good company, limited history
- Inputs: 6 years, 0 missing Big 5, 0 ROIC missing, 90 stale days, 0 turnarounds.
- Raw confidence: 75.
- Cap: 69 (`limited_history_under_8_years`).
- Final confidence: 69 (`medium`).

### 9.3 Fragmented data and staleness
- Inputs: 4 years, missing Big 5 count 3, ROIC missing years 5, 500 stale days, turnarounds 2.
- Raw confidence: 0 after penalties.
- Cap: 59 (min of 59, 64, 64, 64, 69).
- Final confidence: 0 (`insufficient`) with multiple flags.

## 10. Related Specs

- `docs/specs/investment-confidence-model-v1.md`
- `docs/specs/rule1-formula-spec-v1.md`

## 11. Related Issues

- `IntrinsicAI-2uh` (this spec)
- `IntrinsicAI-e15` (investment quality score philosophy)
- `IntrinsicAI-fy9` (analysis provenance contract)
- `IntrinsicAI-mxg` (provenance/confidence display in UI)

## 12. Acceptance Criteria for IntrinsicAI-2uh

- A versioned data-confidence policy spec exists under `docs/specs`.
- Tier, cap, and flag rules are deterministic and machine-readable.
- Display requirements define mandatory confidence visibility behavior.
- Spec explicitly preserves company-quality-first scoring philosophy.
- Status remains `Draft` pending review and approval.
