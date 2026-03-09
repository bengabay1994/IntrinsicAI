# IntrinsicAI Investment Confidence Model v1

Status: Draft for review  
Issue: IntrinsicAI-e15  
Owner: bengabay1994  
Last updated: 2026-03-09

## 1. Purpose

Define a canonical score that answers:

"How attractive is this company as a Rule #1 investment candidate?"

This score is about business quality and investment attractiveness first. Data completeness does not add points; it only limits certainty using caps and warning flags.

## 2. Output Contract

For each analyzed ticker, produce:
- `investment_score` (0-100): attractiveness score.
- `investment_grade`: one of `excellent`, `good`, `watchlist`, `avoid`.
- `score_breakdown`: points by component.
- `confidence_cap`: optional cap applied due to data/trust limitations.
- `cap_reasons`: list of cap reasons.

## 3. Scoring Philosophy

### 3.1 Principles
- Reward durable compounding quality (Big 5 + ROIC + consistency).
- Reward management quality and owner-oriented behavior (CEO letters and other signals when available).
- Penalize fragility, instability, and weak economics.
- Never reward a stock just because data is complete.

### 3.2 Score equation

`final_investment_score = min(base_quality_score, confidence_cap_if_any)`

Where:
- `base_quality_score` is computed from company quality components.
- `confidence_cap_if_any` defaults to 100 when no cap applies.

## 4. Base Quality Score (0-100)

### 4.1 Component weights
- `fundamentals_score` (0-70)
- `management_score` (0-20)
- `moat_score` (0-10)

`base_quality_score = fundamentals_score + management_score + moat_score`

### 4.2 Fundamentals score (0-70)

#### A) Big 5 growth quality (0-45)

Metrics:
- EPS growth
- Equity growth
- Revenue growth
- Free cash flow growth
- Operating cash flow growth

Per metric scoring (0-9 each):
- >= 10%: 9
- >= 8% and < 10%: 7
- >= 5% and < 8%: 4
- > 0% and < 5%: 2
- <= 0%: 0
- turnaround or missing: 3 (neutral-caution, not full fail)

Window policy:
- Primary: 10y growth.
- Adjustment: if 5y materially contradicts 10y trend, subtract up to 2 points from that metric.

#### B) ROIC quality (0-25)

Use 10y average ROIC as primary signal:
- >= 15%: 25
- >= 12% and < 15%: 22
- >= 10% and < 12%: 19
- >= 8% and < 10%: 14
- >= 5% and < 8%: 8
- < 5%: 2
- missing: 6

Adjustments:
- If negative ROIC years exist in 10y set: -3
- If extreme outlier flags exist: -2
- Floor at 0.

## 5. Management Score (0-20)

Scored from CEO letters and management evidence (manual or AI-assisted with review).

### 5.1 CEO communication quality (0-10)
- Candor about mistakes/risks: 0-3
- Long-term strategy clarity (5-10 year lens): 0-3
- Capital allocation discipline discussion: 0-2
- Shareholder alignment language and behavior: 0-2

### 5.2 Execution and alignment signals (0-10)
- Consistency between stated strategy and observed financial outcomes: 0-4
- Evidence of moat strengthening initiatives: 0-3
- Owner-operator behavior (long-term incentives, prudence): 0-3

If CEO letters unavailable, default management score is 8 with low-confidence flag (neutral baseline, not a reward).

## 6. Moat Score (0-10)

Based on Rule #1 moat categories (`Brand`, `Secret`, `Toll`, `Switching`, `Price`, `None`).

Scoring guide:
- Strong durable moat evidence: 8-10
- Moderate moat evidence: 5-7
- Weak/uncertain moat: 2-4
- None: 0-1

When uncertain, score conservatively.

## 7. Confidence Caps (Data/Trust Modifiers)

Caps prevent overconfidence when evidence quality is weak. They do not increase score.

Start with cap = 100, then apply minimum of all applicable caps.

### 7.1 Cap rules
- Years of data < 8: cap 69
- Years of data < 5: cap 59
- Missing 10y values for 2+ Big 5 metrics: cap 64
- ROIC missing for 4+ of last 10 years: cap 64
- Latest update older than 400 days: cap 64
- Multiple turnaround flags across Big 5: cap 69

### 7.2 Cap reason reporting

Each cap must emit structured reason text (example: `insufficient_history_under_8_years`).

## 8. Grade Mapping

- `excellent`: score >= 85
- `good`: score >= 70 and < 85
- `watchlist`: score >= 55 and < 70
- `avoid`: score < 55

If a cap is active, include badge: `capped_confidence`.

## 9. Examples

### 9.1 High-quality compounder
- Base score: 90
- Cap: 100
- Final: 90 (`excellent`)

### 9.2 Good company but insufficient history
- Base score: 82
- Cap due to 6 years only: 69
- Final: 69 (`watchlist`, with cap reason)

### 9.3 Near-threshold grower with weak ROIC stability
- Base score: 63
- Cap: 100
- Final: 63 (`watchlist`)

## 10. Implementation Notes

- This document is a scoring contract; implementation should be incremental.
- Keep all component scores and cap reasons explainable in UI.
- AI-derived management/moat signals should be reviewable and overrideable.

## 11. Related Issues

- `IntrinsicAI-2uh`: data quality policy and confidence scoring model.
- `IntrinsicAI-fy9`: analysis provenance contract.
- `IntrinsicAI-mxg`: provenance display in UI.
- `IntrinsicAI-s4v`: benchmark ticker set.
- `IntrinsicAI-oms`: golden regression tests.

## 12. Acceptance Criteria for IntrinsicAI-e15

- A versioned scoring model spec exists and is committed.
- Model explicitly separates quality score from data/trust caps.
- Big 5, ROIC, management, and moat contributions are defined.
- Caps and grades are deterministic and reviewable.
